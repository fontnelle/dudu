#!/usr/bin/env bash
# Global npm packages, per Node version when nvm is used, plus ~/.npmrc (tokens masked).

NPM_BUILTIN="npm corepack"

# Package names inside a node_modules folder, scoped ones as @scope/name.
npm_list_modules() {
  local root=$1 d s
  [ -d "$root" ] || return 0
  for d in "$root"/*; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in
      .*) ;;
      @*) for s in "$d"/*; do [ -d "$s" ] && printf '%s/%s\n' "$(basename "$d")" "$(basename "$s")"; done ;;
      *) basename "$d" ;;
    esac
  done | awk '$0 != "npm" && $0 != "corepack"'
}

npm_detect() { has npm || [ -d "$(node_nvm_dir)/versions/node" ]; }

npm_backup() {
  local dir v root
  dir=$(node_nvm_dir)
  : > "$1/globals.txt"
  if [ -d "$dir/versions/node" ]; then
    for v in "$dir"/versions/node/v*; do
      [ -d "$v" ] || continue
      npm_list_modules "$v/lib/node_modules" | sed "s|^|$(basename "$v") |" >> "$1/globals.txt"
    done
  else
    root=$(npm root -g 2>/dev/null) || return 1
    npm_list_modules "$root" | sed 's|^|default |' >> "$1/globals.txt"
  fi
  save_file "$HOME/.npmrc" "$1/home"
  summary "$1" "$(count_lines "$1/globals.txt") global packages"
}

npm_restore() {
  local dir version pkgs wanted
  dir=$(node_nvm_dir)
  wanted=$(mktemp)
  [ -n "${DUDU_DRY_RUN:-}" ] || node_load_nvm 2>/dev/null
  # shellcheck disable=SC2013
  for version in $(awk '{ print $1 }' "$1/globals.txt" | sort -u); do
    printf '%s\n' "$version" | pkg_filter | grep -q . || continue
    awk -v v="$version" '$1 == v { print $2 }' "$1/globals.txt" | pkg_filter > "$wanted"
    if [ "$version" = default ]; then
      pkgs=$(npm_list_modules "$(npm root -g 2>/dev/null)" | missing_from "$wanted")
      # shellcheck disable=SC2086
      [ -n "$pkgs" ] && act npm install -g $pkgs
    elif [ -d "$dir/versions/node/$version" ] || [ -n "${DUDU_DRY_RUN:-}" ]; then
      pkgs=$(npm_list_modules "$dir/versions/node/$version/lib/node_modules" | missing_from "$wanted")
      # shellcheck disable=SC2086
      [ -n "$pkgs" ] && act env PATH="$dir/versions/node/$version/bin:$PATH" npm install -g $pkgs
    else
      warn "node $version is not installed, skipping its globals: $(tr '\n' ' ' < "$wanted")"
      continue
    fi
    [ -z "$pkgs" ] && dim "  = node $version globals"
  done
  rm -f "$wanted"
  # After the installs: a .npmrc pointing at another registry must not decide where they come from.
  restore_home "$1/home" ".npmrc"
}

npm_outdated() {
  npm outdated -g 2>/dev/null | awk 'NR > 1 && $2 != $4 { print $1, $2, $4 }'
}

npm_upgrade_hint() { echo "npm update -g"; }
npm_upgrade() { npm install -g "$1@latest"; }
