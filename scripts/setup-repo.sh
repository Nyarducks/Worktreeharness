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

usage() {
  echo "Usage: $0 <[org/]repo-name>" >&2
  echo "  Examples:" >&2
  echo "    $0 owner/MyRepo" >&2
  echo "    $0 MyRepo   # requires GH_ORG or existing clone" >&2
  exit 1
}

[[ $# -ne 1 ]] && usage

REPO_ARG="$1"

if [[ "$REPO_ARG" == */* ]]; then
  GH_ORG="${REPO_ARG%%/*}"
  REPO_NAME="${REPO_ARG##*/}"
else
  GH_ORG="${GH_ORG:-}"
  REPO_NAME="$REPO_ARG"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="${WORKTREE_LAB_DIR:-}"

if [[ -z "$LAB_DIR" ]]; then
  LAB_DIR="$SCRIPT_DIR"
  while [[ "$LAB_DIR" != "/" && ! -d "$LAB_DIR/repos" ]]; do
    LAB_DIR="$(dirname "$LAB_DIR")"
  done
  if [[ ! -d "$LAB_DIR/repos" ]]; then
    LAB_DIR="$(dirname "$SCRIPT_DIR")"
    mkdir -p "$LAB_DIR/repos"
  fi
fi

REPO_PATH="$LAB_DIR/repos/$REPO_NAME"

if [[ ! -d "$REPO_PATH/.git" ]]; then
  if [[ -z "$GH_ORG" ]]; then
    echo "Error: cannot determine GitHub org." >&2
    echo "  Use '<org>/<repo>' syntax or set the GH_ORG environment variable." >&2
    exit 1
  fi
  echo "Cloning $GH_ORG/$REPO_NAME into $REPO_PATH ..." >&2
  gh repo clone "$GH_ORG/$REPO_NAME" "$REPO_PATH" >&2
else
  if [[ -z "$GH_ORG" ]]; then
    GH_ORG=$(git -C "$REPO_PATH" remote get-url origin \
      | sed 's|.*github\.com[:/]\([^/]*\)/.*|\1|')
  fi
  echo "Updating $REPO_NAME ..." >&2
  git -C "$REPO_PATH" fetch origin main >&2
  git -C "$REPO_PATH" pull --ff-only origin main >&2
fi

echo "$REPO_PATH"
