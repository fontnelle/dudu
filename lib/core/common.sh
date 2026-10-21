#!/usr/bin/env bash
# Paths, config, collector selection and helpers shared by every command.

DUDU_REPO="fontnelle/dudu"
DUDU_HOMEPAGE="https://github.com/${DUDU_REPO}"
# The Windows edition lives on its own branch and is released as win-vX.Y.Z, so its releases
# never become the repository's "latest" (the macOS/Linux one).
DUDU_BRANCH="windows"
DUDU_TAG_PREFIX="win-v"
DUDU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dudu"
DUDU_CONFIG_FILE="$DUDU_CONFIG_DIR/config"
DUDU_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dudu"
DUDU_LOG="$DUDU_CACHE_DIR/dudu.log"
DUDU_DESTINATIONS="local icloud gdrive notes"

# Order matters: restore follows it (package managers first, then shell, runtimes, editors).
DUDU_COLLECTORS="brew syspkgs winget scoop choco shell git terminal node npm pnpm yarn bun python ruby cargo go vscode cursor macos"

has() { command -v "$1" >/dev/null 2>&1; }

# Reading a tool's state must never install anything. Corepack shims (yarn, pnpm) otherwise
# download on first use and wait on a "[Y/n]" prompt.
read_only_mode() {
  export COREPACK_ENABLE_NETWORK=0 COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
}

list_has() {
  case ",$1," in *",$2,"*) return 0 ;; esac
  return 1
}

# Runs the command, or only prints it in --dry-run.
act() {
  if [ -n "${DUDU_DRY_RUN:-}" ]; then
    printf '  %s→ %s%s\n' "$GRAY" "$*" "$NC"
    return 0
  fi
  "$@"
}

# Same as act, for pipelines and installers that need a shell.
act_sh() {
  if [ -n "${DUDU_DRY_RUN:-}" ]; then
    printf '  %s→ %s%s\n' "$GRAY" "$1" "$NC"
    return 0
  fi
  bash -c "$1"
}

# $HOME/x -> ~/x, for display.
tilde() {
  case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac
}

expand_home() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Why <path> cannot hold backups, printed for people: a link, a relative path ("q", which
# would land wherever dudu runs) or control characters. Prints nothing and returns 1 for a
# usable folder path, so: if problem=$(folder_path_error "$p"); then warn "$problem"; fi
folder_path_error() { # <path, ~ already expanded>
  case "$1" in
    *://*)
      case "$1" in
        *drive.google.com*) t "That is a Google Drive link: it goes in the Google Drive step (%s)" "dudu config gdrive" ;;
        *) t "%s is a link, not a folder on this computer" "$(safe_text "$1")" ;;
      esac
      return 0 ;;
    /*) ;;
    *) t "%s is not a full path: start it with / or ~/" "$(safe_text "$1")"; return 0 ;;
  esac
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    t "%s has control characters" "$(safe_text "$1")"
    return 0
  fi
  return 1
}

# destination= is a comma list (icloud,notes): every backup goes to all of them.
# path= is the local folder, gdrive_path= a Google Drive folder that was not auto-detected.
# language= is auto (follow the system), en, pt-BR or es: i18n_init reads it on its own.
config_load() {
  DUDU_DESTINATION=""
  DUDU_PATH=""
  DUDU_GDRIVE_PATH=""
  DUDU_INCLUDE=""
  DUDU_EXCLUDE=""
  DUDU_KEEP=5
  DUDU_RCLONE_REMOTE=""
  DUDU_ENCRYPT=off
  DUDU_LANGUAGE=auto
  [ -f "$DUDU_CONFIG_FILE" ] || return 1
  local key value
  # shellcheck disable=SC2094 # the file name only goes into a warning
  while IFS='=' read -r key value || [ -n "$key" ]; do
    # Tolerant of hand edits: spaces around "=", Windows line ends, quoted values.
    key=$(printf '%s' "$key" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    value=$(printf '%s' "$value" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$value" in \"*\"|\'*\') value=${value:1:${#value}-2} ;; esac
    case "$key" in
      destination) DUDU_DESTINATION=$value ;;
      path) DUDU_PATH=$(expand_home "$value") ;;
      include) DUDU_INCLUDE=$value ;;
      exclude) DUDU_EXCLUDE=$value ;;
      keep) case "$value" in ''|*[!0-9]*|0) ;; *) DUDU_KEEP=$value ;; esac ;;
      rclone_remote) DUDU_RCLONE_REMOTE=$value ;;
      gdrive_path) DUDU_GDRIVE_PATH=$(expand_home "$value") ;;
      encrypt) [ "$value" = on ] && DUDU_ENCRYPT=on ;;
      language) DUDU_LANGUAGE=${value:-auto} ;;
      ''|'#'*) ;;
      *) printf 'dudu: %s\n' "$(t "unknown setting \"%s\" in %s, ignored" "$key" "$DUDU_CONFIG_FILE")" >&2 ;;
    esac
  done < "$DUDU_CONFIG_FILE"
  # Configs from 0.1.0 kept the Google Drive folder in path=.
  if [ "$DUDU_DESTINATION" = gdrive ] && [ -n "$DUDU_PATH" ] && [ -z "$DUDU_GDRIVE_PATH" ]; then
    DUDU_GDRIVE_PATH=$DUDU_PATH
    DUDU_PATH=""
  fi
  # A hand-edited or pasted value that is not a folder (a link, "q") is never written to:
  # a relative path would put backups wherever dudu happens to run.
  local problem
  if [ -n "$DUDU_PATH" ] && problem=$(folder_path_error "$DUDU_PATH"); then
    printf 'dudu: path= %s · %s\n' "$problem" "$(t "using %s, fix it with: %s" "~/dudu-backups" "dudu config")" >&2
    DUDU_PATH=""
  fi
  if [ -n "$DUDU_GDRIVE_PATH" ] && problem=$(folder_path_error "$DUDU_GDRIVE_PATH"); then
    printf 'dudu: gdrive_path= %s · %s\n' "$problem" "$(t "ignored, fix it with: %s" "dudu config gdrive")" >&2
    DUDU_GDRIVE_PATH=""
  fi
  return 0
}

# Written to a temp file and renamed, so a reader never sees a half-written config.
config_save() {
  mkdir -p "$DUDU_CONFIG_DIR"
  {
    echo "# dudu config, edit freely or run: dudu config"
    echo "destination=$DUDU_DESTINATION"
    echo "path=$DUDU_PATH"
    echo "include=$DUDU_INCLUDE"
    echo "exclude=$DUDU_EXCLUDE"
    echo "keep=$DUDU_KEEP"
    echo "rclone_remote=$DUDU_RCLONE_REMOTE"
    echo "gdrive_path=$DUDU_GDRIVE_PATH"
    echo "encrypt=$DUDU_ENCRYPT"
    echo "language=${DUDU_LANGUAGE:-auto}"
  } > "$DUDU_CONFIG_FILE.tmp" && mv "$DUDU_CONFIG_FILE.tmp" "$DUDU_CONFIG_FILE"
}

# First run: say which language dudu picked, then ask for a destination (or default to a
# local folder when not interactive).
ensure_configured() {
  config_load && [ -n "$DUDU_DESTINATION" ] && return 0
  # A config file without a destination is a typo to fix by hand, never a reason to
  # overwrite the user's settings (a cron run would otherwise switch backups to local).
  if [ -f "$DUDU_CONFIG_FILE" ]; then
    err "$(t "No destination in %s: set one with dudu config" "$DUDU_CONFIG_FILE")"
    return 1
  fi
  if [ -t 0 ] && [ -t 1 ]; then
    # The checklist clears the screen: the language line goes under its title, and again
    # after it, where it stays in the scrollback.
    local CL_NOTE
    CL_NOTE=$(first_run_language)
    printf '%s\n' "$(t "First run: where should dudu keep your backups?")"
    config_pick_destination || return 1
    [ -n "$CL_NOTE" ] && { echo; printf '%s\n' "$CL_NOTE"; }
  else
    DUDU_DESTINATION=local
    DUDU_PATH="$HOME/dudu-backups"
    config_save
  fi
}

# Detected, not asked: say so once, with how to change it.
first_run_language() {
  [ "$DUDU_LANG_SOURCE" = system ] || return 0
  printf '%s\n' "$(t "Language: %s, detected from the system" "$(i18n_name "$DUDU_LANG_ACTIVE")")"
  dim "$(t "To change it: Settings › Language  or  %s" "dudu config set language en|pt-BR|es")"
}

collector_enabled() {
  local name=$1
  if [ -n "${DUDU_ONLY:-}" ]; then
    list_has "$DUDU_ONLY" "$name"
    return
  fi
  if [ -n "$DUDU_INCLUDE" ] && ! list_has "$DUDU_INCLUDE" "$name"; then return 1; fi
  if list_has "$DUDU_EXCLUDE" "$name"; then return 1; fi
  return 0
}

# The configured destinations, space separated.
dest_list() { printf '%s' "$DUDU_DESTINATION" | tr ',' ' '; }

dest_label() {
  case "$1" in
    local) t "Local folder"; echo ;;
    icloud) echo "iCloud Drive" ;;
    gdrive) echo "Google Drive" ;;
    notes) echo "Apple Notes" ;;
    *) echo "$1" ;;
  esac
}

# "iCloud Drive, Apple Notes"
dest_labels() {
  local d out=""
  for d in $(dest_list); do out="$out, $(dest_label "$d")"; done
  printf '%s' "${out#, }"
}

# Machines with a backup in any configured destination.
dest_all_hosts() {
  local d
  for d in $(dest_list); do
    "${d}_available" 2>/dev/null && "${d}_hosts" 2>/dev/null
  done | grep . | sort -u
}

# Loads the newest backup of <host> found across the configured destinations into <out>,
# and writes the destination it came from to <out>/.dudu-source (this often runs under spin,
# a subshell, so a variable would be lost).
dest_load_latest() { # <host> <out>
  local d base best
  base=$(mktemp -d)
  tmp_register "$base"
  for d in $(dest_list); do
    "${d}_available" 2>/dev/null || continue
    mkdir -p "$base/$d"
    "${d}_load" "$1" "$base/$d" 2>/dev/null || continue
  done
  best=$(dest_pick_best "$base")
  if [ -z "$best" ]; then rm -rf "$base"; return 1; fi
  cp -R "$base/$best/." "$2/"
  printf '%s\n' "$best" > "$2/.dudu-source"
  rm -rf "$base"
}

# Of the backups loaded into <base>/<dest>, prints the destination of the one to restore.
dest_pick_best() { # <base>
  local d best="" best_created="" created full=""
  for d in $(dest_list); do
    [ -f "$1/$d/manifest.json" ] || continue
    created=$(sed -n 's/.*"created": *"\([^"]*\)".*/\1/p' "$1/$d/manifest.json")
    # A complete backup beats a newer partial one (made with --only, with tools missing).
    if manifest_is_partial "$1/$d/manifest.json"; then
      [ -n "$full" ] && continue
      if [ -z "$best" ] || [[ "$created" > "$best_created" ]]; then best=$d; best_created=$created; fi
    elif [ -z "$full" ] || [[ "$created" > "$best_created" ]]; then
      best=$d
      best_created=$created
      full=1
    fi
  done
  [ -n "$best" ] && printf '%s' "$best"
}

# Copies a file under $HOME into <backup>/home/<relative path>, masking secrets.
save_file() {
  local src=$1 dest=$2 rel
  [ -f "$src" ] || return 1
  rel=${src#"$HOME"/}
  mkdir -p "$dest/$(dirname "$rel")"
  cp -L "$src" "$dest/$rel" || return 1
  secrets_scrub "$dest/$rel" "~/$rel"
}

# Paths a restore never writes, whatever a backup holds: they would let a tampered backup
# run code (login items, PATH shims), open SSH access or replace keys.
DUDU_RESTORE_DENY=".ssh/authorized_keys* .ssh/id_* .ssh/known_hosts* .ssh/rc .gnupg/* .aws/* .kube/* .docker/* \
Library/LaunchAgents/* Library/LaunchDaemons/* .config/autostart/* .config/systemd/* .local/bin/* bin/* \
AppData/Roaming/Microsoft/Windows/Start?Menu/* .secrets *.dudu-bak*"

# Text from a backup, safe to print: no escape sequences that could rewrite the screen.
safe_text() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013-\037\177'; }

restore_denied() { # <relative path>
  local p
  for p in $DUDU_RESTORE_DENY; do
    # shellcheck disable=SC2254
    case "$1" in $p) return 0 ;; esac
  done
  return 1
}

restore_allowed() { # <relative path> <globs, one per line>
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # shellcheck disable=SC2254
    case "$1" in $p) return 0 ;; esac
  done <<< "$2"
  return 1
}

# A free name for the copy kept before overwriting: never replaces an older copy.
backup_copy_name() { # <file>
  if [ -e "$1.dudu-bak" ] || [ -L "$1.dudu-bak" ]; then printf '%s.dudu-bak.%s' "$1" "$(now_stamp)"; else printf '%s.dudu-bak' "$1"; fi
}

# Copies every file of <backup>/home back into $HOME, keeping a .dudu-bak of what differs.
# Only paths matching <allowed> are written (when given), never DUDU_RESTORE_DENY, never
# through a symlink. Masked secrets take the real value from the current file when it has
# the same line, otherwise the line is restored commented out.
restore_home() { # <backup home dir> [allowed globs, one per line]
  local base=$1 allow=${2:-} src rel dst bak merged rc=0
  [ -d "$base" ] || return 0
  while IFS= read -r src; do
    rel=${src#"$base"/}
    if restore_denied "$rel" || { [ -n "$allow" ] && ! restore_allowed "$rel" "$allow"; }; then
      warn "$(t "ignored unexpected file in the backup: %s" "~/$(safe_text "$rel")")"
      continue
    fi
    dst="$HOME/$rel"
    # macOS-only places (Library/...) from a Mac backup mean nothing on Linux.
    if ! is_macos && [ "${rel#Library/}" != "$rel" ]; then
      dim "  - $(t "%s (macOS only)" "~/$(safe_text "$rel")")"
      continue
    fi
    # And Windows' AppData/... means nothing on a Mac or Linux.
    if ! is_windows && [ "${rel#AppData/}" != "$rel" ]; then
      dim "  - $(t "%s (Windows only)" "~/$(safe_text "$rel")")"
      continue
    fi
    if [ -L "$dst" ] && [ -z "${DUDU_FOLLOW_SYMLINKS:-}" ]; then
      warn "$(t "%s is a symlink (dotfiles manager?), left as is. Backup copy: %s" "~/$rel" "$(safe_text "$src")")"
      continue
    fi
    merged=""
    if grep -q '<redacted-by-dudu>' "$src" 2>/dev/null; then
      merged=$(mktemp)
      secrets_unmask "$src" "$dst" > "$merged"
      src=$merged
    fi
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      dim "  = ~/$rel"
      [ -n "$merged" ] && rm -f "$merged"
      continue
    fi
    [ -n "$merged" ] && grep -q '^# dudu: fill in' "$merged" &&
      warn "$(t "%s had secrets masked in the backup: fill in the lines marked \"%s\"" "~/$rel" "# dudu: fill in")"
    if [ -n "${DUDU_DRY_RUN:-}" ]; then
      printf '  %s→ %s%s\n' "$GRAY" "$(t "write %s" "~/$(safe_text "$rel")")" "$NC"
    else
      mkdir -p "$(dirname "$dst")"
      if [ -f "$dst" ]; then
        bak=$(backup_copy_name "$dst")
        cp -p "$dst" "$bak" || { warn "$(t "could not keep a copy of %s, left as is" "~/$rel")"; rc=1; [ -n "$merged" ] && rm -f "$merged"; continue; }
      fi
      if cp "$src" "$dst"; then ok "~/$rel"; else warn "$(t "could not write %s" "~/$rel")"; rc=1; fi
    fi
    [ -n "$merged" ] && rm -f "$merged"
  done < <(find "$base" -type f | sort)
  return $rc
}

# Lines of <backup> whose secret was masked, replaced by the real line of <current> that
# masks to the same text. Lines with no match are commented out to be filled in by hand.
secrets_unmask() { # <backup file> <current file>
  local masked
  masked=$(mktemp)
  if [ -f "$2" ]; then
    cp "$2" "$masked"
    DUDU_REDACT_LOG="" DUDU_SKIP_LOG="" secrets_scrub "$masked" || : > "$masked"
  fi
  # Line counts differ only when a PEM block was collapsed: then nothing is matched.
  LC_ALL=C awk -v cur="${2:-/dev/null}" -v msk="$masked" '
    BEGIN {
      n = 0; while ((getline l < cur) > 0) real[++n] = l
      m = 0; while ((getline l < msk) > 0) mk[++m] = l
      if (n == m) for (i = 1; i <= n; i++) if (index(mk[i], "<redacted-by-dudu>")) map[mk[i]] = real[i]
    }
    index($0, "<redacted-by-dudu>") { if ($0 in map) print map[$0]; else print "# dudu: fill in: " $0; next }
    { print }' "$1"
  rm -f "$masked"
}

# Names from a backup list that are safe to hand to an installer: no options (-x), no URLs
# or other sources that make installers fetch code from elsewhere. Others are reported.
pkg_filter() { # stdin -> stdout
  local bad n
  bad=$(mktemp)
  LC_ALL=C awk -v bad="$bad" '
    /^[A-Za-z0-9@][A-Za-z0-9@._+\/:-]*$/ && !/:\/\// && !/\.\./ { print; next }
    NF { print > bad }'
  while IFS= read -r n; do
    warn "$(t "ignored suspicious entry in the backup: %s" "$(safe_text "$n")")" >&2
  done < "$bad"
  rm -f "$bad"
}

# missing_from for lists that reach an installer: the backup list is filtered first.
missing_pkgs() { # <backup list>  (current list on stdin)
  local f
  f=$(mktemp)
  pkg_filter < "$1" > "$f"
  missing_from "$f"
  rm -f "$f"
}

# Lines of $1 not present in the current list given on stdin (both unsorted).
missing_from() {
  local wanted=$1 have
  have=$(mktemp)
  sort -u > "$have"
  sort -u "$wanted" | comm -23 - "$have"
  rm -f "$have"
}

# Dependency names from a package.json (yarn/bun global), without jq.
json_deps() {
  [ -f "$1" ] || return 0
  sed -n '/"dependencies"[[:space:]]*:/,/}/p' "$1" | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:.*/\1/p' | sed '/^dependencies$/d'
}

summary() {
  printf '%s' "$2" > "$1/.summary"
}

count_lines() {
  [ -f "$1" ] || { echo 0; return; }
  grep -c . "$1" | tr -d ' '
}

now_stamp() { date +%Y-%m-%d_%H%M%S; }
