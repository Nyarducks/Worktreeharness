#!/usr/bin/env bash
# Usage: spawn-repo-agent.sh [--kind <claude|agy|...>] [--no-sandbox] <[org/]repo> [-- <task text...>]
#
# Dispatches a dedicated agent process via herdr:
#   1. imports/refreshes repos/<repo> and creates a worktree at
#      worktree/<repo>/task/<uuid> with a detached HEAD at origin/main —
#      the uuid leaf keeps concurrent dispatches collision-free and no
#      branch is named before the task is understood
#   2. reuses the repo's herdr workspace (one workspace per repo, matched by
#      label) or creates it, adding a tab bound to the new worktree
#   3. starts the agent in that tab's root pane with cwd=<worktree>, so the
#      repo's own AGENTS.md/.agents/skills load — the worker knows nothing
#      about this harness. By default the agent runs inside a bubblewrap
#      mount namespace (scripts/lib/sandbox-wrap.sh): the filesystem is
#      read-only except the worktree, the base repo's .git, the herdr socket,
#      and the agent's own config dirs. --no-sandbox disables it.
#   4. submits a prompt via `herdr agent prompt` (atomic paste+Enter). It
#      always carries the self-naming contract — rename agent + tab to a
#      task-derived slug — so names stay meaningful. With a task the worker
#      starts immediately; with none the prompt is a standby instruction
#      and the worker idles until `herdr agent prompt <pane> "<task>"`.
#
# Monitoring is pull-based: `herdr agent wait <pane> --until idle` and
# `herdr agent read <pane>` — workers carry no reporting protocol.
set -euo pipefail

usage() {
  echo "Usage: $0 [--kind <claude|agy|...>] [--no-sandbox] <[org/]repo> [-- <task text...>]" >&2
  exit 1
}

require_herdr() {
  command -v herdr > /dev/null 2>&1 || {
    echo "Error: herdr not found on PATH. Cannot dispatch a worker." >&2
    exit 1
  }
  [[ "${HERDR_ENV:-}" == "1" ]] || {
    echo "Error: not running inside a herdr session (HERDR_ENV is unset)." >&2
    exit 1
  }
}

# gen_uuid — short lowercase id for the worktree dir and branch suffix.
gen_uuid() {
  local u=""
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    u="$(cat /proc/sys/kernel/random/uuid)"
  elif command -v uuidgen > /dev/null 2>&1; then
    u="$(uuidgen)"
  else
    u="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  fi
  u="${u//-/}"
  printf '%s\n' "${u:0:12}"
}

# wait_for_agent <pane_id>
# After `herdr pane run`, `herdr agent wait` errors with "agent_not_found"
# until the agent's SessionStart hook registers the pane — retry briefly.
wait_for_agent() {
  local pane_id="$1" attempt=0
  until herdr agent wait "${pane_id}" --until idle --until blocked --timeout 5000 >&2; do
    attempt=$((attempt + 1))
    if [[ ${attempt} -ge 6 ]]; then
      echo "Error: agent at pane ${pane_id} did not register/become ready in time." >&2
      exit 1
    fi
    sleep 1
  done
}

# json_merge_atomic <file> <path-arg> <jq-filter>
# Applies <jq-filter> (with $path bound to <path-arg>) to <file> in place,
# atomically (flock + mktemp + mv). Recovers an empty object first when the
# file is corrupt.
json_merge_atomic() {
  local settings_file="$1" path_arg="$2" filter="$3"
  (
    flock -x 200
    if ! jq -e 'type == "object"' "${settings_file}" >/dev/null 2>&1; then
      local backup_file recovery_tmp
      backup_file="$(mktemp "${settings_file}.corrupt-XXXXXX.bak")"
      cp "${settings_file}" "${backup_file}" 2>/dev/null || true
      recovery_tmp="$(mktemp "${settings_file}.XXXXXX")"
      echo "{}" > "${recovery_tmp}"
      mv "${recovery_tmp}" "${settings_file}" 2>/dev/null || rm -f "${recovery_tmp}"
    fi

    local tmp_file
    tmp_file="$(mktemp "${settings_file}.XXXXXX")"
    if jq --arg path "${path_arg}" "${filter}" "${settings_file}" > "${tmp_file}" 2>/dev/null; then
      mv "${tmp_file}" "${settings_file}" 2>/dev/null || rm -f "${tmp_file}"
    else
      rm -f "${tmp_file}"
    fi
  ) 200>"${settings_file}.lock"
}

# ensure_trusted_workspace <worktree_path>
# Pre-trusts the worktree for supported agent CLIs so the worker does not
# stop at a first-run workspace-confirmation dialog:
#   - agy:    ~/.gemini/antigravity-cli/settings.json → trustedWorkspaces
#   - claude: ~/.claude.json → projects[<wt>].hasTrustDialogAccepted
ensure_trusted_workspace() {
  local worktree_path="$1"
  command -v jq >/dev/null 2>&1 || return 0

  local agy_settings="${HOME}/.gemini/antigravity-cli/settings.json"
  if [[ -f "${agy_settings}" ]]; then
    # single quotes are intentional — $path is a jq variable, not shell
    # shellcheck disable=SC2016
    json_merge_atomic "${agy_settings}" "${worktree_path}" \
      '.trustedWorkspaces = ((.trustedWorkspaces // []) + [$path] | unique)'
  fi

  local claude_settings="${HOME}/.claude.json"
  if [[ -f "${claude_settings}" ]]; then
    # single quotes are intentional — $path is a jq variable, not shell
    # shellcheck disable=SC2016
    json_merge_atomic "${claude_settings}" "${worktree_path}" \
      '.projects[$path] = ((.projects[$path] // {}) + {hasTrustDialogAccepted: true})'
  fi
}

# workspace_pane_for <repo_name> <worktree_path> <tab_label>
# Prints the pane_id hosting the new worktree: a new tab in the repo's
# existing workspace when one exists, otherwise a new workspace's root pane.
workspace_pane_for() {
  local repo_name="$1" wt="$2" tab_label="$3"
  local ws_id pane_id
  ws_id="$(herdr workspace list 2>/dev/null | jq -r --arg l "${repo_name}" \
    '[.result.workspaces[]? | select(.label == $l)][0].workspace_id // empty')"

  if [[ -n "${ws_id}" ]]; then
    pane_id="$(herdr tab create --workspace "${ws_id}" --cwd "${wt}" \
      --label "${tab_label}" --no-focus |
      jq -r '.result.root_pane.pane_id // .result.pane.pane_id // empty')"
  else
    pane_id="$(herdr workspace create --cwd "${wt}" --label "${repo_name}" --no-focus |
      jq -r '.result.root_pane.pane_id // empty')"
  fi
  [[ -n "${pane_id}" && "${pane_id}" != "null" ]] || {
    echo "Error: could not obtain a pane for ${wt}." >&2
    exit 1
  }
  printf '%s\n' "${pane_id}"
}

main() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local kind="claude" sandbox=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind) kind="${2:?--kind needs a value}"; shift 2 ;;
      --kind=*) kind="${1#*=}"; shift ;;
      --sandbox) sandbox=1; shift ;;
      --no-sandbox) sandbox=0; shift ;;
      *) break ;;
    esac
  done

  [[ $# -lt 1 ]] && usage
  local repo_arg="$1"
  shift
  local task_text=""
  if [[ $# -gt 0 ]]; then
    [[ "$1" == "--" ]] || usage
    shift
    task_text="$*"
  fi

  require_herdr

  local repo_name="${repo_arg##*/}"
  repo_name="${repo_name%.git}"
  local uuid leaf wt pane_id
  uuid="$(gen_uuid)"
  leaf="task/${uuid}"

  # create-worktree.sh also imports/refreshes repos/<repo> via setup-repo.sh
  # and installs the harness git hooks. Its summary goes to stdout; only the
  # Path line is consumed here. The worktree starts on a detached HEAD at
  # origin/main — no branch is named until the work (and its slug) is known.
  wt="$("${script_dir}/create-worktree.sh" --detach "${repo_arg}" "${leaf}" |
    awk '/^  Path:/ {print $2; exit}')"
  [[ -n "${wt}" && -d "${wt}" ]] || {
    echo "Error: worktree was not created for ${repo_arg} ${leaf}." >&2
    exit 1
  }

  pane_id="$(workspace_pane_for "${repo_name}" "${wt}" "${leaf//\//-}")"
  local tab_id
  tab_id="$(herdr pane get "${pane_id}" | jq -r '.result.pane.tab_id // empty')"

  # Pre-trust the worktree so the worker's first-run dialog does not block it.
  ensure_trusted_workspace "${wt}"

  local agent_flags=""
  case "${kind}" in
    claude) agent_flags="--permission-mode auto" ;;
    agy|antigravity)
      kind="agy"
      agent_flags="--dangerously-skip-permissions"
      ;;
    devin) agent_flags="--permission-mode dangerous --respect-workspace-trust false" ;;
  esac

  # Placeholder name; the worker renames itself (and its tab) to a task slug
  # once it reads the prompt — the dispatcher cannot know a meaningful name
  # before the worker does. herdr agent names: [a-z][a-z0-9_-]{0,31}
  local agent_name="w-${uuid}"
  if [[ ${sandbox} -eq 1 ]]; then
    # Sandboxed workers can't use `agent start --kind` (it execs the bare
    # binary); the pane gets a bwrap-wrapped command instead. Fail closed:
    # a worker without its filesystem boundary is worse than no worker.
    command -v bwrap > /dev/null 2>&1 || {
      echo "Error: sandboxed workers require bubblewrap (bwrap). Install it, or pass --no-sandbox." >&2
      exit 1
    }
    # shellcheck source=scripts/lib/sandbox-wrap.sh
    source "${script_dir}/lib/sandbox-wrap.sh"
    local -a agent_argv
    read -ra agent_argv <<< "${kind} ${agent_flags}"
    local wrapped
    wrapped="$(sandbox_wrap_cmd "${wt}" "${kind}" "${agent_argv[@]}")" || {
      echo "Error: failed to build sandbox command (rc=$?)." >&2
      exit 1
    }
    herdr pane run "${pane_id}" "exec ${wrapped}" >&2
    wait_for_agent "${pane_id}"
  else
    # `agent start` is the native path (waits for readiness itself). It can be
    # denied by the calling agent's own permission classifier; `pane run`
    # (typing the launch command into an existing pane) is not, and the agent
    # still self-registers via its SessionStart hook.
    # ${agent_flags} must word-split — it is a flag string, not a path
    # shellcheck disable=SC2086
    if ! herdr agent start "${agent_name}" --kind "${kind}" --pane "${pane_id}" -- ${agent_flags} >&2; then
      if ! herdr agent get "${pane_id}" > /dev/null 2>&1; then
        herdr pane run "${pane_id}" "cd ${wt} && ${kind} ${agent_flags}" >&2
        wait_for_agent "${pane_id}"
      fi
    fi
  fi

  # Every spawn sends a prompt carrying the self-naming contract — with a
  # task the worker renames from it and starts immediately; without one the
  # prompt is a standby instruction so the contract survives for follow-up
  # `herdr agent prompt`s (names like w-<uuid> mean nothing otherwise).
  local prompt
  if [[ -n "${task_text}" ]]; then
    prompt="You are running inside a herdr pane (pane id: ${pane_id}, tab id: ${tab_id:-unknown}).

First, once the task below is clear to you, pick a short lowercase slug for it and rename yourself and your tab:
  herdr agent rename ${pane_id} <slug>
  herdr tab rename ${tab_id:-<tab-id>} <short-title>
Slug rules: starts with a lowercase letter, only [a-z0-9_-], at most 32 chars. Then proceed with the task.

Task: ${task_text}"
  else
    prompt="You are running inside a herdr pane (pane id: ${pane_id}, tab id: ${tab_id:-unknown}) as a standby worker for ${repo_name} (worktree: ${wt}).

No task is assigned yet — wait for follow-up prompts. When you receive a task, first pick a short lowercase slug for it and rename yourself and your tab:
  herdr agent rename ${pane_id} <slug>
  herdr tab rename ${tab_id:-<tab-id>} <short-title>
Slug rules: starts with a lowercase letter, only [a-z0-9_-], at most 32 chars. For now just acknowledge briefly and make no changes."
  fi

  # agent prompt submits paste+Enter atomically; --wait --until working
  # confirms the agent picked the task up without blocking on completion.
  if ! herdr agent prompt "${pane_id}" "${prompt}" \
      --wait --until working --until blocked --timeout 15000; then
    echo "Warning: task submission was not confirmed as started. Check the pane:" >&2
    echo "  herdr agent read ${pane_id} --lines 30" >&2
  fi

  echo "Dispatched to pane ${pane_id} (repo=${repo_name} worktree=${wt})."
  if [[ -z "${task_text}" ]]; then
    echo "  Idle (standby prompt sent) — send a task with: herdr agent prompt ${pane_id} \"<task>\" --wait"
  fi
}

main "$@"
