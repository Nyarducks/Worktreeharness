#!/usr/bin/env bash
# Install git hooks as symlinks into the common git dir.
# Safe to call from both the main repo and any worktree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
GIT_COMMON_DIR="$(git -C "$REPO_ROOT" rev-parse --git-common-dir)"

if [[ "$GIT_COMMON_DIR" != /* ]]; then
  GIT_COMMON_DIR="$REPO_ROOT/$GIT_COMMON_DIR"
fi

mkdir -p "$GIT_COMMON_DIR/hooks"
ln -sf "$REPO_ROOT/scripts/hooks/pre-commit" "$GIT_COMMON_DIR/hooks/pre-commit"
echo "git hooks installed"
