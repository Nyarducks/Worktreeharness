#!/bin/bash
# PreToolUse hook for Antigravity CLI (agy):
# Block view_file outside repository root and managed directories
set -uo pipefail

deny() {
  local MSG="$1"
  jq -n --arg reason "${MSG}" '{decision:"deny",reason:$reason}'
  exit 0
}

is_under() {
  local PATH_TO_CHECK="$1"
  local BASE="$2"
  [[ "${PATH_TO_CHECK}" == "${BASE}"/* || "${PATH_TO_CHECK}" == "${BASE}" ]]
}

resolve_harness_root() {
  local DIR="$(realpath "$(dirname "$0")" 2>/dev/null)"
  while [[ -n "${DIR}" && "${DIR}" != "/" ]]; do
    if [[ -d "${DIR}/worktree" && -d "${DIR}/repos" ]]; then
      HARNESS_ROOT="${DIR}"
      return 0
    fi
    DIR="$(dirname "${DIR}")"
  done
  HARNESS_ROOT="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
}

main() {
  local INPUT FP
  INPUT="$(cat)"
  FP="$(jq -r '.toolCall.args.AbsolutePath // .toolCall.args.TargetFile // empty' <<< "${INPUT}")"
  [[ -z "${FP}" ]] && exit 0

  FP="$(realpath -m "${FP}" 2>/dev/null || echo "${FP}")"

  local HARNESS_ROOT
  resolve_harness_root
  [[ -z "${HARNESS_ROOT}" || ! -d "${HARNESS_ROOT}" ]] && exit 0

  if is_under "${FP}" "${HARNESS_ROOT}"; then exit 0; fi

  # shellcheck disable=SC1091
  source "${HARNESS_ROOT}/scripts/lib/rm-guard.sh" 2>/dev/null || true
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local ALLOWED_DIRS
    ALLOWED_DIRS="$(load_allowed_ext_dirs "${HARNESS_ROOT}")"
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${FP}" "${ALLOWED_DIRS}"; then
      exit 0
    fi
  fi

  deny "Access outside repository root blocked: ${FP}. Use repos/ for base clones and worktree/ for active worktrees, or add this path to ALLOWED_EXT_DIRS in .env."
}

main
