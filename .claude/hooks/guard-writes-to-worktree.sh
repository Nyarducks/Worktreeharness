#!/bin/bash
# PreToolUse hook: Block Edit/Write outside worktrees (worktree/) — forces all code changes through worktrees
set -uo pipefail

deny() {
  local MSG="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${MSG}"
  exit 0
}

# Output variable: MAIN_REPO
# Derive harness root from this script's own path: <HARNESS>/.claude/hooks/<script>
# Two dirname calls navigate up to the harness root — no CWD or env var dependency.
resolve_main_repo() {
  MAIN_REPO="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  if [[ -z "${MAIN_REPO}" || ! -d "${MAIN_REPO}" ]]; then
    deny "Write blocked: could not determine harness root from hook path ($0). Expected layout: <root>/.claude/hooks/<hook>."
  fi
}

main() {
  local FP
  FP="$(jq -r '.tool_input.file_path // empty')"
  [[ -z "${FP}" ]] && exit 0

  FP="$(realpath -m "${FP}" 2>/dev/null || echo "${FP}")"

  local MAIN_REPO
  resolve_main_repo

  local WORKTREE_DIR="${MAIN_REPO}/worktree"
  if [[ "${FP}" == "${WORKTREE_DIR}"/* || "${FP}" == "${WORKTREE_DIR}" ]]; then
    exit 0
  fi

  deny "Write blocked outside worktrees: ${FP}. All code changes must happen in a worktree under worktree/ (see .claude/skills/parallel-worktree/SKILL.md)."
}

main
