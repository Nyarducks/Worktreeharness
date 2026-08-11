#!/bin/bash
# PreToolUse hook: Block Edit/Write outside worktrees (worktree/) — forces all code changes through worktrees
set -uo pipefail

deny() {
  local MSG="$1"
  jq -n --arg reason "${MSG}" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
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
    # shellcheck disable=SC1091
    source "${MAIN_REPO}/scripts/lib/worktree-ownership.sh" 2>/dev/null || true
    if declare -F worktree_ownership_denial_reason >/dev/null; then
      local OWNERSHIP_REASON
      if OWNERSHIP_REASON="$(worktree_ownership_denial_reason "${MAIN_REPO}" "${FP}")"; then
        deny "Write blocked: ${OWNERSHIP_REASON}"
      fi
    fi
    exit 0
  fi

  # shellcheck disable=SC1091
  source "${MAIN_REPO}/scripts/lib/rm-guard.sh" 2>/dev/null
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local ALLOWED_DIRS
    ALLOWED_DIRS="$(load_allowed_ext_dirs "${MAIN_REPO}")"
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${FP}" "${ALLOWED_DIRS}"; then
      exit 0
    fi
  fi

  deny "Write blocked outside worktrees: ${FP}. All code changes must happen in a worktree under worktree/, or add this path to ALLOWED_EXT_DIRS in .env (see .claude/skills/parallel-worktree/SKILL.md)."
}

main
