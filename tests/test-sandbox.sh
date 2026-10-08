#!/usr/bin/env bash
# test-sandbox.sh — verifies that scripts/lib/sandbox-wrap.sh builds a
# sandboxed command line that actually confines a spawned process to its
# worktree, enforced by the OS: a bubblewrap mount namespace on Linux,
# a Seatbelt profile via sandbox-exec on macOS.
#
# Live tests run the real platform backend against a sandboxed lab with a
# real linked worktree, then assert effects on the REAL filesystem (a
# write either landed or it didn't).
#
# Usage: bash tests/test-sandbox.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/sandbox-wrap.sh
source "${repo_root}/scripts/lib/sandbox-wrap.sh"
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

os="$(uname -s)"

# The scratch root must NOT live under /tmp on Linux: the sandbox mounts a
# tmpfs over /tmp, which would orphan a worktree bind beneath it. On macOS
# it must not live under the sandbox's writable scratch either (/tmp,
# $TMPDIR): an "outside the worktree" write landing in an allowed dir is
# not a confinement violation — the lab goes under $HOME instead, where
# writes are denied.
case "${os}" in
  Darwin) sand_base="${HOME}" ;;
  *)
    sand_base="/var/tmp"
    [[ -w "${sand_base}" ]] || sand_base="${HOME}"
    ;;
esac
sand="$(realpath "$(mktemp -d "${sand_base}/wth-sandbox.XXXXXX")")"
trap 'rm -rf "${sand}"' EXIT

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
expect_grep() { # <name> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then
    ok "$1"
  else
    bad "$1"; printf '       missing: %s\n' "$3"
  fi
}
expect_not_grep() { # <name> <haystack> <needle>
  if [[ "$2" != *"$3"* ]]; then
    ok "$1"
  else
    bad "$1"; printf '       unexpected: %s\n' "$3"
  fi
}

# run_sandbox <bash-script> [kind] — run <script> inside the wrapped sandbox,
# against worktree $wt (set by the caller). Prints captured output.
wt=""
run_sandbox() {
  local wrapped
  wrapped="$(sandbox_wrap_cmd "${wt}" "${2:-claude}" bash -c "$1")" || return 99
  # sandbox-exec inherits the caller's cwd — start inside the worktree like
  # a herdr pane (created with --cwd <worktree>) does; bwrap overrides with
  # --chdir anyway
  ( cd "${wt}" && bash -c "${wrapped}" ) 2>&1
}

# ---------------- unit: command construction ----------------
echo "== unit: command construction =="

sandbox_wrap_cmd "" "" bash > /dev/null 2>&1
expect_rc "usage error is non-zero" "$?" nz

case "${os}" in
Linux)
  out="$(sandbox_wrap_cmd "/some/wt" claude bash -c 'echo hi')"
  expect_rc "wrap command builds" "$?" 0
  expect_grep "emits bwrap"        "${out}" "bwrap"
  expect_grep "chdir to worktree"  "${out}" "--chdir /some/wt"
  expect_grep "worktree rw bind"   "${out}" "--bind /some/wt /some/wt"
  expect_grep "command tail"       "${out}" "bash -c"

  # herdr pane run types the line before the shell reads input: 1024-byte
  # cap. Use a realistic lab-style worktree path and agent flags.
  long_wt="${HOME}/Development/lab/worktree/some-org-repo-name/feat/a-fairly-long-branch-name"
  out="$(sandbox_wrap_cmd "${long_wt}" claude claude --permission-mode bypassPermissions)"
  if ((${#out} < 1024)); then ok "command line under 1024 bytes"; else bad "command line under 1024 bytes (${#out})"; fi

  # worktree under /tmp → /tmp is bound rw instead of replaced by tmpfs
  out="$(sandbox_wrap_cmd "/tmp/wt-x" claude bash)"
  expect_grep     "tmp worktree: /tmp bound"   "${out}" "--bind /tmp /tmp"
  expect_not_grep "tmp worktree: no /tmp tmpfs" "${out}" "--tmpfs /tmp"

  # nonexistent bind sources are skipped (bwrap would fail on a missing source)
  missing="${sand}/does-not-exist"
  out="$(sandbox_wrap_cmd "/some/wt" claude bash)"
  expect_not_grep "missing path not bound" "${out}" "${missing}"

  # per-kind binds appear only when the dir exists on the host
  out="$(sandbox_wrap_cmd "/some/wt" devin devin)"
  if [[ -d "${HOME}/.config/devin" ]]; then
    expect_grep "devin kind binds config dir" "${out}" ".config/devin"
  else
    expect_not_grep "devin kind skips absent config dir" "${out}" ".config/devin"
  fi

  # an agent binary installed under $HOME is rebound at its PATH location —
  # otherwise the tmpfs'd $HOME hides it from execvp
  devin_bin="$(command -v devin 2>/dev/null || true)"
  if [[ -n "${devin_bin}" && "${devin_bin}" == "${HOME}/"* ]]; then
    expect_grep "agent binary under HOME is rebound" "${out}" "--bind"
    expect_grep "agent binary rebound at PATH path" "${out}" "${devin_bin}"
  fi

  # herdr is always rebound too — workers self-rename via `herdr agent rename`
  herdr_bin="$(command -v herdr 2>/dev/null || true)"
  if [[ -n "${herdr_bin}" && "${herdr_bin}" == "${HOME}/"* ]]; then
    expect_grep "herdr binary under HOME is rebound" "${out}" "${herdr_bin}"
  fi
  ;;
Darwin)
  # the worktree path must exist to land in the profile — seatbelt
  # canonicalizes paths, so assertions compare against realpath output
  fake_wt="${sand}/fake-wt"
  mkdir -p "${fake_wt}"
  out="$(sandbox_wrap_cmd "${fake_wt}" claude bash -c 'echo hi')"
  expect_rc "wrap command builds" "$?" 0
  expect_grep "emits sandbox-exec"    "${out}" "sandbox-exec -f"
  expect_grep "command tail"          "${out}" "bash -c"

  # the profile lives in a file named by -f — read it back before asserting
  # on profile content
  local_profile=""
  profile_file=""
  eval "set -- ${out}"
  while (($#)); do [[ "$1" == "-f" ]] && { profile_file="$2"; break; }; shift; done
  [[ -f "${profile_file}" ]] && local_profile="$(cat "${profile_file}")"
  # herdr pane run types the line before the shell reads input: 1024-byte cap
  if ((${#out} < 1024)); then ok "command line under 1024 bytes"; else bad "command line under 1024 bytes (${#out})"; fi
  rm -f "${profile_file}"
  expect_grep "profile extracted"     "${local_profile}" "(version 1)"
  expect_grep "writes denied by default" "${local_profile}" "(deny file-write*)"
  expect_grep "worktree writable"     "${local_profile}" "(subpath \"$(realpath "${fake_wt}")\")"

  # nonexistent paths are skipped — a stale subpath filter would hide the
  # failure until the worker ran
  missing="${sand}/does-not-exist"
  expect_not_grep "missing path not in profile" "${local_profile}" "${missing}"

  out="$(sandbox_wrap_cmd "${fake_wt}" devin devin)"
  eval "set -- ${out}"
  while (($#)); do [[ "$1" == "-f" ]] && { profile_file="$2"; break; }; shift; done
  out="$(cat "${profile_file}")"
  rm -f "${profile_file}"
  if [[ -d "${HOME}/.config/devin" ]]; then
    expect_grep "devin kind allows config dir" "${out}" ".config/devin"
  else
    expect_not_grep "devin kind skips absent config dir" "${out}" ".config/devin"
  fi
  if [[ -d "${HOME}/.ssh" ]]; then
    expect_grep "ssh keys read-denied" "${out}" ".ssh"
  fi
  ;;
*)
  echo "== unit tests skipped: unsupported platform ${os} =="
  ;;
esac

# backend missing → rc 3 (fail closed at the call site)
# PATH override is deliberate — simulates the sandbox tool being absent
# (it also hides uname, which maps to "unsupported platform" = same rc 3)
# shellcheck disable=SC2123
( PATH="/nonexistent"; sandbox_wrap_cmd "/x" claude bash ) > /dev/null 2>&1
rc=$?
if [[ "${rc}" -eq 3 ]]; then
  ok "sandbox backend missing -> rc 3"
else
  bad "sandbox backend missing -> rc 3"
fi

# ---------------- live: real sandbox confinement ----------------
case "${os}" in
Linux)
  if ! command -v bwrap > /dev/null 2>&1; then
    echo "== live tests skipped: bwrap not installed =="
  else
    echo "== live: sandboxed process inside a split lab (bwrap) =="
    lab="${sand}/lab"
    build_split "${lab}"
    wt="${lab}/worktree/TestRepo/feat-x"

    run_sandbox 'touch wt-file.txt' > /dev/null
    expect_file "write inside worktree persists" "${wt}/wt-file.txt" exists

    run_sandbox 'git add wt-file.txt && git -c user.email=t@t -c user.name=t commit -qm sb-test' > /dev/null
    last_commit="$(git -C "${wt}" log -1 --pretty=%s 2>/dev/null)"
    if [[ "${last_commit}" == "sb-test" ]]; then
      ok "git commit works (base .git bound)"
    else
      bad "git commit works (base .git bound)"
    fi

    run_sandbox "touch ${lab}/escape.txt 2>/dev/null; true" > /dev/null
    expect_file "write at lab root blocked" "${lab}/escape.txt" absent

    run_sandbox 'touch /etc/wth-evil 2>/dev/null; true' > /dev/null
    expect_file "/etc write blocked" "/etc/wth-evil" absent

    # $HOME is a tmpfs: host content hidden, writes don't persist
    marker="${HOME}/.wth-sbx-marker-$$"
    touch "${marker}"
    out="$(run_sandbox 'ls -a ~')"
    expect_not_grep "home contents hidden" "${out}" ".wth-sbx-marker-$$"
    run_sandbox "touch ~/wth-evil-$$; true" > /dev/null
    expect_file "home write is ephemeral" "${HOME}/wth-evil-$$" absent
    rm -f "${marker}"

    run_sandbox 'touch /tmp/wth-ephemeral-test; true' > /dev/null
    expect_file "/tmp write is ephemeral" "/tmp/wth-ephemeral-test" absent

    if [[ -d "${HOME}/.ssh" ]]; then
      # remotes are https via `gh` — nothing under ~/.ssh is bound at all
      priv_marker="${HOME}/.ssh/wth-privkey-$$"
      touch "${priv_marker}"
      out="$(run_sandbox 'ls ~/.ssh')"
      expect_not_grep "ssh private keys hidden" "${out}" "wth-privkey-$$"
      rm -f "${priv_marker}"
    fi
    if [[ -S "${SSH_AUTH_SOCK:-}" ]]; then
      # the var must expand inside the sandbox, not here — single quotes are
      # intentional
      # shellcheck disable=SC2016
      run_sandbox 'test -S "${SSH_AUTH_SOCK}"' > /dev/null 2>&1
      expect_rc "ssh agent socket not bound" "$?" 1
    fi
    if [[ -S "${HOME}/.config/herdr/herdr.sock" ]]; then
      run_sandbox 'test -S ~/.config/herdr/herdr.sock' > /dev/null 2>&1
      expect_rc "herdr socket reachable" "$?" 0
    fi
    if [[ -f "${HOME}/.gitconfig" ]]; then
      run_sandbox 'test -r ~/.gitconfig' > /dev/null 2>&1
      expect_rc "${HOME}/.gitconfig readable" "$?" 0
      run_sandbox 'touch ~/.gitconfig 2>/dev/null' > /dev/null 2>&1
      expect_rc "${HOME}/.gitconfig read-only" "$?" nz
    fi

    # pid namespace: sandbox sees only its own processes
    procs="$(run_sandbox 'ls /proc | grep -cE "^[0-9]+"')"
    if [[ "${procs}" =~ ^[0-9]+$ && ${procs} -lt 20 ]]; then
      ok "pid namespace isolates process table (${procs} visible)"
    else
      bad "pid namespace isolates process table (saw: ${procs})"
    fi

    # an agent CLI installed under $HOME still launches inside the sandbox
    if [[ -n "${devin_bin:-}" && "${devin_bin}" == "${HOME}/"* ]]; then
      out="$(run_sandbox 'devin --version' devin)"
      expect_grep "home-installed agent binary runs" "${out}" "devin"
    fi

    # herdr CLI stays usable inside the sandbox (self-rename path)
    if [[ -n "${herdr_bin:-}" && "${herdr_bin}" == "${HOME}/"* ]]; then
      run_sandbox 'command -v herdr' > /dev/null 2>&1
      expect_rc "herdr binary usable inside sandbox" "$?" 0
    fi
  fi
  ;;
Darwin)
  if ! command -v sandbox-exec > /dev/null 2>&1; then
    echo "== live tests skipped: sandbox-exec not installed =="
  else
    echo "== live: sandboxed process inside a split lab (seatbelt) =="
    lab="${sand}/lab"
    build_split "${lab}"
    wt="${lab}/worktree/TestRepo/feat-x"

    run_sandbox 'touch wt-file.txt' > /dev/null
    expect_file "write inside worktree persists" "${wt}/wt-file.txt" exists

    out="$(run_sandbox 'git add wt-file.txt && git -c user.email=t@t -c user.name=t commit -qm sb-test')"
    last_commit="$(git -C "${wt}" log -1 --pretty=%s 2>/dev/null)"
    if [[ "${last_commit}" == "sb-test" ]]; then
      ok "git commit works (base .git writable)"
    else
      bad "git commit works (base .git writable)"
      printf '       out=%s\n' "${out:0:400}"
    fi

    # the lab sits under $HOME — every write outside the allowed set must fail
    run_sandbox "touch ${lab}/escape.txt 2>/dev/null; true" > /dev/null
    expect_file "write at lab root blocked" "${lab}/escape.txt" absent

    run_sandbox "touch ${lab}/repos/TestRepo/escape.txt 2>/dev/null; true" > /dev/null
    expect_file "write in base repo checkout blocked" "${lab}/repos/TestRepo/escape.txt" absent

    run_sandbox 'touch /etc/wth-evil 2>/dev/null; true' > /dev/null
    expect_file "/etc write blocked" "/etc/wth-evil" absent

    run_sandbox "touch ~/wth-evil-$$; true" > /dev/null
    expect_file "home write blocked" "${HOME}/wth-evil-$$" absent

    # no tmpfs on macOS — host scratch dirs stay writable by design
    run_sandbox 'touch /tmp/wth-scratch-test; true' > /dev/null
    expect_file "/tmp scratch write allowed" "/tmp/wth-scratch-test" exists
    rm -f /tmp/wth-scratch-test

    # other lab trees are read-denied; own worktree and base .git are not
    if [[ -d "${HOME}/.ssh" ]]; then
      priv_marker="${HOME}/.ssh/wth-privkey-$$"
      touch "${priv_marker}"
      run_sandbox 'ls ~/.ssh' > /dev/null 2>&1
      expect_rc "ssh private keys unreadable" "$?" nz
      rm -f "${priv_marker}"
    fi
    if [[ -S "${SSH_AUTH_SOCK:-}" ]]; then
      # the var must expand inside the sandbox, not here — single quotes are
      # intentional
      # shellcheck disable=SC2016
      run_sandbox 'test -S "${SSH_AUTH_SOCK}"' > /dev/null 2>&1
      expect_rc "ssh agent socket unreachable" "$?" nz
    fi
    run_sandbox 'ls ../..' > /dev/null 2>&1
    expect_rc "sibling worktrees unreadable" "$?" nz
    if [[ -S "${HOME}/.config/herdr/herdr.sock" ]]; then
      run_sandbox 'test -S ~/.config/herdr/herdr.sock' > /dev/null 2>&1
      expect_rc "herdr socket reachable" "$?" 0
    fi
    if [[ -f "${HOME}/.gitconfig" ]]; then
      run_sandbox 'test -r ~/.gitconfig' > /dev/null 2>&1
      expect_rc "${HOME}/.gitconfig readable" "$?" 0
      run_sandbox 'touch ~/.gitconfig 2>/dev/null' > /dev/null 2>&1
      expect_rc "${HOME}/.gitconfig read-only" "$?" nz
    fi
  fi
  ;;
*)
  echo "== live tests skipped: unsupported platform ${os} =="
  ;;
esac

echo
echo "passed: ${pass}  failed: ${fail}"
if [[ ${fail} -gt 0 ]]; then
  printf 'failed tests:\n'
  printf '  - %s\n' "${failed_names[@]}"
  exit 1
fi
