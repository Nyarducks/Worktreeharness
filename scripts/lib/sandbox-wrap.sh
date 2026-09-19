#!/usr/bin/env bash
# sandbox-wrap.sh — build a bubblewrap command line that confines a spawned
# agent to its worktree at the OS level (mount namespace), independent of
# which agent CLI is inside.
#
# Policy:
#   /            read-only bind
#   /tmp         tmpfs (ephemeral scratch; skipped when the worktree lives
#                under /tmp — a parent tmpfs would orphan the worktree bind)
#   $HOME        tmpfs (hides ~/.ssh, other repos, credentials, ...)
#   <worktree>   rw bind — the only project path the worker can write
#   <base>/.git  rw bind — linked worktrees keep index/objects/refs there;
#                without it `git add`/`commit` cannot work
#   agent dirs   rw bind — the CLI's own state (~/.claude, ~/.config/devin, ...)
#   agent binary ro bind — CLIs installed under $HOME (e.g. ~/.local/bin/devin)
#                would otherwise vanish with the tmpfs'd $HOME
#   herdr socket dir  rw — workers self-rename via `herdr agent rename`
#   gh/gitconfig  ro — https push credentials; readable but not writable
#   ssh          nothing — remotes are https via `gh`, so ~/.ssh and
#                SSH_AUTH_SOCK are left hidden entirely
#
# sandbox_wrap_cmd <worktree> <kind> <argv...>
#   Prints a shell-quoted command line "bwrap ... -- <argv>" on stdout.
#   rc: 0 ok · 2 usage · 3 bwrap not installed

# sandbox_bind <args-array-name> <rw|ro> <path>
# Appends a bind pair only when <path> exists on the host.
sandbox_bind() {
  local -n _args="$1"
  local mode="$2" path="$3"
  [[ -e "${path}" ]] || return 0
  if [[ "${mode}" == "rw" ]]; then
    _args+=(--bind "${path}" "${path}")
  else
    _args+=(--ro-bind "${path}" "${path}")
  fi
}

sandbox_wrap_cmd() {
  local wt="$1" kind="$2"
  shift 2
  [[ -n "${wt}" && -n "${kind}" && $# -ge 1 ]] || return 2
  command -v bwrap > /dev/null 2>&1 || return 3

  local common_git
  common_git="$(git -C "${wt}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"

  local -a args=(
    bwrap
    --ro-bind / /
    --dev /dev
    --proc /proc
    --unshare-pid --unshare-uts --unshare-ipc
    --die-with-parent
    --chdir "${wt}"
  )

  case "${wt}" in
    /tmp/*|/private/tmp/*) args+=(--bind /tmp /tmp) ;;
    *) args+=(--tmpfs /tmp) ;;
  esac

  args+=(--tmpfs "${HOME}")
  args+=(--bind "${wt}" "${wt}")
  [[ -d "${common_git}" ]] && args+=(--bind "${common_git}" "${common_git}")

  # Binaries under $HOME (e.g. ~/.local/bin/devin, ~/.local/bin/herdr) vanish
  # with the tmpfs'd $HOME — bind each resolved binary back at its
  # PATH-visible location so execvp finds it. `herdr` is always rebound:
  # workers self-rename via `herdr agent rename`.
  local bin bin_lookup bin_real
  for bin in "$1" herdr; do
    bin_lookup="$(command -v "${bin}" 2>/dev/null || true)"
    bin_real="$(realpath "${bin_lookup}" 2>/dev/null || true)"
    [[ -n "${bin_real}" && "${bin_lookup}" == "${HOME}/"* ]] || continue
    local d="" seg i
    IFS='/' read -ra seg <<< "${bin_lookup#/}"
    for ((i = 0; i < ${#seg[@]} - 1; i++)); do
      d+="/${seg[i]}"
      args+=(--dir "${d}")
    done
    args+=(--bind "${bin_real}" "${bin_lookup}")
  done

  # Orchestration + credentials (read or write as needed)
  sandbox_bind args rw "${HOME}/.config/herdr"
  sandbox_bind args rw "${HOME}/.config/gh"
  sandbox_bind args ro "${HOME}/.gitconfig"
  sandbox_bind args ro "${HOME}/.git-credentials"
  sandbox_bind args ro "${HOME}/.netrc"

  # No ssh: this harness clones and pushes over https via `gh`, so ~/.ssh
  # and SSH_AUTH_SOCK stay hidden inside the tmpfs'd $HOME.

  # Per-agent CLI state — the agent must be able to write its own
  # config/session dirs even though the rest of $HOME is hidden.
  case "${kind}" in
    claude)
      sandbox_bind args rw "${HOME}/.claude"
      sandbox_bind args rw "${HOME}/.claude.json"
      ;;
    devin)
      sandbox_bind args rw "${HOME}/.config/devin"
      sandbox_bind args rw "${HOME}/.local/share/devin"
      sandbox_bind args rw "${HOME}/.devin"
      ;;
    agy)
      sandbox_bind args rw "${HOME}/.gemini"
      ;;
    codex)
      sandbox_bind args rw "${HOME}/.codex"
      ;;
  esac

  args+=(--)
  printf '%q ' "${args[@]}" "$@"
}
