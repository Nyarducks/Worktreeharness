---
name: herdr-dispatch
description: Spawn a dedicated agent process via herdr bound to a fresh repo worktree — one herdr workspace per repo, one tab per dispatched task. The worker runs with the worktree as cwd so the target repo's own skills and CLAUDE.md/AGENTS.md load. Use for cross-repo tasks or whenever a task should run as a real separate agent.
---

# herdr Dispatch (Orchestrator)

## Why this exists, and when to use it instead of `/parallel-worktree`

`/parallel-worktree` does the work **in this same agent process**, rooted at
the harness root — a target repo's own skills and rules are never loaded.
Dispatch instead spawns a *separate* agent process via `herdr` whose cwd is
the worktree, so the repo's own `.claude/skills` (or `.agents`/`.codex` for
other hosts) and `CLAUDE.md`/`AGENTS.md` apply.

Use it when a task should run as a standalone agent, or when the target
repo's own conventions matter. Otherwise `/parallel-worktree` is simpler.

## Precondition

```bash
[[ "${HERDR_ENV:-}" == "1" ]] && command -v herdr >/dev/null
```

If this fails, tell the user herdr isn't available and fall back to
`/parallel-worktree`.

## Dispatching a task

```bash
scripts/spawn-repo-agent.sh <[owner/]repo> -- "<task>"
scripts/spawn-repo-agent.sh --kind agy <owner>/<repo> -- "<task>"
scripts/spawn-repo-agent.sh --kind devin <owner>/<repo> -- "<task>"
```

One call does the whole sequence:

1. `create-worktree.sh` imports/refreshes `repos/<repo>` and creates
   `worktree/<repo>/task/<uuid>` on branch `task/<uuid>` — the uuid leaf
   keeps concurrent dispatches collision-free.
2. `herdr workspace list` finds the workspace labeled `<repo>`; a new tab is
   added to it, or a new workspace is created — one workspace per repo, one
   tab per task.
3. `herdr agent start w-<uuid> --kind <kind> --pane <pane>` launches the
   agent in that tab's root pane under a placeholder name (falls back to
   `herdr pane run` when the caller's own permission classifier denies
   `agent start`).
4. `herdr agent prompt <pane> "<task>" --wait` submits the task atomically.
   The prompt embeds a short preamble telling the worker to rename itself
   (`herdr agent rename <pane> <slug>`) and its tab
   (`herdr tab rename <tab> <title>`) once it knows the task — names like
   `w-<repo>-<uuid>` mean nothing, so the worker picks a task slug itself.

The script prints `Dispatched to pane <pane_id> (repo=... branch=...
worktree=...)` — keep the `pane_id` for monitoring and follow-ups.

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
- Each dispatch creates a fresh worktree and branch; nothing is reused
  across tasks except the repo's herdr workspace itself.
- The worker starts as `w-<uuid>` and self-renames from the task prompt —
  if it skipped that step (or the rename failed), fall back to addressing
  it by pane id, which always works.
