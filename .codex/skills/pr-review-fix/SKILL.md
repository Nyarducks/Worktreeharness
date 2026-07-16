---
name: pr-review-fix
description: Review a GitHub pull request in Worktreeharness and fix every finding. Use when asked to review a PR, request changes, post inline findings, address review feedback, or push fixes to an existing PR branch.
---

# Review and Fix a Pull Request

Never approve or merge a PR. Human reviewers perform those actions. Treat any finding, including a nit, as requiring changes; post it to the PR and fix it.

## Review

Gather the branch and head SHA, then inspect the diff:

```bash
PR=<number>
OWNER_REPO=<owner>/<repo>
BRANCH=$(gh pr view "$PR" --repo "$OWNER_REPO" --json headRefName -q .headRefName)
HEAD_SHA=$(gh pr view "$PR" --repo "$OWNER_REPO" --json headRefOid -q .headRefOid)
gh pr diff "$PR" --repo "$OWNER_REPO"
```

Check correctness, security, naming, layer boundaries, and tests. Record each finding with an in-diff file and line, severity (`critical`, `major`, or `nit`), and a concise explanation.

## Post findings

Post inline comments before making fixes:

```bash
gh api repos/$OWNER_REPO/pulls/$PR/comments -X POST \
  -f "commit_id=$HEAD_SHA" -f 'path=<file>' -F 'line=<line>' \
  -f 'side=RIGHT' -f 'body=**[major]** <explanation>'
```

The line must be within the diff hunk; otherwise use the API's diff position. Submit `gh pr review ... --request-changes` when findings exist. Do not submit a review when none exist.

## Fix every finding

Create or reuse the PR-branch worktree, then edit only there:

```bash
scripts/create-worktree.sh "$OWNER_REPO" "$BRANCH"
git -C worktree/<repo>/<branch> add <files>
git -C worktree/<repo>/<branch> commit -m "fix(<scope>): address review findings"
git -C worktree/<repo>/<branch> push origin "$BRANCH"
```

Use `$git-operations` to append the pushed commit to the PR decision log.

## Report completion

Post a PR summary listing findings, their file and line, and the fix commit. If there are no findings, post a concise `LGTM — no findings` comment, but do not approve the PR. Keep the worktree until the PR merges.
