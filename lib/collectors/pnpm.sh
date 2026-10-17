#!/usr/bin/env bash
# Global pnpm packages.

pnpm_detect() { has pnpm && [ -d "$(pnpm root -g 2>/dev/null)" ]; }

pnpm_backup() {
  local root
  root=$(pnpm root -g 2>/dev/null) || return 1
  npm_list_modules "$root" | sort -u > "$1/globals.txt"
  summary "$1" "$(count_lines "$1/globals.txt") global packages"
}

pnpm_restore() {
  [ -s "$1/globals.txt" ] || return 0
  if ! has pnpm && [ -z "${DUDU_DRY_RUN:-}" ]; then
    warn "pnpm is not installed (restore npm/brew first), skipping"
    return 0
  fi
  local pkgs
  pkgs=$(npm_list_modules "$(pnpm root -g 2>/dev/null)" | missing_pkgs "$1/globals.txt")
  # shellcheck disable=SC2086
  if [ -n "$pkgs" ]; then act pnpm add -g $pkgs; else dim "  = all installed"; fi
}
