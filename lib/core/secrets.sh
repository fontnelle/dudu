#!/usr/bin/env bash
# Secrets never leave the machine: config files are masked, key files are skipped and reported.

# Masks secrets in place. $1 = file, $2 = label shown in the report.
# Files without secrets are not rewritten (keeps them byte-identical).
# Fails closed: a text file the scrubber could not read is deleted, never kept as is.
secrets_scrub() {
  local file=$1 label=${2:-$1} tmp rc
  [ -s "$file" ] || return 0
  # Binary means a NUL byte. grep -I also calls Latin-1 text "binary", which skipped masking.
  [ "$(LC_ALL=C tr -dc '\000' < "$file" | wc -c | tr -d ' ')" -eq 0 ] || return 0
  tmp=$(mktemp)
  rc=0
  LC_ALL=C awk -v label="$label" -v logf="${DUDU_REDACT_LOG:-}" -f "$DUDU_ROOT/lib/core/scrub.awk" "$file" > "$tmp" || rc=$?
  case $rc in
    0) cat "$tmp" > "$file" ;;
    3) ;;
    *)
      rm -f "$file"
      [ -n "${DUDU_SKIP_LOG:-}" ] && echo "$label (could not be checked for secrets, left out)" >> "$DUDU_SKIP_LOG"
      rm -f "$tmp"
      return 1
      ;;
  esac
  rm -f "$tmp"
}

# True when <real> only differs from <backup> by the masked secrets.
secrets_same_masked() { # <backup> <real>
  grep -q '<redacted-by-dudu>' "$1" 2>/dev/null || return 1
  local tmp rc
  tmp=$(mktemp)
  cp "$2" "$tmp"
  DUDU_REDACT_LOG="" secrets_scrub "$tmp"
  cmp -s "$1" "$tmp"
  rc=$?
  rm -f "$tmp"
  return $rc
}

# Known secret files that dudu deliberately leaves out. Listed so the user moves them by hand.
DUDU_SECRET_PATHS=".ssh/id_rsa .ssh/id_ed25519 .ssh/id_ecdsa .gnupg .aws/credentials .netrc \
.docker/config.json .kube/config .config/gh/hosts.yml .pypirc .gem/credentials .cargo/credentials.toml \
.config/rclone/rclone.conf .secrets .git-credentials .vault-token .config/gcloud .azure \
.terraform.d/credentials.tfrc.json"

# Where dudu secrets moves keys found in shell files. Never backed up (listed above).
DUDU_SECRETS_FILE="$HOME/.secrets"

# Shell files whose "export NAME=value" lines can move to DUDU_SECRETS_FILE.
DUDU_SECRET_SHELL_FILES=".zshrc .zprofile .zshenv .bashrc .bash_profile .profile .aliases .zsh_aliases .bash_aliases"

secrets_report_skipped() {
  local p
  for p in $DUDU_SECRET_PATHS; do
    [ -e "$HOME/$p" ] && echo "~/$p" >> "$DUDU_SKIP_LOG"
  done
  return 0
}

# One row per key found by the scrubber: "⚠ OPENROUTER_API_KEY   ~/.zshrc line 261". Never the value.
secrets_list_found() { # <redact log> [max rows] [indent]
  local max=${2:-0} pad=${3:-4} n=0 total label line name
  total=$(sort -u "$1" | grep -c .)
  while IFS=: read -r label line name; do
    n=$((n + 1))
    if [ "$max" -gt 0 ] && [ $n -gt "$max" ]; then
      printf '%*s  %s… and %d more, see dudu secrets%s\n' "$pad" "" "$GRAY" $((total - max)) "$NC"
      break
    fi
    printf '%*s%s⚠%s %-28s %s%s line %s%s\n' "$pad" "" "$YELLOW" "$NC" "${name:-secret value}" "$GRAY" "$label" "$line" "$NC"
  done < <(sort -u -t: -k1,1 -k2,2n "$1")
}

# Moving keys out of dotfiles (dudu secrets). Every check runs again at move time, by the
# key's NAME rather than the line number of the earlier scan, so edits made in between
# never move the wrong line.

# "export NAME=..." lines that are safe to move: top level (not indented, so not inside an
# if or a function), one physical line (no trailing \), balanced quotes.
secrets_shell_line() { # <file> <NAME> -> line number of the only such line, or nothing
  [ -f "$1" ] || return 1
  printf '%s' "$2" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || return 1
  LC_ALL=C awk -v n="$2" '
    $0 ~ "^(export[ \t]+)?" n "=" {
      line = $0
      sq = gsub(/'"'"'/, "&", line); dq = gsub(/"/, "&", line)
      if ($0 !~ /\\$/ && sq % 2 == 0 && dq % 2 == 0) { found = found ? -1 : NR }
      else found = -1
    }
    END { if (found > 0) print found }' "$1"
}

# The .npmrc line holding the token of <host>, when it is a literal value.
# The line of the scan is used while it still holds that host's literal token; otherwise the
# only such line in the file.
secrets_npm_line() { # <host> [line from the scan]
  [ -f "$HOME/.npmrc" ] || return 1
  LC_ALL=C awk -v h="//$1/" -v hint="${2:-0}" '
    function ok() { return index($0, h) == 1 && index($0, ":_authToken=") && $0 !~ /:_authToken=["'"'"']?\$/ }
    NR == hint && ok() { exact = NR }
    ok() { found = found ? -1 : NR }
    END { if (exact) print exact; else if (found > 0) print found }' "$HOME/.npmrc"
}

# Entries of the redact log that can move to DUDU_SECRETS_FILE, as "label:line:name".
secrets_movable() { # <redact log>
  local label line name file n
  while IFS=: read -r label line name; do
    if [ "$label" = "~/.npmrc" ]; then
      case "$name" in "npm token "*) n=$(secrets_npm_line "${name#npm token }" "$line") ;; *) n="" ;; esac
    else
      list_has "$(echo "$DUDU_SECRET_SHELL_FILES" | tr ' ' ',')" "${label#\~/}" || continue
      file=$(expand_home "$label")
      n=$(secrets_shell_line "$file" "$name")
    fi
    [ -n "$n" ] && printf '%s:%s:%s\n' "$label" "$n" "$name"
  done < <(sort -u -t: -k1,1 -k2,2n "$1")
  return 0
}

# Adds "export NAME=value" to DUDU_SECRETS_FILE, replacing an older line for the same NAME.
secrets_put() { # <NAME> <line>
  local f=$DUDU_SECRETS_FILE tmp
  if [ ! -f "$f" ]; then
    ( umask 077; echo "# Keys for your shell, sourced by your shell config. dudu never backs this file up." > "$f" )
  fi
  chmod 600 "$f"
  tmp=$(mktemp)
  LC_ALL=C awk -v n="$1" '$0 !~ "^(export[ \t]+)?" n "=" { print }' "$f" > "$tmp"
  printf '%s\n' "$2" >> "$tmp"
  cat "$tmp" > "$f"
  rm -f "$tmp"
}

secrets_sources_file() { # <shell file>
  grep -Eq '^[^#]*(source|\.)[[:space:]]+(~|\$HOME)/\.secrets' "$1" 2>/dev/null
}

# Rewrites <file> from <new>, keeping a dated copy, through symlinks, rolling back on error.
secrets_commit() { # <file> <new> <label>
  local bak
  bak=$(backup_copy_name "$1")
  # Messages go to stderr: stdout carries the name of the copy.
  if ! cp -p "$1" "$bak" || ! chmod 600 "$bak"; then
    warn "$3: could not keep a copy, left as is" >&2
    return 1
  fi
  [ -L "$1" ] && warn "$3 is a symlink (dotfiles repo?): its history may still hold the key" >&2
  if ! cat "$2" > "$1"; then
    cat "$bak" > "$1"
    warn "$3: could not be written, restored as it was" >&2
    return 1
  fi
  printf '%s' "$bak"
}

secrets_count() { # <entries file> <label>
  awk -F: -v l="$2" '$1 == l' "$1" | grep -c . | tr -d ' '
}

# Moves the given "label:line:name" entries into DUDU_SECRETS_FILE. Shell files source it
# where the first key was, so the load order stays the same.
secrets_move() { # <entries file>
  local label n
  if [ -n "${DUDU_DRY_RUN:-}" ]; then
    while IFS= read -r label; do
      n=$(secrets_count "$1" "$label")
      printf '  %s→ move %s key%s from %s to %s%s\n' "$GRAY" "$n" "$([ "$n" -gt 1 ] && echo s)" \
        "$label" "$(tilde "$DUDU_SECRETS_FILE")" "$NC"
    done < <(cut -d: -f1 "$1" | sort -u)
    return 0
  fi
  while IFS= read -r label; do
    if [ "$label" = "~/.npmrc" ]; then
      secrets_move_npmrc "$1"
    else
      secrets_move_shell "$1" "$label"
    fi
  done < <(cut -d: -f1 "$1" | sort -u)
}

secrets_move_shell() { # <entries file> <label>
  local file name line lines="," src new bak n=0 moved
  file=$(expand_home "$2")
  moved=$(mktemp)
  while IFS=: read -r _ _ name; do
    line=$(secrets_shell_line "$file" "$name")
    if [ -z "$line" ]; then warn "$2: $name changed since the scan, left in place"; continue; fi
    lines="$lines$line,"
  done < <(awk -F: -v l="$2" '$1 == l' "$1")
  [ "$lines" = "," ] && { rm -f "$moved"; return 0; }
  src='[ -f ~/.secrets ] && source ~/.secrets  # keys kept out of backups (dudu secrets)'
  secrets_sources_file "$file" && src=""
  new=$(mktemp)
  LC_ALL=C awk -v lines="$lines" -v moved="$moved" -v src="$src" '
    index(lines, "," NR ",") { print > moved; if (src != "") { print src; src = "" }; next }
    { print }' "$file" > "$new"
  if bak=$(secrets_commit "$file" "$new" "$2"); then
    while IFS= read -r line; do
      name=$(printf '%s' "$line" | sed -E 's/^(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/')
      case "$line" in export*) ;; *) line="export $line" ;; esac
      secrets_put "$name" "$line"
      n=$((n + 1))
    done < "$moved"
    step_row ok "$2" "$n key$([ $n -gt 1 ] && echo s) moved to $(tilde "$DUDU_SECRETS_FILE"), old version in $(tilde "$bak")"
  fi
  rm -f "$new" "$moved"
}

# Env var for an npm registry token: NPM_TOKEN for npmjs.org, NPM_TOKEN_LOCALHOST_4873 otherwise.
npm_token_var() { # <npmrc line>
  local host
  host=$(printf '%s' "$1" | sed -n 's|^//\([^/]*\).*|\1|p')
  case "$host" in
    registry.npmjs.org|"") echo NPM_TOKEN ;;
    *) printf 'NPM_TOKEN_%s\n' "$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9\n' '_')" ;;
  esac
}

# A variable name for <value> not already holding another value in DUDU_SECRETS_FILE.
npm_free_var() { # <base name> <quoted value> <names taken in this run>
  local v=$1 i=1
  while :; do
    if ! list_has "$3" "$v" &&
       { ! grep -q "^export $v=" "$DUDU_SECRETS_FILE" 2>/dev/null || grep -qxF "export $v=$2" "$DUDU_SECRETS_FILE"; }; then
      printf '%s' "$v"
      return
    fi
    i=$((i + 1))
    v="${1}_$i"
  done
}

# Tokens of ~/.npmrc become "${NAME}" there and "export NAME='value'" in DUDU_SECRETS_FILE.
secrets_move_npmrc() { # <entries file>
  local file="$HOME/.npmrc" name line lines="," l nr=0 var val q taken="" new bak n=0 rc exports
  while IFS=: read -r _ line name; do
    line=$(secrets_npm_line "${name#npm token }" "$line")
    if [ -z "$line" ]; then warn "~/.npmrc: $name changed since the scan, left in place"; continue; fi
    lines="$lines$line,"
  done < <(awk -F: '$1 == "~/.npmrc"' "$1")
  [ "$lines" = "," ] && return 0
  new=$(mktemp)
  exports=$(mktemp)
  while IFS= read -r l || [ -n "$l" ]; do
    nr=$((nr + 1))
    l=${l%$'\r'}
    case "$lines" in
      *",$nr,"*)
        val=${l#*:_authToken=}
        val=${val#\"}; val=${val%\"}; val=${val#\'}; val=${val%\'}
        q="'$(printf '%s' "$val" | sed "s/'/'\\\\''/g")'"
        var=$(npm_free_var "$(npm_token_var "$l")" "$q" "$taken")
        taken="$taken,$var"
        printf '%s %s\n' "$var" "export $var=$q" >> "$exports"
        printf '%s:_authToken=${%s}\n' "${l%%:_authToken=*}" "$var" >> "$new"
        n=$((n + 1))
        ;;
      *) printf '%s\n' "$l" >> "$new" ;;
    esac
  done < "$file"
  if bak=$(secrets_commit "$file" "$new" "~/.npmrc"); then
    while read -r var line; do secrets_put "$var" "$line"; done < "$exports"
    step_row ok "~/.npmrc" "$n token$([ $n -gt 1 ] && echo s) moved to $(tilde "$DUDU_SECRETS_FILE"), old version in $(tilde "$bak")"
  fi
  rm -f "$new" "$exports"
  # npm only sees the token if the shell loads the secrets file.
  for rc in .zshrc .bashrc; do
    secrets_sources_file "$HOME/$rc" && return 0
  done
  case "${SHELL##*/}" in bash) rc=.bashrc ;; *) rc=.zshrc ;; esac
  [ -n "$(tail -c1 "$HOME/$rc" 2>/dev/null)" ] && echo >> "$HOME/$rc"
  printf '\n[ -f ~/.secrets ] && source ~/.secrets  # keys kept out of backups (dudu secrets)\n' >> "$HOME/$rc"
  step_row ok "~/$rc" "now loads $(tilde "$DUDU_SECRETS_FILE")"
}
