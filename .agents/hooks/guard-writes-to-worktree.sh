#!/bin/bash
# PreToolUse hook for Antigravity CLI (agy):
# Block replace_file_content / write_to_file / multi_replace_file_content outside worktrees (worktree/)
# Forces all code changes through worktrees.
set -uo pipefail

deny() {
  local MSG="$1"
  jq -n --arg reason "${MSG}" '{decision:"deny",reason:$reason}'
  exit 0
}

resolve_main_repo() {
  local DIR="$(realpath "$(dirname "$0")" 2>/dev/null)"
  while [[ -n "${DIR}" && "${DIR}" != "/" ]]; do
    if [[ -d "${DIR}/worktree" && -d "${DIR}/repos" ]]; then
      MAIN_REPO="${DIR}"
      return 0
    fi
    DIR="$(dirname "${DIR}")"
  done
  MAIN_REPO="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  if [[ -z "${MAIN_REPO}" || ! -d "${MAIN_REPO}" ]]; then
    deny "Write blocked: could not determine harness root from hook path ($0)."
  fi
}

main() {
  local INPUT FP
  INPUT="$(cat)"
  FP="$(jq -r '.toolCall.args.TargetFile // .toolCall.args.AbsolutePath // empty' <<< "${INPUT}")"
  [[ -z "${FP}" ]] && exit 0

  FP="$(realpath -m "${FP}" 2>/dev/null || echo "${FP}")"

  local MAIN_REPO
  resolve_main_repo

  local WORKTREE_DIR="${MAIN_REPO}/worktree"
  if [[ "${FP}" == "${WORKTREE_DIR}"/* || "${FP}" == "${WORKTREE_DIR}" ]]; then
    exit 0
  fi

  # Check ALLOWED_EXT_DIRS escape hatch
  # shellcheck disable=SC1091
  source "${MAIN_REPO}/scripts/lib/rm-guard.sh" 2>/dev/null || true
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local ALLOWED_DIRS
    ALLOWED_DIRS="$(load_allowed_ext_dirs "${MAIN_REPO}")"
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${FP}" "${ALLOWED_DIRS}"; then
      exit 0
    fi
  fi

  deny "Write blocked outside worktrees: ${FP}. All code changes must happen in a worktree under worktree/, or add this path to ALLOWED_EXT_DIRS in .env (see AGENTS.md)."
}

main
