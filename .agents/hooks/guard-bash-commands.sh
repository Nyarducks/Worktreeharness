#!/usr/bin/env bash
# PreToolUse hook (antigravity): guard run_command — dangerous `rm` plus
# paths outside the harness root. Shared logic: scripts/lib/hook-common.sh.
set -uo pipefail

script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
# shellcheck source=scripts/lib/hook-common.sh
source "${script_root}/scripts/lib/hook-common.sh" 2>/dev/null || exit 0

hook_main_command agy '.toolCall.args.CommandLine' '.toolCall.args.Cwd'
