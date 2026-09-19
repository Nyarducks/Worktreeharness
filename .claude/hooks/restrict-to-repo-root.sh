#!/bin/bash
# PreToolUse hook: Block Read/Edit/Write outside the repository root and managed directories
set -uo pipefail

deny() {
  local MSG="$1"
  jq -n --arg reason "${MSG}" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

is_under() {
  local PATH_TO_CHECK="$1"
  local BASE="$2"
  [[ "${PATH_TO_CHECK}" == "${BASE}"/* || "${PATH_TO_CHECK}" == "${BASE}" ]]
}

main() {
  local FP
  FP="$(jq -r '.tool_input.file_path // empty')"
  [[ -z "${FP}" ]] && exit 0

  FP="$(realpath -m "${FP}" 2>/dev/null || echo "${FP}")"

  # SCRIPT_ROOT = the checkout containing this script (scripts/lib/, .env).
  # HARNESS_ROOT = nearest ancestor holding both repos/ and worktree/ — works
  # whether the checkout IS the lab root or sits under <lab>/worktree/<repo>/<branch>.
  local SCRIPT_ROOT HARNESS_ROOT DIR
  SCRIPT_ROOT="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  DIR="${SCRIPT_ROOT}"
  while [[ -n "${DIR}" && "${DIR}" != "/" ]]; do
    if [[ -d "${DIR}/worktree" && -d "${DIR}/repos" ]]; then
      HARNESS_ROOT="${DIR}"
      break
    fi
    DIR="$(dirname "${DIR}")"
  done
  [[ -z "${HARNESS_ROOT:-}" ]] && HARNESS_ROOT="${SCRIPT_ROOT}"
  [[ -z "${HARNESS_ROOT}" || ! -d "${HARNESS_ROOT}" ]] && exit 0

  if is_under "${FP}" "${HARNESS_ROOT}"; then exit 0; fi

  # shellcheck disable=SC1091
  source "${SCRIPT_ROOT}/scripts/lib/rm-guard.sh" 2>/dev/null
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local ALLOWED_DIRS
    ALLOWED_DIRS="$(load_allowed_ext_dirs "${HARNESS_ROOT}"; load_allowed_ext_dirs "${SCRIPT_ROOT}")"
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${FP}" "${ALLOWED_DIRS}"; then
      exit 0
    fi
  fi

  deny "Access outside repository root blocked: ${FP}. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env (see .agents/skills/parallel-worktree/SKILL.md)."
}

main
