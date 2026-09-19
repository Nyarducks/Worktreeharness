#!/usr/bin/env bash
# PreToolUse hook for Antigravity CLI (agy):
# Block view_file outside repository root and managed directories
set -uo pipefail

deny() {
  local msg="$1"
  jq -n --arg reason "${msg}" '{decision:"deny",reason:$reason}'
  exit 0
}

is_under() {
  local path_to_check="$1"
  local base="$2"
  [[ "${path_to_check}" == "${base}"/* || "${path_to_check}" == "${base}" ]]
}

# Output variables: script_root, harness_root
# script_root = the checkout containing this script (scripts/lib/, .env).
# harness_root = nearest ancestor holding both repos/ and worktree/.
resolve_harness_root() {
  script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  local dir="${script_root}"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -d "${dir}/worktree" && -d "${dir}/repos" ]]; then
      harness_root="${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  harness_root="${script_root}"
}

main() {
  local input fp
  input="$(cat)"
  fp="$(jq -r '.toolCall.args.AbsolutePath // .toolCall.args.TargetFile // empty' <<< "${input}")"
  [[ -z "${fp}" ]] && exit 0

  fp="$(realpath -m "${fp}" 2>/dev/null || echo "${fp}")"

  local script_root harness_root
  resolve_harness_root
  [[ -z "${harness_root}" || ! -d "${harness_root}" ]] && exit 0

  if is_under "${fp}" "${harness_root}"; then exit 0; fi

  # shellcheck disable=SC1091
  source "${script_root}/scripts/lib/rm-guard.sh" 2>/dev/null || true
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local allowed_dirs
    allowed_dirs="$(load_allowed_ext_dirs "${harness_root}"; load_allowed_ext_dirs "${script_root}")"
    if [[ -n "${allowed_dirs}" ]] && ext_dir_is_allowed "${fp}" "${allowed_dirs}"; then
      exit 0
    fi
  fi

  deny "Access outside repository root blocked: ${fp}. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env."
}

main
