---
name: git-operations
description: Git workflow guide for this harness. Use when cloning, branching, committing, or creating/editing PRs — enforces gh-based clone for private repos, feature branch from latest main, and PATCH-based PR edits.
---

# Git Operations Guide

## Clone a repository

Use `gh repo clone` for private repositories (bare `git clone` fails on auth):

```bash
gh repo clone <owner>/<repo>
```

## Branch policy

### Protected branches

Direct commits to `main` are blocked by the pre-commit hook. Always create a feature branch.

### Creating a feature branch

Always branch from the latest `main`.

```bash
git -C worktree/<repo>/<branch> checkout main
git -C worktree/<repo>/<branch> pull
```

Branch names must follow: `feat/<feature>`, `fix/<issue>`, `refactor/<scope>`.

## Commit

Use standard `git -C <worktree-path> add / commit`. Never commit directly in `repos/` — work only in `worktree/`.

## Creating a PR

**Always push the branch before running `gh pr create`.**

```bash
git -C worktree/<repo>/<branch> push -u origin <branch-name>
gh pr create \
  --repo <owner>/<repo> \
  --head <branch-name> \
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

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Always pass `--assignee @me` and `--label`.

## Labels

Apply labels based on the change content.

### Type labels

| Label | When |
|---|---|
| `bug` | Fixes a bug |
| `enhancement` | New feature or improvement |
| `dependencies` | Dependency version updates |
| `documentation` | Documentation changes |
| `ci` | CI/CD pipeline changes |

## Editing a PR body

`gh pr edit` may fail with a deprecation warning — use the REST API PATCH instead:

```bash
gh api repos/<owner>/<repo>/pulls/<number> -X PATCH \
  -f title="<new title>" \
  -f body="<new body>" \
  --jq '.title'
```

## Replying to PR review comments

```bash
gh api repos/<owner>/<repo>/pulls/<pull_number>/comments/<comment_id>/replies \
  -X POST -f 'body=reply text'
```

Pitfalls:
1. **Missing pull number in path** — `/pulls/{pull_number}/comments/{comment_id}/replies`; omitting it returns 404.
2. **Backticks in double-quoted strings** — always use single quotes for `-f body=` when the body contains backticks.

## Merging a PR

```bash
gh pr merge <number> --repo <owner>/<repo> --merge --delete-branch
```

Always use `--merge` (merge commit). Do not use `--squash` or `--rebase`.

## Viewing raw file content

```bash
gh api repos/<owner>/<repo>/contents/<path> \
  -H "Accept: application/vnd.github.raw"

# On a specific branch:
gh api "repos/<owner>/<repo>/contents/<path>?ref=<branch>" \
  -H "Accept: application/vnd.github.raw"
```

## Cleaning up after a merged PR

```bash
git -C repos/<repo> worktree remove ../../worktree/<repo>/<branch>
git -C repos/<repo> branch -d <branch>
```
