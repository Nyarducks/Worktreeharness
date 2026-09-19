---
name: worktreeharness-development
description: Development workflow for the Worktreeharness repository itself. Use when the task targets this repo — the orchestrator creates the worktree itself and works in it directly. For any other repository, use worktree-development (herdr dispatch) instead.
---

# Worktreeharness Development

Workflow for developing **the Worktreeharness repository itself**. The
orchestrator does the work directly in a self-created worktree — no worker
is dispatched. Tasks targeting any *other* repository go through
`worktree-development` (herdr dispatch); the orchestrator never edits
other repos in-process.

Use `git-operations` for clone/branch/commit/PR discipline — that skill is
scoped to this workflow only.

## Directory conventions

```
./repos/<repo-name>/              # Base repository (clone only — never edit directly)
./worktree/<repo-name>/<branch>/  # Active worktree; edit files here
```

All paths below are relative to the lab root. Resolve it at any time with:

```bash
LAB=$(git rev-parse --show-toplevel)
```

## Step 1: Set up the base repository

Use `setup-repo.sh` to clone into `repos/` or fast-forward an existing clone to latest main:

```bash
REPO_PATH=$(scripts/setup-repo.sh <owner>/Worktreeharness)
# → repos/Worktreeharness  (absolute path printed to stdout)
```

The script prints the absolute path on stdout.

## Step 2: Investigate the codebase

Before writing any code, read the relevant files in `repos/Worktreeharness/` using absolute paths. Identify:

- Which files will change
- Cross-cutting interfaces or contracts
- Tasks that can be parallelised (non-overlapping changed files) vs. sequential

## Step 3: Plan tasks

Document the plan before touching any files:

| Task | Branch | Files | Depends on |
|---|---|---|---|
| Implement X | feat/topic-a | path/to/file | — |
| Implement Y | feat/topic-b | path/to/other | — |

## Step 4: Create worktrees

```bash
scripts/create-worktree.sh <owner>/Worktreeharness feat/topic-a
scripts/create-worktree.sh <owner>/Worktreeharness feat/topic-b
# Paths: worktree/Worktreeharness/feat/topic-a/  and  worktree/Worktreeharness/feat/topic-b/
```

Self-created worktrees get a named branch (`feat/`, `fix/`, `refactor/`).
The detached-HEAD initial state is for dispatched task worktrees only —
do not pass `--detach` here.

## Step 5: Implement each task

Work directly in each worktree using absolute paths. Always read before writing:

```bash
LAB=$(git rev-parse --show-toplevel)
grep -n '<symbol>' $LAB/worktree/Worktreeharness/feat/topic-a/<file>
```

Edit using absolute worktree paths:

```
Edit: $LAB/worktree/Worktreeharness/feat/topic-a/<path/to/file>
# where $LAB = output of: git rev-parse --show-toplevel
```

After completing a task, commit in that worktree:

```bash
git -C worktree/Worktreeharness/feat/topic-a add <file1> <file2> ...
git -C worktree/Worktreeharness/feat/topic-a commit -m "$(cat <<'EOF'
<type>(<scope>): <short imperative summary>
EOF
)"
git -C worktree/Worktreeharness/feat/topic-a log --oneline -3
```

Docs are part of the change (AGENTS.md rule 4): update `docs/design/` in
the same commit as any behavior change, and record significant decisions
as `docs/adr/NNNN-<slug>.md`. Run the test suites in `tests/` before
pushing — see `CONTRIBUTING.md`.

## Step 6: Create PRs

**PR title, body, and all Decision Log entries must be written in English.**

```bash
git -C worktree/Worktreeharness/feat/topic-a push -u origin feat/topic-a
PR_URL=$(gh pr create \
  --repo <owner>/Worktreeharness \
  --head feat/topic-a \
  --title "<title>" \
  --assignee @me \
  --label "<labels>" \
  --body "$(cat <<'EOF'
## Summary

- change 1
- change 2

## Background

Motivation and context

## Test plan

- [ ] item 1
- [ ] item 2
EOF
)")
PR=$(basename "$PR_URL")   # extract PR number from URL
```

Immediately after PR creation, log the initial commit to Decision Logs:

```bash
scripts/append-pr-log.sh <owner>/Worktreeharness "$PR" worktree/Worktreeharness/feat/topic-a <<'EOF'
### What changed
- <describe what this commit implements>

### Why
<rationale for the approach taken>
EOF
```

### Subsequent commits on the same PR

After every additional commit pushed to the PR branch, append another entry:

```bash
git -C worktree/Worktreeharness/feat/topic-a add <files>
git -C worktree/Worktreeharness/feat/topic-a commit -m "..."
git -C worktree/Worktreeharness/feat/topic-a push origin feat/topic-a

scripts/append-pr-log.sh <owner>/Worktreeharness "$PR" worktree/Worktreeharness/feat/topic-a <<'EOF'
### What changed
- <describe changes in this commit>

### Why
<reason: review feedback / bug found / design refinement / etc.>
EOF
```

Each entry is collapsed by default under a `<details>` block. The summary line is `<commit message> (<short SHA>)`.

Edit PR body via REST API PATCH if needed (`gh pr edit` may fail with a deprecation warning):

```bash
gh api repos/<owner>/<repo>/pulls/<number> -X PATCH \
  -f title="..." -f body="..." --jq '.title'
```

## Step 7: Cleanup

After PRs are merged, remove worktrees and branches:

```bash
git -C repos/Worktreeharness worktree remove ../../worktree/Worktreeharness/feat/topic-a
git -C repos/Worktreeharness branch -d feat/topic-a
```

List all worktrees for a repo:

```bash
git -C repos/Worktreeharness worktree list
```

## Notes

- Each worktree shares `.git` with `repos/Worktreeharness` but has its own working directory
- The same branch cannot be checked out in multiple worktrees simultaneously
- Never edit `repos/<repo>` directly — the guard hook enforces this
- Set `WORKTREE_LAB_DIR=<lab-root>` if auto-detection fails (e.g. `export WORKTREE_LAB_DIR=$(git rev-parse --show-toplevel)`)
- Never use `cd` to navigate into repos — use `git -C <path>` for git commands and absolute paths for file operations
