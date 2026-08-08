#!/bin/bash
# PreToolUse hook: Guard Bash commands.
#   1. Unconditional safety net — deny any recursive `rm` that would purge
#      $HOME, /, or another critical top-level directory, regardless of
#      ALLOWED_EXT_DIRS. This is the last line of defense against a mistyped
#      `rm -rf ~` or similar run with --dangerously-skip-permissions.
#   2. Path restriction — absolute (or ../-relative) paths referenced in the
#      command must resolve under the harness root, unless they fall under
#      one of the directories listed in ALLOWED_EXT_DIRS (see .env.sample).
set -uo pipefail

deny() {
  local MSG="$1"
  jq -n --arg reason "${MSG}" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

is_system_path() {
  case "$1" in
    /bin/*|/usr/bin/*|/usr/local/bin/*|/dev/null) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  local INPUT COMMAND CWD HARNESS_ROOT
  INPUT="$(cat)"
  COMMAND="$(jq -r '.tool_input.command // empty' <<< "${INPUT}")"
  [[ -z "${COMMAND}" ]] && exit 0
  CWD="$(jq -r '.cwd // empty' <<< "${INPUT}")"

  # Derive harness root from this script's own path: <HARNESS>/.claude/hooks/<script>
  HARNESS_ROOT="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  [[ -z "${HARNESS_ROOT}" || ! -d "${HARNESS_ROOT}" ]] && exit 0
  CWD="${CWD:-${HARNESS_ROOT}}"

  # shellcheck disable=SC1091
  source "${HARNESS_ROOT}/scripts/lib/rm-guard.sh" 2>/dev/null || exit 0

  # 1) Always-on safety net, checked before any allowlist bypass.
  local RM_REASON
  RM_REASON="$(rm_guard_dangerous_reason "${COMMAND}" "${CWD}")"
  [[ -n "${RM_REASON}" ]] && deny "${RM_REASON}"

  # 2) Harness-root restriction, with ALLOWED_EXT_DIRS as a scoped escape hatch.
  local ALLOWED_DIRS
  ALLOWED_DIRS="$(load_allowed_ext_dirs "${HARNESS_ROOT}")"

  local CANDIDATE TARGET
  while IFS= read -r CANDIDATE; do
    [[ -z "${CANDIDATE}" ]] && continue
    if [[ "${CANDIDATE}" = /* ]]; then
      TARGET="$(realpath -m "${CANDIDATE}")"
    else
      TARGET="$(realpath -m "${CWD}/${CANDIDATE}")"
    fi

    is_system_path "${TARGET}" && continue
    [[ "${TARGET}" == "${HARNESS_ROOT}" || "${TARGET}" == "${HARNESS_ROOT}/"* ]] && continue
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${TARGET}" "${ALLOWED_DIRS}"; then
      continue
    fi

    deny "Access outside harness root blocked: ${TARGET}. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env."
  done < <(
    tr -c '[:alnum:]_./:+%@=-' '\n' <<< "${COMMAND}" |
      awk '/^\// || /^\.\.?\//'
  )
}

main
