---
name: herdr-dispatch
description: Orchestrator workflow — spawn a dedicated Claude Code process via herdr inside a target repo's own worktree, so that repo's own .claude/skills and CLAUDE.md actually load. Use for cross-repo tasks (e.g. an app repo change that also needs an infra repo change), or whenever you want a task to run as a real separate agent instead of in-process. Also use when a message arrives prefixed [CROSS-REPO-REQUEST].
---

# herdr Dispatch (Orchestrator)

`$parallel-worktree` stays rooted at the Worktreeharness root, so a target repo's own `.claude/skills/`/`CLAUDE.md` never load. `/herdr-dispatch` instead spawns a **separate** Claude Code process via `herdr`, cwd'd at the target repo's worktree, so that repo's own skills/CLAUDE.md apply. Use it when a task spans more than one repo, you want the target repo's own conventions to apply, or a message arrives prefixed `[CROSS-REPO-REQUEST]`. Otherwise `$parallel-worktree` is simpler and stays the default.

## Precondition

```bash
[[ "${HERDR_ENV:-}" == "1" ]] && command -v herdr >/dev/null
```

If this fails, tell the user herdr isn't available and fall back to `$parallel-worktree`.

## Dispatch a repo

```bash
scripts/spawn-repo-agent.sh <[owner/]repo> <branch> -- <task text...>
```

Before dispatching, `export HERDR_ORCH_MODEL=<your own model id>` so a `HERDR_WORKER_MODEL=inherit` (the default) resolves to the Orchestrator's model instead of launching with no `--model` flag.

This creates/reuses the worktree, reuses an existing herdr agent on that worktree if one is already running (`herdr agent list` by `cwd`), otherwise opens a dedicated tab and starts `claude --permission-mode auto` in it, then hands it the task framed with the reporting protocol below via `herdr_submit`. It prints `Dispatched to pane <pane_id> (repo=... branch=...)`.

```bash
herdr agent wait "<pane_id>" --status idle --timeout 60000   # block until idle or timeout
herdr agent read "<pane_id>" --lines 200                     # see recent output
```

## Reporting protocol

Sub-agents report back to the Orchestrator's pane with one of three prefixes — never by spawning agents themselves:

| Prefix | Meaning | Orchestrator's response |
|---|---|---|
| `[CROSS-REPO-REQUEST] repo=<owner/repo> branch=<branch> from=<pane_id> task=<text>` | Needs work in a different repo | Run `scripts/spawn-repo-agent.sh <repo> <branch> -- <task>` |
| `[TASK-DONE] from=<pane_id> summary=<text>` | Sub-agent finished | Relay to the human; wait for direction |
| `[TASK-BLOCKED] from=<pane_id> reason=<text>` | Sub-agent is stuck | Relay to the human; wait for direction |

**Length cap — hard requirement.** `scripts/lib/herdr-report.sh`'s `herdr_submit` refuses — and never calls `herdr agent send` for — any message over `HERDR_REPORT_MAX_CHARS` (default **800** characters). Oversized pastes make the Enter-submission race below worse, and retries never bypass the cap, so a refused message must be shortened and resent, not retried as-is. Keep every `task=`/`summary=`/`reason=` to a sentence or two; put logs, diffs, and long explanations in the PR description or commit body instead.

## Execution discipline

1. A delegated worktree stays agent-owned. Send follow-ups through `scripts/spawn-repo-agent.sh <repo> <branch> -- "<task>"`; never edit it directly, even after `[TASK-DONE]`/`[TASK-BLOCKED]`.
2. Never interrupt a user-authorized worker unless the user says `stop`, `cancel`, or `abort`. Ambiguous scope changes are additive.
3. Dispatch independent authorized work in parallel; don't block existing workers.
4. No periodic progress reports unless asked — wait for completion or idle events.
5. On each `[TASK-DONE]`/idle event, check and report that worker's result immediately; don't batch with unrelated workers.
6. After completion, verify only that worker's result, PR, labels, clean worktree, and stated test result.
7. Release ownership only when the human confirms no more delegated work is needed: `scripts/spawn-repo-agent.sh --release <owner>/<repo> <branch>`. This drops the ownership record only — it does not stop the agent or remove the worktree.

## Notes

- `herdr agent send` only types into the pane's input box; it never submits. Firing `herdr pane send-keys <pane> Enter` right after (or after a flat `sleep 1`) is a real race for longer messages. Use `herdr_submit <target_pane> "<message>"` (source `scripts/lib/herdr-report.sh` first) for every reply — it scales the settle delay to message length and retries the Enter, and if needed the send, until the pane leaves `idle`.
- `herdr agent start ... -- claude ...` is denied by the Orchestrator's own auto-mode Bash classifier; `herdr tab create` + `herdr pane run "<pane_id>" "claude ..."` is not, and the launched process still self-registers as a herdr agent via the `SessionStart` hook.
- Launch workers with `--permission-mode auto`, not `acceptEdits` (every non-edit Bash call needs manual approval) or `--dangerously-skip-permissions` (disables all safety checks and shows an unscriptable first-launch dialog).
- A Bash command containing shell variable expansion (e.g. `$HERDR_PANE_ID`) triggers a manual approval prompt under `auto` mode even though a literal value doesn't — `spawn-repo-agent.sh` embeds `from=<pane_id>` and the `source <literal-path>/scripts/lib/herdr-report.sh` line as literals for this reason; use those literals, not `$HERDR_PANE_ID`/`$HERDR_HARNESS_ROOT`, in your own commands too.
- `herdr agent wait <pane_id>` can fail with `agent_not_found` for a second or two right after `herdr pane run` — retry briefly before giving up.
- Dispatched agents must never call `herdr agent start` themselves — all cross-repo requests flow back through the Orchestrator, the single place responsible for avoiding duplicate worktrees/agents on the same repo+branch.
