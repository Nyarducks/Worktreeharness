#!/usr/bin/env bash
# test-create-worktree.sh — scripts/create-worktree.sh creates
# worktree/<repo>/<branch> on a new branch from origin/main, refuses to
# overwrite an existing worktree, and installs harness git hooks.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LAB="${T}/lab"
make_lab "${LAB}"
export WORKTREE_LAB_DIR="${LAB}"
stub_gh
seed_origin TestRepo

echo "== creates worktree =="

out="$(WORKTREE_LAB_DIR="${LAB}" "${REPO_ROOT}/scripts/create-worktree.sh" owner/TestRepo feat/topic)"
expect_grep "prints path" "${out}" "Path:   ${LAB}/worktree/TestRepo/feat/topic"
expect_file "worktree dir exists" "${LAB}/worktree/TestRepo/feat/topic" exists

branch="$(git -C "${LAB}/worktree/TestRepo/feat/topic" rev-parse --abbrev-ref HEAD)"
expect_eq "branch checked out" "${branch}" "feat/topic"
base="$(git -C "${LAB}/worktree/TestRepo/feat/topic" rev-parse HEAD)"
origin_main="$(git -C "${LAB}/repos/TestRepo" rev-parse origin/main)"
expect_eq "based on origin/main" "${base}" "${origin_main}"

echo "== --detach creates a detached HEAD =="

out="$(WORKTREE_LAB_DIR="${LAB}" "${REPO_ROOT}/scripts/create-worktree.sh" --detach owner/TestRepo task/abc123)"
expect_grep "prints detached" "${out}" "HEAD:   detached at origin/main"
head_ref="$(git -C "${LAB}/worktree/TestRepo/task/abc123" rev-parse --abbrev-ref HEAD)"
expect_eq "HEAD detached" "${head_ref}" "HEAD"
base="$(git -C "${LAB}/worktree/TestRepo/task/abc123" rev-parse HEAD)"
expect_eq "based on origin/main" "${base}" "$(git -C "${LAB}/repos/TestRepo" rev-parse origin/main)"
expect_eq "no branch created" "$(git -C "${LAB}/repos/TestRepo" branch --list 'task/abc123')" ""

echo "== refuses to clobber =="

err="$(WORKTREE_LAB_DIR="${LAB}" "${REPO_ROOT}/scripts/create-worktree.sh" owner/TestRepo feat/topic 2>&1)"
rc=$?
expect_rc "existing worktree -> error" "${rc}" nz
expect_grep "error message" "${err}" "already exists"

echo "== installs harness git hooks =="

hooks_dir="$(git -C "${LAB}/repos/TestRepo" rev-parse --path-format=absolute --git-dir)/hooks"
expect_file "pre-commit installed" "${hooks_dir}/pre-commit" exists

echo "== usage =="

WORKTREE_LAB_DIR="${LAB}" "${REPO_ROOT}/scripts/create-worktree.sh" owner/TestRepo > /dev/null 2>&1
expect_rc "missing args -> usage error" "$?" nz

echo ""
printf 'passed: %d  failed: %d\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
