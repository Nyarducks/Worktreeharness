#!/bin/bash
# PreToolUse hook: Block writes outside worktrees (worktree/) — forces all
# code changes through worktrees.
# Devin CLI variant: emits devin's {"decision":"block"} output format.
set -uo pipefail

deny() {
  local MSG="$1"
  jq -n --arg reason "${MSG}" '{decision:"block",reason:$reason}'
  exit 0
}

# Output variables: SCRIPT_ROOT, MAIN_REPO
# SCRIPT_ROOT = the checkout containing this script — scripts/lib/ and .env
# live there. MAIN_REPO = nearest ancestor holding both repos/ and worktree/
# (the lab root). They differ when the checkout sits under
# <lab>/worktree/<repo>/<branch>.
resolve_main_repo() {
  local dir
  SCRIPT_ROOT="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  dir="${SCRIPT_ROOT}"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -d "${dir}/repos" && -d "${dir}/worktree" ]]; then
      MAIN_REPO="${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  deny "Write blocked: could not find a harness root (a directory holding both repos/ and worktree/) above $0."
}

main() {
  local FP
  FP="$(jq -r '.tool_input.file_path // empty')"
  [[ -z "${FP}" ]] && exit 0

  FP="$(realpath -m "${FP}" 2>/dev/null || echo "${FP}")"

  local MAIN_REPO SCRIPT_ROOT
  resolve_main_repo

  local WORKTREE_DIR="${MAIN_REPO}/worktree"
  if [[ "${FP}" == "${WORKTREE_DIR}"/* || "${FP}" == "${WORKTREE_DIR}" ]]; then
    exit 0
  fi

  # shellcheck disable=SC1091
  source "${SCRIPT_ROOT}/scripts/lib/rm-guard.sh" 2>/dev/null
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local ALLOWED_DIRS
    ALLOWED_DIRS="$(load_allowed_ext_dirs "${MAIN_REPO}"; load_allowed_ext_dirs "${SCRIPT_ROOT}")"
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${FP}" "${ALLOWED_DIRS}"; then
      exit 0
    fi
  fi

  deny "Write blocked outside worktrees: ${FP}. All code changes must happen in a worktree under worktree/, or add this path to ALLOWED_EXT_DIRS in .env (see AGENTS.md)."
}

main
