#!/usr/bin/env bash
# PreToolUse hook: Guard exec commands.
#   1. Unconditional safety net — deny any recursive `rm` that would purge
#      $HOME, /, or another critical top-level directory, regardless of
#      ALLOWED_EXT_DIRS. This is the last line of defense against a mistyped
#      `rm -rf ~` or similar run with --dangerously-skip-permissions.
#   2. Path restriction — absolute (or ../-relative) paths referenced in the
#      command must resolve under the harness root, unless they fall under
#      one of the directories listed in ALLOWED_EXT_DIRS (see .env.sample).
# Devin CLI variant: emits devin's {"decision":"block"} output format.
set -uo pipefail

deny() {
  local msg="$1"
  jq -n --arg reason "${msg}" '{decision:"block",reason:$reason}'
  exit 0
}

is_system_path() {
  case "$1" in
    /bin/*|/usr/bin/*|/usr/local/bin/*|/dev/null) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  local input command cwd script_root harness_root
  input="$(cat)"
  command="$(jq -r '.tool_input.command // empty' <<< "${input}")"
  [[ -z "${command}" ]] && exit 0
  cwd="$(jq -r '.cwd // empty' <<< "${input}")"

  # script_root = the checkout containing this script (scripts/lib/, .env).
  # harness_root = nearest ancestor holding both repos/ and worktree/ — works
  # whether the checkout IS the lab root or sits under <lab>/worktree/<repo>/<branch>.
  local dir
  script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  dir="${script_root}"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -d "${dir}/repos" && -d "${dir}/worktree" ]]; then
      harness_root="${dir}"
      break
    fi
    dir="$(dirname "${dir}")"
  done
  [[ -z "${harness_root}" ]] && harness_root="${script_root}"
  [[ -z "${harness_root}" || ! -d "${harness_root}" ]] && exit 0
  cwd="${cwd:-${harness_root}}"

  # shellcheck disable=SC1091
  # shellcheck source=scripts/lib/rm-guard.sh
  source "${script_root}/scripts/lib/rm-guard.sh" 2>/dev/null || exit 0

  # 1) Always-on safety net, checked before any allowlist bypass.
  local rm_reason
  rm_reason="$(rm_guard_dangerous_reason "${command}" "${cwd}")"
  [[ -n "${rm_reason}" ]] && deny "${rm_reason}"

  # 2) Harness-root restriction, with ALLOWED_EXT_DIRS as a scoped escape hatch.
  local allowed_dirs
  allowed_dirs="$(load_allowed_ext_dirs "${harness_root}"; load_allowed_ext_dirs "${script_root}")"

  local candidate target
  while IFS= read -r candidate; do
    [[ -z "${candidate}" ]] && continue
    if [[ "${candidate}" = /* ]]; then
      target="$(realpath -m "${candidate}")"
    else
      target="$(realpath -m "${cwd}/${candidate}")"
    fi

    is_system_path "${target}" && continue
    [[ "${target}" == "${harness_root}" || "${target}" == "${harness_root}/"* ]] && continue
    if [[ -n "${allowed_dirs}" ]] && ext_dir_is_allowed "${target}" "${allowed_dirs}"; then
      continue
    fi

    deny "Access outside harness root blocked: ${target}. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env."
  done < <(
    tr -c '[:alnum:]_./:+%@=-' '\n' <<< "${command}" |
      awk '/^\// || /^\.\.?\//'
  )
}

main
