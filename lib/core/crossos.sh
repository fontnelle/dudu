#!/usr/bin/env bash
# Backups made on another OS (a Mac's backup restored on Linux or Windows, or the reverse):
# what of them applies here, and a Mac's Brewfile turned into this system's packages.
# The names that differ between Homebrew and Linux are in lib/data/brew-linux.map, and the
# winget and scoop names in lib/data/brew-windows.map.

# Tools of one OS only: a backup from the other one has nothing to restore here for them.
collector_applies() { # <collector>
  case "$1" in
    macos) is_macos ;;
    syspkgs) is_linux ;;
    winget | scoop | choco) is_windows ;;
    *) return 0 ;;
  esac
}

# "macOS", "Linux": the OS a backup's manifest names.
os_label() { # <macos|linux>
  case "$1" in
    macos) printf 'macOS' ;;
    linux) printf 'Linux' ;;
    windows) printf 'Windows' ;;
    *) printf '%s' "$1" ;;
  esac
}

# The OS a tool of one OS only belongs to (collector_applies).
collector_os() { # <collector>
  case "$1" in
    macos) printf 'macOS' ;;
    syspkgs) printf 'Linux' ;;
    winget | scoop | choco) printf 'Windows' ;;
  esac
}

# The backup was made on another OS than this one.
crossos_bundle() { # <bundle>
  local os
  os=$(manifest_field "$1" os)
  [ -n "$os" ] && [ "$os" != "$(dudu_os)" ]
}

# Every package name this system's repositories offer, one per line.
crossos_available() { # <pm>
  case "$1" in
    apt) apt-cache pkgnames 2>/dev/null ;;
    dnf) dnf repoquery -q --qf '%{name}\n' 2>/dev/null ;;
    pacman) pacman -Slq 2>/dev/null ;;
  esac
}

# The map column of a package manager.
crossos_column() { # <pm>
  case "$1" in
    apt) echo 3 ;;
    dnf) echo 4 ;;
    pacman) echo 5 ;;
  esac
}

# What each entry of a Mac's Brewfile becomes here, one per line:
#   native|<package>|<name>     a package of this system's manager
#   flatpak|<app id>|<name>     a Flathub app
#   brew|<formula>|<name>       a formula for the Homebrew of this machine ("brew" given)
#   none|<name>                 nothing to install it with here
# Entries another collector installs (nvm, rustup) or the system already has print nothing.
crossos_brew_plan() { # <Brewfile> <pm> [brew]
  local avail col kind name base line pkg fp trust=""
  avail=$(mktemp)
  crossos_available "$2" | sort -u > "$avail"
  # Without the repository lists (apt update never ran), the mapped names are tried as is.
  [ -s "$avail" ] || trust=1
  col=$(crossos_column "$2")
  while IFS='|' read -r kind name; do
    base=${name##*/}
    pkg=""
    fp=""
    line=$(awk -F'|' -v k="$kind" -v n="$base" '$1 == k && $2 == n { print; exit }' "$CROSSOS_MAP")
    if [ -n "$line" ]; then
      [ -n "$col" ] && pkg=$(printf '%s' "$line" | cut -d'|' -f"$col")
      fp=$(printf '%s' "$line" | cut -d'|' -f6)
    fi
    case "$pkg" in -|@*) continue ;; esac
    case "$kind" in
      brew)
        [ -n "$pkg" ] || pkg=$base
        if [ -n "$col" ] && { [ -n "$trust" ] || grep -qxF -- "$pkg" "$avail"; }; then
          echo "native|$pkg|$base"
        elif [ -n "${3:-}" ]; then echo "brew|$name|$base"
        elif [ -n "$fp" ]; then echo "flatpak|$fp|$base"
        else echo "none|$base"
        fi
        ;;
      cask)
        if [ -n "$pkg" ] && [ -n "$col" ] && { [ -n "$trust" ] || grep -qxF -- "$pkg" "$avail"; }; then
          echo "native|$pkg|$base (cask)"
        elif [ -n "$fp" ]; then echo "flatpak|$fp|$base (cask)"
        else echo "none|$base (cask)"
        fi
        ;;
      mas) echo "none|$name (App Store)" ;;
      whalebrew) echo "none|$name (whalebrew)" ;;
    esac
  done < <(brew_safe_brewfile "$1" 2>/dev/null | LC_ALL=C awk '
    /^(brew|cask|whalebrew) "/ { split($0, q, "\""); if (q[2] ~ /^[A-Za-z0-9@][A-Za-z0-9@._+\/-]*$/) print $1 "|" q[2]; next }
    /^mas "/ { split($0, q, "\""); gsub(/\|/, "", q[2]); print "mas|" q[2] }')
  rm -f "$avail"
}

CROSSOS_MAP="$DUDU_ROOT/lib/data/brew-linux.map"

# A Mac's brew folder made ready for this Linux: the Brewfile becomes linux/<pm>.txt,
# linux/flatpak.txt and linux/brew.txt, holding only what this machine is missing, so the
# comparison and brew_restore see the same thing. The rest goes to <left out file>.
crossos_brew_localize() { # <brew dir> <left out file>
  local pm brewfile kind id name have
  pm=$(linux_pm)
  brewfile=$(mktemp)
  mv "$1/Brewfile" "$brewfile"
  mkdir -p "$1/linux"
  have=""
  { has brew || brew_load_shellenv; } >/dev/null 2>&1 && have=brew
  while IFS='|' read -r kind id name; do
    case "$kind" in
      native) printf '%s\n' "$id" >> "$1/linux/$pm.txt" ;;
      flatpak) printf '%s\n' "$id" >> "$1/linux/flatpak.txt" ;;
      brew) printf '%s\n' "$id" >> "$1/linux/brew.txt" ;;
      none) printf 'brew|%s\n' "$id" >> "$2" ;;
    esac
  done < <(crossos_brew_plan "$brewfile" "$pm" ${have:+"$have"})
  rm -f "$brewfile"
  # Only what is missing: installed apps are not part of what a restore would do.
  local f now
  now=$(mktemp)
  for f in "$1"/linux/*.txt; do
    [ -f "$f" ] || continue
    case "$(basename "$f" .txt)" in
      flatpak) flatpak list --app --columns=application 2>/dev/null ;;
      brew) brew list --formula -1 2>/dev/null ;;
      *) syspkgs_list_installed "$pm" ;;
    esac > "$now"
    missing_pkgs "$f" < "$now" > "$f.new" 2>/dev/null
    mv "$f.new" "$f"
  done
  rm -f "$now"
}

# Makes a backup from the other OS look like one from this machine before it is compared
# and restored: editor settings move to where this OS keeps them, macOS-only files are set
# aside, and on Linux a Mac's Brewfile becomes this system's packages. What has no place here
# goes to <left out file> as "<tool>|<what>" lines.
crossos_localize() { # <bundle> <left out file>
  local b=$1 c d f tmp
  crossos_bundle "$b" || return 0
  for c in vscode cursor; do
    [ -d "$b/$c/home" ] || continue
    tmp=$(mktemp -d)
    editor_home_for_this_os "$b/$c/home" "$tmp"
    rm -rf "${b:?}/$c/home"
    mv "$tmp" "$b/$c/home"
  done
  # Windows' AppData (Windows Terminal, nvim) means nothing on macOS or Linux.
  is_windows || crossos_set_aside "$b" AppData "$2"
  is_macos && return 0

  # Ghostty reads the same config from ~/.config/ghostty on Linux.
  f="$b/terminal/home/Library/Application Support/com.mitchellh.ghostty/config"
  if ! is_windows && [ -f "$f" ] && [ ! -f "$b/terminal/home/.config/ghostty/config" ]; then
    mkdir -p "$b/terminal/home/.config/ghostty"
    mv "$f" "$b/terminal/home/.config/ghostty/config"
  fi
  # Terminal.app and iTerm2 preferences, and anything under ~/Library.
  for f in "$b"/terminal/defaults/*.plist; do
    [ -f "$f" ] && printf 'terminal|%s\n' "$(pretty_file "defaults/$(basename "$f")")" >> "$2"
  done
  rm -rf "$b/terminal/defaults"
  crossos_set_aside "$b" Library "$2"
  if [ -f "$b/brew/Brewfile" ]; then
    if is_windows; then crossos_brew_localize_windows "$b/brew" "$2"; else crossos_brew_localize "$b/brew" "$2"; fi
  fi
  return 0
}

# Takes every tool's home/<top> folder (Library, AppData) out of the bundle, listing its
# files in <left out file>.
crossos_set_aside() { # <bundle> <top folder> <left out file>
  local d c
  for d in "$1"/*/home/"$2"; do
    [ -d "$d" ] || continue
    c=$(basename "$(dirname "$(dirname "$d")")")
    (cd "$d/.." && find "$2" -type f) | LC_ALL=C sort | sed "s#^#$c|~/#" >> "$3"
    rm -rf "$d"
  done
}

CROSSOS_WIN_MAP="$DUDU_ROOT/lib/data/brew-windows.map"

# What each entry of a Brewfile becomes on Windows, one per line:
#   winget|<id>|<name>   scoop|<app>|<name>   none|<name>
# winget comes first; scoop takes what winget has no id for, when scoop is installed.
crossos_windows_plan() { # <Brewfile>
  local kind name base line w sc
  while IFS='|' read -r kind name; do
    base=${name##*/}
    w="" sc=""
    line=$(awk -F'|' -v k="$kind" -v n="$base" '$1 == k && $2 == n { print; exit }' "$CROSSOS_WIN_MAP")
    if [ -n "$line" ]; then
      w=$(printf '%s' "$line" | cut -d'|' -f3)
      sc=$(printf '%s' "$line" | cut -d'|' -f4)
    elif [ "$kind" = brew ]; then
      sc=$base
    fi
    case "$w" in -|@*) continue ;; esac
    case "$kind" in
      brew | cask)
        local label=$base
        [ "$kind" = cask ] && label="$base (cask)"
        if [ -n "$w" ] && has winget; then echo "winget|$w|$label"
        elif [ -n "$sc" ] && has scoop; then echo "scoop|$sc|$label"
        else echo "none|$label"
        fi
        ;;
      mas) echo "none|$name (App Store)" ;;
      whalebrew) echo "none|$name (whalebrew)" ;;
    esac
  done < <(brew_safe_brewfile "$1" 2>/dev/null | LC_ALL=C awk '
    /^(brew|cask|whalebrew) "/ { split($0, q, "\""); if (q[2] ~ /^[A-Za-z0-9@][A-Za-z0-9@._+\/-]*$/) print $1 "|" q[2]; next }
    /^mas "/ { split($0, q, "\""); gsub(/\|/, "", q[2]); print "mas|" q[2] }')
}

# A Mac's brew folder made ready for Windows: the Brewfile becomes windows/winget.txt and
# windows/scoop.txt, holding only what this machine is missing. The rest goes to <left out>.
crossos_brew_localize_windows() { # <brew dir> <left out file>
  local brewfile kind id name f now
  brewfile=$(mktemp)
  mv "$1/Brewfile" "$brewfile"
  mkdir -p "$1/windows"
  while IFS='|' read -r kind id name; do
    case "$kind" in
      winget | scoop) printf '%s\n' "$id" >> "$1/windows/$kind.txt" ;;
      none) printf 'brew|%s\n' "$id" >> "$2" ;;
    esac
  done < <(crossos_windows_plan "$brewfile")
  rm -f "$brewfile"
  now=$(mktemp)
  for f in "$1"/windows/*.txt; do
    [ -f "$f" ] || continue
    case "$(basename "$f" .txt)" in
      winget) winget_ids ;;
      scoop) scoop list 2>/dev/null | tr -d '\r' | awk 'NR > 2 && NF { print $1 }' ;;
    esac > "$now"
    missing_pkgs "$f" < "$now" > "$f.new" 2>/dev/null
    mv "$f.new" "$f"
  done
  rm -f "$now"
}

# Installs a Mac's Homebrew apps on Windows, from what crossos_brew_localize_windows left.
crossos_brew_restore_windows() { # <brew dir>
  local d=$1/windows id
  if [ -s "$d/winget.txt" ]; then
    while IFS= read -r id; do
      winget_install "$id" || warn "$(t "could not install %s" "$id")"
    done < <(pkg_filter < "$d/winget.txt")
  fi
  if [ -s "$d/scoop.txt" ] && has scoop; then
    # Most apps (the casks) are in the extras bucket.
    scoop bucket list 2>/dev/null | grep -q '^extras' || act scoop bucket add extras || warn "$(t "could not add %s" extras)"
    while IFS= read -r id; do
      act scoop install "$id" || warn "$(t "could not install %s" "$id")"
    done < <(pkg_filter < "$d/scoop.txt")
  fi
  return 0
}

# Installs a Mac's Homebrew apps on this Linux, from what crossos_brew_localize left in
# <brew dir>/linux.
crossos_brew_restore() { # <brew dir>
  local d=$1/linux pm f
  pm=$(linux_pm)
  if [ -f "$d/$pm.txt" ]; then
    syspkgs_install_missing "$pm" "$d/$pm.txt"
  fi
  if [ -s "$d/flatpak.txt" ]; then
    if ! has flatpak && [ -z "${DUDU_DRY_RUN:-}" ]; then
      step "$(t "Installing %s" flatpak)"
      syspkgs_install "$pm" flatpak || { warn "$(t "could not install %s" flatpak)"; return 1; }
    fi
    as_root flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo ||
      warn "$(t "could not add %s" Flathub)"
    syspkgs_flatpak_missing "$d/flatpak.txt"
  fi
  if [ -s "$d/brew.txt" ] && { has brew || brew_load_shellenv; }; then
    while IFS= read -r f; do
      act brew install "$f" || warn "$(t "could not install %s" "$f")"
    done < <(brew list --formula -1 2>/dev/null | missing_pkgs "$d/brew.txt")
  fi
  return 0
}

# The "left out" list of a restore: what has nothing to go to on this OS, by tool.
crossos_show_left_out() { # <left out file>
  [ -s "$1" ] || return 0
  local c n shown what
  section "$(t "Left out")" "$(t "made for the other system, nothing to restore it with here")"
  while IFS= read -r c; do
    printf '  %s%s%s\n' "$BOLD" "$c" "$NC"
    n=$(grep -c "^$c|" "$1")
    shown=0
    while IFS= read -r what; do
      shown=$((shown + 1))
      if [ $shown -gt 8 ]; then
        printf '      %s%s%s\n' "$GRAY" "$(t "… and %d more" $((n - 8)))" "$NC"
        break
      fi
      printf '    %s- %s%s\n' "$GRAY" "$(safe_text "$what")" "$NC"
    done < <(grep "^$c|" "$1" | cut -d'|' -f2-)
  done < <(cut -d'|' -f1 "$1" | awk '!seen[$0]++')
  return 0
}
