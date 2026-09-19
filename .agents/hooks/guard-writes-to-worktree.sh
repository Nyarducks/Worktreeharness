#!/usr/bin/env bash
# PreToolUse hook (antigravity): block replace_file_content /
# write_to_file / multi_replace_file_content outside worktrees.
# Shared logic: scripts/lib/hook-common.sh.
set -uo pipefail

script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
# shellcheck source=scripts/lib/hook-common.sh
source "${script_root}/scripts/lib/hook-common.sh" 2>/dev/null || exit 0

hook_main_file agy '.toolCall.args.TargetFile // .toolCall.args.AbsolutePath' worktree
