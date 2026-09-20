---
type: ADR
title: Word-level scanning for command path candidates
description: guard-bash-commands lexes shell words instead of splitting on a character sieve; regex/program words are not paths.
status: accepted
last_modified: 2026-09-20
tags: [hooks, security, parsing]
---

# ADR-0009: Word-level scanning for command path candidates

## Status

Accepted

## Context

`hook_guard_command` extracted path candidates by splitting the command
on every non-path character and keeping tokens starting with `/`, `~`,
`./`, `../`. Quoted program arguments were invisible to this sieve:
`sed -n '/^usage/,/^}/p' f` yielded a bare `/` token and was denied as a
filesystem-root reference — a false positive on a routine command.

Two cheap fixes were rejected. Checking that a candidate *exists* leaks:
creation targets (`touch /etc/cron.d/x`) never exist and would all pass.
Allowlisting `/` disables the boundary entirely. The sieve also cannot
distinguish a sed delimiter from a real path because the delimiters are
exactly what produced the candidate.

## Decision

Scan the command as shell words instead of characters
(`hook_lex_candidates` / `hook_emit_candidate` in
`scripts/lib/hook-common.sh`):

- Quotes and backslashes are honored; `| & ; < > ( ) $ `` ` `` terminate
  a word, so `cmd>/etc/x` and `a;cat /etc` still expose their paths.
- `$( )`, `${ }` and backtick interiors recurse into the same lexer —
  `x=$(cat /etc/shadow)` is still denied, matching the old recall.
- A word containing program/regex metachars (`^ , { } ( ) ! \`) is an
  expression, not a path; it is skipped whole.
- A glob word (`* ? [`) is checked by its literal directory prefix —
  `/etc/*.conf` still denies via `/etc/`.
- Bare delimiters (`/`, `~`, `./`, `../` alone) are not references.

## Consequences

- `sed -n '/^usage/,/^}/p'`, `awk '{print}'`, `sed 's|/a|/b|'`,
  `grep '^/home'` — all allowed; real paths (including nested inside
  substitutions and redirects) still denied.
- Residuals, accepted under the advisory threat model: a bare `/` word
  (`ls /`) now passes; a genuine path containing `,` `{` `}` `(` `)` `!`
  `\` or `^` is skipped. The file-tool guards and the worker bwrap
  sandbox are unaffected.
- Regression coverage lives in `tests/test-hooks.sh` (tokenizer cases
  run in both lab topologies).
