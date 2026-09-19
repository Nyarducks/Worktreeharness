#!/usr/bin/env bash
# PreToolUse hook (devin): block reads outside the harness root — work goes
# through worktree/ unless the path is in ALLOWED_EXT_DIRS (.env.sample).
# Shared logic: scripts/lib/hook-common.sh.
set -uo pipefail

script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
# shellcheck source=scripts/lib/hook-common.sh
source "${script_root}/scripts/lib/hook-common.sh" 2>/dev/null || exit 0

hook_main_file devin '.tool_input.file_path' harness
