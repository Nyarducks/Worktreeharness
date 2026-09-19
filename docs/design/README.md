# Design docs

Design documentation in Google OKF v0.2 — markdown body with YAML
frontmatter (`type`, `title`, `description`, `status`, `last_modified`,
`sources`). Update the relevant doc in the same commit as any behavior
change; see `CONTRIBUTING.md`.

Start with [overview.md](overview.md) — the goal, requirements, and
high-level architecture. Design docs capture *what* and *why*; read the
code for implementation detail.

| Doc | Contents |
|---|---|
| [overview.md](overview.md) | Goal/non-goal, requirements, high-level architecture, directory layout, security posture |
| [orchestration.md](orchestration.md) | How to ask the orchestrator to run workers; lifecycle, monitoring, ownership, cleanup |
| [sandbox.md](sandbox.md) | Worker sandbox permission model — path × access × reason matrix, process isolation, known holes |
| [guard-hooks.md](guard-hooks.md) | Orchestrator-side `PreToolUse` policies — dual-root resolution, `ALLOWED_EXT_DIRS`, rm safety net |

Fact inventories (config tables, script/skill lists) live in
[../reference/](../reference/).
