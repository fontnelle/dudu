#!/usr/bin/env bash
# Chocolatey: the packages installed with choco (installing needs an admin terminal).

choco_detect() { is_windows && has choco; }

# "name" per line. choco 2 lists local packages by default; 1.x needs --local-only.
choco_list() {
  { choco list --limit-output 2>/dev/null || choco list --local-only --limit-output 2>/dev/null; } |
    tr -d '\r' | awk -F'|' 'NF >= 2 && $1 != "chocolatey" { print $1 }' | sort -u
}

choco_backup() {
  choco_list > "$1/packages.txt" || return 1
  summary "$1" "$(tn "%d %s package" "%d %s packages" "$(count_lines "$1/packages.txt")" choco)"
}

choco_restore() {
  local pkgs
  pkgs=$(choco_list | missing_pkgs "$1/packages.txt")
  if [ -z "$pkgs" ]; then
    dim "  $(t "all packages already installed")"
    return 0
  fi
  # shellcheck disable=SC2086
  act choco install -y --no-progress $pkgs
}

choco_outdated() {
  # name|current|available|pinned
  choco outdated --limit-output 2>/dev/null | tr -d '\r' | awk -F'|' 'NF >= 3 { print $1, $2, $3 }'
}

choco_upgrade_hint() { echo "choco upgrade all -y"; }
choco_upgrade() { choco upgrade -y "$1"; }
