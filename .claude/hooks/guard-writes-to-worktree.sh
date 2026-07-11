#!/bin/bash
# PreToolUse hook: Block Edit/Write outside worktrees (worktree/) — forces all code changes through worktrees
set -uo pipefail

deny() {
  local MSG="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${MSG}"
  exit 0
}

# Output variable: MAIN_REPO
resolve_main_repo() {
  if [[ -n "${WORKTREE_LAB_DIR:-}" ]]; then
    if [[ ! -d "${WORKTREE_LAB_DIR}" ]]; then
      deny "Write blocked: WORKTREE_LAB_DIR=${WORKTREE_LAB_DIR} is invalid (directory not found). Fix the env var or unset it to use auto-detection."
    fi
    MAIN_REPO="${WORKTREE_LAB_DIR}"
    return
  fi
  MAIN_REPO="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
  if [[ -z "${MAIN_REPO}" ]]; then
    deny "Write blocked: could not determine repository root. Create a worktree under worktree/ first (see .claude/skills/parallel-worktree/SKILL.md)."
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
