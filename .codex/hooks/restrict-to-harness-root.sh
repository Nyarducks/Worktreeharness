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

  # shellcheck disable=SC1091
  source "$harness_root/scripts/lib/rm-guard.sh" 2>/dev/null || true

  # Always-on safety net: never allow a recursive rm on $HOME, /, or another
  # critical directory, even when ALLOW_EXTERNAL_DIR=true.
  if declare -F rm_guard_dangerous_reason > /dev/null; then
    local rm_reason
    rm_reason="$(rm_guard_dangerous_reason "$command" "$cwd")"
    if [[ -n "$rm_reason" ]]; then
      deny "$rm_reason"
      exit 0
    fi
  fi

  if [[ -f "$harness_root/.env" ]]; then
    # shellcheck disable=SC1090
    source "$harness_root/.env"
  fi
  if [[ "${ALLOW_EXTERNAL_DIR:-false}" == "true" ]]; then
    exit 0
  fi

  local allowed_dirs=""
  if declare -F load_allowed_ext_dirs > /dev/null; then
    allowed_dirs="$(load_allowed_ext_dirs "$harness_root")"
  fi

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
      if [[ -n "$allowed_dirs" ]] && ext_dir_is_allowed "$target" "$allowed_dirs"; then
        continue
      fi
      deny "Access outside harness root blocked: ${target}. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env."
      exit 0
    fi
  done < <(
    tr -c '[:alnum:]_./:+%@=-' '\n' <<< "$command" |
      awk '/^\// || /^\.\.?\//'
  )
}

main "$@"
