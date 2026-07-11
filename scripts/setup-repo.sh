#!/usr/bin/env bash
# Usage: setup-repo.sh <[org/]repo-name>
#
# Clones the repository into $LAB/repos/<repo-name>/ if not present,
# or fetches and fast-forwards to the latest main if it already exists.
# Prints the absolute path to the repository on stdout.
#
# Org resolution order:
#   1. <org>/<repo> syntax in the first argument
#   2. GH_ORG environment variable
#   3. git remote URL of existing clone
set -euo pipefail

# Output variables set by parse_repo_arg
GH_ORG=""
REPO_NAME=""

usage() {
  echo "Usage: $0 <[org/]repo-name>" >&2
  echo "  Examples:" >&2
  echo "    $0 owner/MyRepo" >&2
  echo "    $0 MyRepo   # requires GH_ORG or existing clone" >&2
  exit 1
}

parse_repo_arg() {
  local ARG="$1"
  if [[ "${ARG}" == */* ]]; then
    GH_ORG="${ARG%%/*}"
    REPO_NAME="${ARG##*/}"
  else
    GH_ORG="${GH_ORG:-}"
    REPO_NAME="${ARG}"
  fi
}

# Output variable: LAB_DIR
find_lab_dir() {
  local SCRIPT_DIR="$1"
  if [[ -n "${WORKTREE_LAB_DIR:-}" ]]; then
    LAB_DIR="${WORKTREE_LAB_DIR}"
    return
  fi
  LAB_DIR="${SCRIPT_DIR}"
  while [[ "${LAB_DIR}" != "/" && ! -d "${LAB_DIR}/repos" ]]; do
    LAB_DIR="$(dirname "${LAB_DIR}")"
  done
  if [[ ! -d "${LAB_DIR}/repos" ]]; then
    LAB_DIR="$(dirname "${SCRIPT_DIR}")"
    mkdir -p "${LAB_DIR}/repos"
  fi
}

clone_repo() {
  local REPO_PATH="$1"
  if [[ -z "${GH_ORG}" ]]; then
    echo "Error: cannot determine GitHub org." >&2
    echo "  Use '<org>/<repo>' syntax or set the GH_ORG environment variable." >&2
    exit 1
  fi
  echo "Cloning ${GH_ORG}/${REPO_NAME} into ${REPO_PATH} ..." >&2
  gh repo clone "${GH_ORG}/${REPO_NAME}" "${REPO_PATH}" >&2
}

update_repo() {
  local REPO_PATH="$1"
  if [[ -z "${GH_ORG}" ]]; then
    GH_ORG="$(git -C "${REPO_PATH}" remote get-url origin \
      | sed 's|.*github\.com[:/]\([^/]*\)/.*|\1|')"
  fi
  echo "Updating ${REPO_NAME} ..." >&2
  git -C "${REPO_PATH}" fetch origin main >&2
  git -C "${REPO_PATH}" pull --ff-only origin main >&2
}

main() {
  [[ $# -ne 1 ]] && usage

  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  parse_repo_arg "$1"

  local LAB_DIR
  find_lab_dir "${SCRIPT_DIR}"

  local REPO_PATH="${LAB_DIR}/repos/${REPO_NAME}"

  if [[ ! -d "${REPO_PATH}/.git" ]]; then
    clone_repo "${REPO_PATH}"
  else
    update_repo "${REPO_PATH}"
  fi

  echo "${REPO_PATH}"
}

main "$@"
