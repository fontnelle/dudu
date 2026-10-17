#!/usr/bin/env bash
# dudu restore: fetches a backup and reinstalls everything, collector by collector.

# Picks which machine's backup to use: --from, this host, the only one, or a menu.
pick_host() {
  local hosts host n
  if [ -n "$DUDU_FROM" ]; then printf '%s' "$DUDU_FROM"; return 0; fi
  hosts=$(dest_all_hosts)
  [ -n "$hosts" ] || return 1
  host=$(backup_host)
  if printf '%s\n' "$hosts" | grep -qxF "$host"; then printf '%s' "$host"; return 0; fi
  n=$(printf '%s\n' "$hosts" | grep -c .)
  if [ "$n" -eq 1 ]; then printf '%s' "$hosts" | head -1; return 0; fi
  # Without a terminal, never guess which machine's dotfiles to install.
  if [ ! -t 0 ]; then
    err "$(t "Backups of several machines found (%s): pick one with --from <machine>" "$(printf '%s' "$hosts" | paste -sd, - | sed 's/,/, /g')")"
    return 2
  fi
  local items=() h
  while IFS= read -r h; do items+=("$h|"); done <<< "$hosts"
  MENU_FOOTER="↑↓  |  Enter  |  $(t "Q Cancel")"
  MENU_HOTKEYS=""
  menu_select pick_host_header "${items[@]}" >/dev/tty || return 1
  printf '%s' "$hosts" | sed -n "$((MENU_CHOICE + 1))p"
}

pick_host_header() { title "$(t "Restore from which machine?")"; echo; }

# Fills <out> with the backup to restore. Prints errors itself.
fetch_backup() { # <out>
  if [ -n "$DUDU_FILE" ]; then
    local src
    src=$(expand_home "$DUDU_FILE")
    [ -d "$src" ] || { err "$(t "Not a folder: %s" "$src")"; return 1; }
    # Accept either a backup folder or a <host> folder with a "latest" file.
    if [ -f "$src/latest" ]; then
      local stamp
      stamp=$(head -1 "$src/latest" | tr -d '\r')
      valid_stamp "$stamp" || { err "$(t "%s does not name a backup" "$src/latest")"; return 1; }
      src="$src/$stamp"
    fi
    cp -R "$src/." "$1/" || { err "$(t "Could not read %s" "$src")"; return 1; }
    crypto_open "$1"
    return
  fi
  ensure_configured || return 1
  local host
  local rc=0
  host=$(pick_host) || rc=$?
  if [ $rc -eq 2 ]; then return 1; fi
  if [ $rc -ne 0 ] || [ -z "$host" ]; then
    err "$(t "No backups found in %s. Run dudu backup on your old machine first." "$(dest_labels)")"
    return 1
  fi
  spin "$(t "Fetching the newest backup of %s from %s" "$host" "$(dest_labels)")" dest_load_latest "$host" "$1" || {
    err "$(t "Could not read the backup of %s, see %s" "$host" "$DUDU_LOG")"
    return 1
  }
  crypto_open "$1"
}

manifest_field() { # <bundle> <field>
  safe_text "$(sed -n "s/.*\"$2\": *\"\\([^\"]*\\)\".*/\\1/p" "$1/manifest.json" 2>/dev/null | head -1)"
}

# Names in a manifest array ("collectors", "carried", "failed"), only known collector names.
manifest_list() { # <bundle> <field>
  local c
  for c in $(sed -n "s/.*\"$2\": *\[\(.*\)\].*/\1/p" "$1/manifest.json" 2>/dev/null | head -1 | tr -d '" ' | tr ',' ' '); do
    case " $DUDU_COLLECTORS " in *" $c "*) printf '%s\n' "$c" ;; esac
  done
}

# Warns about tools the manifest lists but whose data is not in the backup, and tools that
# had failed when the backup was made.
restore_check_contents() { # <bundle>
  local c missing="" failed=""
  for c in $(manifest_list "$1" collectors) $(manifest_list "$1" carried); do
    [ -d "$1/$c" ] || missing="$missing $c"
  done
  for c in $(manifest_list "$1" failed); do failed="$failed $c"; done
  [ -n "$missing" ] && warn "$(t "Listed in the backup but missing from it:%s" "$missing")"
  [ -n "$failed" ] && warn "$(t "Not in this backup (they failed when it was made):%s" "$failed")"
  for c in $(manifest_list "$1" carried); do
    [ -d "$1/$c" ] && dim "  $(t "%s is from an earlier backup (it could not be read that day)" "$c")"
  done
  return 0
}

cmd_restore() {
  parse_common_opts "$@"
  config_load
  [ -n "$DUDU_DRY_RUN" ] || dudu_lock || return 1
  local work c todo=""
  work=$(mktemp -d)
  tmp_register "$work"
  printf '\n=== restore %s ===\n' "$(now_stamp)" >> "$DUDU_LOG"

  fetch_backup "$work" || { rm -rf "$work"; return 1; }
  if [ ! -f "$work/manifest.json" ]; then
    err "$(t "This does not look like a dudu backup (no manifest.json)")"
    rm -rf "$work"
    return 1
  fi

  title "$(t "Backup of %s, %s, %s" "$(manifest_field "$work" host)" "$(manifest_field "$work" os_version)" "$(friendly_date "$(manifest_field "$work" created)")")"
  if [ -f "$work/.dudu-source" ]; then
    dim "$(t "From %s (the newest among %s)" "$(dest_label "$(cat "$work/.dudu-source")")" "$(dest_labels)")"
    rm -f "$work/.dudu-source"
  fi
  echo
  for c in $DUDU_COLLECTORS; do
    [ -d "$work/$c" ] || continue
    collector_enabled "$c" || continue
    todo="$todo $c"
    row "${BLUE}•${NC}" "$c" "$(safe_text "$(head -c 200 "$work/$c/.summary" 2>/dev/null)")"
  done
  todo=${todo# }
  restore_check_contents "$work"
  if [ -z "$todo" ]; then
    warn "$(t "Nothing to restore")"
    rm -rf "$work"
    return 0
  fi
  echo
  if [ -z "$DUDU_DRY_RUN" ] && [ -z "$DUDU_YES" ] && [ ! -t 0 ]; then
    err "$(t "No terminal to confirm in: run dudu restore -y to restore without asking")"
    rm -rf "$work"
    return 1
  fi
  if [ -z "$DUDU_DRY_RUN" ] && [ -z "$DUDU_YES" ]; then
    confirm "$(tn "Restore this %d item on %s?" "Restore these %d items on %s?" "$(echo "$todo" | wc -w | tr -d ' ')" "$(dudu_host)")" || { rm -rf "$work"; return 0; }
  fi

  local failed=""
  for c in $todo; do
    title "── $c"
    if ! "${c}_restore" "$work/$c"; then
      failed="$failed $c"
      err "$(t "%s did not finish" "$c")"
    fi
  done

  echo
  if [ -n "$DUDU_DRY_RUN" ]; then
    dim "$(t "Dry run: nothing was changed.")"
  elif [ -n "$failed" ]; then
    warn "$(t "Done, with problems in:%s. Run dudu restore --only <name> to retry." "$failed")"
  else
    ok "$(t "Restore finished. Open a new terminal to load your shell config.")"
  fi
  if [ -f "$work/RESTORE.md" ] && grep -q '^## Not backed up' "$work/RESTORE.md"; then
    warn "$(t "Remember the keys/credentials that were not backed up:")"
    sed -n '/^## Not backed up/,/^## /p' "$work/RESTORE.md" | grep '^- ' | sed 's/^- /    /' | LC_ALL=C tr -d '\000-\010\013-\037\177'
  fi
  rm -rf "$work"
  [ -z "$failed" ] || return 2
}
