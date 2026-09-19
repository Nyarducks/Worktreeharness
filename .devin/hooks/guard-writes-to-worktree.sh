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

# Output variable: MAIN_REPO
# Harness root = nearest ancestor of this script that holds both repos/ and
# worktree/. Walking up (rather than a fixed ../.. hop) keeps working whether
# the checkout IS the lab root or lives under <lab>/worktree/<repo>/<branch>.
resolve_main_repo() {
  local dir
  dir="$(realpath "$(dirname "$0")" 2>/dev/null)"
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

  local MAIN_REPO
  resolve_main_repo

  local WORKTREE_DIR="${MAIN_REPO}/worktree"
  if [[ "${FP}" == "${WORKTREE_DIR}"/* || "${FP}" == "${WORKTREE_DIR}" ]]; then
    exit 0
  fi

  # shellcheck disable=SC1091
  source "${MAIN_REPO}/scripts/lib/rm-guard.sh" 2>/dev/null
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local ALLOWED_DIRS
    ALLOWED_DIRS="$(load_allowed_ext_dirs "${MAIN_REPO}")"
    if [[ -n "${ALLOWED_DIRS}" ]] && ext_dir_is_allowed "${FP}" "${ALLOWED_DIRS}"; then
      exit 0
    fi
  fi

  deny "Write blocked outside worktrees: ${FP}. All code changes must happen in a worktree under worktree/, or add this path to ALLOWED_EXT_DIRS in .env (see .agents/skills/parallel-worktree/SKILL.md)."
}

main
