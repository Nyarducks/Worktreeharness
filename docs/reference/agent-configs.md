---
type: Reference
title: Agent config directories
description: Which config directory each supported agent CLI reads, and what lives there.
status: current
last_modified: 2026-09-20
tags: [agents, config, reference]
sources: [.claude, .codex, .agents, .devin]
---

# Agent config directories

Each agent reads its own config dir; the guard-hook policies are
implemented per format — Codex ships only two of the three (no file-path
tool, so no `restrict-to-repo-root.sh`). Design rationale:
[../design/guard-hooks.md](../design/guard-hooks.md).

| Directory | Agent | Defines |
|---|---|---|
| `.claude/` | Claude Code | `settings.json` with `hooks` (standalone `hooks.json` is not supported); `hooks/` scripts; `skills` → symlink to `../.agents/skills` |
| `.codex/` | Codex CLI | `hooks.json` (shell + `apply_patch` matchers); `hooks/` scripts |
| `.agents/` | Antigravity | `hooks.json` (named-group schema); `hooks/` scripts; canonical `skills/` |
| `.devin/` | Devin CLI | `hooks.v1.json` (Claude-compatible schema, `decision: block` output); `hooks/` scripts |

Tool matchers per config:

| Config | Read | Write | Shell |
|---|---|---|---|
| `.claude/settings.json` | `Read` | `Edit\|Write` | `Bash` |
| `.codex/hooks.json` | — | `apply_patch` | `shell` |
| `.agents/hooks.json` | `view_file` | `replace_file_content\|write_to_file\|multi_replace_file_content` | `run_command` |
| `.devin/hooks.v1.json` | `read` | `write\|edit\|notebook_edit\|apply_patch` | `exec` |

Notes:

- `.agents/skills/` is canonical — Codex, Devin, Antigravity read it
  natively; `.claude/skills` is a symlink (ADR-0005). Dispatching work to
  other repos lives solely in the `worktree-development` skill —
  `spawn-repo-agent.sh` is the single entry point — task text optional;
  an idle spawn still receives a standby prompt carrying the self-naming
  contract (see `orchestration.md`).
- `AGENTS.md` is canonical; `CLAUDE.md` contains only `@AGENTS.md`.
- `.agents/hooks.json` collides with nothing — only Antigravity reads
  `.agents/` for hooks.
- Verified for live dispatch (`--kind`): Devin CLI, Antigravity. Claude
  Code and Codex configs are implemented but not yet live-verified.
