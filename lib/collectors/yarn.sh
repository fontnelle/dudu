#!/usr/bin/env bash
# Global yarn (classic) packages.

yarn_global_dir() { yarn global dir 2>/dev/null; }

yarn_detect() {
  has yarn || return 1
  case "$(yarn --version 2>/dev/null)" in 1.*) [ -f "$(yarn_global_dir)/package.json" ] ;; *) return 1 ;; esac
}

yarn_backup() {
  local dir
  dir=$(yarn_global_dir) || return 1
  [ -f "$dir/package.json" ] || return 1
  json_deps "$dir/package.json" | sort -u > "$1/globals.txt"
  summary "$1" "$(tn "%d global package" "%d global packages" "$(count_lines "$1/globals.txt")")"
}

yarn_restore() {
  [ -s "$1/globals.txt" ] || return 0
  has yarn || [ -n "${DUDU_DRY_RUN:-}" ] || { warn "$(t "%s is not installed, skipping" yarn)"; return 0; }
  local pkgs
  pkgs=$(json_deps "$(yarn_global_dir)/package.json" | missing_pkgs "$1/globals.txt")
  # shellcheck disable=SC2086
  if [ -n "$pkgs" ]; then act yarn global add $pkgs; else dim "  = $(t "all installed")"; fi
}
