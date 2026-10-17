#!/usr/bin/env bash
# Node.js versions through nvm (or fnm/volta), with the default version.

NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh"

node_nvm_dir() { printf '%s' "${NVM_DIR:-$HOME/.nvm}"; }

node_load_nvm() {
  local dir
  dir=$(node_nvm_dir)
  [ -s "$dir/nvm.sh" ] || return 1
  export NVM_DIR="$dir"
  # shellcheck source=/dev/null
  . "$dir/nvm.sh" --no-use
}

node_detect() { [ -s "$(node_nvm_dir)/nvm.sh" ] || has fnm || has volta || has node; }

node_backup() {
  local dir raw
  dir=$(node_nvm_dir)
  if [ -s "$dir/nvm.sh" ]; then
    echo nvm > "$1/manager"
    : > "$1/versions.txt"
    for raw in "$dir"/versions/node/v*; do [ -d "$raw" ] && basename "$raw" >> "$1/versions.txt"; done
    [ -f "$dir/alias/default" ] && cat "$dir/alias/default" > "$1/default"
  elif has fnm; then
    echo fnm > "$1/manager"
    raw=$(fnm list 2>/dev/null) || return 1
    printf '%s\n' "$raw" | grep -o 'v[0-9][0-9.]*' | sort -u > "$1/versions.txt"
    printf '%s\n' "$raw" | grep 'default' | grep -o 'v[0-9][0-9.]*' | head -1 > "$1/default"
  elif has volta; then
    echo volta > "$1/manager"
    raw=$(volta list node --format plain 2>/dev/null) || return 1
    printf '%s\n' "$raw" | grep -o 'node@[0-9][0-9.]*' | sed 's/node@/v/' > "$1/versions.txt"
  else
    echo system > "$1/manager"
    node --version > "$1/versions.txt" || return 1
  fi
  save_file "$HOME/.nvmrc" "$1/home"
  summary "$1" "$(count_lines "$1/versions.txt") versions via $(cat "$1/manager")$( [ -s "$1/default" ] && printf ', default %s' "$(cat "$1/default")")"
}

node_restore() {
  local manager v default dir
  manager=$(cat "$1/manager")
  default=$(pkg_filter < "$1/default" 2>/dev/null | head -1)
  dir=$(node_nvm_dir)
  case "$manager" in
    nvm)
      if [ ! -s "$dir/nvm.sh" ]; then
        step "Installing nvm"
        # PROFILE=/dev/null: the restored .zshrc already loads nvm.
        act_sh "curl -fsSL $NVM_INSTALL_URL | PROFILE=/dev/null bash" || return 1
      fi
      [ -n "${DUDU_DRY_RUN:-}" ] || node_load_nvm || return 1
      while IFS= read -r v; do
        if [ -d "$dir/versions/node/$v" ]; then dim "  = node $v"; else act nvm install "$v"; fi
      done < <(pkg_filter < "$1/versions.txt")
      if [ -n "$default" ] && [ "$(cat "$dir/alias/default" 2>/dev/null)" != "$default" ]; then
        act nvm alias default "$default"
      fi
      ;;
    fnm)
      while IFS= read -r v; do act fnm install "$v"; done < <(pkg_filter < "$1/versions.txt")
      [ -n "$default" ] && act fnm default "$default"
      ;;
    volta)
      while IFS= read -r v; do act volta install "node@${v#v}"; done < <(pkg_filter < "$1/versions.txt")
      ;;
    system)
      dim "  Node $(cat "$1/versions.txt") was installed system-wide (Brewfile/packages cover it)"
      ;;
  esac
  restore_home "$1/home" ".nvmrc"
}

node_outdated() {
  node_load_nvm 2>/dev/null || return 0
  local current latest
  current=$(nvm version default 2>/dev/null)
  latest=$(nvm version-remote --lts 2>/dev/null)
  if [ -n "$latest" ] && [ "$latest" != "N/A" ] && [ "$current" != "$latest" ]; then
    printf 'node(default) %s %s(LTS)\n' "$current" "$latest"
  fi
}

node_upgrade_hint() { echo "nvm install --lts --reinstall-packages-from=default"; }

# Installs the latest LTS, carries the global packages over and makes it the default.
node_upgrade() {
  node_load_nvm || return 1
  local current latest
  current=$(nvm version default)
  latest=$(nvm version-remote --lts)
  { [ -n "$latest" ] && [ "$latest" != N/A ]; } || return 1
  nvm install "$latest" --reinstall-packages-from="$current" && nvm alias default "$latest"
}
