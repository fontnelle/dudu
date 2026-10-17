#!/usr/bin/env bash
# Global bun packages.

BUN_GLOBAL_PKG="${BUN_INSTALL:-$HOME/.bun}/install/global/package.json"

bun_detect() { has bun && [ -f "$BUN_GLOBAL_PKG" ]; }

bun_backup() {
  [ -f "$BUN_GLOBAL_PKG" ] || return 1
  json_deps "$BUN_GLOBAL_PKG" | sort -u > "$1/globals.txt"
  summary "$1" "$(count_lines "$1/globals.txt") global packages"
}

bun_restore() {
  [ -s "$1/globals.txt" ] || return 0
  if ! has bun; then
    step "Installing bun"
    act_sh 'curl -fsSL https://bun.sh/install | bash' || return 1
    export PATH="${BUN_INSTALL:-$HOME/.bun}/bin:$PATH"
  fi
  local pkgs
  pkgs=$(json_deps "$BUN_GLOBAL_PKG" | missing_pkgs "$1/globals.txt")
  # shellcheck disable=SC2086
  if [ -n "$pkgs" ]; then act bun add -g $pkgs; else dim "  = all installed"; fi
}
