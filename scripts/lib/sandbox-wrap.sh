#!/usr/bin/env bash
# sandbox-wrap.sh — build a sandboxed command line that confines a spawned
# agent to its worktree at the OS level, independent of which agent CLI is
# inside. One backend per platform:
#
#   Linux  bubblewrap mount namespace (bwrap)
#   macOS  Seatbelt profile applied via /usr/bin/sandbox-exec
#
# Shared policy:
#   /            everything readable except hidden paths; not writable
#   scratch      ephemeral — Linux: tmpfs over /tmp + $HOME; macOS: /tmp,
#                the $TMPDIR tree, ~/Library/{Caches,Logs}, ~/.cache
#   <worktree>   rw — the only project path the worker can write
#   <base>/.git  rw — linked worktrees keep index/objects/refs there;
#                without it `git add`/`commit` cannot work
#   agent dirs   rw — the CLI's own state (~/.claude, ~/.config/devin, ...)
#   agent binary Linux only: rebound at its PATH location — CLIs installed
#                under $HOME (e.g. ~/.local/bin/devin) would otherwise
#                vanish with the tmpfs'd $HOME
#   herdr socket dir  rw — workers self-rename via `herdr agent rename`
#   gh config, gitconfig, git-credentials, netrc — readable; gitconfig/
#                credentials/netrc stay unwritable
#   ssh          hidden — remotes are https via `gh`, so ~/.ssh and
#                SSH_AUTH_SOCK stay out of reach
#   lab trees    macOS: repos/ and worktree/ siblings of the assignment are
#                read-denied (what the tmpfs'd $HOME hides on Linux when
#                the lab lives under it — applied unconditionally here)
#
# sandbox_backend — prints the platform's sandbox tool (bwrap |
#   sandbox-exec). rc 3 when it is missing or the platform is unsupported.
#
# sandbox_wrap_cmd <worktree> <kind> <argv...>
#   Prints a shell-quoted command line "<backend> ... <argv>" on stdout.
#   rc: 0 ok · 2 usage · 3 sandbox backend unavailable

sandbox_backend() {
  case "$(uname -s)" in
    Linux)
      command -v bwrap > /dev/null 2>&1 || return 3
      printf 'bwrap\n' ;;
    Darwin)
      command -v sandbox-exec > /dev/null 2>&1 || return 3
      printf 'sandbox-exec\n' ;;
    *) return 3 ;;
  esac
}

sandbox_wrap_cmd() {
  local wt="$1" kind="$2"
  shift 2
  [[ -n "${wt}" && -n "${kind}" && $# -ge 1 ]] || return 2
  case "$(uname -s)" in
    Linux)  _sandbox_wrap_bwrap "${wt}" "${kind}" "$@" ;;
    Darwin) _sandbox_wrap_seatbelt "${wt}" "${kind}" "$@" ;;
    *) return 3 ;;
  esac
}

# --- shared ---------------------------------------------------------------

_sandbox_common_git() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true
}

# _sandbox_agent_dirs <kind> — the CLI's own config paths, one per line.
_sandbox_agent_dirs() {
  case "$1" in
    claude) printf '%s\n' "${HOME}/.claude" "${HOME}/.claude.json" ;;
    devin)  printf '%s\n' "${HOME}/.config/devin" "${HOME}/.local/share/devin" "${HOME}/.devin" ;;
    agy)    printf '%s\n' "${HOME}/.gemini" ;;
    codex)  printf '%s\n' "${HOME}/.codex" ;;
  esac
}

# --- Linux: bubblewrap ----------------------------------------------------

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

_sandbox_wrap_bwrap() {
  local wt="$1" kind="$2"
  shift 2
  command -v bwrap > /dev/null 2>&1 || return 3

  local common_git
  common_git="$(_sandbox_common_git "${wt}")"

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
  while IFS= read -r d; do
    sandbox_bind args rw "${d}"
  done < <(_sandbox_agent_dirs "${kind}")

  args+=(--)
  printf '%q ' "${args[@]}" "$@"
}

# --- macOS: Seatbelt (sandbox-exec) ---------------------------------------
#
# The profile follows the bazel/anthropic-style "allow default, then
# restrict" shape rather than deny-default: an exhaustive op allowlist
# (mach services, sysctl, iokit, ...) is fragile across macOS releases and
# a missing op breaks agents silently — while the property the harness
# actually promises is write confinement plus credential hiding.
# Seatbelt is last-match-wins, so write allows land after the global
# write-deny and read denies land last so nothing re-opens them.

# _seatbelt_escape <path> — escape a path for a double-quoted SBPL string.
_seatbelt_escape() {
  local p="$1"
  p="${p//\\/\\\\}"
  p="${p//\"/\\\"}"
  printf '%s' "${p}"
}

# _seatbelt_subpath <args-array-name> <path>
# Appends `(subpath "<canonical>")` when <path> exists. Seatbelt matches
# canonicalized paths, so symlinks (/tmp → /private/tmp, /var →
# /private/var) are resolved here — realpath exists on macOS and the path
# is existence-checked first.
_seatbelt_subpath() {
  local -n _out="$1"
  local path="$2" canon
  [[ -e "${path}" ]] || return 0
  canon="$(realpath "${path}" 2>/dev/null || printf '%s' "${path}")"
  _out+=("(subpath \"$(_seatbelt_escape "${canon}")\")")
}

_sandbox_wrap_seatbelt() {
  local wt="$1" kind="$2"
  shift 2
  command -v sandbox-exec > /dev/null 2>&1 || return 3

  local common_git
  common_git="$(_sandbox_common_git "${wt}")"
  local wt_canon
  wt_canon="$(realpath "${wt}" 2>/dev/null || printf '%s' "${wt}")"

  # Writable set — mirrors the bwrap rw binds. Seatbelt has no tmpfs, so
  # host scratch dirs stand in for the ephemeral /tmp + $HOME mounts.
  local -a writes=()
  _seatbelt_subpath writes "${wt}"
  [[ -n "${common_git}" ]] && _seatbelt_subpath writes "${common_git}"
  _seatbelt_subpath writes "${HOME}/.config/herdr"
  _seatbelt_subpath writes "${HOME}/.config/gh"
  local d
  while IFS= read -r d; do _seatbelt_subpath writes "${d}"; done \
    < <(_sandbox_agent_dirs "${kind}")
  _seatbelt_subpath writes "/dev"
  _seatbelt_subpath writes "/tmp"
  _seatbelt_subpath writes "/var/tmp"
  if [[ -n "${TMPDIR:-}" ]]; then
    # TMPDIR's parent covers the per-user Caches sibling (…/T and …/C)
    _seatbelt_subpath writes "$(dirname "${TMPDIR}")"
  fi
  _seatbelt_subpath writes "${HOME}/Library/Caches"
  _seatbelt_subpath writes "${HOME}/Library/Logs"
  _seatbelt_subpath writes "${HOME}/.cache"

  # Hidden reads — credentials, plus the lab trees a worker has no
  # business in (its own worktree + base .git are carved back out via
  # require-not). require-not needs one filter per level, so each rule is
  # require-all(deny-subtree, require-not(carve-out)).
  local -a reads=()
  _seatbelt_subpath reads "${HOME}/.ssh"
  _seatbelt_subpath reads "${HOME}/.gnupg"
  _seatbelt_subpath reads "${HOME}/.aws"
  _seatbelt_subpath reads "${HOME}/.azure"
  _seatbelt_subpath reads "${HOME}/.kube"
  _seatbelt_subpath reads "${HOME}/.docker"
  _seatbelt_subpath reads "${HOME}/.config/gcloud"

  local dir="${wt}" lab_root=""
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -d "${dir}/worktree" && -d "${dir}/repos" ]]; then
      lab_root="$(realpath "${dir}")"
      break
    fi
    dir="$(dirname "${dir}")"
  done
  if [[ -n "${lab_root}" ]]; then
    local git_canon=""
    [[ -n "${common_git}" ]] && git_canon="$(realpath "${common_git}" 2>/dev/null || true)"
    if [[ -n "${git_canon}" ]]; then
      reads+=("(require-all (subpath \"$(_seatbelt_escape "${lab_root}/repos")\") (require-not (subpath \"$(_seatbelt_escape "${git_canon}")\")))")
    else
      _seatbelt_subpath reads "${lab_root}/repos"
    fi
    reads+=("(require-all (subpath \"$(_seatbelt_escape "${lab_root}/worktree")\") (require-not (subpath \"$(_seatbelt_escape "${wt_canon}")\")))")
  fi

  local profile="(version 1) (allow default) (deny file-write*)"
  profile+=" (allow file-write* ${writes[*]})"
  ((${#reads[@]})) && profile+=" (deny file-read* ${reads[*]})"
  # The ssh-agent socket sits under a launchd dir outside $HOME — deny it
  # explicitly since nothing else covers it.
  if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    profile+=" (deny file-read* file-write* network-outbound network-inbound (literal \"$(_seatbelt_escape "${SSH_AUTH_SOCK}")\"))"
  fi

  printf '%q ' sandbox-exec -p "${profile}" "$@"
}
