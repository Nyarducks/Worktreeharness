#!/bin/bash
# PreToolUse hook: Block reads outside the harness root — forces work through
# worktrees unless the path is in ALLOWED_EXT_DIRS (see .env.sample).
# Devin CLI variant: emits devin's {"decision":"block"} output format.
set -uo pipefail

deny() {
  local MSG="$1"
  jq -n --arg reason "${MSG}" '{decision:"block",reason:$reason}'
  exit 0
}

main() {
  local FP
  FP="$(jq -r '.tool_input.file_path // empty')"
  [[ -z "${FP}" ]] && exit 0

  FP="$(realpath -m "${FP}" 2>/dev/null || echo "${FP}")"

  # SCRIPT_ROOT = the checkout containing this script (scripts/lib/, .env).
  # HARNESS_ROOT = nearest ancestor holding both repos/ and worktree/ — works
  # whether the checkout IS the lab root or sits under <lab>/worktree/<repo>/<branch>.
  local SCRIPT_ROOT HARNESS_ROOT dir
  SCRIPT_ROOT="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  dir="${SCRIPT_ROOT}"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -d "${dir}/repos" && -d "${dir}/worktree" ]]; then
      HARNESS_ROOT="${dir}"
      break
    fi
    dir="$(dirname "${dir}")"
  done
  [[ -z "${HARNESS_ROOT:-}" ]] && HARNESS_ROOT="${SCRIPT_ROOT}"
  [[ -z "${HARNESS_ROOT}" || ! -d "${HARNESS_ROOT}" ]] && exit 0

  [[ "${FP}" == "${HARNESS_ROOT}" || "${FP}" == "${HARNESS_ROOT}/"* ]] && exit 0

  # shellcheck disable=SC1091
  source "${SCRIPT_ROOT}/scripts/lib/rm-guard.sh" 2>/dev/null
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local ALLOWED_DIRS
    ALLOWED_DIRS="$(load_allowed_ext_dirs "${HARNESS_ROOT}"; load_allowed_ext_dirs "${SCRIPT_ROOT}")"
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${FP}" "${ALLOWED_DIRS}"; then
      exit 0
    fi
  fi

  deny "Read blocked outside harness root: ${FP}. Work inside worktree/, or add this path to ALLOWED_EXT_DIRS in .env."
}

main
