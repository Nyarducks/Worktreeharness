#!/usr/bin/env bash
# PreToolUse hook: Block Read/Edit/Write outside the repository root and managed directories
set -uo pipefail

deny() {
  local msg="$1"
  jq -n --arg reason "${msg}" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

is_under() {
  local path_to_check="$1"
  local base="$2"
  [[ "${path_to_check}" == "${base}"/* || "${path_to_check}" == "${base}" ]]
}

main() {
  local fp
  fp="$(jq -r '.tool_input.file_path // empty')"
  [[ -z "${fp}" ]] && exit 0

  fp="$(realpath -m "${fp}" 2>/dev/null || echo "${fp}")"

  # script_root = the checkout containing this script (scripts/lib/, .env).
  # harness_root = nearest ancestor holding both repos/ and worktree/ — works
  # whether the checkout IS the lab root or sits under <lab>/worktree/<repo>/<branch>.
  local script_root harness_root dir
  script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  dir="${script_root}"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -d "${dir}/worktree" && -d "${dir}/repos" ]]; then
      harness_root="${dir}"
      break
    fi
    dir="$(dirname "${dir}")"
  done
  [[ -z "${harness_root:-}" ]] && harness_root="${script_root}"
  [[ -z "${harness_root}" || ! -d "${harness_root}" ]] && exit 0

  if is_under "${fp}" "${harness_root}"; then exit 0; fi

  # shellcheck disable=SC1091
  # shellcheck source=scripts/lib/rm-guard.sh
  source "${script_root}/scripts/lib/rm-guard.sh" 2>/dev/null
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local allowed_dirs
    allowed_dirs="$(load_allowed_ext_dirs "${harness_root}"; load_allowed_ext_dirs "${script_root}")"
    if [[ -n "${allowed_dirs}" ]] && ext_dir_is_allowed "${fp}" "${allowed_dirs}"; then
      exit 0
    fi
  fi

  deny "Access outside repository root blocked: ${fp}. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env (see AGENTS.md)."
}

main
