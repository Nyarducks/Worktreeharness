#!/usr/bin/env bash
# Install git hooks as symlinks into the common git dir.
# Safe to call from both the main repo and any worktree.
set -euo pipefail

# Output variables: REPO_ROOT, GIT_COMMON_DIR
resolve_git_dirs() {
  local SCRIPT_DIR="$1"
  REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
  GIT_COMMON_DIR="$(git -C "${REPO_ROOT}" rev-parse --git-common-dir)"
  if [[ "${GIT_COMMON_DIR}" != /* ]]; then
    GIT_COMMON_DIR="${REPO_ROOT}/${GIT_COMMON_DIR}"
  fi
}

install_hooks() {
  mkdir -p "${GIT_COMMON_DIR}/hooks"
  ln -sf "${REPO_ROOT}/scripts/hooks/pre-commit" "${GIT_COMMON_DIR}/hooks/pre-commit"
  echo "git hooks installed"
}

main() {
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local REPO_ROOT GIT_COMMON_DIR
  resolve_git_dirs "${SCRIPT_DIR}"
  install_hooks
}

main "$@"
