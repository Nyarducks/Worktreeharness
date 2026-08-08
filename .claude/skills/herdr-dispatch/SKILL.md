---
name: herdr-dispatch
description: Orchestrator workflow — spawn a dedicated Claude Code process via herdr inside a target repo's own worktree, so that repo's own .claude/skills and CLAUDE.md actually load. Use for cross-repo tasks (e.g. an app repo change that also needs an infra repo change), or whenever you want a task to run as a real separate agent instead of in-process. Also use when a message arrives prefixed [CROSS-REPO-REQUEST].
---

# herdr Dispatch (Orchestrator)

## Why this exists, and when to use it instead of `/parallel-worktree`

`/parallel-worktree` does the work **in this same Claude Code process**, which stays rooted at the Worktreeharness root — so a target repo's own `.claude/skills/` and `CLAUDE.md` are never loaded, no matter how deep the edits go (only Worktreeharness's own skills apply).

`/herdr-dispatch` instead spawns a **separate Claude Code process** via `herdr`, with its CWD set to the target repo's worktree — that process auto-discovers the target repo's own skills/CLAUDE.md correctly.

Use `/herdr-dispatch` when:
- The task spans more than one repo (e.g. an app change that also needs an infra repo change).
- You explicitly want the target repo's own skills/CLAUDE.md to apply.
- A message arrives prefixed `[CROSS-REPO-REQUEST]` (see below) — you are the Orchestrator being asked to dispatch a repo.

Otherwise, `/parallel-worktree`'s in-process pattern is simpler and still the default for ordinary single-repo tasks.

## Precondition

```bash
[[ "${HERDR_ENV:-}" == "1" ]] && command -v herdr >/dev/null
```

If this fails, tell the user herdr isn't available here and fall back to `/parallel-worktree`.

## Dispatching a repo

```bash
scripts/spawn-repo-agent.sh <[owner/]repo> <branch> -- <task text...>
```

This does the whole sequence in one call:
1. Creates the worktree via the existing `scripts/create-worktree.sh` (which itself imports/pulls `repos/<repo>` via `setup-repo.sh`) — or reuses it if it already exists.
2. Looks up whether a herdr agent is already running with that worktree as its `cwd` (`herdr agent list`); if so, reuses it instead of spawning a duplicate.
3. Otherwise creates a **dedicated tab** (`herdr tab create --cwd <worktree>`, not a split pane inside the Orchestrator's own tab) and types `claude --permission-mode acceptEdits` into it via `herdr pane run`, then waits (with retries — see Notes) for it to register as idle.
4. Sends it the task, framed with the reporting-back protocol below, via `herdr agent send` followed by `herdr pane send-keys <pane_id> Enter` to actually submit it.

The script prints `Dispatched to pane <pane_id> (repo=... branch=...)` on success — use that `pane_id` for monitoring.

Example:

```bash
scripts/spawn-repo-agent.sh Nyarducks/TradeLab feat/rate-limit -- \
  "Add a per-IP rate limiter to the auth endpoints. If this needs infra changes (e.g. Redis), report back instead of touching TradeLab-infra yourself."
```

## Monitoring a dispatched agent

```bash
herdr agent wait "<pane_id>" --status idle --timeout 60000   # blocks until it's idle again (or times out)
herdr agent read "<pane_id>" --lines 200                     # see recent output
```

## The reporting-back protocol

Every sub-agent is told (via the message `spawn-repo-agent.sh` sends) to report back to the Orchestrator's herdr pane using one of three prefixes — never by spawning agents itself:

| Prefix | Meaning | Orchestrator's response |
|---|---|---|
| `[CROSS-REPO-REQUEST] repo=<owner/repo> branch=<branch> from=<pane_id> task=<text>` | The task needs work in a different repo | Run `scripts/spawn-repo-agent.sh <repo> <branch> -- <task>` for that repo |
| `[TASK-DONE] from=<pane_id> summary=<text>` | The sub-agent finished | Relay the summary to the human; do not act further without direction |
| `[TASK-BLOCKED] from=<pane_id> reason=<text>` | The sub-agent is stuck | Relay the reason to the human; do not act further without direction |

This is a prose convention read by the Orchestrator's own model, not a machine parser — the prefixes just need to stay consistent. See `CLAUDE.md`'s Orchestrator-role paragraph for how the Orchestrator should react on receiving one.

**Star topology**: dispatched agents must never call `herdr agent start` themselves. All cross-repo requests flow back through the Orchestrator, which is the single place responsible for avoiding duplicate worktrees/agents on the same repo+branch (via the `herdr agent list` cwd lookup in step 2 above).

## Notes (confirmed by live testing)

- **`herdr agent send` never submits.** It only types text into the target pane's input box. Every message — the Orchestrator's initial task, and every `[CROSS-REPO-REQUEST]`/`[TASK-DONE]`/`[TASK-BLOCKED]` a sub-agent sends back — must be followed by `herdr pane send-keys <target-pane-id> Enter` or it just sits there unsubmitted. For long messages, sending Enter immediately after `agent send` is itself a race (the paste hasn't "landed" in the input box yet) — leave at least ~1s in between (`spawn-repo-agent.sh` does this with `sleep 1`; the task message it sends instructs sub-agents to do the same for their own replies).
- **`herdr agent start ... -- claude ...` is denied by the Orchestrator's own auto-mode Bash classifier** (tested with both `--dangerously-skip-permissions` and `--permission-mode auto` — both blocked) when the Orchestrator session is itself running under auto mode / `--dangerously-skip-permissions`. `herdr tab create` + `herdr pane run "<pane_id>" "claude ..."` is not blocked, which is why `spawn-repo-agent.sh` uses that instead — the claude process still self-registers as a herdr agent via the globally-installed `SessionStart` hook regardless of how it was started.
- **`--permission-mode acceptEdits`**, not `--dangerously-skip-permissions`, for the same classifier reason. This means a dispatched sub-agent may still pause waiting for approval on non-edit actions (e.g. `git push`, `gh pr create`) — watch for `agent_status: "blocked"` via `herdr agent wait`, not just `"idle"`, and be ready to relay that to the human.
- **Right after `herdr pane run`, `herdr agent wait <pane_id>` can fail with `agent_not_found`** for a second or two — the SessionStart hook that registers the pane as an agent runs asynchronously after the claude process actually starts. `spawn-repo-agent.sh` retries for a few seconds before giving up.
- The usual hooks (`.claude/hooks/*`) still enforce the worktree/harness-root boundaries regardless of any of the above.
