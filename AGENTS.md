# Worktreeharness Codex Guide

Worktreeharness manages base clones under `repos/` and active worktrees under `worktree/`.

## Core Rules

- Before changing code, create or resume an isolated worktree with `scripts/create-worktree.sh <owner>/<repo> <branch>`.
- Make code changes only under `worktree/`. Never edit `repos/` directly.
- Do not commit directly to `main`. Use branches named `feat/<feature>`, `fix/<issue>`, or `refactor/<scope>`.
- Use `git -C <path>` for Git commands instead of changing into managed repositories.
- Never approve or merge a pull request; those actions belong to a human reviewer.

The repository-local Codex hooks enforce the write boundary for `apply_patch` and reject explicit Bash paths outside the harness root. Start a new Codex session after changing `.codex/hooks.json` or files under `.codex/hooks/`.

## Workflow

1. Import or update a repository with `scripts/setup-repo.sh <owner>/<repo>`.
2. Create a task worktree with `scripts/create-worktree.sh <owner>/<repo> feat/<topic>`.
3. Read and edit files only in that worktree.
4. Commit, push, and open a PR from the task branch.

Use `$parallel-worktree` for worktree preparation, `$git-operations` for branches and PRs, `$pr-review-fix` for review findings, `$setup-harness` for onboarding, and `$workflow-shell-test` for GitHub Actions shell-test work.
