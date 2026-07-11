---
name: pr-review-fix
description: PR review and auto-fix guide. Use when reviewing a pull request — posts all findings as GitHub PR comments under the Claude GitHub App identity, then fixes every finding directly in a worktree and pushes the fix commit back to the PR branch.
---

# PR Review & Fix Guide

## Approval policy

> **Approve only when there are zero findings of any kind — including nits.**
>
> A single nit is sufficient grounds for Request Changes. If something is worth noting, it blocks approval.

All comments are posted under the **Claude GitHub App** identity (shows as `<app-name>[bot]` in GitHub), not as your personal account.

---

## Prerequisites: GitHub App token

All `gh api` calls that post comments or reviews must use a GitHub App installation token instead of the user's default `gh` credentials.

### One-time setup

1. Create a GitHub App at **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**.
   - Name: e.g. `Claude Code`
   - Permissions → Pull requests: **Read & Write**
   - Permissions → Contents: **Read** (for reading file content via API)
   - Uncheck "Webhook active" unless you need it
2. After creation, note the **App ID** shown on the app's settings page.
3. Under **Private keys**, generate and download a `.pem` key file. Store it outside the repository, e.g. `~/.config/github-apps/claude-code.pem`.
4. Install the App on the target repository: **App settings → Install App → select repo**.

### Environment variables

Export these before running any review commands (add to `~/.bashrc` or `~/.zshrc`):

```bash
export GITHUB_APP_ID=<numeric-app-id>
export GITHUB_APP_PRIVATE_KEY_PATH="${HOME}/.config/github-apps/claude-code.pem"
```

### Obtain a token

```bash
# Prints a short-lived installation token (valid ~1 hour)
BOT_TOKEN="$(scripts/github-app-token.sh <owner>/<repo>)"
```

Pass `GITHUB_TOKEN="${BOT_TOKEN}"` to every `gh api` call that should appear as the bot. Read-only `gh` calls (diff, view) can use the default user credentials.

---

## Step 1: Gather PR context

```bash
PR=<pull_number>
OWNER_REPO=<owner>/<repo>

BRANCH="$(gh pr view "${PR}" --repo "${OWNER_REPO}" --json headRefName -q .headRefName)"
HEAD_SHA="$(gh pr view "${PR}" --repo "${OWNER_REPO}" --json headRefOid -q .headRefOid)"

gh pr diff "${PR}" --repo "${OWNER_REPO}"

# Obtain bot token once; reuse for all posting steps
BOT_TOKEN="$(scripts/github-app-token.sh "${OWNER_REPO}")"
```

## Step 2: Review the diff

Review criteria: correctness, naming conventions, layer boundary violations, test coverage, security. For each finding record:

| Field | Value |
|---|---|
| `file` | Relative file path |
| `line` | Line number (must be in the diff hunk) |
| `severity` | `critical` / `major` / `nit` |
| `description` | Concise explanation |

**Every finding must be fixed — nits included.**

## Step 3: Post inline comments as the bot

```bash
GITHUB_TOKEN="${BOT_TOKEN}" gh api "repos/${OWNER_REPO}/pulls/${PR}/comments" \
  -X POST \
  -f "commit_id=${HEAD_SHA}" \
  -f 'path=<file>' \
  -F 'line=<line_number>' \
  -f 'side=RIGHT' \
  -f 'body=**[severity]** description'
```

Pitfalls:
1. **Backticks in `-f body=`** — always use single quotes.
2. **`line` must be in the diff** — use `position` (diff line offset) if the absolute line is not in the hunk.
3. **Missing pull number in path** — `/pulls/{pull_number}/comments/{comment_id}/replies` requires `{pull_number}`.

## Step 4: Submit a Request Changes review as the bot

```bash
GITHUB_TOKEN="${BOT_TOKEN}" gh pr review "${PR}" --repo "${OWNER_REPO}" \
  --request-changes --body "$(cat <<'EOF'
## Review verdict: Request Changes

All inline findings must be resolved before this PR can be approved.
See individual comments for details.
EOF
)"
```

Skip if there are zero findings — proceed to Step 9.

## Step 5: Create a worktree on the PR branch

```bash
scripts/create-worktree.sh "${OWNER_REPO}" "${BRANCH}"
# Worktree path: worktree/<repo>/<branch>/  (relative to harness root)
```

If the worktree already exists, skip creation and use the existing path.

## Step 6: Investigate before fixing

```bash
LAB="$(git rev-parse --show-toplevel)"
# Read: ${LAB}/worktree/<repo>/<branch>/<path/to/file>
```

## Step 7: Fix findings

Edit files in the worktree using absolute paths:

```bash
# Edit: ${LAB}/worktree/<repo>/<branch>/<path/to/file>
```

After all edits, commit:

```bash
git -C "worktree/<repo>/<branch>" add <file1> <file2> ...
git -C "worktree/<repo>/<branch>" commit -m "$(cat <<'EOF'
fix(<scope>): address review findings

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
git -C "worktree/<repo>/<branch>" log --oneline -3
```

## Step 8: Push the fix commit

```bash
git -C "worktree/<repo>/<branch>" push origin "${BRANCH}"
```

No new PR needed — the fix commit lands on the existing PR branch.

## Step 9: Post summary comment and approve as the bot

```bash
GITHUB_TOKEN="${BOT_TOKEN}" gh pr comment "${PR}" --repo "${OWNER_REPO}" \
  --body "$(cat <<'EOF'
## Review-Fix Summary

### Findings
| Severity | File | Line | Fixed? |
|---|---|---|---|
| critical | foo/bar.go | 42 | ✅ auto-fixed |

### Fix commit
Commit: <hash>
EOF
)"

GITHUB_TOKEN="${BOT_TOKEN}" gh pr review "${PR}" --repo "${OWNER_REPO}" \
  --approve --body "All findings fixed — LGTM."
```

If zero findings:

```bash
GITHUB_TOKEN="${BOT_TOKEN}" gh pr review "${PR}" --repo "${OWNER_REPO}" \
  --approve --body "LGTM — no findings."
```

---

## Notes

- `BOT_TOKEN` is valid for ~1 hour. Re-run `github-app-token.sh` if a session spans longer.
- Read-only commands (`gh pr view`, `gh pr diff`) do not need `GITHUB_TOKEN` override — they use your personal credentials, which is fine.
- Do not summarise findings in the chat — the PR is the canonical record.
- Keep the worktree after the fix in case follow-up changes are needed. Clean up only after the PR merges.
