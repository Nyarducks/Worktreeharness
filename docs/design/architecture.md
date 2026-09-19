---
type: Design Doc
title: Worktreeharness Architecture
description: System topology, directory layout, orchestrator/worker roles, and the dispatch pipeline.
status: current
author: Devin
last_modified: 2026-09-20
tags: [architecture, worktree, herdr, orchestrator]
sources: [scripts/create-worktree.sh, scripts/setup-repo.sh, scripts/spawn-repo-agent.sh, scripts/lib/sandbox-wrap.sh]
---

# Worktreeharness Architecture

## Purpose

Worktreeharness is a harness for worktree-driven multi-repository
development. An **Orchestrator** agent runs at the harness root and either
edits worktrees in-process (`/parallel-worktree`) or dispatches a task to a
separate **Worker** agent process via herdr (`/herdr-dispatch`). Every task
runs in an isolated `git worktree`; base clones are never edited directly.

## Directory layout

```
<lab root>/
├── repos/<repo>/                    # Base clones — read-only, never edited
├── worktree/<repo>/<branch>/        # Active worktrees — all edits happen here
│   └── Worktreeharness/<branch>/    # Harness self-development worktrees
├── scripts/                         # Harness management scripts
│   ├── hooks/                       # git hooks (pre-commit, pre-push)
│   └── lib/                         # shared shell libraries
├── .agents/                         # canonical skills + Antigravity config
├── .claude/                         # Claude Code config (skills → symlink)
├── .codex/                          # Codex hooks
├── .devin/                          # Devin CLI hooks
├── docs/design/                     # design docs (OKF v0.2)
├── docs/adr/                        # architecture decision records
└── tests/                           # shell test suites
```

`repos/` and `worktree/` are gitignored — they are ephemeral working
directories, not project files.

## Topologies

Two layouts are supported:

- **Split**: the lab root holds `repos/` and `worktree/`; each checkout lives
  at `<lab>/worktree/<repo>/<branch>`. Hooks resolve the lab root by walking
  up from the checkout until an ancestor contains both `repos/` and
  `worktree/`.
- **Unified**: the checkout itself is the lab root (harness repo cloned
  directly). `repos/` and `worktree/` sit beside `.git`.

Every hook and script derives `SCRIPT_ROOT` (the checkout holding the code)
separately from the lab root (the policy boundary). Shared libraries and
checkout-local `.env` come from `SCRIPT_ROOT`; write/read confinement uses
the lab root.

## Roles

- **Orchestrator**: the agent the human talks to. Runs at the lab root.
  Owns dispatch, monitoring, and cleanup. Never edits a worker's delegated
  worktree.
- **Worker**: a separate agent process spawned inside a task worktree by
  `spawn-repo-agent.sh`. It knows nothing about the harness — it only sees
  its worktree, its repo's own `AGENTS.md`/skills, and the herdr
  environment variables needed for self-naming.

## Dispatch pipeline

`spawn-repo-agent.sh` performs one dispatch end to end:

1. `create-worktree.sh` imports/refreshes `repos/<repo>` and creates
   `worktree/<repo>/task/<uuid>` on branch `task/<uuid>` — the uuid leaf
   keeps concurrent dispatches collision-free.
2. Herdr workspace labelled `<repo>` is reused or created (one workspace
   per repo); one tab is added per task, bound to the worktree.
3. The agent launches in the tab's root pane with `cwd = worktree`,
   wrapped in a bubblewrap sandbox by default (see
   `sandbox.md`). `--no-sandbox` falls back to a bare launch.
4. The task prompt is submitted via `herdr agent prompt --wait`. A preamble
   asks the worker to rename its agent and tab once it understands the
   task (`w-<uuid>` placeholders carry no meaning).

## Guard model

Two complementary layers:

- **Repo-local `PreToolUse` hooks** (`.claude`, `.codex`, `.agents`,
  `.devin`) — advisory confinement to the harness root plus an
  unconditional dangerous-`rm` safety net. See `agent-integrations.md`.
- **Worker sandbox** — kernel-enforced mount-namespace confinement applied
  at spawn time, agent-agnostic. See `sandbox.md`.

Hooks guard the orchestrator's own edits; the sandbox confines dispatched
workers regardless of whether the target repo ships hooks.
