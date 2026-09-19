#!/usr/bin/env bash
# PreToolUse hook: Block reads outside the harness root — forces work through
# worktrees unless the path is in ALLOWED_EXT_DIRS (see .env.sample).
# Devin CLI variant: emits devin's {"decision":"block"} output format.
set -uo pipefail

deny() {
  local msg="$1"
  jq -n --arg reason "${msg}" '{decision:"block",reason:$reason}'
  exit 0
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
    if [[ -d "${dir}/repos" && -d "${dir}/worktree" ]]; then
      harness_root="${dir}"
      break
    fi
    dir="$(dirname "${dir}")"
  done
  [[ -z "${harness_root:-}" ]] && harness_root="${script_root}"
  [[ -z "${harness_root}" || ! -d "${harness_root}" ]] && exit 0

  [[ "${fp}" == "${harness_root}" || "${fp}" == "${harness_root}/"* ]] && exit 0

  # shellcheck disable=SC1091
  source "${script_root}/scripts/lib/rm-guard.sh" 2>/dev/null
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local allowed_dirs
    allowed_dirs="$(load_allowed_ext_dirs "${harness_root}"; load_allowed_ext_dirs "${script_root}")"
    if [[ -n "${allowed_dirs}" ]] && ext_dir_is_allowed "${fp}" "${allowed_dirs}"; then
      exit 0
    fi
  fi

  deny "Read blocked outside harness root: ${fp}. Work inside worktree/, or add this path to ALLOWED_EXT_DIRS in .env."
}

main
