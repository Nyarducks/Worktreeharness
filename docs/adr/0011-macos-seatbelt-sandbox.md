---
type: ADR
title: macOS support — Seatbelt sandbox backend and portable locking
description: Dispatch the worker sandbox by platform (bwrap on Linux, sandbox-exec on macOS); replace flock with a mkdir lockdir; fall back from realpath -m to grealpath/python3.
status: accepted
last_modified: 2026-10-03
tags: [sandbox, seatbelt, macos, portability]
---

# ADR-0011: macOS support — Seatbelt sandbox backend and portable locking

## Status

Accepted

## Context

The harness was Linux-only. Three dependencies blocked macOS:

- `bwrap` is Linux-only (mount namespaces have no macOS equivalent).
- `flock(1)` — used by `spawn-repo-agent.sh` to serialize agent-settings
  merges — does not exist on macOS and was never listed in Requirements.
- `realpath -m` — used by the guard-hook libs — is a GNU extension;
  macOS's builtin BSD `realpath` has no `-m`, and Homebrew coreutils
  installs only the `grealpath` name.

## Decision

- `scripts/lib/sandbox-wrap.sh` dispatches per `uname -s`. macOS builds a
  Seatbelt profile written to a temp file and passed via `sandbox-exec -f` (an inline `-p` profile exceeds the 1024-byte pane input line limit): `allow default`,
  `deny file-write*`, `allow file-write*` for the worktree + base `.git`
  + agent config dirs + OS scratch dirs, then `deny file-read*` for
  credential paths (`~/.ssh`, `~/.gnupg`, `~/.aws`, ...) and for sibling
  lab trees via `require-all(subpath)` + `require-not(subpath)` carve-outs.
  `sandbox_backend` reports the platform tool; dispatch stays fail-closed
  on both OSes.
- `json_merge_atomic` locks with `mkdir <file>.lock.d` — mkdir(2) is
  atomic everywhere — with stale-lock reclaim; `mktemp` templates keep
  X's trailing for BSD mktemp.
- `wth_realpath_m` in `rm-guard.sh` chains GNU `realpath -m` →
  `grealpath -m` → python3 `os.path.realpath` (present via the Command
  Line Tools every git user has).
- CI gains a `macos-latest` job running the same suites, so the seatbelt
  path is exercised for real.

Alternatives rejected:

- **Fail open / auto `--no-sandbox` on macOS** — breaks the fail-closed
  contract; the sandbox is the worker's only enforcement layer.
- **`deny default` Seatbelt profile** — an exhaustive op allowlist (mach
  services, sysctl, iokit) is fragile across macOS releases and a missing
  op breaks agents silently. `allow default` + write confinement +
  targeted read-denies delivers the promised guarantee (Bazel's shape).
- **Keeping `flock` and documenting it** — no maintained macOS flock(1)
  port; the mkdir lockdir has zero dependencies and identical semantics
  for a short critical section.
- **Requiring GNU coreutils on macOS** — Homebrew installs `grealpath`,
  not `realpath`; telling every macOS user to shadow PATH with gnubin is
  worse than a fallback chain.

## Consequences

- macOS users get a confined worker with zero extra installs beyond the
  documented requirements (`bash` via brew is the only real addition).
- macOS confinement is weaker than Linux: no pid/uts/ipc namespaces, host
  scratch dirs stay writable (no tmpfs), and only enumerated credential
  paths are hidden rather than all of `$HOME`. Documented in
  `sandbox.md`'s known holes.
- `sandbox-exec` is deprecated by Apple but still ships and is relied on
  by Bazel, Homebrew, Claude Code, and Codex; no replacement exists for
  CLI process sandboxing. If Apple removes it, macOS dispatch becomes
  `--no-sandbox` only.
- The mkdir lockdir leaves a stale lock if a holder is SIGKILLed
  mid-merge; the next caller reclaims it after ~10s (the dir is always
  empty, so `rmdir` is a safe reclaim).
- ADR-0006 remains the decision of record for the Linux backend.
