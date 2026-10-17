#!/usr/bin/env bash
# Shell and prompt: dotfiles, Oh My Zsh with its custom plugins/themes, starship, tmux, vim.

SHELL_FILES=".zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .profile .aliases .bash_aliases \
.zsh_aliases .p10k.zsh .inputrc .tmux.conf .vimrc .editorconfig .hushlogin .config/starship.toml \
.config/fish/config.fish .config/tmux/tmux.conf"

shell_omz_dir() { printf '%s' "${ZSH:-$HOME/.oh-my-zsh}"; }

shell_detect() { return 0; }

shell_backup() {
  local f n=0 omz custom d url extra=""
  for f in $SHELL_FILES; do
    save_file "$HOME/$f" "$1/home" && n=$((n + 1))
  done
  # Small config trees (fish functions, neovim), without git metadata.
  for d in .config/fish/functions .config/fish/conf.d .config/nvim; do
    [ -d "$HOME/$d" ] || continue
    while IFS= read -r f; do
      save_file "$f" "$1/home" && n=$((n + 1))
    done < <(find "$HOME/$d" -type f -not -path '*/.git/*' -size -512k 2>/dev/null | head -500)
  done
  basename "${SHELL:-}" > "$1/login_shell"

  omz=$(shell_omz_dir)
  if [ -d "$omz" ]; then
    touch "$1/ohmyzsh"
    extra=", Oh My Zsh"
    custom="${ZSH_CUSTOM:-$omz/custom}"
    : > "$1/omz-custom.txt"
    for d in "$custom"/plugins/* "$custom"/themes/*; do
      [ -d "$d/.git" ] || continue
      url=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
      printf '%s %s\n' "${d#"$custom"/}" "$url" >> "$1/omz-custom.txt"
    done
    for f in "$custom"/*.zsh; do
      [ -f "$f" ] && save_file "$f" "$1/home" && n=$((n + 1))
    done
    extra="$extra + $(tn "%d custom plugin/theme" "%d custom plugins/themes" "$(count_lines "$1/omz-custom.txt")")"
  fi
  summary "$1" "$(tn "%d dotfile" "%d dotfiles" "$n")$extra"
}

shell_restore() {
  local omz custom rel url
  omz=$(shell_omz_dir)
  if [ -f "$1/ohmyzsh" ] && [ ! -d "$omz" ]; then
    step "$(t "Installing %s" "Oh My Zsh")"
    act_sh 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
  fi
  if [ -s "$1/omz-custom.txt" ]; then
    custom="${ZSH_CUSTOM:-$omz/custom}"
    while read -r rel url; do
      [ -n "$url" ] || continue
      # Only plugins/<name> or themes/<name>, cloned from a plain https or ssh git URL.
      if ! printf '%s %s\n' "$rel" "$url" | grep -Eq '^(plugins|themes)/[A-Za-z0-9._-]+ (https://|git@)[A-Za-z0-9._/:@~-]+$' ||
         [ "${rel#*..}" != "$rel" ]; then
        warn "$(t "ignored suspicious plugin entry in the backup: %s" "$(safe_text "$rel $url")")"
        continue
      fi
      if [ -d "$custom/$rel" ]; then
        dim "  = $rel"
      else
        act git clone --depth=1 -- "$url" "$custom/$rel" && ok "$rel $GRAY($(safe_text "$url"))$NC"
      fi
    done < "$1/omz-custom.txt"
  fi
  restore_home "$1/home" "$(echo "$SHELL_FILES" | tr -s ' ' '\n')
.config/fish/functions/*
.config/fish/conf.d/*
.config/nvim/*
${custom#"$HOME"/}/*.zsh"

  local want
  want=$(cat "$1/login_shell" 2>/dev/null)
  if [ -n "$want" ] && [ "$want" != "$(basename "${SHELL:-}")" ] && has "$want"; then
    warn "$(t "Your login shell was %s. Change it with: %s" "$want" "chsh -s $(command -v "$want")")"
  fi
}
