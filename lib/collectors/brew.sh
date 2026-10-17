#!/usr/bin/env bash
# Homebrew: formulae, casks, taps and Mac App Store apps through a Brewfile.

brew_detect() { has brew; }

brew_backup() {
  brew bundle dump --file="$1/Brewfile" --force || return 1
  summary "$1" "$(grep -c '^brew ' "$1/Brewfile") formulae, $(grep -c '^cask ' "$1/Brewfile") casks, $(grep -c '^mas ' "$1/Brewfile") App Store"
}

brew_load_shellenv() {
  local p
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$p" ]; then
      eval "$("$p" shellenv)"
      return 0
    fi
  done
  return 1
}

# Brewfile lines that only declare packages: tap/brew/cask/mas/vscode/whalebrew with string
# names and simple options. Ruby code (system, backticks, #{}, blocks) is dropped and reported.
# Taps from a custom URL are kept but shown, since they decide where formulae come from.
brew_safe_brewfile() { # <Brewfile>
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) printf '%s\n' "$line"; continue ;; esac
    # Newer brew bundle dumps these too; the npm, python, go and cargo collectors restore them.
    case "$line" in npm\ \"*|uv\ \"*|go\ \"*|cargo\ \"*) continue ;; esac
    if printf '%s\n' "$line" | LC_ALL=C grep -Eq '^[[:space:]]*(tap|brew|cask|mas|vscode|whalebrew)[[:space:]]+"[^"`$#\\]+"([[:space:]]*,[[:space:]]*([a-z_]+:[[:space:]]*)?("[^"`$#\\]*"|\[[^]`$#\\]*\]|:[a-z_]+|[0-9]+|true|false))*[[:space:]]*$'; then
      printf '%s\n' "$line"
      case "$line" in *tap*'"'*','*'"'*) warn "Brewfile taps a custom source: $(safe_text "$line")" >&2 ;; esac
    else
      warn "ignored unexpected Brewfile line: $(safe_text "$line")" >&2
    fi
  done < "$1"
}

brew_restore() {
  if ! has brew && ! brew_load_shellenv; then
    step "Installing Homebrew"
    act_sh 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' || return 1
    [ -n "${DUDU_DRY_RUN:-}" ] || brew_load_shellenv || return 1
  fi
  # A Brewfile is Ruby: keep only plain tap/brew/cask/mas/vscode lines, never code.
  local brewfile
  brewfile=$(mktemp)
  brew_safe_brewfile "$1/Brewfile" > "$brewfile"
  if [ -n "${DUDU_DRY_RUN:-}" ]; then
    if ! has brew; then
      dim "  $(cat "$1/.summary" 2>/dev/null)"
    elif brew bundle check --no-upgrade --file="$brewfile" >/dev/null 2>&1; then
      dim "  = everything in the Brewfile is installed"
    else
      brew bundle check --no-upgrade --file="$brewfile" --verbose 2>&1 | grep '^→' | sed 's/^/  /'
    fi
    rm -f "$brewfile"
    return 0
  fi
  # Restore installs what is missing; upgrading stays a separate decision (dudu outdated).
  local rc=0
  brew bundle install --no-upgrade --file="$brewfile" || rc=$?
  rm -f "$brewfile"
  return $rc
}

# Each <collector>_outdated prints "name current latest", one per line.
brew_outdated() {
  # "git (2.50.0) < 2.51.0" or "font-x (1.0, 1.1) != 1.2": keep the last installed version.
  brew outdated --verbose 2>/dev/null |
    sed -E 's/^([^ ]+) \((.*)\) [<!=]+ (.*)$/\1|\2|\3/' |
    awk -F'|' 'NF == 3 { n = split($2, v, ", "); print $1, v[n], $3 }'
}

brew_upgrade_hint() { echo "brew upgrade"; }
brew_upgrade() { brew upgrade "$1"; }
