# Architecture decision records

ADRs record significant decisions in Context / Decision / Consequences
form, numbered sequentially as `NNNN-<slug>.md`, with OKF v0.2 frontmatter
(`type: ADR`, `status`, `last_modified`). Write one in the same commit as
the change that introduces the decision; see `CONTRIBUTING.md`.

| ADR | Decision |
|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions — this convention itself |
| [0002](0002-one-worktree-per-task.md) | One git worktree per task; base clones never edited |
| [0003](0003-herdr-native-dispatch.md) | Dispatch through herdr-native workspaces/tabs/panes |
| [0004](0004-worker-self-naming.md) | Workers rename their own agent and tab |
| [0005](0005-canonical-agents-skills.md) | Canonical `.agents/skills`; per-agent hook config formats |
| [0006](0006-bubblewrap-worker-sandbox.md) | Confine workers with bubblewrap; fail closed |
| [0007](0007-repo-local-guard-hooks.md) | Repo-local guard hooks with dual-root (SCRIPT_ROOT / lab root) resolution |
