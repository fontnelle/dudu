#!/usr/bin/env bash
# OS and package manager detection.

# ./dudu sets DUDU_UNAME once: forking uname for every check is slow in Git Bash.
dudu_os() {
  case "${DUDU_UNAME:-$(uname -s)}" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    MINGW* | MSYS* | CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

is_macos() { [ "${DUDU_UNAME:-$(uname -s)}" = Darwin ]; }
is_linux() { [ "${DUDU_UNAME:-$(uname -s)}" = Linux ]; }
# Git Bash (MSYS2), the shell dudu runs in on Windows.
is_windows() { case "${DUDU_UNAME:-$(uname -s)}" in MINGW* | MSYS* | CYGWIN*) return 0 ;; esac; return 1; }

# Windows paths <-> Git Bash paths (C:\Users\x <-> /c/Users/x).
win_path() { if has cygpath; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
unix_path() { if has cygpath; then cygpath -u "$1"; else printf '%s' "$1"; fi; }

# %APPDATA% and %LOCALAPPDATA% as Git Bash paths, with the usual default when unset.
win_appdata() {
  if [ -n "${APPDATA:-}" ]; then unix_path "$APPDATA"; else printf '%s' "$HOME/AppData/Roaming"; fi
}
win_localappdata() {
  if [ -n "${LOCALAPPDATA:-}" ]; then unix_path "$LOCALAPPDATA"; else printf '%s' "$HOME/AppData/Local"; fi
}

# One value from the Windows registry: win_reg 'HKLM\...\Key' ValueName.
win_reg() {
  reg query "$1" //v "$2" 2>/dev/null | sed -n 's/.*REG_[A-Z_]*[[:space:]]*//p' | tr -d '\r' | head -n 1
}

# Windows package manager (winget and scoop are their own collectors).
win_pm() {
  if has winget; then echo winget
  elif has scoop; then echo scoop
  elif has choco; then echo choco
  fi
}

# System package manager on Linux (brew is its own collector).
linux_pm() {
  if has apt-get; then echo apt
  elif has dnf; then echo dnf
  elif has pacman; then echo pacman
  fi
}

os_pretty() {
  if is_macos; then
    printf 'macOS %s' "$(sw_vers -productVersion 2>/dev/null)"
  elif is_windows; then
    local key='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' v build
    v=$(win_reg "$key" ProductName)
    build=$(win_reg "$key" CurrentBuild)
    # Windows 11 still says "Windows 10" in ProductName; its builds start at 22000.
    case "$build" in [0-9]*) [ "$build" -ge 22000 ] && v=$(printf '%s' "$v" | sed 's/Windows 10/Windows 11/') ;; esac
    printf '%s' "${v:-Windows}"
  elif [ -r /etc/os-release ]; then
    (. /etc/os-release && printf '%s' "${PRETTY_NAME:-Linux}")
  else
    uname -sr
  fi
}

# Stable machine id. On macOS `hostname` follows the network (DHCP/VPN), LocalHostName does not.
dudu_host() {
  local h=""
  is_macos && h=$(scutil --get LocalHostName 2>/dev/null)
  is_windows && h=${COMPUTERNAME:-}
  [ -n "$h" ] || h=$(hostname -s 2>/dev/null || uname -n)
  printf '%s' "$h" | tr -cd 'A-Za-z0-9._-'
}

file_mtime() {
  if is_macos; then /usr/bin/stat -f %m "$1" 2>/dev/null; else stat -c %Y "$1" 2>/dev/null; fi
}

# sudo only when needed (containers often run as root without sudo).
# Git Bash has no sudo: the command runs as is, with the rights of this terminal.
as_root() {
  if is_windows || [ "$(id -u)" -eq 0 ]; then act "$@"; else act sudo "$@"; fi
}

# Seconds since epoch for an ISO date like 2026-10-17T13:02:20Z (UTC).
iso_to_epoch() {
  if is_macos; then
    /bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
  else
    date -u -d "$1" +%s 2>/dev/null
  fi
}

# "today 10:02", "yesterday 18:40" or "15/10 09:12", in local time.
human_date() { # <epoch>
  local day today yesterday
  if is_macos; then
    day=$(/bin/date -r "$1" +%Y-%m-%d)
    yesterday=$(/bin/date -v-1d +%Y-%m-%d)
  else
    day=$(date -d "@$1" +%Y-%m-%d)
    yesterday=$(date -d yesterday +%Y-%m-%d)
  fi
  today=$(date +%Y-%m-%d)
  local hm
  if is_macos; then hm=$(/bin/date -r "$1" +%H:%M); else hm=$(date -d "@$1" +%H:%M); fi
  if [ "$day" = "$today" ]; then t "today %s" "$hm"
  elif [ "$day" = "$yesterday" ]; then t "yesterday %s" "$hm"
  elif is_macos; then /bin/date -r "$1" '+%d/%m/%Y %H:%M'
  else date -d "@$1" '+%d/%m/%Y %H:%M'
  fi
}

# "just now", "6 min ago", "3 h ago", "12 days ago".
time_ago() { # <epoch>
  local d=$(( $(date +%s) - $1 ))
  if [ $d -lt 60 ]; then t "just now"
  elif [ $d -lt 3600 ]; then t "%d min ago" $((d / 60))
  elif [ $d -lt 86400 ]; then t "%d h ago" $((d / 3600))
  else tn "%d day ago" "%d days ago" $((d / 86400))
  fi
}

# "today 10:02 (6 min ago)" from the ISO date stored in a manifest.
friendly_date() { # <iso>
  local e
  e=$(iso_to_epoch "$1")
  if [ -n "$e" ]; then printf '%s (%s)' "$(human_date "$e")" "$(time_ago "$e")"; else printf '%s' "$1"; fi
}
