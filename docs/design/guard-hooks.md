---
type: Design Doc
title: Guard Hooks
description: The repo-local PreToolUse policies that confine the orchestrator — dual-root resolution, ALLOWED_EXT_DIRS, and the unconditional rm safety net.
status: current
last_modified: 2026-09-20
tags: [hooks, security, agents]
sources: [scripts/lib/hook-common.sh, scripts/lib/rm-guard.sh, .env.sample, .claude/settings.json, .codex/hooks.json, .agents/hooks.json, .devin/hooks.v1.json]
---

# Guard Hooks

## Goal

Confine the **orchestrator's** own file/shell access to the lab root —
advisory guardrails against accidents, in each agent's native hook format.
(Workers are confined by the sandbox instead — see [sandbox.md](sandbox.md).)

## Design

Three `PreToolUse` policies; each agent implements the subset its tool
surface needs — Codex ships only the command and write guards because it
has no file-path tool for `restrict-to-repo-root.sh` to guard (file
reads go through `shell`, writes through `apply_patch`). Each file under
`.<agent>/hooks/` is a thin adapter that names the agent kind and its
stdin JSON fields; the decision logic lives in
`scripts/lib/hook-common.sh` (which sources `rm-guard.sh`):

| Hook | Effect |
|---|---|
| `guard-writes-to-worktree.sh` | Denies writes outside `worktree/` (unless allowlisted) |
| `restrict-to-repo-root.sh` | Denies reads/shell access outside the lab root unless allowlisted |
| `guard-bash-commands.sh` | Restricts command paths to the lab root or allowlist — `~/` expands to `$HOME` as the shell would; dangerous recursive `rm` always blocked |

```mermaid
flowchart TD
    Agent -->|PreToolUse JSON| Hook
    Hook --> R1{"SCRIPT_ROOT<br/>= checkout<br/>(from hook path)"}
    Hook --> R2{"lab root<br/>= ancestor with<br/>repos/ + worktree/"}
    R1 -->|source hook-common.sh<br/>+ rm-guard.sh,<br/>read checkout .env(.sample)| Lib
    R2 -->|policy boundary,<br/>read lab .env(.sample)| Policy
    Lib --> Decision{"path under<br/>boundary or<br/>allowlisted?"}
    Policy --> Decision
    Decision -->|yes| Allow["exit 0 — allow"]
    Decision -->|no| Deny["deny / block"]
    Decision -->|"recursive rm of<br/>$HOME, /, /etc…"| Block["always block"]
```

## Key decisions

- **Dual-root resolution** (ADR-0007): `SCRIPT_ROOT` (the checkout —
  shared libs, checkout `.env`) is derived from the hook's own path —
  the configured `command` embeds `$(git rev-parse --show-toplevel)`, so
  `$0` is checkout-absolute; the lab root (policy boundary) is the
  nearest ancestor containing `repos/` + `worktree/`. Works in both split
  and unified topologies.
- **Allowlist**: `.env.sample` carries the shipped default
  `ALLOWED_EXT_DIRS` (`/tmp` plus every supported agent's own config
  dir) — the single source of the default, applied even with no `.env`.
  `load_allowed_ext_dirs` unions `.env.sample`, `.env`, and an exported
  `ALLOWED_EXT_DIRS` — a user `.env` can only add, never shadow — and
  reads from both roots, so one lab-root `.env` covers every checkout.
  External access exists only for listed paths; there is no global
  bypass.
- **Unconditional `rm` net**: recursive deletes of `$HOME`, `/`,
  `/home`, `/etc`, `/usr`, `/var`, … — including `sudo` and glob forms —
  are blocked regardless of the allowlist.

## Security

Hooks are **advisory**: they run inside the agent's tool-call pipeline and
assume a cooperating runtime. Obfuscated shell can evade path matching —
the bwrap sandbox is the enforcement layer for workers. Hooks exist to
stop orchestrator accidents, not attacks.

## Testing

`tests/test-hooks.sh` simulates each agent's stdin JSON protocol against
sandboxed labs (both topologies), asserting allow/deny, the built-in
agent dirs plus `ALLOWED_EXT_DIRS` union, and that each config's
`command` actually resolves and fires.
