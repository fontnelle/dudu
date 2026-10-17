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
    err "Backups of several machines found ($(printf '%s' "$hosts" | paste -sd, - | sed 's/,/, /g')): pick one with --from <machine>"
    return 2
  fi
  local items=() h
  while IFS= read -r h; do items+=("$h|"); done <<< "$hosts"
  MENU_FOOTER="↑↓  |  Enter  |  Q Cancel"
  MENU_HOTKEYS=""
  menu_select pick_host_header "${items[@]}" >/dev/tty || return 1
  printf '%s' "$hosts" | sed -n "$((MENU_CHOICE + 1))p"
}

pick_host_header() { title "Restore from which machine?"; echo; }

# Fills <out> with the backup to restore. Prints errors itself.
fetch_backup() { # <out>
  if [ -n "$DUDU_FILE" ]; then
    local src
    src=$(expand_home "$DUDU_FILE")
    [ -d "$src" ] || { err "Not a folder: $src"; return 1; }
    # Accept either a backup folder or a <host> folder with a "latest" file.
    if [ -f "$src/latest" ]; then
      local stamp
      stamp=$(head -1 "$src/latest" | tr -d '\r')
      valid_stamp "$stamp" || { err "$src/latest does not name a backup"; return 1; }
      src="$src/$stamp"
    fi
    cp -R "$src/." "$1/" || { err "Could not read $src"; return 1; }
    crypto_open "$1"
    return
  fi
  ensure_configured || return 1
  local host
  local rc=0
  host=$(pick_host) || rc=$?
  if [ $rc -eq 2 ]; then return 1; fi
  if [ $rc -ne 0 ] || [ -z "$host" ]; then
    err "No backups found in $(dest_labels). Run dudu backup on your old machine first."
    return 1
  fi
  spin "Fetching the newest backup of $host from $(dest_labels)" dest_load_latest "$host" "$1" || {
    err "Could not read the backup of $host, see $DUDU_LOG"
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
  [ -n "$missing" ] && warn "Listed in the backup but missing from it:$missing"
  [ -n "$failed" ] && warn "Not in this backup (they failed when it was made):$failed"
  for c in $(manifest_list "$1" carried); do
    [ -d "$1/$c" ] && dim "  $c is from an earlier backup (it could not be read that day)"
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
    err "This does not look like a dudu backup (no manifest.json)"
    rm -rf "$work"
    return 1
  fi

  title "Backup of $(manifest_field "$work" host), $(manifest_field "$work" os_version), $(friendly_date "$(manifest_field "$work" created)")"
  if [ -f "$work/.dudu-source" ]; then
    dim "From $(dest_label "$(cat "$work/.dudu-source")") (the newest among $(dest_labels))"
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
    warn "Nothing to restore"
    rm -rf "$work"
    return 0
  fi
  echo
  if [ -z "$DUDU_DRY_RUN" ] && [ -z "$DUDU_YES" ] && [ ! -t 0 ]; then
    err "No terminal to confirm in: run dudu restore -y to restore without asking"
    rm -rf "$work"
    return 1
  fi
  if [ -z "$DUDU_DRY_RUN" ] && [ -z "$DUDU_YES" ]; then
    confirm "Restore these $(echo "$todo" | wc -w | tr -d ' ') items on $(dudu_host)?" || { rm -rf "$work"; return 0; }
  fi

  local failed=""
  for c in $todo; do
    title "── $c"
    if ! "${c}_restore" "$work/$c"; then
      failed="$failed $c"
      err "$c did not finish"
    fi
  done

  echo
  if [ -n "$DUDU_DRY_RUN" ]; then
    dim "Dry run: nothing was changed."
  elif [ -n "$failed" ]; then
    warn "Done, with problems in:$failed. Run dudu restore --only <name> to retry."
  else
    ok "Restore finished. Open a new terminal to load your shell config."
  fi
  if [ -f "$work/RESTORE.md" ] && grep -q '^## Not backed up' "$work/RESTORE.md"; then
    warn "Remember the keys/credentials that were not backed up:"
    sed -n '/^## Not backed up/,/^## /p' "$work/RESTORE.md" | grep '^- ' | sed 's/^- /    /' | LC_ALL=C tr -d '\000-\010\013-\037\177'
  fi
  rm -rf "$work"
  [ -z "$failed" ] || return 2
}
