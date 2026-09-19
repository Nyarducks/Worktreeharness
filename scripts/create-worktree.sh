#!/usr/bin/env bash
# Usage: create-worktree.sh [--detach] <[org/]repo-name> <name>
#   repo-name:   MyRepo | owner/MyRepo
#   name:        feat/<topic> | fix/<issue> | refactor/<scope> | task/<uuid>
#   --detach:    create the worktree with a detached HEAD at origin/main
#                instead of creating a branch named <name>
set -euo pipefail

usage() {
  echo "Usage: $0 [--detach] <[org/]repo-name> <name>" >&2
  echo "  Examples:" >&2
  echo "    $0 owner/MyRepo feat/my-feature" >&2
  echo "    $0 MyRepo feat/my-feature   # requires GH_ORG or existing clone" >&2
  echo "    $0 --detach owner/MyRepo task/abc123   # detached HEAD at origin/main" >&2
  exit 1
}

# Output variables: repo_name, worktree_path
compute_paths() {
  local repo_path="$1"
  local name="$2"
  repo_name="$(basename "${repo_path}")"
  local lab_dir
  lab_dir="$(dirname "$(dirname "${repo_path}")")"
  worktree_path="${lab_dir}/worktree/${repo_name}/${name}"
}

add_worktree() {
  local repo_path="$1"
  local worktree_path="$2"
  local name="$3"
  local detach="$4"

  if [[ -d "${worktree_path}" ]]; then
    echo "Error: worktree already exists at ${worktree_path}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${worktree_path}")"
  echo "Creating worktree for ${repo_name} at ${worktree_path} ..."
  if [[ "${detach}" -eq 1 ]]; then
    git -C "${repo_path}" worktree add --detach "${worktree_path}" origin/main
  else
    git -C "${repo_path}" worktree add "${worktree_path}" -b "${name}" origin/main
  fi
}

install_hooks_if_present() {
  local repo_path="$1"
  if [[ -f "${repo_path}/scripts/setup-hooks.sh" ]]; then
    bash "${repo_path}/scripts/setup-hooks.sh"
  fi
}

install_harness_hooks() {
  local repo_path="$1"
  local hooks_src
  hooks_src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hooks"
  local hooks_dst="${repo_path}/.git/hooks"
  [[ -d "${hooks_src}" ]] || return 0
  for hook in "${hooks_src}"/*; do
    local name
    name="$(basename "${hook}")"
    if [[ ! -f "${hooks_dst}/${name}" ]]; then
      cp "${hook}" "${hooks_dst}/${name}"
      chmod +x "${hooks_dst}/${name}"
    fi
  done
}

main() {
  local detach=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --detach) detach=1; shift ;;
      *) break ;;
    esac
  done
  [[ $# -ne 2 ]] && usage

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local repo_arg="$1"
  local name="$2"

  local repo_path
  repo_path="$("${script_dir}/setup-repo.sh" "${repo_arg}")"

  local repo_name worktree_path
  compute_paths "${repo_path}" "${name}"

  add_worktree "${repo_path}" "${worktree_path}" "${name}" "${detach}"
  install_hooks_if_present "${repo_path}"
  install_harness_hooks "${repo_path}"

  echo ""
  echo "Done."
  echo "  Repo:   ${repo_name}"
  echo "  Path:   ${worktree_path}"
  if [[ "${detach}" -eq 1 ]]; then
    echo "  HEAD:   detached at origin/main"
  else
    echo "  Branch: ${name}"
  fi
}

main "$@"
