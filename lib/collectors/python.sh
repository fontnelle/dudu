#!/usr/bin/env bash
# Python: pyenv versions, pipx and uv tools, pip --user packages, pip config.

# On macOS /usr/bin/python3 is a stub that may pop up the Xcode tools installer.
python_real() {
  has python3 || return 1
  ! is_macos || [ "$(command -v python3)" != /usr/bin/python3 ] || xcode-select -p >/dev/null 2>&1
}

python_detect() { has pyenv || has pipx || has uv || python_real; }

python_backup() {
  local parts=""
  if has pyenv; then
    pyenv versions --bare 2>/dev/null | awk '!/\/envs\//' > "$1/pyenv.txt" || return 1
    pyenv global 2>/dev/null | head -1 > "$1/pyenv-global"
    parts="$parts$(count_lines "$1/pyenv.txt") pyenv versions, "
  fi
  if has pipx; then
    pipx list --short 2>/dev/null | awk '{ print $1 }' > "$1/pipx.txt" || return 1
    parts="$parts$(t "%d pipx" "$(count_lines "$1/pipx.txt")"), "
  fi
  if has uv; then
    uv tool list 2>/dev/null | awk '!/^[-[:space:]]/ { print $1 }' > "$1/uv-tools.txt" || return 1
    parts="$parts$(tn "%d uv tool" "%d uv tools" "$(count_lines "$1/uv-tools.txt")"), "
  fi
  if python_real; then
    python3 -m pip list --user --format=freeze 2>/dev/null | awk '!/^-e/' > "$1/pip-user.txt" || return 1
    parts="$parts$(t "%d pip --user" "$(count_lines "$1/pip-user.txt")"), "
  fi
  save_file "$HOME/.config/pip/pip.conf" "$1/home"
  save_file "$HOME/.pip/pip.conf" "$1/home"
  summary "$1" "${parts%, }"
}

python_restore() {
  local v t
  if [ -s "$1/pyenv.txt" ]; then
    if has pyenv || [ -n "${DUDU_DRY_RUN:-}" ]; then
      while IFS= read -r v; do
        act pyenv install -s "$v"
      done < <(pyenv versions --bare 2>/dev/null | missing_pkgs "$1/pyenv.txt")
      v=$(pkg_filter < "$1/pyenv-global" 2>/dev/null | head -1)
      if [ -n "$v" ] && [ "$v" != system ] && [ "$(pyenv global 2>/dev/null | head -1)" != "$v" ]; then
        act pyenv global "$v"
      fi
    else
      warn "$(t "pyenv is not installed (it is usually in the Brewfile), skipping Python versions")"
    fi
  fi
  if [ -s "$1/pipx.txt" ]; then
    while IFS= read -r t; do
      act pipx install "$t" || warn "$(t "could not install %s" "$t")"
    done < <(pipx list --short 2>/dev/null | awk '{ print $1 }' | missing_pkgs "$1/pipx.txt")
  fi
  if [ -s "$1/uv-tools.txt" ]; then
    while IFS= read -r t; do
      act uv tool install "$t" || warn "$(t "could not install %s" "$t")"
    done < <(uv tool list 2>/dev/null | grep -v '^[-[:space:]]' | awk '{ print $1 }' | missing_pkgs "$1/uv-tools.txt")
  fi
  if [ -s "$1/pip-user.txt" ] && python_real; then
    local req names
    req=$(mktemp)
    names=$(mktemp)
    # Compare by name: a newer version installed here must not be downgraded.
    sed 's/==.*//' "$1/pip-user.txt" > "$names"
    # Plain names only: a "--index-url" or "git+https://" line would make pip fetch code elsewhere.
    python3 -m pip list --user --format=freeze 2>/dev/null | sed 's/==.*//' | missing_pkgs "$names" > "$req"
    rm -f "$names"
    if [ -s "$req" ]; then
      act python3 -m pip install --user -r "$req" ||
        warn "$(t "pip refused (externally managed Python?). Prefer pipx/uv for CLI tools.")"
    else
      dim "  = $(t "pip --user packages")"
    fi
    rm -f "$req"
  fi
  # After the installs: a pip.conf with another index must not decide where they come from.
  restore_home "$1/home" ".config/pip/pip.conf
.pip/pip.conf"
}

python_outdated() {
  python_real || return 0
  python3 -m pip list --user --outdated 2>/dev/null | awk 'NR > 2 { print $1, $2, $3 }'
}

python_upgrade_hint() { echo "python3 -m pip install --user -U <package>"; }
python_upgrade() { python3 -m pip install --user -U "$1"; }
