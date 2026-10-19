#!/usr/bin/env bash
# dudu status: compares what is installed now against the latest backup of this machine.

# Files compared as sets of lines (package lists); anything else is just "changed".
is_list_file() {
  case "$1" in *.txt|Brewfile|*/Brewfile) return 0 ;; esac
  return 1
}

# One-line files holding a setting ("nvm", "20"): shown with their value.
is_value_file() {
  case "$1" in manager|default|login_shell|pyenv-global|rbenv-global) return 0 ;; esac
  return 1
}

value_name() {
  case "$1" in
    manager) t "version manager" ;;
    login_shell) t "login shell" ;;
    *) t "default version" ;;
  esac
}

# A list entry as people know it: 'brew "git"' -> git, 'cask "iterm2"' -> iterm2 (cask),
# "v20.19.6 vercel" (npm globals per Node version) -> vercel (node v20.19.6).
# Blank lines and comments are left out, and so are the Brewfile lines brew_restore does
# not install (npm, go, cargo...: their own collectors cover them).
pretty_list() { # <relative path>  (lines on stdin)
  case "$1" in
    Brewfile|*/Brewfile)
      awk '/^(tap|brew|cask|mas|vscode|whalebrew) "/ { k = $1; split($0, q, "\""); n = q[2]
             if (k == "brew") print n; else if (k == "mas") print n " (App Store)"; else print n " (" k ")" }' ;;
    *globals.txt)
      awk 'NF == 2 && $1 ~ /^v[0-9]/ { print $2 " (node " $1 ")"; next }
           NF == 2 && $1 == "default" { print $2; next } NF { print }' ;;
    *) awk 'NF' ;;
  esac
}

# Two files hold the same settings. Terminal plists are compared on the keys people set,
# not on window positions the app rewrites at every launch.
same_content() { # <old> <new>
  cmp -s "$1" "$2" && return 0
  case "$1" in
    *.plist) is_macos && [ "$(terminal_plist_digest "$1")" = "$(terminal_plist_digest "$2")" ] ;;
    *) return 1 ;;
  esac
}

# Readable name for a backed up file: "~/.zshrc", "Terminal profiles", "Brewfile".
pretty_file() {
  case "$1" in
    home/*) printf '~/%s' "${1#home/}" ;;
    defaults/com.apple.Terminal.plist) t "Terminal.app profiles" ;;
    defaults/com.googlecode.iterm2.plist) t "iTerm2 profiles" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Prints one line per difference of a collector: a sign (+ added, - removed, ~ changed),
# what kind of thing it is, then its name:
#   +L git              a package (an entry of a list)
#   +D com.apple.dock   a macOS preference
#   ~F ~/.zshrc         a file
#   ~V version manager: system → nvm   a setting, with its value
status_changes() { # <old dir> <new dir>
  local old=$1 new=$2 rel f k
  while IFS= read -r rel; do
    [ "$rel" = .summary ] && continue
    if is_value_file "$rel"; then
      status_value_change "$rel" "$old/$rel" "$new/$rel"
      continue
    fi
    k=L
    case "$rel" in *defaults.txt) k=D ;; esac
    if [ ! -f "$old/$rel" ]; then
      is_list_file "$rel" && pretty_list "$rel" < "$new/$rel" | sed "s/^/+$k /" || printf '+F %s\n' "$(pretty_file "$rel")"
      continue
    fi
    if [ ! -f "$new/$rel" ]; then
      is_list_file "$rel" && pretty_list "$rel" < "$old/$rel" | sed "s/^/-$k /" || printf -- '-F %s\n' "$(pretty_file "$rel")"
      continue
    fi
    same_content "$old/$rel" "$new/$rel" && continue
    if is_list_file "$rel"; then
      f=$(mktemp)
      sort -u "$old/$rel" > "$f"
      sort -u "$new/$rel" | comm -13 "$f" - | pretty_list "$rel" | sed "s/^/+$k /"
      sort -u "$new/$rel" | comm -23 "$f" - | pretty_list "$rel" | sed "s/^/-$k /"
      rm -f "$f"
    else
      printf '~F %s\n' "$(pretty_file "$rel")"
    fi
  done < <( { (cd "$old" 2>/dev/null && find . -type f); (cd "$new" 2>/dev/null && find . -type f); } |
            sed 's|^\./||' | sort -u)
}

# "~V version manager: system → nvm", "+V default version: 20".
status_value_change() { # <relative path> <old file> <new file>
  local before now
  before=$(head -1 "$2" 2>/dev/null | tr -d '\r')
  now=$(head -1 "$3" 2>/dev/null | tr -d '\r')
  [ "$before" = "$now" ] && return 0
  if [ -z "$before" ]; then printf '+V %s: %s\n' "$(value_name "$1")" "$now"
  elif [ -z "$now" ]; then printf -- '-V %s: %s\n' "$(value_name "$1")" "$before"
  else printf '~V %s: %s → %s\n' "$(value_name "$1")" "$before" "$now"
  fi
}

# Colors a change line (from status_changes) by its sign.
print_change() { # <line> [indent]
  local pad=${2:-13} text
  set -- "$(safe_text "$1")"
  text=${1#?? }
  case "$1" in
    +*) printf '%*s%s+%s %s\n' "$pad" '' "$GREEN" "$NC" "$text" ;;
    -*) printf '%*s%s-%s %s\n' "$pad" '' "$RED" "$NC" "$text" ;;
    "~F "*) printf '%*s%s~%s %s\n' "$pad" '' "$YELLOW" "$NC" "$(t "%s changed" "$text")" ;;
    *) printf '%*s%s~%s %s\n' "$pad" '' "$YELLOW" "$NC" "$text" ;;
  esac
}

cmd_status() {
  parse_common_opts "$@"
  ensure_configured || return 1
  read_only_mode
  local work host c created changes n total=0 shown
  work=$(mktemp -d)
  tmp_register "$work"
  mkdir -p "$work/old" "$work/new/now"
  host=$(backup_host)
  DUDU_REDACT_LOG="$work/redacted"
  : > "$DUDU_REDACT_LOG"
  DUDU_SKIP_LOG="$work/skipped"

  title "$(t "Status of %s" "$host")"
  dim "$(t "Backups in %s" "$(dest_labels)")"
  echo

  if ! spin "$(t "Reading the latest backup")" dest_load_latest "$host" "$work/old" || [ ! -f "$work/old/manifest.json" ]; then
    warn "$(t "No backup of this machine yet.")"
    rm -rf "$work"
    # Other machines have backups: this is probably a new machine to set up, and a backup
    # now would only save an empty setup.
    if [ -n "$(dest_all_hosts)" ]; then
      dim "$(t "Backups of other machines exist. On a new machine, start with: dudu restore")"
      return 0
    fi
    offer_backup "$(t "Back up now?")"
    return 0
  fi
  crypto_open "$work/old" || { rm -rf "$work"; return 1; }
  created=$(sed -n 's/.*"created": *"\([^"]*\)".*/\1/p' "$work/old/manifest.json")
  ok "$(t "Last backup: %s" "$(friendly_date "$created")") ${GRAY}· $(dest_label "$(cat "$work/old/.dudu-source" 2>/dev/null)")$NC"
  local sched
  sched=$(schedule_time 2>/dev/null) && [ -n "$sched" ] && dim "  $(t "Next scheduled backup at %s" "$sched")"
  rm -f "$work/old/.dudu-source"

  collect_all "$work/new/now" quiet
  ok "$(tn "Checked this machine: %d tool" "Checked this machine: %d tools" "$(echo "$COLLECTED" | wc -w | tr -d ' ')")"
  if [ -s "$DUDU_REDACT_LOG" ]; then
    n=$(sort -u "$DUDU_REDACT_LOG" | grep -c .)
    warn "$(tn "%d key in %s" "%d keys in %s" "$n" "$(cut -d: -f1 "$DUDU_REDACT_LOG" | sort -u | paste -sd, - | sed 's/,/, /g')") $GRAY$(t "(masked in backups, see dudu secrets)")$NC"
  fi
  echo

  for c in $DUDU_COLLECTORS; do
    collector_enabled "$c" || continue
    if [ ! -d "$work/old/$c" ] && [ ! -d "$work/new/now/$c" ]; then continue; fi
    if [ ! -d "$work/old/$c" ]; then
      row "${GREEN}+${NC}" "$c" "$(t "found on this machine, not in the backup yet")"
      total=$((total + 1))
      continue
    fi
    if [ ! -d "$work/new/now/$c" ] && case " $FAILED " in *" $c "*) true ;; *) false ;; esac; then
      row "${YELLOW}?${NC}" "$c" "$(t "could not be read now (failed or timed out, see %s)" "$(tilde "$DUDU_LOG")")"
      continue
    fi
    if [ ! -d "$work/new/now/$c" ]; then
      row "${RED}-${NC}" "$c" "$(t "in the backup, not found on this machine anymore")"
      total=$((total + 1))
      continue
    fi
    changes=$(status_changes "$work/old/$c" "$work/new/now/$c")
    if [ -z "$changes" ]; then
      row "${GREEN}✓${NC}" "$c" "$(t "up to date")"
      continue
    fi
    n=$(printf '%s\n' "$changes" | grep -c .)
    total=$((total + n))
    row "${YELLOW}~${NC}" "$c" "$(tn "%d change" "%d changes" "$n")"
    shown=0
    while IFS= read -r line; do
      shown=$((shown + 1))
      if [ $shown -gt 8 ]; then
        printf '             %s%s%s\n' "$GRAY" "$(t "… and %d more" $((n - 8)))" "$NC"
        break
      fi
      print_change "$line"
    done <<< "$changes"
  done
  rm -rf "$work"

  echo
  if [ $total -eq 0 ]; then
    printf '%s%s✓ %s%s\n' "$GREEN" "$BOLD" "$(t "Everything is backed up")" "$NC"
  else
    printf '%s%s⚠ %s%s\n' "$YELLOW" "$BOLD" "$(tn "%d change since the last backup" "%d changes since the last backup" "$total")" "$NC"
    # 3 = the backup is behind this machine (useful in scripts).
    offer_backup "$(t "Back up now?")" || return 3
  fi
}

# Asks to run a backup right away (only when someone is at the keyboard). True when a
# backup was made.
offer_backup() {
  if [ -t 0 ] && [ -t 1 ]; then
    echo
    confirm "$1" && { echo; cmd_backup; return; }
  else
    dim "$(t "Run dudu backup to save them.")"
  fi
  return 1
}
