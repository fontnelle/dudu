#!/usr/bin/env bash
# VS Code: extensions, settings, keybindings and snippets.
# The editor_* helpers are shared with cursor.sh.

# CLI path even when the shell command was never installed.
editor_cli() { # <cli> <App Name>
  if has "$1"; then command -v "$1"; return 0; fi
  local p="/Applications/$2.app/Contents/Resources/app/bin/$1"
  [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  # VS Code from Flathub (a Mac's cask restored on Linux) exports its command here.
  if [ "$1" = code ]; then
    for p in "$HOME/.local/share/flatpak/exports/bin/com.visualstudio.code" /var/lib/flatpak/exports/bin/com.visualstudio.code; do
      [ -x "$p" ] && { printf '%s' "$p"; return 0; }
    done
  fi
  return 1
}

editor_user_dir() { # <config dir name>
  if is_macos; then
    printf '%s' "$HOME/Library/Application Support/$1/User"
  else
    printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/$1/User"
  fi
}

editor_backup() { # <cli> <App Name> <config dir> <backup dir>
  local cli user f
  user=$(editor_user_dir "$3")
  if cli=$(editor_cli "$1" "$2"); then
    "$cli" --list-extensions 2>/dev/null | sort -u > "$4/extensions.txt" || return 1
  fi
  for f in "$user/settings.json" "$user/keybindings.json"; do save_file "$f" "$4/home"; done
  if [ -d "$user/snippets" ]; then
    while IFS= read -r f; do save_file "$f" "$4/home"; done < <(find "$user/snippets" -type f)
  fi
  summary "$4" "$(tn "%d extension + settings" "%d extensions + settings" "$(count_lines "$4/extensions.txt")")"
}

# Editor settings from the other OS: "Library/Application Support/Code/User/..." (macOS)
# and ".config/Code/User/..." (Linux) are the same files, moved to where this OS reads them.
editor_home_for_this_os() { # <backup home> <out dir>
  local f rel
  while IFS= read -r f; do
    rel=${f#"$1"/}
    if is_macos; then
      case "$rel" in .config/*/User/*) rel="Library/Application Support/${rel#.config/}" ;; esac
    else
      case "$rel" in "Library/Application Support/"*/User/*) rel=".config/${rel#Library/Application Support/}" ;; esac
    fi
    mkdir -p "$2/$(dirname "$rel")"
    cp "$f" "$2/$rel"
  done < <(find "$1" -type f 2>/dev/null)
}

editor_restore() { # <cli> <App Name> <backup dir>
  local home
  home=$(mktemp -d)
  tmp_register "$home"
  editor_home_for_this_os "$3/home" "$home"
  restore_home "$home" "Library/Application Support/*/User/settings.json
Library/Application Support/*/User/keybindings.json
Library/Application Support/*/User/snippets/*
.config/*/User/settings.json
.config/*/User/keybindings.json
.config/*/User/snippets/*"
  rm -rf "$home"
  [ -s "$3/extensions.txt" ] || return 0
  local cli e
  if ! cli=$(editor_cli "$1" "$2"); then
    if [ -z "${DUDU_DRY_RUN:-}" ]; then warn "$(t "%s is not installed, skipping extensions" "$2")"; return 0; fi
    cli=$1
  fi
  while IFS= read -r e; do
    act "$cli" --install-extension "$e" --force || warn "$(t "could not install %s" "$e")"
  done < <("$cli" --list-extensions 2>/dev/null | missing_pkgs "$3/extensions.txt")
  [ -z "${DUDU_DRY_RUN:-}" ] && ok "$(tn "%d extension in place" "%d extensions in place" "$(count_lines "$3/extensions.txt")")"
  return 0
}

vscode_detect() { editor_cli code "Visual Studio Code" >/dev/null || [ -d "$(editor_user_dir Code)" ]; }
vscode_backup() { editor_backup code "Visual Studio Code" Code "$1"; }
vscode_restore() { editor_restore code "Visual Studio Code" "$1"; }
