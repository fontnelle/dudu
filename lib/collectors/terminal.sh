#!/usr/bin/env bash
# Terminal apps: Terminal.app and iTerm2 profiles (macOS), Ghostty, Alacritty, Kitty, WezTerm,
# plus the list of Nerd Fonts the prompt depends on.

# One path per line (some contain spaces).
TERMINAL_FILES=".config/ghostty/config
.config/alacritty/alacritty.toml
.config/alacritty/alacritty.yml
.config/kitty/kitty.conf
.wezterm.lua
.config/wezterm/wezterm.lua
.hyper.js
Library/Application Support/com.mitchellh.ghostty/config"

TERMINAL_DOMAINS="com.apple.Terminal com.googlecode.iterm2"

terminal_installed_fonts() {
  ls "$HOME/Library/Fonts" /Library/Fonts "$HOME/.local/share/fonts" "$HOME/.fonts" 2>/dev/null |
    grep -i 'nerd' | sort -u
}

# The parts of a terminal plist a person actually sets (profiles, default profile, shell).
# Everything else is window state the app rewrites on every launch.
TERMINAL_PLIST_KEYS="Window Settings|Default Window Settings|Startup Window Settings|Shell|\
SecureKeyboardEntry|NewWindowWorkingDirectoryBehavior|New Bookmarks|Default Bookmark Guid"

terminal_plist_digest() { # <plist>
  local key
  while IFS= read -r key; do
    printf '== %s\n' "$key"
    plutil -extract "$key" xml1 -o - "$1" 2>/dev/null
  done < <(printf '%s\n' "$TERMINAL_PLIST_KEYS" | tr '|' '\n')
}

# A plist value as an XML fragment, without the document wrapper.
terminal_plist_value() { # <plist> <key>
  plutil -extract "$2" xml1 -o - "$1" 2>/dev/null |
    sed -e '/^<?xml/d' -e '/^<!DOCTYPE/d' -e '/^<plist/d' -e '/^<\/plist>/d'
}

# Copies only TERMINAL_PLIST_KEYS of <src> into a new XML plist <dst>. The rest (window
# state, recent dirs, anything a tool stored there) never enters the backup.
terminal_plist_filter() { # <src> <dst>
  local key val
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0">' '<dict/>' '</plist>' > "$2"
  while IFS= read -r key; do
    val=$(terminal_plist_value "$1" "$key")
    [ -n "$val" ] && plutil -insert "$key" -xml "$val" "$2"
  done < <(printf '%s\n' "$TERMINAL_PLIST_KEYS" | tr '|' '\n')
  return 0
}

terminal_detect() {
  is_macos && return 0
  local f
  for f in .config/ghostty/config .config/alacritty .config/kitty .wezterm.lua .config/wezterm; do
    [ -e "$HOME/$f" ] && return 0
  done
  return 1
}

terminal_backup() {
  local f n=0 d profiles=""
  while IFS= read -r f; do
    [ -n "$f" ] && save_file "$HOME/$f" "$1/home" && n=$((n + 1))
  done <<< "$TERMINAL_FILES"

  if is_macos; then
    mkdir -p "$1/defaults"
    for d in $TERMINAL_DOMAINS; do
      if defaults read "$d" >/dev/null 2>&1; then
        f=$(mktemp)
        if defaults export "$d" "$f" && terminal_plist_filter "$f" "$1/defaults/$d.plist"; then
          secrets_scrub "$1/defaults/$d.plist" "${d##*.} profiles" && profiles="$profiles ${d##*.}"
        fi
        rm -f "$f"
      fi
    done
    if [ -d "$HOME/Library/Application Support/iTerm2/DynamicProfiles" ]; then
      while IFS= read -r f; do save_file "$f" "$1/home"; done \
        < <(find "$HOME/Library/Application Support/iTerm2/DynamicProfiles" -type f)
    fi
  fi

  terminal_installed_fonts > "$1/fonts.txt"
  summary "$1" "$(tn "%d config" "%d configs" "$n")${profiles:+, $(t "profiles:%s" "$profiles")}, $(tn "%d Nerd Font file" "%d Nerd Font files" "$(count_lines "$1/fonts.txt")")"
}

terminal_restore() {
  restore_home "$1/home" "$TERMINAL_FILES
Library/Application Support/iTerm2/DynamicProfiles/*"
  local p d current imported="" key val undo
  if [ -d "$1/defaults" ]; then
    if is_macos; then
      for p in "$1"/defaults/*.plist; do
        [ -f "$p" ] || continue
        d=$(basename "$p" .plist)
        # Only the two terminal domains, whatever else a backup folder may contain.
        list_has "$(echo "$TERMINAL_DOMAINS" | tr ' ' ',')" "$d" || { warn "$(t "ignored unexpected file %s" "defaults/$d.plist")"; continue; }
        current=$(mktemp)
        defaults export "$d" "$current" 2>/dev/null || printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0">' '<dict/>' '</plist>' > "$current"
        if [ "$(terminal_plist_digest "$current")" = "$(terminal_plist_digest "$p")" ]; then
          rm -f "$current"
          dim "  = $(t "%s profiles" "$d")"
          continue
        fi
        if [ -n "${DUDU_DRY_RUN:-}" ]; then
          printf '  %s→ %s%s\n' "$GRAY" "$(t "merge profiles into %s (current settings saved first)" "$d")" "$NC"
          rm -f "$current"
          continue
        fi
        # Keep the current settings to undo with: defaults import <domain> <file>
        undo="$DUDU_CACHE_DIR/defaults-$d-$(now_stamp).plist"
        cp "$current" "$undo"
        plutil -convert xml1 "$current"
        # Merge the profile keys into the current settings instead of replacing the domain.
        while IFS= read -r key; do
          val=$(terminal_plist_value "$p" "$key")
          [ -n "$val" ] || continue
          if printf '%s' "$val" | grep -q '<redacted-by-dudu>'; then
            warn "$(t "%s: kept your current \"%s\" (the backup had a masked secret there)" "$d" "$key")"
            continue
          fi
          plutil -replace "$key" -xml "$val" "$current"
        done < <(printf '%s\n' "$TERMINAL_PLIST_KEYS" | tr '|' '\n')
        defaults import "$d" "$current" && ok "$(t "%s profiles" "$d") $GRAY($(t "previous settings in %s" "$(tilde "$undo")"))$NC"
        rm -f "$current"
        imported=1
      done
      [ -n "$imported" ] && [ "${TERM_PROGRAM:-}" = Apple_Terminal ] &&
        warn "$(t "Terminal.app is open: quit it with ⌘Q (not the window) and reopen, or it may overwrite the imported profiles.")"
    else
      dim "  $(t "Terminal.app/iTerm2 profiles are macOS only, skipped")"
    fi
  fi
  local missing
  missing=$(terminal_installed_fonts | missing_from "$1/fonts.txt")
  if [ -n "$missing" ]; then
    warn "$(t "Your prompt used these Nerd Fonts, install them (e.g. %s):" "brew install --cask font-fira-code-nerd-font")"
    printf '%s\n' "$missing" | head -20 | sed 's/^/    /'
  fi
  return 0
}
