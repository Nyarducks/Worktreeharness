---
name: setup-harness
description: Bootstrap Worktreeharness in a new repository or onboard an existing GitHub repository for worktree-based development. Use when installing the harness, importing a repository into repos/, or preparing a task worktree.
---

# Set Up Worktreeharness

Use one of the following flows.

## Onboard an existing repository

```bash
REPO_PATH=$(scripts/setup-repo.sh <owner>/<repo>)
scripts/create-worktree.sh <owner>/<repo> feat/<topic>
```

`setup-repo.sh` clones to `repos/<repo>/` on first use and fast-forwards it later. Treat it as read-only. Do all development in `worktree/<repo>/feat/<topic>/`, using `git -C` for Git commands. Use `$git-operations` for commits and pull requests.

## Bootstrap a new harness repository

Create the repository plus these tracked paths:

```text
.codex/skills/
.codex/hooks.json
.codex/hooks/guard-writes-to-worktree.sh
.codex/hooks/restrict-to-harness-root.sh
scripts/hooks/
scripts/setup-repo.sh
scripts/create-worktree.sh
scripts/setup-hooks.sh
repos/
worktree/
```

Copy the harness scripts, `.codex/hooks.json`, both files in `.codex/hooks/`, and the required `.codex/skills/*/SKILL.md` files from this repository. Make shell scripts executable, install Git hooks with `scripts/setup-hooks.sh`, and add `repos/`, `tmp/`, and `worktree/` to `.gitignore`.

Add a repository instruction file that states these invariants:

- Create or resume a worktree before every code change.
- Make code changes only under `worktree/`.
- Never edit `repos/` directly.
- Use `git -C <path>` rather than changing into managed repositories.

Avoid hard-coded absolute paths. Resolve the harness root with `git rev-parse --show-toplevel`; set `WORKTREE_LAB_DIR` only when automatic detection fails.
