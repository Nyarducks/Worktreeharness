#!/bin/bash
# PreToolUse hook: Block Edit/Write outside worktrees (worktree/) — forces all code changes through worktrees

fp=$(jq -r '.tool_input.file_path // empty')
[ -z "$fp" ] && exit 0

fp=$(realpath -m "$fp" 2>/dev/null || echo "$fp")

if [ -n "$WORKTREE_LAB_DIR" ]; then
    main_repo="$WORKTREE_LAB_DIR"
    if [ ! -d "$main_repo" ]; then
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Write blocked: WORKTREE_LAB_DIR=%s is invalid (directory not found). Fix the env var or unset it to use auto-detection."}}\n' "$main_repo"
        exit 0
    fi
else
    main_repo=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
    if [ -z "$main_repo" ]; then
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Write blocked: could not determine repository root. Create a worktree under worktree/ first (see .claude/skills/parallel-worktree/SKILL.md)."}}\n'
        exit 0
    fi
fi

worktree_dir="$main_repo/worktree"

[[ "$fp" == "$worktree_dir"/* || "$fp" == "$worktree_dir" ]] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Write blocked outside worktrees: %s. All code changes must happen in a worktree under worktree/ (see .claude/skills/parallel-worktree/SKILL.md)."}}\n' "$fp"
