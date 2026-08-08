#!/usr/bin/env bash
# Shared helpers for PreToolUse Bash hooks:
#   - rm_guard_dangerous_reason: unconditional safety net against `rm -rf`
#     incidents that would purge $HOME, /, or another critical top-level dir.
#   - load_allowed_ext_dirs / ext_dir_is_allowed: ALLOWED_EXT_DIRS allowlist,
#     letting commands touch specific external paths (e.g. ~/.claude, /tmp)
#     without opening access to the whole filesystem.
#
# Sourced by .claude/hooks/*.sh and .codex/hooks/*.sh — keep POSIX-ish bash,
# no external deps beyond coreutils (realpath) already required by the harness.

# Absolute top-level directories that must never be the direct target of a
# recursive rm, regardless of ALLOWED_EXT_DIRS.
_RM_GUARD_CRITICAL_DIRS=(
  /home /Users /root /etc /usr /var /bin /sbin /boot /lib /lib64
  /opt /System /Library /mnt /media /srv
)

# rm_guard_is_critical_path <resolved-path> <home>
# True if deleting (or wiping the contents of) <resolved-path> would destroy
# a user's home directory or another critical system location.
rm_guard_is_critical_path() {
  local target="$1" home="$2"
  [[ "${target}" == "/" ]] && return 0
  [[ -n "${home}" && "${target}" == "${home}" ]] && return 0
  # target is a strict ancestor of $HOME (e.g. rm -rf /home wipes every user)
  [[ -n "${home}" && "${home}" == "${target}"/* ]] && return 0
  local critical
  for critical in "${_RM_GUARD_CRITICAL_DIRS[@]}"; do
    [[ "${target}" == "${critical}" ]] && return 0
  done
  return 1
}

# rm_guard_resolve_token <token> <cwd> <home>
# Expands ~ / $HOME / ${HOME} and strips a trailing "/*" (glob wipe of a
# directory's contents), then resolves the result. Prints:
#   "<resolved-path> <wipe:0|1>"
rm_guard_resolve_token() {
  local tok="$1" cwd="$2" home="$3" wipe=0

  tok="${tok//\$\{HOME\}/${home}}"
  tok="${tok//\$HOME/${home}}"
  if [[ "${tok}" == "~" ]]; then
    tok="${home}"
  elif [[ "${tok}" == "~/"* ]]; then
    # NOTE: ${tok#~/} would tilde-expand the "~/" pattern itself and fail
    # to strip the literal prefix, so slice by fixed length instead.
    tok="${home}/${tok:2}"
  fi

  if [[ "${tok}" == "*" ]]; then
    wipe=1
    tok="${cwd}"
  elif [[ "${tok}" == */\* ]]; then
    wipe=1
    tok="${tok%/\*}"
    [[ -z "${tok}" ]] && tok="/"
  fi

  local resolved
  if [[ "${tok}" == /* ]]; then
    resolved="$(realpath -m "${tok}" 2>/dev/null)"
  else
    resolved="$(realpath -m "${cwd}/${tok}" 2>/dev/null)"
  fi
  [[ -z "${resolved}" ]] && resolved="${tok}"

  printf '%s %s\n' "${resolved}" "${wipe}"
}

# rm_guard_dangerous_reason <command> <cwd>
# Prints a human-readable deny reason on stdout if <command> contains an
# `rm` invocation (optionally via sudo) with a recursive flag whose target
# resolves to $HOME, /, or another critical directory. Prints nothing (and
# always returns 0) when the command looks safe — callers check for
# non-empty output.
rm_guard_dangerous_reason() {
  local command="$1" cwd="$2"
  local home="${HOME:-}"
  [[ -z "${command}" ]] && return 0

  local segment
  while IFS= read -r segment; do
    segment="$(echo "${segment}" | sed -E 's/^[[:space:]]+//')"
    [[ -z "${segment}" ]] && continue

    local -a words
    read -ra words <<< "${segment}"
    [[ ${#words[@]} -eq 0 ]] && continue

    local idx=0
    [[ "${words[0]}" == "sudo" ]] && idx=1
    [[ "${words[${idx}]:-}" == "rm" ]] || continue
    idx=$((idx + 1))

    local has_recursive=0 past_dashdash=0
    local -a targets=()
    local w
    for ((; idx < ${#words[@]}; idx++)); do
      w="${words[${idx}]}"
      if [[ ${past_dashdash} -eq 0 && "${w}" == "--" ]]; then
        past_dashdash=1
        continue
      fi
      if [[ ${past_dashdash} -eq 0 && "${w}" == -* ]]; then
        [[ "${w}" == *r* || "${w}" == *R* || "${w}" == "--recursive" ]] && has_recursive=1
        continue
      fi
      targets+=("${w}")
    done

    [[ ${has_recursive} -eq 1 && ${#targets[@]} -gt 0 ]] || continue

    local t resolved wipe
    for t in "${targets[@]}"; do
      read -r resolved wipe <<< "$(rm_guard_resolve_token "${t}" "${cwd}" "${home}")"
      if rm_guard_is_critical_path "${resolved}" "${home}"; then
        if [[ "${wipe}" == "1" ]]; then
          printf 'Blocked dangerous command: recursive rm would wipe the contents of %s (from target "%s"). This looks like an accidental home/system purge.' "${resolved}" "${t}"
        else
          printf 'Blocked dangerous command: recursive rm targets %s (from target "%s"), a critical directory. This looks like an accidental home/system purge.' "${resolved}" "${t}"
        fi
        return 0
      fi
    done
  done < <(printf '%s\n' "${command}" | tr ';|' '\n' | sed -E 's/&&/\n/g; s/\|\|/\n/g')

  return 0
}

# load_allowed_ext_dirs <harness_root>
# Sources <harness_root>/.env if present, then prints each normalized entry
# of ALLOWED_EXT_DIRS (comma or colon separated, ~ expansion supported) on
# its own line.
load_allowed_ext_dirs() {
  local harness_root="$1"
  if [[ -f "${harness_root}/.env" ]]; then
    # shellcheck disable=SC1090
    source "${harness_root}/.env"
  fi
  [[ -z "${ALLOWED_EXT_DIRS:-}" ]] && return 0

  local -a entries=()
  IFS=',:' read -ra entries <<< "${ALLOWED_EXT_DIRS}"
  local entry expanded
  for entry in "${entries[@]}"; do
    entry="$(echo "${entry}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "${entry}" ]] && continue
    expanded="${entry/#\~/${HOME:-}}"
    realpath -m "${expanded}" 2>/dev/null
  done
}

# ext_dir_is_allowed <resolved-target> <allowed-dirs-newline-list>
# True if <resolved-target> is one of, or nested under, an allowed dir.
ext_dir_is_allowed() {
  local target="$1" allowed_list="$2"
  local dir
  while IFS= read -r dir; do
    [[ -z "${dir}" ]] && continue
    [[ "${target}" == "${dir}" || "${target}" == "${dir}/"* ]] && return 0
  done <<< "${allowed_list}"
  return 1
}
