---
type: ADR
title: Confine dispatched workers with bubblewrap, fail closed
description: Agent-agnostic mount-namespace sandbox at spawn time; / read-only, $HOME and /tmp tmpfs, worktree + base .git writable.
status: accepted
author: Devin
last_modified: 2026-09-20
tags: [sandbox, bubblewrap, security, worker]
---

# ADR-0006: Confine dispatched workers with bubblewrap, fail closed

## Status

Accepted

## Context

Repo-local hooks are advisory: they only exist where someone shipped
them, and their path matching can be evaded with obfuscated shell. A
dispatched worker previously inherited the dispatcher's full filesystem
privileges. Devin's built-in `--sandbox` only covers one agent kind.

## Decision

`spawn-repo-agent.sh` wraps the worker command in bubblewrap
(`scripts/lib/sandbox-wrap.sh`): `/` is read-only, `$HOME` and `/tmp` are
tmpfs, and only the worktree, the base repo's `.git`, the herdr socket,
and the agent's own config dirs stay writable. `$HOME`-installed binaries
(the agent, `herdr`) are rebound at their PATH locations. No ssh is bound
at all — this harness clones and pushes over https via `gh`, so `~/.ssh`
and `SSH_AUTH_SOCK` stay hidden. Dispatch fails closed when `bwrap` is
missing; `--no-sandbox` opts out. Sandboxed workers launch via
`herdr pane run` because `agent start --kind` cannot inject a wrapper.

## Consequences

- Confinement applies to every agent kind and every subprocess.
- Full permission matrix: `docs/design/sandbox.md`.
- Known hole: base `.git` is writable (linked worktrees cannot commit
  without it). Network is shared.
