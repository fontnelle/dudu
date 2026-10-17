#!/usr/bin/env bash
# Version check (cached, at most once a day, in background) and self-update.

DUDU_LATEST_CACHE="$DUDU_CACHE_DIR/latest_version"

# True when version $1 is newer than $2. A pre-release (1.2.0-rc1) is older than its
# release (1.2.0), and pre-releases compare by their suffix.
version_gt() {
  awk -v a="${1#v}" -v b="${2#v}" 'BEGIN {
    pa = ""; pb = ""
    if (index(a, "-")) { pa = substr(a, index(a, "-") + 1); a = substr(a, 1, index(a, "-") - 1) }
    if (index(b, "-")) { pb = substr(b, index(b, "-") + 1); b = substr(b, 1, index(b, "-") - 1) }
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) {
      if ((x[i] + 0) > (y[i] + 0)) exit 0
      if ((x[i] + 0) < (y[i] + 0)) exit 1
    }
    if (pa == pb) exit 1
    if (pa == "") exit 0
    if (pb == "") exit 1
    exit !(pa > pb)
  }'
}

latest_version() {
  curl -fsSL --max-time 5 "https://api.github.com/repos/$DUDU_REPO/releases/latest" 2>/dev/null |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -1
}

check_for_updates_bg() {
  [ -n "${DUDU_NO_UPDATE_CHECK:-}" ] && return 0
  has curl || return 0
  local mtime
  if [ -f "$DUDU_LATEST_CACHE" ]; then
    mtime=$(file_mtime "$DUDU_LATEST_CACHE")
    [ -n "$mtime" ] && [ $(( $(date +%s) - mtime )) -lt 86400 ] && return 0
  fi
  (
    v=$(latest_version)
    [ -n "$v" ] && printf '%s\n' "$v" > "$DUDU_LATEST_CACHE"
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# Homebrew keeps dudu in its Cellar and updates it itself.
installed_by_brew() { case "$DUDU_ROOT" in */Cellar/dudu/*) return 0 ;; esac; return 1; }

# Where dudu lives, by a path that survives updates: Homebrew's opt/ link, not the Cellar
# folder of one version.
stable_root() {
  if installed_by_brew; then printf '%s/opt/dudu/libexec' "${DUDU_ROOT%%/Cellar/dudu/*}"; else printf '%s' "$DUDU_ROOT"; fi
}

update_command() { if installed_by_brew; then printf 'brew upgrade dudu'; else printf 'dudu update'; fi; }

update_notice() {
  [ -f "$DUDU_LATEST_CACHE" ] || return 0
  local latest
  latest=$(cat "$DUDU_LATEST_CACHE")
  if [ -n "$latest" ] && version_gt "$latest" "$VERSION"; then
    printf '\n%sUpdate %s available, run %s%s%s\n' "$NC" "$latest" "$GREEN" "$(update_command)" "$NC"
  fi
}

cmd_update() {
  if installed_by_brew; then
    step "dudu was installed with Homebrew, running brew upgrade dudu"
    brew upgrade dudu
    return
  fi
  # A git checkout updates itself with git.
  if [ -d "$DUDU_ROOT/.git" ]; then
    step "dudu is a git checkout, pulling $DUDU_ROOT"
    git -C "$DUDU_ROOT" pull --ff-only && ok "Updated"
    return
  fi
  local latest bin_dir
  latest=$(latest_version)
  if [ -z "$latest" ]; then
    err "Could not reach GitHub to check the latest version"
    return 1
  fi
  if ! version_gt "$latest" "$VERSION"; then
    ok "Already on the latest version ($VERSION)"
    return 0
  fi
  bin_dir=$(dirname "$(command -v dudu 2>/dev/null || echo "$HOME/.local/bin/dudu")")
  step "Updating dudu $VERSION → $latest"
  # The installer of that release (not main), downloaded whole before it runs.
  local installer
  installer=$(mktemp)
  if ! curl -fsSL "https://raw.githubusercontent.com/$DUDU_REPO/v$latest/install.sh" -o "$installer"; then
    rm -f "$installer"
    err "Could not download the installer of $latest"
    return 1
  fi
  bash "$installer" --prefix "$bin_dir" "$latest" && printf '%s\n' "$latest" > "$DUDU_LATEST_CACHE"
  local rc=$?
  rm -f "$installer"
  return $rc
}

cmd_completion() {
  case "${1:-}" in
    zsh) cat "$DUDU_ROOT/completions/_dudu" ;;
    bash) cat "$DUDU_ROOT/completions/dudu.bash" ;;
    highlight)
      # --path: the file itself, to source from ~/.zshrc without starting dudu in every shell.
      if [ "${2:-}" = --path ]; then printf '%s\n' "$(stable_root)/completions/dudu.zsh"
      else cat "$DUDU_ROOT/completions/dudu.zsh"; fi ;;
    *)
      echo "Usage: dudu completion zsh|bash|highlight"
      echo
      echo "  zsh:  dudu completion zsh > \"\${fpath[1]}/_dudu\""
      echo "  bash: echo 'eval \"\$(dudu completion bash)\"' >> ~/.bashrc"
      echo "  highlight (zsh): echo \"source \$(dudu completion highlight --path)\" >> ~/.zshrc"
      return 1
      ;;
  esac
}
