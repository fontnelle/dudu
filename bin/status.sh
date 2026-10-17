#!/usr/bin/env bash
# dudu status: compares what is installed now against the latest backup of this machine.

# Files compared as sets of lines (package lists); anything else is just "changed".
is_list_file() {
  case "$1" in *.txt|*/Brewfile) return 0 ;; esac
  return 1
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
    defaults/com.apple.Terminal.plist) printf 'Terminal.app profiles' ;;
    defaults/com.googlecode.iterm2.plist) printf 'iTerm2 profiles' ;;
    *) printf '%s' "$1" ;;
  esac
}

# Prints one line per difference of a collector ("+ name", "- name", "~ file").
status_changes() { # <old dir> <new dir>
  local old=$1 new=$2 rel f
  while IFS= read -r rel; do
    [ "$rel" = .summary ] && continue
    if [ ! -f "$old/$rel" ]; then
      is_list_file "$rel" && sed 's/^/+ /' "$new/$rel" || printf '+ %s\n' "$(pretty_file "$rel")"
      continue
    fi
    if [ ! -f "$new/$rel" ]; then
      is_list_file "$rel" && sed 's/^/- /' "$old/$rel" || printf -- '- %s\n' "$(pretty_file "$rel")"
      continue
    fi
    same_content "$old/$rel" "$new/$rel" && continue
    if is_list_file "$rel"; then
      f=$(mktemp)
      sort -u "$old/$rel" > "$f"
      sort -u "$new/$rel" | comm -13 "$f" - | sed 's/^/+ /'
      sort -u "$new/$rel" | comm -23 "$f" - | sed 's/^/- /'
      rm -f "$f"
    else
      printf '~ %s changed\n' "$(pretty_file "$rel")"
    fi
  done < <( { (cd "$old" 2>/dev/null && find . -type f); (cd "$new" 2>/dev/null && find . -type f); } |
            sed 's|^\./||' | sort -u)
}

# Colors a change line by its first character.
print_change() {
  set -- "$(safe_text "$1")"
  case "$1" in
    "+ "*) printf '             %s+%s %s\n' "$GREEN" "$NC" "${1#+ }" ;;
    "- "*) printf '             %s-%s %s\n' "$RED" "$NC" "${1#- }" ;;
    *) printf '             %s~%s %s\n' "$YELLOW" "$NC" "${1#\~ }" ;;
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

  title "Status of $host"
  dim "Backups in $(dest_labels)"
  echo

  if ! spin "Reading the latest backup" dest_load_latest "$host" "$work/old" || [ ! -f "$work/old/manifest.json" ]; then
    warn "No backup of this machine yet."
    rm -rf "$work"
    # Other machines have backups: this is probably a new machine to set up, and a backup
    # now would only save an empty setup.
    if [ -n "$(dest_all_hosts)" ]; then
      dim "Backups of other machines exist. On a new machine, start with: dudu restore"
      return 0
    fi
    offer_backup "Back up now?"
    return 0
  fi
  crypto_open "$work/old" || { rm -rf "$work"; return 1; }
  created=$(sed -n 's/.*"created": *"\([^"]*\)".*/\1/p' "$work/old/manifest.json")
  ok "Last backup: $(friendly_date "$created") ${GRAY}· $(dest_label "$(cat "$work/old/.dudu-source" 2>/dev/null)")$NC"
  local sched
  sched=$(schedule_time 2>/dev/null) && [ -n "$sched" ] && dim "  Next scheduled backup at $sched"
  rm -f "$work/old/.dudu-source"

  collect_all "$work/new/now" quiet
  ok "Checked this machine: $(echo "$COLLECTED" | wc -w | tr -d ' ') tools"
  if [ -s "$DUDU_REDACT_LOG" ]; then
    n=$(sort -u "$DUDU_REDACT_LOG" | grep -c .)
    warn "$n key$([ "$n" -gt 1 ] && echo s) in $(cut -d: -f1 "$DUDU_REDACT_LOG" | sort -u | paste -sd, - | sed 's/,/, /g') $GRAY(masked in backups, see dudu secrets)$NC"
  fi
  echo

  for c in $DUDU_COLLECTORS; do
    collector_enabled "$c" || continue
    if [ ! -d "$work/old/$c" ] && [ ! -d "$work/new/now/$c" ]; then continue; fi
    if [ ! -d "$work/old/$c" ]; then
      row "${GREEN}+${NC}" "$c" "found on this machine, not in the backup yet"
      total=$((total + 1))
      continue
    fi
    if [ ! -d "$work/new/now/$c" ] && case " $FAILED " in *" $c "*) true ;; *) false ;; esac; then
      row "${YELLOW}?${NC}" "$c" "could not be read now (failed or timed out, see $(tilde "$DUDU_LOG"))"
      continue
    fi
    if [ ! -d "$work/new/now/$c" ]; then
      row "${RED}-${NC}" "$c" "in the backup, not found on this machine anymore"
      total=$((total + 1))
      continue
    fi
    changes=$(status_changes "$work/old/$c" "$work/new/now/$c")
    if [ -z "$changes" ]; then
      row "${GREEN}✓${NC}" "$c" "up to date"
      continue
    fi
    n=$(printf '%s\n' "$changes" | grep -c .)
    total=$((total + n))
    row "${YELLOW}~${NC}" "$c" "$n change$([ "$n" -gt 1 ] && echo s)"
    shown=0
    while IFS= read -r line; do
      shown=$((shown + 1))
      if [ $shown -gt 8 ]; then
        printf '             %s… and %d more%s\n' "$GRAY" $((n - 8)) "$NC"
        break
      fi
      print_change "$line"
    done <<< "$changes"
  done
  rm -rf "$work"

  echo
  if [ $total -eq 0 ]; then
    printf '%s%s✓ Everything is backed up%s\n' "$GREEN" "$BOLD" "$NC"
  else
    printf '%s%s⚠ %d change%s since the last backup%s\n' "$YELLOW" "$BOLD" "$total" "$([ $total -gt 1 ] && echo s)" "$NC"
    # 3 = the backup is behind this machine (useful in scripts).
    offer_backup "Back up now?" || return 3
  fi
}

# Asks to run a backup right away (only when someone is at the keyboard). True when a
# backup was made.
offer_backup() {
  if [ -t 0 ] && [ -t 1 ]; then
    echo
    confirm "$1" && { echo; cmd_backup; return; }
  else
    dim "Run dudu backup to save them."
  fi
  return 1
}
