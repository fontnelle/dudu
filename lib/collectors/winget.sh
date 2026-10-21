#!/usr/bin/env bash
# winget: the packages Windows' package manager knows about, by package id.

winget_detect() { is_windows && has winget; }

WINGET_ACCEPT="--accept-source-agreements --accept-package-agreements --disable-interactivity"

# Package ids installed from winget's sources, one per line (apps it cannot match are left out).
winget_ids() {
  local f
  f=$(mktemp)
  # shellcheck disable=SC2086
  winget export -o "$(win_path "$f")" --accept-source-agreements --disable-interactivity >/dev/null 2>&1
  sed -n 's/.*"PackageIdentifier"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | tr -d '\r' | sort -u
  rm -f "$f"
}

winget_backup() {
  winget_ids > "$1/packages.txt" || return 1
  [ -s "$1/packages.txt" ] || return 1
  summary "$1" "$(tn "%d %s package" "%d %s packages" "$(count_lines "$1/packages.txt")" winget)"
}

winget_install() { # <id>
  # shellcheck disable=SC2086
  act winget install --id "$1" --exact --silent $WINGET_ACCEPT
}

winget_restore() {
  local id n=0
  while IFS= read -r id; do
    winget_install "$id" || warn "$(t "could not install %s" "$id")"
    n=$((n + 1))
  done < <(winget_ids | missing_pkgs "$1/packages.txt")
  [ $n -gt 0 ] || dim "  $(t "all packages already installed")"
}

# winget's tables have localized headers and names with spaces: read each row from the
# right (Id Version Available Source). Prints "id current latest" for each row.
winget_table() {
  awk '
    { gsub(/\r/, "") }
    /^-+$/ { on = 1; next }
    on && NF >= 5 {
      i = NF - 2; cur = $i; i--
      if ($i == "<" || $i == ">") i--
      print $i, cur, $(NF - 1)
    }'
}

winget_outdated() {
  winget upgrade --accept-source-agreements --disable-interactivity 2>/dev/null | winget_table
}

winget_upgrade_hint() { echo "winget upgrade --all"; }
# shellcheck disable=SC2086
winget_upgrade() { winget upgrade --id "$1" --exact --silent $WINGET_ACCEPT; }
