#!/usr/bin/env bash
# PreToolUse hook (claude): block Edit/Write outside worktrees — all code
# changes go through worktree/. Shared logic: scripts/lib/hook-common.sh.
set -uo pipefail

script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
# shellcheck source=scripts/lib/hook-common.sh
source "${script_root}/scripts/lib/hook-common.sh" 2>/dev/null || exit 0

hook_main_file claude '.tool_input.file_path' worktree
