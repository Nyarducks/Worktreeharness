#!/usr/bin/env bash
# test-setup-repo.sh — scripts/setup-repo.sh clones a repo into
# $LAB/repos/ on first run and fetches updates on later runs.
# `gh` is stubbed so clone resolves against a local bare origin.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LAB="${T}/lab"
make_lab "${LAB}"
export WORKTREE_LAB_DIR="${LAB}"
stub_gh
seed_origin TestRepo

echo "== clone on first run =="

out="$(WORKTREE_LAB_DIR="${LAB}" "${REPO_ROOT}/scripts/setup-repo.sh" owner/TestRepo)"
expect_eq "prints repo path" "${out}" "${LAB}/repos/TestRepo"
expect_file "repo cloned" "${LAB}/repos/TestRepo/.git" exists
expect_grep "gh repo clone invoked" "$(cat "${GH_STUB_LOG}")" "gh repo clone owner/TestRepo"

echo "== update on second run =="

# add a commit to the origin, then re-run — the base must fetch it
seed="${T}/seed-TestRepo"
git -C "${seed}" -c user.email=t@t -c user.name=t commit -qm second --allow-empty
git -C "${seed}" push -q "${STUB_ORIGIN}/TestRepo.git" main
before="$(git -C "${LAB}/repos/TestRepo" rev-parse origin/main)"
WORKTREE_LAB_DIR="${LAB}" "${REPO_ROOT}/scripts/setup-repo.sh" owner/TestRepo > /dev/null
after="$(git -C "${LAB}/repos/TestRepo" rev-parse origin/main)"
[[ "${before}" != "${after}" ]] && ok "existing clone fetches updates" || bad "existing clone fetches updates"

echo "== org resolution =="

out="$(WORKTREE_LAB_DIR="${LAB}" GH_ORG=other-org "${REPO_ROOT}/scripts/setup-repo.sh" TestRepo)"
expect_eq "GH_ORG resolves bare repo name" "${out}" "${LAB}/repos/TestRepo"

rm -rf "${LAB}/repos/TestRepo"
err="$(WORKTREE_LAB_DIR="${LAB}" "${REPO_ROOT}/scripts/setup-repo.sh" TestRepo 2>&1)"
rc=$?
expect_rc "no org -> error" "${rc}" nz
expect_grep "error message" "${err}" "cannot determine GitHub org"

echo ""
printf 'passed: %d  failed: %d\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
