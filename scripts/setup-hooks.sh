#!/usr/bin/env bash
# Install git hooks as symlinks into the common git dir.
# Safe to call from both the main repo and any worktree.
set -euo pipefail

# Output variables: repo_root, git_common_dir
resolve_git_dirs() {
  local script_dir="$1"
  repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
  git_common_dir="$(git -C "${repo_root}" rev-parse --git-common-dir)"
  if [[ "${git_common_dir}" != /* ]]; then
    git_common_dir="${repo_root}/${git_common_dir}"
  fi
}

install_hooks() {
  mkdir -p "${git_common_dir}/hooks"
  local hook name
  for hook in "${repo_root}"/scripts/hooks/*; do
    [[ -f "${hook}" ]] || continue
    name="$(basename "${hook}")"
    ln -sf "${hook}" "${git_common_dir}/hooks/${name}"
  done
  echo "git hooks installed"
}

main() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local repo_root git_common_dir
  resolve_git_dirs "${script_dir}"
  install_hooks
}

main "$@"
