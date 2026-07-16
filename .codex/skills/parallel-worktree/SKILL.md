---
name: parallel-worktree
description: Create and use isolated git worktrees in Worktreeharness. Use for any code change to a repository managed by this harness, for parallel independent tasks, or when creating, locating, or cleaning a worktree under worktree/.
---

# Worktree Development

Make every code change in `worktree/<repo>/<branch>/`; never edit `repos/`.

## Prepare a task

1. Resolve the harness root: `LAB=$(git rev-parse --show-toplevel)`.
2. Inspect the base clone under `repos/<repo>/` before writing.
3. Choose a branch named `feat/<topic>`, `fix/<issue>`, or `refactor/<scope>`.
4. Create or reuse the task worktree:

```bash
scripts/create-worktree.sh <owner>/<repo> feat/<topic>
```

The script imports or fast-forwards the base clone and prints the absolute worktree path. If the worktree already exists, use it rather than creating another one.

## Work safely

- Read and edit only the task worktree. Use absolute paths for file operations.
- Use `git -C worktree/<repo>/<branch> ...`; do not `cd` into managed repositories.
- For multiple tasks, plan non-overlapping files and give each task its own branch and worktree.
- The same branch cannot be checked out in two worktrees.

## Finish a task

```bash
git -C worktree/<repo>/<branch> add <files>
git -C worktree/<repo>/<branch> commit -m "feat(<scope>): <summary>"
git -C worktree/<repo>/<branch> push -u origin <branch>
```

Use `$git-operations` for pull-request creation and decision-log updates. After the PR merges, clean up:

```bash
git -C repos/<repo> worktree remove ../../worktree/<repo>/<branch>
git -C repos/<repo> branch -d <branch>
```

Set `WORKTREE_LAB_DIR=$(git rev-parse --show-toplevel)` only if root auto-detection fails.
