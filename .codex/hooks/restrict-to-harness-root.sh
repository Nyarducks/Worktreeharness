#!/usr/bin/env bash
set -euo pipefail

deny() {
  local reason="$1"
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"${reason}"'"}}'
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

is_system_path() {
  case "$1" in
    /bin/*|/usr/bin/*|/usr/local/bin/*|/dev/null) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  local input command cwd harness_root candidate target
  input="$(cat)"
  command="$(jq -r '.tool_input.command // empty' <<< "$input")"
  cwd="$(jq -r '.cwd // empty' <<< "$input")"
  harness_root="$(realpath -m "$(resolve_harness_root)")"
  cwd="${cwd:-$harness_root}"

  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    if [[ "$candidate" = /* ]]; then
      target="$(realpath -m "$candidate")"
    else
      target="$(realpath -m "$cwd/$candidate")"
    fi

    if is_system_path "$target"; then
      continue
    fi
    if [[ "$target" != "$harness_root" && "$target" != "$harness_root/"* ]]; then
      deny "Access outside harness root blocked: ${target}. Use repos/ for base clones and worktree/ for active worktrees."
      exit 0
    fi
  done < <(
    tr -c '[:alnum:]_./:+%@=-' '\n' <<< "$command" |
      awk '/^\// || /^\.\.?\//'
  )
}

main "$@"
