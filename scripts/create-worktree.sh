#!/usr/bin/env bash
# Usage: create-worktree.sh <[org/]repo-name> <branch-name>
#   repo-name:   MyRepo | owner/MyRepo
#   branch-name: feat/<topic> | fix/<issue> | refactor/<scope>
set -euo pipefail

usage() {
  echo "Usage: $0 <[org/]repo-name> <branch-name>" >&2
  echo "  Examples:" >&2
  echo "    $0 owner/MyRepo feat/my-feature" >&2
  echo "    $0 MyRepo feat/my-feature   # requires GH_ORG or existing clone" >&2
  exit 1
}

# Output variables: REPO_NAME, WORKTREE_PATH
compute_paths() {
  local REPO_PATH="$1"
  local BRANCH_NAME="$2"
  REPO_NAME="$(basename "${REPO_PATH}")"
  local LAB_DIR
  LAB_DIR="$(dirname "$(dirname "${REPO_PATH}")")"
  WORKTREE_PATH="${LAB_DIR}/worktree/${REPO_NAME}/${BRANCH_NAME}"
}

add_worktree() {
  local REPO_PATH="$1"
  local WORKTREE_PATH="$2"
  local BRANCH_NAME="$3"

  if [[ -d "${WORKTREE_PATH}" ]]; then
    echo "Error: worktree already exists at ${WORKTREE_PATH}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${WORKTREE_PATH}")"
  echo "Creating worktree for ${REPO_NAME} at ${WORKTREE_PATH} ..."
  git -C "${REPO_PATH}" worktree add "${WORKTREE_PATH}" -b "${BRANCH_NAME}" origin/main
}

install_hooks_if_present() {
  local REPO_PATH="$1"
  if [[ -f "${REPO_PATH}/scripts/setup-hooks.sh" ]]; then
    bash "${REPO_PATH}/scripts/setup-hooks.sh"
  fi
}

main() {
  [[ $# -ne 2 ]] && usage

  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local REPO_ARG="$1"
  local BRANCH_NAME="$2"

  local REPO_PATH
  REPO_PATH="$("${SCRIPT_DIR}/setup-repo.sh" "${REPO_ARG}")"

  local REPO_NAME WORKTREE_PATH
  compute_paths "${REPO_PATH}" "${BRANCH_NAME}"

  add_worktree "${REPO_PATH}" "${WORKTREE_PATH}" "${BRANCH_NAME}"
  install_hooks_if_present "${REPO_PATH}"

  echo ""
  echo "Done."
  echo "  Repo:   ${REPO_NAME}"
  echo "  Path:   ${WORKTREE_PATH}"
  echo "  Branch: ${BRANCH_NAME}"
}

main "$@"
