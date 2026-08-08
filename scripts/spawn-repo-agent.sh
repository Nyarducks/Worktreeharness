#!/usr/bin/env bash
# Usage: spawn-repo-agent.sh <[org/]repo-name> <branch-name> -- <task text...>
#
# Orchestrator-side helper: creates (or reuses) a worktree for <repo>/<branch>,
# spawns a dedicated Claude Code process there via herdr (so that repo's own
# .claude/skills and CLAUDE.md load correctly), and hands it the task framed
# with the cross-repo reporting protocol. See .claude/skills/herdr-dispatch.
set -euo pipefail

usage() {
  echo "Usage: $0 <[org/]repo-name> <branch-name> -- <task text...>" >&2
  exit 1
}

require_herdr() {
  command -v herdr > /dev/null 2>&1 || {
    echo "Error: herdr not found on PATH. Fall back to /parallel-worktree instead." >&2
    exit 1
  }
  [[ "${HERDR_ENV:-}" == "1" ]] || {
    echo "Error: not running inside a herdr session (HERDR_ENV is unset)." >&2
    exit 1
  }
  [[ -n "${HERDR_PANE_ID:-}" ]] || {
    echo "Error: HERDR_PANE_ID is not set." >&2
    exit 1
  }
}

# find_existing_pane <worktree_path>
# Prints the pane_id of a herdr agent already running with that cwd, if any.
find_existing_pane() {
  local worktree_path="$1"
  herdr agent list 2>/dev/null |
    jq -r --arg cwd "${worktree_path}" '.result.agents[]? | select(.cwd == $cwd) | .pane_id' |
    head -n1
}

build_message() {
  local repo_name="$1" branch_name="$2" worktree_path="$3" orchestrator_pane="$4" task_text="$5"
  cat <<MSG
[ORCHESTRATOR TASK]
You were spawned via herdr for repo ${repo_name} on branch ${branch_name} (worktree: ${worktree_path}).
Orchestrator herdr pane: ${orchestrator_pane}

Task:
${task_text}

Rules:
- Work only inside this worktree, following this repo's own CLAUDE.md/AGENTS.md and skill conventions.
- If this task needs changes in a DIFFERENT repository, do NOT edit that repository yourself. Instead run:
    herdr agent send ${orchestrator_pane} "[CROSS-REPO-REQUEST] repo=<owner/repo> branch=<suggested-branch> from=\$HERDR_PANE_ID task=<description>"
  and continue your own work — never spawn other repos' agents yourself.
- When you finish, run:
    herdr agent send ${orchestrator_pane} "[TASK-DONE] from=\$HERDR_PANE_ID summary=<one paragraph>"
- If you get stuck and need a human, run:
    herdr agent send ${orchestrator_pane} "[TASK-BLOCKED] from=\$HERDR_PANE_ID reason=<why>"
MSG
}

main() {
  [[ $# -lt 4 ]] && usage
  local repo_arg="$1" branch_name="$2"
  shift 2
  [[ "$1" == "--" ]] || usage
  shift
  local task_text="$*"
  [[ -z "${task_text}" ]] && usage

  require_herdr

  local script_dir harness_root
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  harness_root="$(cd "${script_dir}/.." && pwd)"

  local repo_name="${repo_arg##*/}"
  local worktree_path="${harness_root}/worktree/${repo_name}/${branch_name}"

  if [[ -d "${worktree_path}" ]]; then
    echo "Worktree already exists at ${worktree_path} — reusing." >&2
  else
    "${script_dir}/create-worktree.sh" "${repo_arg}" "${branch_name}" >&2
  fi

  local target existing_pane
  existing_pane="$(find_existing_pane "${worktree_path}")"

  if [[ -n "${existing_pane}" ]]; then
    echo "Reusing existing agent at pane ${existing_pane} (cwd matches ${worktree_path})." >&2
    target="${existing_pane}"
  else
    local agent_name="${repo_name}__${branch_name//\//-}"
    herdr agent start "${agent_name}" --cwd "${worktree_path}" --env "HERDR_ORCH_PANE=${HERDR_PANE_ID}" -- claude --dangerously-skip-permissions >&2
    herdr agent wait "${agent_name}" --status idle --timeout 30000 >&2
    target="${agent_name}"
  fi

  local message
  message="$(build_message "${repo_name}" "${branch_name}" "${worktree_path}" "${HERDR_PANE_ID}" "${task_text}")"
  herdr agent send "${target}" "${message}" >&2

  echo "Dispatched to ${target} (repo=${repo_name} branch=${branch_name})."
}

main "$@"
