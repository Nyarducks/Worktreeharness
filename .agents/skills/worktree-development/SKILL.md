---
name: worktree-development
description: Develop any repository other than Worktreeharness by dispatching a dedicated worker agent via herdr — one herdr workspace per repo, one tab per task. Ask the user which agent kind and which repository when unspecified.
---

# Worktree Development (herdr dispatch)

Any repository **other than Worktreeharness itself** is developed through
this skill: a separate worker agent process spawned via `herdr`, with its
cwd bound to a fresh worktree so the target repo's own `.agents/skills`
and `AGENTS.md`/`CLAUDE.md` apply. The orchestrator never edits other
repos in-process. (For the Worktreeharness repo itself, use
`worktreeharness-development` instead.)

## Before dispatching — confirm with the user

If the request does not specify both of these, ask *before* dispatching
via your agent's ask-question tool — the `ask*question` variant it
exposes (`AskUserQuestion`, `ask_user_question`, `ask_question`, …).
Never default silently.

- **Agent kind** — offer these options (mapped to `--kind`):
  Claude Code → `claude`, Codex → `codex`, Devin → `devin`,
  Antigravity → `agy`.
- **Repository** — ask for the repository *name*. Offer the base clones
  already under `repos/` as options; accept a bare name or `owner/name`.

## Precondition

```bash
[[ "${HERDR_ENV:-}" == "1" ]] && command -v herdr >/dev/null
```

If this fails, tell the user herdr isn't available — there is no
in-process fallback for other repositories.

## Dispatching a task

```bash
scripts/spawn-repo-agent.sh <[owner/]repo> -- "<task>"
scripts/spawn-repo-agent.sh --kind agy <owner>/<repo> -- "<task>"
scripts/spawn-repo-agent.sh --kind devin <owner>/<repo> -- "<task>"
scripts/spawn-repo-agent.sh --no-sandbox <owner>/<repo> -- "<task>"
```

`spawn-repo-agent.sh` is the **only** entry point for other repos — it
goes all the way from worktree to a spawned, prompted agent. Never run
`create-worktree.sh` for another repo and stop there: a worktree with no
worker is a half-finished task. If inputs (task, kind, repo) are
missing, ask first — then dispatch once.

One call does the whole sequence:

1. `create-worktree.sh --detach` imports/refreshes `repos/<repo>` and
   creates `worktree/<repo>/task/<uuid>` on a **detached HEAD at
   `origin/main`** — the uuid leaf keeps concurrent dispatches
   collision-free, and no branch is named before the task is understood.
   The worker names its own branch if and when it needs one; the
   orchestrator does not prescribe one.
2. `herdr workspace list` finds the workspace labeled `<repo>`; a new tab is
   added to it, or a new workspace is created — one workspace per repo, one
   tab per task.
3. The agent launches in that tab's root pane under a placeholder name
   `w-<uuid>`. By default it runs inside a bubblewrap mount namespace built
   by `scripts/lib/sandbox-wrap.sh` — `/` read-only, `$HOME`/`/tmp` tmpfs,
   writable only to the worktree, the base repo's `.git`, the herdr socket,
   and the agent's own config dirs. Sandboxed workers launch via
   `herdr pane run` (bwrap can't be injected into `agent start --kind`);
   `--no-sandbox` falls back to `herdr agent start` (which itself falls back
   to `pane run` if the caller's permission classifier denies it). Dispatch
   fails closed when `bwrap` is missing unless `--no-sandbox` is passed.
4. `herdr agent prompt <pane> "<task>" --wait` submits the task atomically.
   The prompt embeds a short preamble telling the worker to rename itself
   (`herdr agent rename <pane> <slug>`) and its tab
   (`herdr tab rename <tab> <title>`) once it knows the task — names like
   `w-<repo>-<uuid>` mean nothing, so the worker picks a task slug itself.

The script prints `Dispatched to pane <pane_id> (repo=... worktree=...)` —
keep the `pane_id` for monitoring and follow-ups.

## Monitoring (pull model)

Workers are plain agents with no reporting protocol — they just go idle
when done:

```bash
herdr agent wait "<pane_id>" --until idle --timeout 600000
herdr agent read "<pane_id>" --source recent-unwrapped --lines 200
```

Send follow-up work to the same live agent with:

```bash
herdr agent prompt "<pane_id>" "<follow-up task>" --wait --timeout 120000
```

## Notes

- The worker inherits the repo's own conventions because its cwd is the
  worktree — those files must be committed in the repo to exist there.
- The script pre-trusts the worktree so the worker does not stop at a
  first-run confirmation prompt: it registers the path in agy's
  `trustedWorkspaces` and claude's `~/.claude.json` project trust list;
  `devin` is launched with `--respect-workspace-trust false`.
- Each dispatch creates a fresh worktree; nothing is reused across tasks
  except the repo's herdr workspace itself.
- The worker starts as `w-<uuid>` and self-renames from the task prompt —
  if it skipped that step (or the rename failed), fall back to addressing
  it by pane id, which always works.
