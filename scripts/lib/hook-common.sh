#!/usr/bin/env bash
# hook-common.sh — shared core for the per-agent PreToolUse guard hooks
# under .claude/, .agents/, .codex/, and .devin/.
#
# Each hook file stays a thin adapter: it states the agent kind and its
# stdin JSON field names; the harness-root resolution, path scanning,
# ALLOWED_EXT_DIRS handling, and deny-JSON shapes all live here.
#
# Contract: guard functions print a deny reason on stdout, or nothing when
# the action is allowed. The `hook_main_*` entrypoints emit the deny JSON
# (via hook_deny_json) only when a reason exists, then exit 0.
#
# Sources rm-guard.sh (same directory) for the dangerous-rm net and the
# ALLOWED_EXT_DIRS loader.

# shellcheck source=scripts/lib/rm-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/rm-guard.sh" 2>/dev/null || true

# hook_script_root — prints the checkout dir containing the running hook
# (<checkout>/<agent-dir>/hooks/<hook>.sh → <checkout>).
hook_script_root() {
  realpath "$(dirname "$0")/../.." 2>/dev/null
}

# hook_harness_root <start_dir> — prints the nearest ancestor of start_dir
# holding both repos/ and worktree/ (the lab root); falls back to
# start_dir when none qualifies.
hook_harness_root() {
  local dir="$1"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -d "${dir}/worktree" && -d "${dir}/repos" ]]; then
      printf '%s\n' "${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  printf '%s\n' "$1"
}

# hook_deny_json <kind> <reason> — prints the deny decision JSON for the
# agent's wire format: claude/codex use hookSpecificOutput.permissionDecision,
# agy uses decision:"deny", devin uses decision:"block".
hook_deny_json() {
  local kind="$1" reason="$2"
  case "${kind}" in
    claude | codex)
      jq -n --arg reason "${reason}" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' ;;
    devin)
      jq -n --arg reason "${reason}" '{decision:"block",reason:$reason}' ;;
    *)
      jq -n --arg reason "${reason}" '{decision:"deny",reason:$reason}' ;;
  esac
}

# known_agent_dirs — config dirs of the supported agent CLIs. Always
# allowed so an agent can reach its own settings/skills; single source —
# extend here when a new agent kind is added.
known_agent_dirs() {
  [[ -n "${HOME:-}" ]] || return 0
  printf '%s\n' "${HOME}/.claude" "${HOME}/.codex" "${HOME}/.config/devin" "${HOME}/.gemini"
}

# hook_allowed_dirs <harness_root> <script_root> — the effective
# allowlist: built-in agent config dirs plus ALLOWED_EXT_DIRS read from
# both roots' .env files.
hook_allowed_dirs() {
  known_agent_dirs
  if declare -F load_allowed_ext_dirs > /dev/null; then
    load_allowed_ext_dirs "$1"
    load_allowed_ext_dirs "$2"
  fi
}

# Commands routinely reference interpreter/runtime paths that are not a
# filesystem escape (e.g. the binary being exec'd under /usr/bin).
hook_is_system_path() {
  case "$1" in
    /bin/* | /usr/bin/* | /usr/local/bin/* | /dev/null) return 0 ;;
    *) return 1 ;;
  esac
}

# hook_guard_command <command> <cwd>
# Prints a deny reason when <command> is a dangerous `rm` or references a
# path resolving outside the harness root and outside every
# ALLOWED_EXT_DIRS entry. Fails open when no harness root resolves.
hook_guard_command() {
  local command="$1" cwd="$2"
  declare -F rm_guard_dangerous_reason > /dev/null || return 0

  local script_root harness_root
  script_root="$(hook_script_root)"
  harness_root="$(hook_harness_root "${script_root}")"
  [[ -z "${harness_root}" || ! -d "${harness_root}" ]] && return 0
  cwd="${cwd:-${harness_root}}"

  # 1) Always-on safety net, checked before any allowlist bypass.
  local rm_reason
  rm_reason="$(rm_guard_dangerous_reason "${command}" "${cwd}")"
  if [[ -n "${rm_reason}" ]]; then
    printf '%s\n' "${rm_reason}"
    return 0
  fi

  # 2) Harness-root restriction, with the allowlist as the escape hatch.
  local allowed_dirs
  allowed_dirs="$(hook_allowed_dirs "${harness_root}" "${script_root}")"

  local candidate target
  while IFS= read -r candidate; do
    [[ -z "${candidate}" ]] && continue
    # shellcheck disable=SC2088 # "~" tokens are literal matches, expanded manually below
    if [[ "${candidate}" = /* ]]; then
      target="$(realpath -m "${candidate}")"
    elif [[ "${candidate}" == "~/"* || "${candidate}" == "~" ]]; then
      # ~ and ~/x expand to $HOME, exactly like the shell would
      target="$(realpath -m "${HOME:-/}${candidate#\~}")"
    elif [[ "${candidate}" == "~"* ]]; then
      # ~user form cannot be resolved statically — it is outside anyway
      target="${candidate}"
    else
      target="$(realpath -m "${cwd}/${candidate}")"
    fi

    hook_is_system_path "${target}" && continue
    [[ "${target}" == "${harness_root}" || "${target}" == "${harness_root}/"* ]] && continue
    if [[ -n "${allowed_dirs}" ]] && ext_dir_is_allowed "${target}" "${allowed_dirs}"; then
      continue
    fi

    printf 'Access outside harness root blocked: %s. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env.\n' "${target}"
    return 0
  done < <(
    tr -c '[:alnum:]_./:+%@=~-' '\n' <<< "${command}" |
      awk '/^\// || /^\.\.?\// || /^~/'
  )
}

# hook_guard_paths <scope:harness|worktree> <rel_base>
# Reads candidate paths (one per line) on stdin; relative entries resolve
# against <rel_base> (empty = hook's own cwd). Prints a deny reason for
# the first path outside the scope root and outside ALLOWED_EXT_DIRS.
# scope=worktree fails closed when no harness root resolves — writes must
# never silently escape; scope=harness fails open.
hook_guard_paths() {
  local scope="$1" rel_base="${2:+${2}/}"
  local script_root harness_root
  script_root="$(hook_script_root)"
  harness_root="$(hook_harness_root "${script_root}")"
  if [[ -z "${harness_root}" || ! -d "${harness_root}" ]]; then
    if [[ "${scope}" == "worktree" ]]; then
      printf 'Write blocked: could not find a harness root (a directory holding both repos/ and worktree/) above %s.\n' "$0"
    fi
    return 0
  fi

  local root_dir="${harness_root}"
  [[ "${scope}" == "worktree" ]] && root_dir="${harness_root}/worktree"

  local allowed_dirs
  allowed_dirs="$(hook_allowed_dirs "${harness_root}" "${script_root}")"

  local candidate target
  while IFS= read -r candidate; do
    [[ -z "${candidate}" ]] && continue
    if [[ "${candidate}" = /* ]]; then
      target="$(realpath -m "${candidate}" 2>/dev/null || printf '%s\n' "${candidate}")"
    else
      target="$(realpath -m "${rel_base}${candidate}" 2>/dev/null || printf '%s%s\n' "${rel_base}" "${candidate}")"
    fi

    [[ "${target}" == "${root_dir}" || "${target}" == "${root_dir}/"* ]] && continue
    if [[ -n "${allowed_dirs}" ]] && declare -F ext_dir_is_allowed > /dev/null \
      && ext_dir_is_allowed "${target}" "${allowed_dirs}"; then
      continue
    fi

    case "${scope}" in
      worktree)
        printf 'Write blocked outside worktrees: %s. All code changes must happen in a worktree under worktree/, or add this path to ALLOWED_EXT_DIRS in .env (see AGENTS.md).\n' "${target}" ;;
      *)
        printf 'Access outside repository root blocked: %s. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env (see AGENTS.md).\n' "${target}" ;;
    esac
    return 0
  done
}

# hook_main_command <kind> <command_jq> <cwd_jq>
# Full stdin→decision flow for command guards (Bash/exec/run_command):
# extract the command string + cwd with the given jq paths, run
# hook_guard_command, and emit the kind's deny JSON when it reports a reason.
hook_main_command() {
  local kind="$1" command_jq="$2" cwd_jq="$3"
  local input command cwd reason
  input="$(cat)"
  command="$(jq -r "${command_jq} // empty" <<< "${input}")"
  [[ -z "${command}" ]] && exit 0
  cwd="$(jq -r "${cwd_jq} // empty" <<< "${input}")"

  reason="$(hook_guard_command "${command}" "${cwd}")"
  [[ -n "${reason}" ]] && hook_deny_json "${kind}" "${reason}"
  exit 0
}

# hook_main_file <kind> <file_jq> <scope:harness|worktree>
# Full stdin→decision flow for single-file-path guards (Read/Edit/Write
# and the agy equivalents): extract the path, run hook_guard_paths against
# the scope root, emit the kind's deny JSON when it reports a reason.
hook_main_file() {
  local kind="$1" file_jq="$2" scope="$3"
  local input fp reason
  input="$(cat)"
  fp="$(jq -r "${file_jq} // empty" <<< "${input}")"
  [[ -z "${fp}" ]] && exit 0

  reason="$(hook_guard_paths "${scope}" "" <<< "${fp}")"
  [[ -n "${reason}" ]] && hook_deny_json "${kind}" "${reason}"
  exit 0
}
