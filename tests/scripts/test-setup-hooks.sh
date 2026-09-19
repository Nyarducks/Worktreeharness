#!/usr/bin/env bash
# test-setup-hooks.sh — scripts/setup-hooks.sh symlinks scripts/hooks/*
# into the common git dir, and works identically from a linked worktree
# (hooks must land in the shared .git, not the worktree's private one).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "== installs into main repo =="

REPO="${T}/repo"
git init -q "${REPO}"
mkdir -p "${REPO}/scripts/hooks"
cp "${REPO_ROOT}/scripts/setup-hooks.sh" "${REPO}/scripts/"
printf '#!/bin/sh\nexit 0\n' > "${REPO}/scripts/hooks/pre-commit"

out="$(bash "${REPO}/scripts/setup-hooks.sh")"
expect_grep "reports install" "${out}" "git hooks installed"
hook="${REPO}/.git/hooks/pre-commit"
expect_file "pre-commit symlink" "${hook}" exists
[[ -L "${hook}" ]] && ok "installed as symlink" || bad "installed as symlink"

echo "== from a linked worktree, hooks land in the common git dir =="

git -C "${REPO}" -c user.email=t@t -c user.name=t commit -qm init --allow-empty
git -C "${REPO}" worktree add -q "${T}/linked" -b linked 2>/dev/null
rm -f "${REPO}/.git/hooks/pre-commit"   # prove the worktree call re-installs
mkdir -p "${T}/linked/scripts/hooks"
cp "${REPO_ROOT}/scripts/setup-hooks.sh" "${T}/linked/scripts/"
printf '#!/bin/sh\nexit 0\n' > "${T}/linked/scripts/hooks/pre-commit"

bash "${T}/linked/scripts/setup-hooks.sh" > /dev/null
expect_file "pre-commit lands in common hooks dir" "${REPO}/.git/hooks/pre-commit" exists
expect_file "worktree has no private hooks" "${T}/linked/.git/hooks" absent

echo ""
printf 'passed: %d  failed: %d\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
