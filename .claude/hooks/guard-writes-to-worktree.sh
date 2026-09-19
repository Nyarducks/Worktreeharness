#!/bin/bash
# PreToolUse hook: Block Edit/Write outside worktrees (worktree/) — forces all code changes through worktrees
set -uo pipefail

deny() {
  local MSG="$1"
  jq -n --arg reason "${MSG}" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

# Output variables: SCRIPT_ROOT, MAIN_REPO
# SCRIPT_ROOT = the checkout containing this script — scripts/lib/ and .env
# live there. MAIN_REPO = nearest ancestor holding both repos/ and worktree/
# (the lab root) — works whether the checkout IS the lab root or sits under
# <lab>/worktree/<repo>/<branch>. They differ in a split layout.
resolve_main_repo() {
  SCRIPT_ROOT="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  local DIR="${SCRIPT_ROOT}"
  while [[ -n "${DIR}" && "${DIR}" != "/" ]]; do
    if [[ -d "${DIR}/worktree" && -d "${DIR}/repos" ]]; then
      MAIN_REPO="${DIR}"
      return 0
    fi
    DIR="$(dirname "${DIR}")"
  done
  MAIN_REPO="${SCRIPT_ROOT}"
  if [[ -z "${MAIN_REPO}" || ! -d "${MAIN_REPO}" ]]; then
    deny "Write blocked: could not determine harness root from hook path ($0)."
  fi
}

main() {
  local FP
  FP="$(jq -r '.tool_input.file_path // empty')"
  [[ -z "${FP}" ]] && exit 0

  FP="$(realpath -m "${FP}" 2>/dev/null || echo "${FP}")"

  local MAIN_REPO SCRIPT_ROOT
  resolve_main_repo

  local WORKTREE_DIR="${MAIN_REPO}/worktree"
  if [[ "${FP}" == "${WORKTREE_DIR}"/* || "${FP}" == "${WORKTREE_DIR}" ]]; then
    exit 0
  fi

  # shellcheck disable=SC1091
  source "${SCRIPT_ROOT}/scripts/lib/rm-guard.sh" 2>/dev/null
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local ALLOWED_DIRS
    ALLOWED_DIRS="$(load_allowed_ext_dirs "${MAIN_REPO}"; load_allowed_ext_dirs "${SCRIPT_ROOT}")"
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${FP}" "${ALLOWED_DIRS}"; then
      exit 0
    fi
  fi

  deny "Write blocked outside worktrees: ${FP}. All code changes must happen in a worktree under worktree/, or add this path to ALLOWED_EXT_DIRS in .env (see AGENTS.md)."
}

main
