#!/usr/bin/env bash
# Ruby: rbenv versions and user-installed gems (system Ruby on macOS is ignored).

ruby_detect() {
  has rbenv && return 0
  has gem && [ "$(command -v gem)" != /usr/bin/gem ]
}

ruby_gems() {
  local raw
  raw=$(gem list 2>/dev/null) || return 1
  printf '%s\n' "$raw" | awk '!/default:/ { sub(/ \(.*/, ""); if ($0 != "") print }'
}

ruby_backup() {
  if has rbenv; then
    rbenv versions --bare 2>/dev/null > "$1/rbenv.txt" || return 1
    rbenv global 2>/dev/null > "$1/rbenv-global"
  fi
  if has gem; then ruby_gems | sort -u > "$1/gems.txt" || return 1; fi
  save_file "$HOME/.gemrc" "$1/home"
  save_file "$HOME/.irbrc" "$1/home"
  summary "$1" "$(count_lines "$1/gems.txt") gems$( [ -s "$1/rbenv.txt" ] && printf ', %s rbenv versions' "$(count_lines "$1/rbenv.txt")")"
}

ruby_restore() {
  local v gems
  if [ -s "$1/rbenv.txt" ] && { has rbenv || [ -n "${DUDU_DRY_RUN:-}" ]; }; then
    while IFS= read -r v; do
      act rbenv install -s "$v"
    done < <(rbenv versions --bare 2>/dev/null | missing_pkgs "$1/rbenv.txt")
    v=$(pkg_filter < "$1/rbenv-global" 2>/dev/null | head -1)
    [ -n "$v" ] && act rbenv global "$v"
  fi
  if [ -s "$1/gems.txt" ]; then
    gems=$(ruby_gems | missing_pkgs "$1/gems.txt")
    # shellcheck disable=SC2086
    if [ -n "$gems" ]; then act gem install $gems; else dim "  = all gems installed"; fi
  fi
  restore_home "$1/home" ".gemrc
.irbrc"
}

ruby_outdated() {
  # "rake (13.0.6 < 13.2.1)"
  gem outdated 2>/dev/null | sed -E 's/^([^ ]+) \(([^ ]+) < ([^)]+)\)$/\1 \2 \3/'
}

ruby_upgrade_hint() { echo "gem update"; }
ruby_upgrade() { gem update "$1"; }
