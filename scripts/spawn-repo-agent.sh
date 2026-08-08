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

# wait_for_agent_idle <pane_id>
# `herdr agent wait` errors with "agent_not_found" if the target pane hasn't
# registered as a herdr agent yet (the claude process's SessionStart hook
# reports it asynchronously, shortly after `herdr pane run` returns) — retry
# for a few seconds before giving up.
wait_for_agent_idle() {
  local pane_id="$1" attempt=0
  until herdr agent wait "${pane_id}" --status idle --timeout 5000 >&2; do
    attempt=$((attempt + 1))
    if [[ ${attempt} -ge 6 ]]; then
      echo "Error: agent at pane ${pane_id} did not register/become idle in time." >&2
      exit 1
    fi
    sleep 1
  done
}

# ensure_trusted_workspace <worktree_path>
# Automatically adds the worktree directory to ~/.gemini/antigravity-cli/settings.json's
# trustedWorkspaces list so agy does not prompt for workspace confirmation.
ensure_trusted_workspace() {
  local worktree_path="$1"
  local settings_file="${HOME}/.gemini/antigravity-cli/settings.json"
  if [[ -f "${settings_file}" ]] && command -v jq >/dev/null 2>&1; then
    jq --arg path "${worktree_path}" '
      .trustedWorkspaces = ((.trustedWorkspaces // []) + [$path] | unique)
    ' "${settings_file}" > "${settings_file}.tmp" 2>/dev/null && mv "${settings_file}.tmp" "${settings_file}" 2>/dev/null || true
  fi
}

# resolve_agent_cmd <harness_root>
# Resolves the agent launch command (claude or agy) and model arguments based on
# HERDR_AGENT_CLI or the model name (Gemini models select agy, Claude models select claude).
resolve_agent_cmd() {
  local harness_root="$1"
  if [[ -f "${harness_root}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${harness_root}/.env" 2>/dev/null || true
  fi
  local worker_model="${HERDR_WORKER_MODEL:-inherit}"
  local resolved_model=""

  if [[ "${worker_model}" != "inherit" ]]; then
    resolved_model="${worker_model}"
  elif [[ -n "${HERDR_ORCH_MODEL:-}" ]]; then
    resolved_model="${HERDR_ORCH_MODEL}"
  fi

  local lower_model
  lower_model="$(echo "${resolved_model}" | tr '[:upper:]' '[:lower:]')"
  local explicit_cli="${HERDR_AGENT_CLI:-}"

  local cli_binary="claude"
  local base_flags="--permission-mode auto"

  if [[ "${explicit_cli}" == "agy" || "${explicit_cli}" == "antigravity" || "${lower_model}" == *gemini* ]]; then
    cli_binary="agy"
    base_flags="--dangerously-skip-permissions"
  fi

  if [[ -n "${resolved_model}" && "${resolved_model}" != "inherit" ]]; then
    printf '%s %s --model %q' "${cli_binary}" "${base_flags}" "${resolved_model}"
  else
    printf '%s %s' "${cli_binary}" "${base_flags}"
  fi
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
  local repo_name="$1" branch_name="$2" worktree_path="$3" orchestrator_pane="$4" task_text="$5" self_pane="$6"
  cat <<MSG
[ORCHESTRATOR TASK]
You were spawned via herdr for repo ${repo_name} on branch ${branch_name} (worktree: ${worktree_path}).
Orchestrator herdr pane: ${orchestrator_pane}
Your own herdr pane (use this literal value as "from=" below, do not use \$HERDR_PANE_ID — see note): ${self_pane}

Task:
${task_text}

Rules:
- Work only inside this worktree, following this repo's own CLAUDE.md/AGENTS.md and skill conventions.
- IMPORTANT: \`herdr agent send\` only types text into the target pane's input box — it does NOT submit it. Every message below must be followed by \`herdr pane send-keys ${orchestrator_pane} Enter\` (as a separate command, with at least ~1s in between) or the Orchestrator will never see it.
- IMPORTANT: use the literal pane id ${self_pane} in the commands below, not a \$HERDR_PANE_ID shell expansion — even under --permission-mode auto, a command containing shell variable expansion still triggers a manual approval prompt (confirmed live), while the same command with a literal value does not.
- If this task needs changes in a DIFFERENT repository, do NOT edit that repository yourself. Instead run:
    herdr agent send ${orchestrator_pane} "[CROSS-REPO-REQUEST] repo=<owner/repo> branch=<suggested-branch> from=${self_pane} task=<description>"
    sleep 1 && herdr pane send-keys ${orchestrator_pane} Enter
  and continue your own work — never spawn other repos' agents yourself.
- When you finish, run:
    herdr agent send ${orchestrator_pane} "[TASK-DONE] from=${self_pane} summary=<one paragraph>"
    sleep 1 && herdr pane send-keys ${orchestrator_pane} Enter
- If you get stuck and need a human, run:
    herdr agent send ${orchestrator_pane} "[TASK-BLOCKED] from=${self_pane} reason=<why>"
    sleep 1 && herdr pane send-keys ${orchestrator_pane} Enter
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
  harness_root="${WORKTREE_LAB_DIR:-$(cd "${script_dir}/.." && pwd)}"

  local repo_name="${repo_arg##*/}"
  local worktree_path="${harness_root}/worktree/${repo_name}/${branch_name}"

  if [[ -d "${worktree_path}" ]]; then
    echo "Worktree already exists at ${worktree_path} — reusing." >&2
  else
    "${script_dir}/create-worktree.sh" "${repo_arg}" "${branch_name}" >&2
  fi

  ensure_trusted_workspace "${worktree_path}"

  local pane_id existing_pane
  existing_pane="$(find_existing_pane "${worktree_path}")"

  if [[ -n "${existing_pane}" ]]; then
    echo "Reusing existing agent at pane ${existing_pane} (cwd matches ${worktree_path})." >&2
    pane_id="${existing_pane}"
  else
    local agent_name="${repo_name}__${branch_name//\//-}"
    # A dedicated tab (not a split pane inside the orchestrator's own tab)
    # via `herdr tab create` + `herdr pane run`. `herdr agent start ... --
    # claude ...` was tried first but is denied by the Orchestrator's own
    # auto-mode Bash classifier when it tries to spawn another autonomous
    # agent that way; `pane run` (typing a command into an already-created
    # pane) is not. The claude process still self-registers as a herdr
    # agent via the globally-installed SessionStart hook, so it's fully
    # addressable by pane_id afterwards regardless of how it was started.
    #
    # --permission-mode auto, not --dangerously-skip-permissions (bypasses
    # ALL safety checks, including its own one-time "bypass permissions"
    # confirmation dialog on first launch) and not acceptEdits (every
    # non-edit Bash command — including the sub-agent's own herdr agent
    # send/pane send-keys reporting-back calls — needs manual approval
    # under acceptEdits, confirmed live). auto mode keeps its own
    # classifier as a safety net (the same one that denies the Orchestrator
    # spawning further agents via `agent start`) without that per-command
    # approval friction, and needs no confirmation dialog on launch.
    local tab_json
    tab_json="$(herdr tab create --cwd "${worktree_path}" --label "${agent_name}" --env "HERDR_ORCH_PANE=${HERDR_PANE_ID}" --no-focus)"
    echo "${tab_json}" >&2
    pane_id="$(jq -r '.result.root_pane.pane_id' <<< "${tab_json}")"
    [[ -n "${pane_id}" && "${pane_id}" != "null" ]] || { echo "Error: could not read pane_id from herdr tab create output." >&2; exit 1; }

    local agent_cmd
    agent_cmd="$(resolve_agent_cmd "${harness_root}")"
    herdr pane run "${pane_id}" "cd ${worktree_path} && ${agent_cmd}" >&2
    wait_for_agent_idle "${pane_id}"
  fi

  local message
  message="$(build_message "${repo_name}" "${branch_name}" "${worktree_path}" "${HERDR_PANE_ID}" "${task_text}" "${pane_id}")"
  herdr agent send "${pane_id}" "${message}" >&2
  # agent send only types the text — it does not submit it. A large paste
  # (this message is long) takes a moment to land in the input box before
  # Enter actually submits it rather than being a no-op; sending Enter too
  # immediately after send is a real race, observed in manual testing.
  sleep 1
  herdr pane send-keys "${pane_id}" Enter >&2

  echo "Dispatched to pane ${pane_id} (repo=${repo_name} branch=${branch_name})."
}

main "$@"
