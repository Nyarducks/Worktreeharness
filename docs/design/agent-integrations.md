---
type: Design Doc
title: Agent Integrations and Guard Hooks
description: What each agent config directory defines, how the shared guard-hook policies work, and how ALLOWED_EXT_DIRS scopes external access.
status: current
author: Devin
last_modified: 2026-09-20
tags: [agents, hooks, claude, codex, devin, antigravity]
sources: [.claude/settings.json, .codex/hooks.json, .agents/hooks.json, .devin/hooks.v1.json, scripts/lib/rm-guard.sh]
---

# Agent Integrations and Guard Hooks

## Config directories

Each supported agent reads its own config directory; the same three
guard-hook policies are implemented once per agent in that agent's native
hook format.

| Directory | Agent | Defines |
|---|---|---|
| `.claude/` | Claude Code | `settings.json` with `hooks` (standalone `hooks.json` is not supported); `skills` is a symlink to `../.agents/skills` |
| `.codex/` | Codex CLI | `hooks.json` (shell + `apply_patch` matchers); `hooks/` scripts |
| `.agents/` | Antigravity | `hooks.json` (named-group schema); `hooks/` scripts; canonical `skills/` |
| `.devin/` | Devin CLI | `hooks.v1.json` (Claude-compatible schema, `decision: block` output); `hooks/` scripts |

`.agents/skills/` is the canonical skills directory — Codex, Devin, and
Antigravity read it natively; Claude Code sees the same set through the
`.claude/skills` symlink.

## Hook policies

All four hook sets enforce the same three `PreToolUse` policies:

| Hook | Effect |
|---|---|
| `guard-writes-to-worktree.sh` | Denies writes outside `worktree/` (unless under `ALLOWED_EXT_DIRS`) |
| `restrict-to-repo-root.sh` (Codex: `restrict-to-harness-root.sh`) | Denies reads/shell access outside the lab root unless allowlisted |
| `guard-bash-commands.sh` | Restricts command paths to the lab root or `ALLOWED_EXT_DIRS`; dangerous recursive `rm` is always blocked |

Shared logic lives in `scripts/lib/rm-guard.sh` (sourced from
`SCRIPT_ROOT`): the `rm` safety net and the `ALLOWED_EXT_DIRS` loader.
Hooks resolve commands via `git rev-parse --show-toplevel`, so they fire
from any checkout of the harness.

The `rm` safety net is unconditional: recursive deletes targeting `$HOME`,
`/`, an ancestor of `$HOME`, or critical top-level directories (`/etc`,
`/usr`, `/var`, …) — including `sudo rm -rf` and glob forms — are denied
regardless of allowlist contents.

## ALLOWED_EXT_DIRS

`.env` sets `ALLOWED_EXT_DIRS` (comma-separated) to scope access outside
the lab root, e.g. `~/.claude,/tmp`. Hooks read `.env` from **both** the
checkout root and the lab root and combine the lists — one lab-root `.env`
covers every checkout while checkout-local `.env` still works. External
access is enabled exactly when the list is non-empty, and only for listed
paths; there is no global bypass.

## Verified agents

Dispatch (`--kind`) has been verified live for **Devin CLI** and
**Antigravity**. Claude Code and Codex CLI configs are implemented but not
yet live-verified on this harness.
