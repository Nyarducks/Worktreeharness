#!/usr/bin/env bash
set -euo pipefail

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
}

resolve_harness_root() {
  local script_root base_repo
  script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

  base_repo="$(git -C "$script_root" worktree list --porcelain 2>/dev/null | awk '/^worktree / {print substr($0, 10); exit}')"
  if [[ -n "$base_repo" && "$(basename "$(dirname "$base_repo")")" == "repos" ]]; then
    dirname "$(dirname "$base_repo")"
    return
  fi

  printf '%s\n' "$script_root"
}

main() {
  local input patch harness_root worktree_root path target
  input="$(cat)"
  patch="$(jq -r '.tool_input.command // empty' <<< "$input")"
  harness_root="$(resolve_harness_root)"
  worktree_root="$(realpath -m "$harness_root/worktree")"

  local allowed_dirs=""
  # shellcheck disable=SC1091
  source "$harness_root/scripts/lib/rm-guard.sh" 2>/dev/null || true
  if declare -F load_allowed_ext_dirs > /dev/null; then
    allowed_dirs="$(load_allowed_ext_dirs "$harness_root")"
  fi

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    path="${path#a/}"
    path="${path#b/}"
    if [[ "$path" = /* ]]; then
      target="$(realpath -m "$path")"
    else
      target="$(realpath -m "$harness_root/$path")"
    fi

    if [[ "$target" != "$worktree_root" && "$target" != "$worktree_root/"* ]]; then
      if [[ -n "$allowed_dirs" ]] && ext_dir_is_allowed "$target" "$allowed_dirs"; then
        continue
      fi
      deny "Write blocked outside worktrees: ${target}. Create or resume a worktree under ${worktree_root}, or add this path to ALLOWED_EXT_DIRS in .env."
      exit 0
    fi
  done < <(
    sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p; s/^\*\*\* Move to: (.*)$/\1/p' <<< "$patch"
  )
}

main "$@"
