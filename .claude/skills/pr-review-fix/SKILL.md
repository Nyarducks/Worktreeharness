---
name: pr-review-fix
description: PR review and auto-fix guide. Use when reviewing a pull request — posts all findings as GitHub PR comments, then fixes every finding directly in a worktree and pushes the fix commit back to the PR branch.
---

# PR Review & Fix Guide

## Approval policy

> **Approve only when there are zero findings of any kind — including nits.**
>
> A single nit is sufficient grounds for Request Changes. Do not rationalise borderline cases as "too minor to block". If something is worth noting, it blocks approval.

Post findings as GitHub PR comments, then fix every one — including nits — in a worktree and push the fix commit back.

## Step 1: Gather PR context

```bash
PR=<pull_number>
OWNER_REPO=<owner>/<repo>

BRANCH=$(gh pr view $PR --repo $OWNER_REPO --json headRefName -q .headRefName)
HEAD_SHA=$(gh pr view $PR --repo $OWNER_REPO --json headRefOid -q .headRefOid)

gh pr diff $PR --repo $OWNER_REPO
```

## Step 2: Review the diff

Review criteria: correctness, naming conventions, layer boundary violations, test coverage, and security. For each finding record:

| Field | Value |
|---|---|
| `file` | Relative file path |
| `line` | Line number (must be in the diff hunk) |
| `severity` | `critical` / `major` / `nit` |
| `description` | Concise explanation |

**Every finding must be fixed — nits included.**

## Step 3: Post inline comments

For each finding:

```bash
gh api repos/$OWNER_REPO/pulls/$PR/comments \
  -X POST \
  -f "commit_id=$HEAD_SHA" \
  -f 'path=<file>' \
  -F 'line=<line_number>' \
  -f 'side=RIGHT' \
  -f 'body=**[severity]** description

---
🤖 Sent from [Claude Code](https://claude.ai/code)'
```

Pitfalls:
1. **Backticks in `-f body=`** — always use single quotes.
2. **`line` must be in the diff** — use `position` (diff line offset) if the absolute line is not in the hunk.
3. **Missing pull number in path** — `/pulls/{pull_number}/comments/{comment_id}/replies` requires `{pull_number}`.

### Replying to a review comment

```bash
gh api repos/$OWNER_REPO/pulls/$PR/comments/<comment_id>/replies \
  -X POST \
  -f 'body=reply text

---
🤖 Sent from [Claude Code](https://claude.ai/code)'
```

## Step 4: Submit a Request Changes review

```bash
gh pr review $PR --repo $OWNER_REPO --request-changes --body "$(cat <<'EOF'
## Review verdict: Request Changes

All inline findings must be resolved before this PR can be approved.
See individual comments for details.

---
🤖 Sent from [Claude Code](https://claude.ai/code)
EOF
)"
```

Skip if there are zero findings — proceed to Step 9.

## Step 5: Create a worktree on the PR branch

```bash
scripts/create-worktree.sh $OWNER_REPO $BRANCH
# Worktree path: worktree/<repo>/<branch>/  (relative to harness root)
```

If the worktree already exists, skip creation and use the existing path.

## Step 6: Investigate before fixing

Read the relevant files in the worktree directly (use the absolute path printed by `create-worktree.sh`):

```bash
LAB=$(git rev-parse --show-toplevel)
# Read: $LAB/worktree/<repo>/<branch>/<path/to/file>
```

## Step 7: Fix findings

Edit files in the worktree using absolute paths:

```bash
# Edit: $LAB/worktree/<repo>/<branch>/<path/to/file>
# where $LAB = output of: git rev-parse --show-toplevel
```

After all edits, commit:

```bash
git -C worktree/<repo>/<branch>/ add <file1> <file2> ...
git -C worktree/<repo>/<branch>/ commit -m "$(cat <<'EOF'
fix(<scope>): address review findings

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
git -C worktree/<repo>/<branch>/ log --oneline -3
```

## Step 8: Push the fix commit

```bash
git -C worktree/<repo>/<branch>/ push origin $BRANCH
```

No new PR needed — the fix commit lands on the existing PR branch.

## Step 9: Post a summary comment and approve

```bash
gh pr comment $PR --repo $OWNER_REPO --body "$(cat <<'EOF'
## Review-Fix Summary

### Findings
| Severity | File | Line | Fixed? |
|---|---|---|---|
| critical | foo/bar.go | 42 | ✅ auto-fixed |

### Fix commit
Commit: <hash>

---
🤖 Sent from [Claude Code](https://claude.ai/code)
EOF
)"

gh pr review $PR --repo $OWNER_REPO --approve --body "$(cat <<'EOF'
All findings fixed — LGTM.

---
🤖 Sent from [Claude Code](https://claude.ai/code)
EOF
)"
```

If zero findings:

```bash
gh pr review $PR --repo $OWNER_REPO --approve --body "$(cat <<'EOF'
LGTM — no findings.

---
🤖 Sent from [Claude Code](https://claude.ai/code)
EOF
)"
```

## Notes

- Do not summarise findings in the chat — the PR is the canonical record.
- Keep the worktree after the fix in case follow-up changes are needed. Clean up only after the PR merges.
- Edit files directly using their absolute worktree paths.
