---
name: parallel-worktree
description: Parallel development guide using git worktrees. Use when running multiple independent tasks concurrently, or when developing any repository managed by this harness — each task runs in an isolated worktree under ./worktree/<repo>/, main agent works directly in each worktree.
---

# Parallel Development with git worktrees

Workflow for implementing multiple independent tasks concurrently across one or more repositories. Each task gets a dedicated worktree; the main agent works directly in each worktree — no sub-agents are launched for implementation.

## Directory conventions

```
./repos/<repo-name>/              # Base repository (clone only — never edit directly)
./worktree/<repo-name>/<branch>/  # Active worktree; edit files here
```

All paths below are relative to the harness root. Resolve the harness root at any time with:

```bash
LAB=$(git rev-parse --show-toplevel)
```

## Step 1: Set up the base repository

Use `setup-repo.sh` to clone into `repos/` or fast-forward an existing clone to latest main:

```bash
REPO_PATH=$(scripts/setup-repo.sh <owner>/<repo>)
# → repos/<repo>  (absolute path printed to stdout)
```

The script prints the absolute path on stdout.

## Step 2: Investigate the codebase

Before writing any code, read the relevant files in `repos/<repo>/` using absolute paths. Identify:

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
scripts/create-worktree.sh <owner>/<repo> feat/topic-a
scripts/create-worktree.sh <owner>/<repo> feat/topic-b
# Paths: worktree/<repo>/feat/topic-a/  and  worktree/<repo>/feat/topic-b/
```

## Step 5: Implement each task

Work directly in each worktree using absolute paths. Always read before writing:

```bash
LAB=$(git rev-parse --show-toplevel)
grep -n '<symbol>' $LAB/worktree/<repo>/feat/topic-a/<file>
```

Edit using absolute worktree paths:

```
Edit: $LAB/worktree/<repo>/feat/topic-a/<path/to/file>
# where $LAB = output of: git rev-parse --show-toplevel
```

After completing a task, commit in that worktree:

```bash
git -C worktree/<repo>/feat/topic-a add <file1> <file2> ...
git -C worktree/<repo>/feat/topic-a commit -m "$(cat <<'EOF'
<type>(<scope>): <short imperative summary>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
git -C worktree/<repo>/feat/topic-a log --oneline -3
```

## Step 6: Create PRs

```bash
git -C worktree/<repo>/feat/topic-a push -u origin feat/topic-a
PR_URL=$(gh pr create --repo <owner>/<repo> --head feat/topic-a --title "..." --body "...")
PR=$(basename "$PR_URL")   # extract PR number from URL
```

Immediately after PR creation, log the initial commit to Decision Logs:

```bash
scripts/append-pr-log.sh <owner>/<repo> "$PR" worktree/<repo>/feat/topic-a <<'EOF'
### What changed
- <describe what this commit implements>

### Why
<rationale for the approach taken>
EOF
```

### Subsequent commits on the same PR

After every additional commit pushed to the PR branch, append another entry:

```bash
git -C worktree/<repo>/feat/topic-a add <files>
git -C worktree/<repo>/feat/topic-a commit -m "..."
git -C worktree/<repo>/feat/topic-a push origin feat/topic-a

scripts/append-pr-log.sh <owner>/<repo> "$PR" worktree/<repo>/feat/topic-a <<'EOF'
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
git -C repos/<repo> worktree remove ../../worktree/<repo>/feat/topic-a
git -C repos/<repo> branch -d feat/topic-a
```

List all worktrees for a repo:

```bash
git -C repos/<repo> worktree list
```

## Notes

- Each worktree shares `.git` with `repos/<repo>` but has its own working directory
- The same branch cannot be checked out in multiple worktrees simultaneously
- Never edit `repos/<repo>` directly — the guard hook enforces this
- Set `WORKTREE_LAB_DIR=<harness-root>` if auto-detection fails (e.g. `export WORKTREE_LAB_DIR=$(git rev-parse --show-toplevel)`)
- Never use `cd` to navigate into repos — use `git -C <path>` for git commands and absolute paths for file operations
