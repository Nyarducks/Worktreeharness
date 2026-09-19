#!/usr/bin/env bash
# test-spawn-repo-agent.sh — scripts/spawn-repo-agent.sh end to end with
# stubbed gh/herdr/bwrap: asserts the worktree is created, the herdr call
# sequence is right, the sandbox wrapper is applied, and the prompt carries
# the self-naming preamble. No network or real herdr session involved.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

lab="${t}/lab"
make_lab "${lab}"
export WORKTREE_LAB_DIR="${lab}"
export HOME="${t}/home"          # keep ~/.gemini, ~/.claude.json trust edits off the real HOME
mkdir -p "${HOME}"
stub_gh
stub_herdr
stub_bwrap
seed_origin SpawnRepo

spawn="${repo_root}/scripts/spawn-repo-agent.sh"

echo "== sandboxed dispatch (default) =="

out="$("${spawn}" owner/SpawnRepo -- "fix the flaky test")"
expect_grep "reports pane" "${out}" "Dispatched to pane pane-1"
wt="$(find "${lab}/worktree/SpawnRepo/task" -mindepth 1 -maxdepth 1 -type d | head -1)"
[[ -n "${wt}" ]] && ok "task worktree created" || bad "task worktree created"
expect_eq "task worktree is detached" \
  "$(git -C "${wt}" rev-parse --abbrev-ref HEAD)" "HEAD"

log="$(cat "${HERDR_STUB_LOG}")"
expect_grep "workspace created" "${log}" "herdr workspace create"
expect_grep "pane run (sandboxed launch)" "${log}" "herdr pane run pane-1 exec bwrap"
expect_grep "agent wait" "${log}" "herdr agent wait pane-1"
expect_grep "prompt submitted" "${log}" "herdr agent prompt pane-1"
expect_grep "prompt carries self-rename" "${log}" "herdr agent rename pane-1"
expect_grep "prompt carries tab rename" "${log}" "herdr tab rename tab-1"
expect_grep "prompt carries task" "${log}" "fix the flaky test"
expect_not_grep "no bare agent start" "${log}" "herdr agent start"

echo "== --no-sandbox uses agent start =="

: > "${HERDR_STUB_LOG}"
out="$("${spawn}" --no-sandbox --kind devin owner/SpawnRepo -- "ship it")"
expect_grep "reports pane" "${out}" "Dispatched to pane pane-1"
log="$(cat "${HERDR_STUB_LOG}")"
expect_grep "agent start invoked" "${log}" "herdr agent start w-"
expect_grep "kind devin" "${log}" "--kind devin"
expect_grep "devin flags" "${log}" "--permission-mode dangerous"
expect_not_grep "no bwrap pane run" "${log}" "pane run pane-1 exec bwrap"

echo "== requires herdr session =="

err="$(HERDR_ENV= "${spawn}" owner/SpawnRepo -- "x" 2>&1)"
rc=$?
expect_rc "HERDR_ENV unset -> error" "${rc}" nz
expect_grep "error message" "${err}" "not running inside a herdr session"

echo "== requires task text =="

"${spawn}" owner/SpawnRepo -- > /dev/null 2>&1
expect_rc "missing task -> usage error" "$?" nz

echo ""
printf 'passed: %d  failed: %d\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
