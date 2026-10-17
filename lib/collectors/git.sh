#!/usr/bin/env bash
# Git and SSH client config (never keys or tokens).

GIT_FILES=".gitconfig .gitignore_global .gitignore .gitmessage .config/git/config .config/git/ignore \
.config/git/attributes .ssh/config .config/gh/config.yml"

git_detect() { has git; }

git_backup() {
  local f n=0 excludes
  for f in $GIT_FILES; do
    save_file "$HOME/$f" "$1/home" && n=$((n + 1))
  done
  excludes=$(git config --global core.excludesfile 2>/dev/null)
  excludes=$(expand_home "$excludes")
  case "$excludes" in
    "$HOME"/*) [ -f "$1/home/${excludes#"$HOME"/}" ] || { save_file "$excludes" "$1/home" && n=$((n + 1)); } ;;
  esac
  summary "$1" "$(tn "%d file" "%d files" "$n")"
}

git_restore() {
  restore_home "$1/home" "$(echo "$GIT_FILES" | tr -s ' ' '\n')
*ignore*"
  if [ -f "$HOME/.ssh/config" ] && [ -z "${DUDU_DRY_RUN:-}" ]; then
    chmod 700 "$HOME/.ssh" 2>/dev/null
    chmod 600 "$HOME/.ssh/config" 2>/dev/null
    # OpenSSH on Linux refuses the macOS-only UseKeychain option unless told to ignore it.
    if ! is_macos && grep -qi '^[[:space:]]*UseKeychain' "$HOME/.ssh/config" &&
       ! grep -qi '^[[:space:]]*IgnoreUnknown' "$HOME/.ssh/config"; then
      { echo "IgnoreUnknown UseKeychain"; cat "$HOME/.ssh/config"; } > "$HOME/.ssh/config.tmp" &&
        cat "$HOME/.ssh/config.tmp" > "$HOME/.ssh/config"
      rm -f "$HOME/.ssh/config.tmp"
      ok "$(t "%s: added IgnoreUnknown UseKeychain (a macOS option)" "~/.ssh/config")"
    fi
  fi
  return 0
}
