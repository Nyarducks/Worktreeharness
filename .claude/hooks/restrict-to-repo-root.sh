#!/bin/bash
# PreToolUse hook: Block Read/Edit/Write outside the repository root and managed directories
set -uo pipefail

deny() {
  local MSG="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${MSG}"
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

  # Derive harness root from this script's own path: <HARNESS>/.claude/hooks/<script>
  local HARNESS_ROOT
  HARNESS_ROOT="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  [[ -z "${HARNESS_ROOT}" || ! -d "${HARNESS_ROOT}" ]] && exit 0

  if is_under "${FP}" "${HARNESS_ROOT}"; then exit 0; fi

  deny "Access outside repository root blocked: ${FP}. Use repos/ for base clones and worktree/ for active worktrees (see .claude/skills/parallel-worktree/SKILL.md)."
}

main
