#!/bin/bash
# PreToolUse hook: Block Read/Edit/Write outside the repository root and managed directories

fp=$(jq -r '.tool_input.file_path // empty')
[ -z "$fp" ] && exit 0

fp=$(realpath -m "$fp" 2>/dev/null || echo "$fp")

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$repo_root" ] && exit 0

[[ "$fp" == "$repo_root"/* || "$fp" == "$repo_root" ]] && exit 0

main_repo=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')

# Allow worktrees under worktree/
[[ -n "$main_repo" && "$fp" == "$main_repo/worktree"/* ]] && exit 0

# Allow base clones under repos/ (read-only investigation)
[[ -n "$main_repo" && "$fp" == "$main_repo/repos"/* ]] && exit 0

# Allow the main harness root itself
[[ -n "$main_repo" && ( "$fp" == "$main_repo"/* || "$fp" == "$main_repo" ) ]] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Access outside repository root blocked: %s. Use repos/ for base clones and worktree/ for active worktrees (see .claude/skills/parallel-worktree/SKILL.md)."}}\n' "$fp"
