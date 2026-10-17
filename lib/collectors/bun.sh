#!/usr/bin/env bash
# Global bun packages.

BUN_GLOBAL_PKG="${BUN_INSTALL:-$HOME/.bun}/install/global/package.json"

bun_detect() { has bun && [ -f "$BUN_GLOBAL_PKG" ]; }

bun_backup() {
  [ -f "$BUN_GLOBAL_PKG" ] || return 1
  json_deps "$BUN_GLOBAL_PKG" | sort -u > "$1/globals.txt"
  summary "$1" "$(tn "%d global package" "%d global packages" "$(count_lines "$1/globals.txt")")"
}

bun_restore() {
  [ -s "$1/globals.txt" ] || return 0
  if ! has bun; then
    step "$(t "Installing %s" bun)"
    act_sh 'curl -fsSL https://bun.sh/install | bash' || return 1
    export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"
  fi
  local pkgs
  pkgs=$(json_deps "$BUN_GLOBAL_PKG" | missing_pkgs "$1/globals.txt")
  # shellcheck disable=SC2086
  if [ -n "$pkgs" ]; then act bun add -g $pkgs; else dim "  = $(t "all installed")"; fi
}
