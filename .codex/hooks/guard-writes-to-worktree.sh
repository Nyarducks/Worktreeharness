#!/usr/bin/env bash
# PreToolUse hook (codex): guard apply_patch — every Add/Update/Delete/Move
# target must land under worktree/. Shared logic: scripts/lib/hook-common.sh.
set -uo pipefail

script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
# shellcheck source=scripts/lib/hook-common.sh
source "${script_root}/scripts/lib/hook-common.sh" 2>/dev/null || exit 0

main() {
  local input patch reason
  input="$(cat)"
  patch="$(jq -r '.tool_input.command // empty' <<< "${input}")"
  [[ -z "${patch}" ]] && exit 0

  # apply_patch paths are repo-relative — resolve them against the harness
  # root, and strip the a/ b/ prefixes git-style paths carry.
  reason="$(
    sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p; s/^\*\*\* Move to: (.*)$/\1/p' <<< "${patch}" \
      | sed -E 's|^a/||; s|^b/||' \
      | hook_guard_paths worktree "$(hook_harness_root "${script_root}")"
  )"
  [[ -n "${reason}" ]] && hook_deny_json codex "${reason}"
  exit 0
}

main "$@"
