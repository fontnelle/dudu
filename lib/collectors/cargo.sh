#!/usr/bin/env bash
# Rust: crates installed with cargo install.

cargo_detect() { has cargo; }

cargo_list() {
  local raw
  raw=$(cargo install --list 2>/dev/null) || return 1
  printf '%s\n' "$raw" | awk '/^[^[:space:]].*:$/ { print $1 }'
}

cargo_backup() {
  cargo_list | sort -u > "$1/crates.txt" || return 1
  summary "$1" "$(tn "%d crate" "%d crates" "$(count_lines "$1/crates.txt")")"
}

cargo_restore() {
  [ -s "$1/crates.txt" ] || return 0
  if ! has cargo; then
    step "$(t "Installing %s" "Rust (rustup)")"
    if is_windows; then win_pkg_install Rustlang.Rustup rustup || return 1
    else act_sh "curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y" || return 1; fi
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
  local c
  while IFS= read -r c; do
    act cargo install --locked "$c" || warn "$(t "could not install %s" "$c")"
  done < <(cargo_list | missing_pkgs "$1/crates.txt")
}

cargo_outdated() {
  has cargo-install-update || return 0
  cargo install-update -l 2>/dev/null | awk 'tolower($NF) == "yes" { print $1, $2, $3 }'
}

cargo_upgrade_hint() { echo "cargo install-update -a"; }
cargo_upgrade() { cargo install --locked "$1"; }
