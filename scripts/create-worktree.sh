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

[[ $# -ne 2 ]] && usage

REPO_ARG="$1"
BRANCH_NAME="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_PATH=$("$SCRIPT_DIR/setup-repo.sh" "$REPO_ARG")

LAB_DIR="$(dirname "$(dirname "$REPO_PATH")")"
REPO_NAME="$(basename "$REPO_PATH")"
WORKTREE_DIR="$LAB_DIR/worktree"
WORKTREE_PATH="$WORKTREE_DIR/$REPO_NAME/$BRANCH_NAME"

if [[ -d "$WORKTREE_PATH" ]]; then
  echo "Error: worktree already exists at $WORKTREE_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$WORKTREE_PATH")"

echo "Creating worktree for $REPO_NAME at $WORKTREE_PATH ..."
git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" origin/main

if [[ -f "$REPO_PATH/scripts/setup-hooks.sh" ]]; then
  bash "$REPO_PATH/scripts/setup-hooks.sh"
fi

echo ""
echo "Done."
echo "  Repo:   $REPO_NAME"
echo "  Path:   $WORKTREE_PATH"
echo "  Branch: $BRANCH_NAME"
