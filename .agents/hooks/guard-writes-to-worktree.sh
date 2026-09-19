#!/usr/bin/env bash
# PreToolUse hook for Antigravity CLI (agy):
# Block replace_file_content / write_to_file / multi_replace_file_content outside worktrees (worktree/)
# Forces all code changes through worktrees.
set -uo pipefail

deny() {
  local msg="$1"
  jq -n --arg reason "${msg}" '{decision:"deny",reason:$reason}'
  exit 0
}

# Output variables: script_root, main_repo
# script_root = the checkout containing this script (scripts/lib/, .env).
# main_repo = nearest ancestor holding both repos/ and worktree/ (the lab
# root). They differ when the checkout sits under <lab>/worktree/<repo>/<branch>.
resolve_main_repo() {
  script_root="$(realpath "$(dirname "$0")/../.." 2>/dev/null)"
  local dir="${script_root}"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -d "${dir}/worktree" && -d "${dir}/repos" ]]; then
      main_repo="${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  main_repo="${script_root}"
  if [[ -z "${main_repo}" || ! -d "${main_repo}" ]]; then
    deny "Write blocked: could not determine harness root from hook path ($0)."
  fi
}

main() {
  local input fp
  input="$(cat)"
  fp="$(jq -r '.toolCall.args.TargetFile // .toolCall.args.AbsolutePath // empty' <<< "${input}")"
  [[ -z "${fp}" ]] && exit 0

  fp="$(realpath -m "${fp}" 2>/dev/null || echo "${fp}")"

  local main_repo script_root
  resolve_main_repo

  local worktree_dir="${main_repo}/worktree"
  if [[ "${fp}" == "${worktree_dir}"/* || "${fp}" == "${worktree_dir}" ]]; then
    exit 0
  fi

  # Check ALLOWED_EXT_DIRS escape hatch
  # shellcheck disable=SC1091
  # shellcheck source=scripts/lib/rm-guard.sh
  source "${script_root}/scripts/lib/rm-guard.sh" 2>/dev/null || true
  if declare -F load_allowed_ext_dirs >/dev/null; then
    local allowed_dirs
    allowed_dirs="$(load_allowed_ext_dirs "${main_repo}"; load_allowed_ext_dirs "${script_root}")"
    if [[ -n "${allowed_dirs}" ]] && ext_dir_is_allowed "${fp}" "${allowed_dirs}"; then
      exit 0
    fi
  fi

  deny "Write blocked outside worktrees: ${fp}. All code changes must happen in a worktree under worktree/, or add this path to ALLOWED_EXT_DIRS in .env (see AGENTS.md)."
}

main
