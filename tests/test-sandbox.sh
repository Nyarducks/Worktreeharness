#!/usr/bin/env bash
# test-sandbox.sh — verifies that scripts/lib/sandbox-wrap.sh builds a
# bubblewrap command line that actually confines a spawned process to its
# worktree (kernel mount-namespace enforcement, agent-agnostic).
#
# Live tests run a real `bwrap ... -- bash -c ...` against a sandboxed lab
# with a real linked worktree, then assert effects on the REAL filesystem
# (a write either landed or it didn't).
#
# Usage: bash tests/test-sandbox.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/sandbox-wrap.sh
source "${REPO_ROOT}/scripts/lib/sandbox-wrap.sh"
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The scratch root must NOT live under /tmp: the sandbox mounts a tmpfs over
# /tmp, which would orphan a worktree bind beneath it (the worktree-under-/tmp
# fallback is covered by a separate unit check).
SAND_BASE="/var/tmp"
[[ -w "${SAND_BASE}" ]] || SAND_BASE="${HOME}"
SAND="$(realpath "$(mktemp -d "${SAND_BASE}/wth-sandbox.XXXXXX")")"
trap 'rm -rf "${SAND}"' EXIT

expect_rc() { # <name> <rc> <want: 0|nz>
  if [[ "$3" == 0 && "$2" -eq 0 ]] || [[ "$3" == nz && "$2" -ne 0 ]]; then
    ok "$1"
  else
    bad "$1"; printf '       rc=%s\n' "$2"
  fi
}
expect_file() { # <name> <path> <exists|absent>
  if [[ "$3" == exists && -e "$2" ]] || [[ "$3" == absent && ! -e "$2" ]]; then
    ok "$1"
  else
    bad "$1"; printf '       path=%s\n' "$2"
  fi
}
expect_grep()     { [[ "$2" == *"$3"* ]] && ok "$1" || { bad "$1"; printf '       missing: %s\n' "$3"; }; }
expect_not_grep() { [[ "$2" != *"$3"* ]] && ok "$1" || { bad "$1"; printf '       unexpected: %s\n' "$3"; }; }

# run_sandbox <bash-script> [kind] — run <script> inside the wrapped sandbox,
# against worktree $WT (set by the caller). Prints captured output.
WT=""
run_sandbox() {
  local wrapped
  wrapped="$(sandbox_wrap_cmd "${WT}" "${2:-claude}" bash -c "$1")" || return 99
  bash -c "${wrapped}" 2>&1
}

# ---------------- unit: command construction ----------------
echo "== unit: command construction =="

sandbox_wrap_cmd "" "" bash > /dev/null 2>&1
expect_rc "usage error is non-zero" "$?" nz

out="$(sandbox_wrap_cmd "/some/wt" claude bash -c 'echo hi')"
expect_rc "wrap command builds" "$?" 0
expect_grep "emits bwrap"        "${out}" "bwrap"
expect_grep "chdir to worktree"  "${out}" "--chdir /some/wt"
expect_grep "worktree rw bind"   "${out}" "--bind /some/wt /some/wt"
expect_grep "command tail"       "${out}" "bash -c"

# worktree under /tmp → /tmp is bound rw instead of replaced by tmpfs
out="$(sandbox_wrap_cmd "/tmp/wt-x" claude bash)"
expect_grep     "tmp worktree: /tmp bound"   "${out}" "--bind /tmp /tmp"
expect_not_grep "tmp worktree: no /tmp tmpfs" "${out}" "--tmpfs /tmp"

# nonexistent bind sources are skipped (bwrap would fail on a missing source)
MISSING="${SAND}/does-not-exist"
out="$(sandbox_wrap_cmd "/some/wt" claude bash)"
expect_not_grep "missing path not bound" "${out}" "${MISSING}"

# bwrap missing → rc 3 (fail closed at the call site)
( PATH="/nonexistent"; sandbox_wrap_cmd "/x" claude bash ) > /dev/null 2>&1
[[ $? -eq 3 ]] && ok "bwrap missing -> rc 3" || bad "bwrap missing -> rc 3"

# per-kind binds appear only when the dir exists on the host
out="$(sandbox_wrap_cmd "/some/wt" devin devin)"
if [[ -d "${HOME}/.config/devin" ]]; then
  expect_grep "devin kind binds config dir" "${out}" ".config/devin"
else
  expect_not_grep "devin kind skips absent config dir" "${out}" ".config/devin"
fi

# an agent binary installed under $HOME is rebound at its PATH location —
# otherwise the tmpfs'd $HOME hides it from execvp
DEVIN_BIN="$(command -v devin 2>/dev/null || true)"
if [[ -n "${DEVIN_BIN}" && "${DEVIN_BIN}" == "${HOME}/"* ]]; then
  expect_grep "agent binary under HOME is rebound" "${out}" "--bind"
  expect_grep "agent binary rebound at PATH path" "${out}" "${DEVIN_BIN}"
fi

# herdr is always rebound too — workers self-rename via `herdr agent rename`
HERDR_BIN="$(command -v herdr 2>/dev/null || true)"
if [[ -n "${HERDR_BIN}" && "${HERDR_BIN}" == "${HOME}/"* ]]; then
  expect_grep "herdr binary under HOME is rebound" "${out}" "${HERDR_BIN}"
fi

# ---------------- live: real sandbox confinement ----------------
if ! command -v bwrap > /dev/null 2>&1; then
  echo "== live tests skipped: bwrap not installed =="
else
  echo "== live: sandboxed process inside a split lab =="
  LAB="${SAND}/lab"
  build_split "${LAB}"
  WT="${LAB}/worktree/TestRepo/feat-x"

  run_sandbox 'touch wt-file.txt' > /dev/null
  expect_file "write inside worktree persists" "${WT}/wt-file.txt" exists

  run_sandbox 'git add wt-file.txt && git -c user.email=t@t -c user.name=t commit -qm sb-test' > /dev/null
  last_commit="$(git -C "${WT}" log -1 --pretty=%s 2>/dev/null)"
  [[ "${last_commit}" == "sb-test" ]] \
    && ok "git commit works (base .git bound)" \
    || bad "git commit works (base .git bound)"

  run_sandbox "touch ${LAB}/escape.txt 2>/dev/null; true" > /dev/null
  expect_file "write at lab root blocked" "${LAB}/escape.txt" absent

  run_sandbox 'touch /etc/wth-evil 2>/dev/null; true' > /dev/null
  expect_file "/etc write blocked" "/etc/wth-evil" absent

  # $HOME is a tmpfs: host content hidden, writes don't persist
  MARKER="${HOME}/.wth-sbx-marker-$$"
  touch "${MARKER}"
  out="$(run_sandbox 'ls -a ~')"
  expect_not_grep "home contents hidden" "${out}" ".wth-sbx-marker-$$"
  run_sandbox "touch ~/wth-evil-$$; true" > /dev/null
  expect_file "home write is ephemeral" "${HOME}/wth-evil-$$" absent
  rm -f "${MARKER}"

  run_sandbox 'touch /tmp/wth-ephemeral-test; true' > /dev/null
  expect_file "/tmp write is ephemeral" "/tmp/wth-ephemeral-test" absent

  if [[ -d "${HOME}/.ssh" ]]; then
    # remotes are https via `gh` — nothing under ~/.ssh is bound at all
    PRIV_MARKER="${HOME}/.ssh/wth-privkey-$$"
    touch "${PRIV_MARKER}"
    out="$(run_sandbox 'ls ~/.ssh')"
    expect_not_grep "ssh private keys hidden" "${out}" "wth-privkey-$$"
    rm -f "${PRIV_MARKER}"
  fi
  if [[ -S "${SSH_AUTH_SOCK:-}" ]]; then
    run_sandbox 'test -S "${SSH_AUTH_SOCK}"' > /dev/null 2>&1
    expect_rc "ssh agent socket not bound" "$?" 1
  fi
  if [[ -S "${HOME}/.config/herdr/herdr.sock" ]]; then
    run_sandbox 'test -S ~/.config/herdr/herdr.sock' > /dev/null 2>&1
    expect_rc "herdr socket reachable" "$?" 0
  fi
  if [[ -f "${HOME}/.gitconfig" ]]; then
    run_sandbox 'test -r ~/.gitconfig' > /dev/null 2>&1
    expect_rc "~/.gitconfig readable" "$?" 0
    run_sandbox 'touch ~/.gitconfig 2>/dev/null' > /dev/null 2>&1
    expect_rc "~/.gitconfig read-only" "$?" nz
  fi

  # pid namespace: sandbox sees only its own processes
  procs="$(run_sandbox 'ls /proc | grep -cE "^[0-9]+"')"
  [[ "${procs}" =~ ^[0-9]+$ && ${procs} -lt 20 ]] \
    && ok "pid namespace isolates process table (${procs} visible)" \
    || bad "pid namespace isolates process table (saw: ${procs})"

  # an agent CLI installed under $HOME still launches inside the sandbox
  if [[ -n "${DEVIN_BIN:-}" && "${DEVIN_BIN}" == "${HOME}/"* ]]; then
    out="$(run_sandbox 'devin --version' devin)"
    expect_grep "home-installed agent binary runs" "${out}" "devin"
  fi

  # herdr CLI stays usable inside the sandbox (self-rename path)
  if [[ -n "${HERDR_BIN:-}" && "${HERDR_BIN}" == "${HOME}/"* ]]; then
    run_sandbox 'command -v herdr' > /dev/null 2>&1
    expect_rc "herdr binary usable inside sandbox" "$?" 0
  fi
fi

echo
echo "passed: ${PASS}  failed: ${FAIL}"
if [[ ${FAIL} -gt 0 ]]; then
  printf 'failed tests:\n'
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
