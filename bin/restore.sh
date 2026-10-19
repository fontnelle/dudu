#!/usr/bin/env bash
# dudu restore: fetches a backup, compares it with this machine and reinstalls what differs,
# collector by collector.

# Picks which machine's backup to use from <hosts>: this host, the only one, or a menu.
pick_host() { # <hosts, one per line>
  local hosts=$1 host n
  [ -n "$hosts" ] || return 1
  host=$(backup_host)
  # Not printf | grep -q: under pipefail, grep stopping early can fail the pipeline.
  if grep -qxF -- "$host" <<< "$hosts"; then printf '%s' "$host"; return 0; fi
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

# dest_all_hosts into a file: it runs under spin, whose output goes to the log.
dest_hosts_to() { dest_all_hosts > "$1"; }

# Phase 1: finds the backup to restore and copies it to <out>. Sets RESTORE_CREATED.
# Prints errors itself.
restore_fetch() { # <out>
  if [ -n "$DUDU_FILE" ]; then
    restore_fetch_file "$1"
    return
  fi
  ensure_configured || return 1
  local host=$DUDU_FROM list rc=0
  if [ -z "$host" ]; then
    list=$(mktemp)
    tmp_register "$list"
    spin "$(t "Looking for backups in %s" "$(dest_labels)")" dest_hosts_to "$list"
    host=$(pick_host "$(cat "$list")") || rc=$?
    rm -f "$list"
    if [ $rc -eq 2 ]; then return 1; fi
    if [ $rc -ne 0 ] || [ -z "$host" ]; then
      err "$(t "No backups found in %s. Run dudu backup on your old machine first." "$(dest_labels)")"
      return 1
    fi
  fi
  printf '\n%s%s%s\n' "$BOLD" "$(t "Restoring %s" "$host")" "$NC"
  restore_fetch_sources "$host" "$1"
}

# Loads the backup of <host> from every destination, shows each one's date and copies the
# one to restore (the newest complete one) to <out>.
restore_fetch_sources() { # <host> <out>
  local d base best n_dest detail unavailable="" SPIN_DRAW=spin_draw_progress SPIN_CLEAR=spin_clear_progress
  base=$(mktemp -d)
  tmp_register "$base"
  n_dest=$(dest_list | wc -w | tr -d ' ')
  phase "1/3" "$(t "Source")" "$(tn "the newest backup in %d destination" "the newest backup in %d destinations" "$n_dest")"
  progress_start "$n_dest"
  for d in $(dest_list); do
    mkdir -p "$base/$d"
    if "${d}_available" 2>/dev/null; then
      DUDU_STEP_TIMEOUT=${DUDU_SAVE_TIMEOUT:-1800} spin "$(dest_label "$d")" "${d}_load" "$1" "$base/$d" || true
    else
      unavailable="$unavailable $d"
    fi
    PROG_DONE=$((PROG_DONE + 1))
  done
  # The rows wait for every destination: only then is it known which one is used.
  best=$(dest_pick_best "$base")
  for d in $(dest_list); do
    if list_has "$(echo "$unavailable" | tr ' ' ',')" "$d"; then
      step_row fail "$(dest_label "$d")" "$(t "not available on this machine")"
    elif [ ! -f "$base/$d/manifest.json" ]; then
      step_row warn "$(dest_label "$d")" "$(t "no backup found")"
    else
      detail=$(friendly_date "$(manifest_field "$base/$d" created)")
      manifest_is_partial "$base/$d/manifest.json" && detail="$detail · $(t "partial")"
      if [ "$d" = "$best" ]; then
        step_row ok "$(dest_label "$d")" "$detail" "${NC}${CYAN}← $(t "restoring this one")"
      else
        step_row ok "$(dest_label "$d")" "$detail"
      fi
    fi
  done
  if [ -z "$best" ]; then
    rm -rf "$base"
    err "$(t "Could not read the backup of %s, see %s" "$1" "$(tilde "$DUDU_LOG")")"
    return 1
  fi
  cp -R "$base/$best/." "$2/"
  rm -rf "$base"
  restore_source_done "$2"
}

# A backup folder given with --file: the source is that folder.
restore_fetch_file() { # <out>
  local src stamp
  src=$(expand_home "$DUDU_FILE")
  [ -d "$src" ] || { err "$(t "Not a folder: %s" "$src")"; return 1; }
  # Accept either a backup folder or a <host> folder with a "latest" file.
  if [ -f "$src/latest" ]; then
    stamp=$(head -1 "$src/latest" | tr -d '\r')
    valid_stamp "$stamp" || { err "$(t "%s does not name a backup" "$src/latest")"; return 1; }
    src="$src/$stamp"
  fi
  printf '\n%s%s%s\n' "$BOLD" "$(t "Restoring %s" "$(tilde "$src")")" "$NC"
  phase "1/3" "$(t "Source")" "$(t "a backup folder")"
  progress_start 1
  cp -R "$src/." "$1/" || { err "$(t "Could not read %s" "$src")"; return 1; }
  if [ ! -f "$1/manifest.json" ]; then
    err "$(t "This does not look like a dudu backup (no manifest.json)")"
    return 1
  fi
  step_row ok "$(t "Folder")" "$(friendly_date "$(manifest_field "$1" created)")"
  restore_source_done "$1"
}

# Closes phase 1: the machine the backup came from, then opens it if encrypted.
restore_source_done() { # <bundle>
  RESTORE_CREATED=$(friendly_date "$(manifest_field "$1" created)")
  phase_done "$(manifest_field "$1" host) · $(manifest_field "$1" os_version) · dudu $(manifest_field "$1" dudu)"
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

# Reads this machine's tools, without leaving the read-only settings to the restore itself
# (corepack must be able to download pnpm and yarn then).
restore_collect_now() { # <dir> <collectors, comma separated>
  local COREPACK_ENABLE_NETWORK COREPACK_ENABLE_DOWNLOAD_PROMPT HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_INSTALL_CLEANUP
  # Only the tools in the backup, and what they are now: no earlier copy stands in for one
  # (a backup run from the menu before leaves DUDU_CARRY set).
  local DUDU_ONLY=$2 DUDU_CARRY=""
  read_only_mode
  collect_all "$1" progress
}

# Phase 2: compares each tool in <bundle> with this machine.
# Sets RESTORE_ITEMS (the tools in the backup), RESTORE_DIFF (those that differ) and
# RESTORE_DETAIL ("<tool>|<state>" lines, for the checklist). What a restore of each tool
# would change goes to <work dir>/plan/<tool>, as status_changes lines.
restore_compare() { # <bundle> <work dir>
  local b=$1 now="$2/now" c n line same=""
  RESTORE_ITEMS=""
  RESTORE_DIFF=""
  RESTORE_DETAIL=""
  RESTORE_PLAN="$2/plan"
  for c in $DUDU_COLLECTORS; do
    [ -d "$b/$c" ] && collector_enabled "$c" && RESTORE_ITEMS="$RESTORE_ITEMS $c"
  done
  RESTORE_ITEMS=${RESTORE_ITEMS# }
  [ -n "$RESTORE_ITEMS" ] || return 0

  phase "2/3" "$(t "Comparing")" "$(t "the backup with this machine")"
  mkdir -p "$now" "$RESTORE_PLAN" "$2/empty"
  DUDU_REDACT_LOG="$2/redacted"
  DUDU_SKIP_LOG="$2/skipped"
  : > "$DUDU_REDACT_LOG"
  : > "$DUDU_SKIP_LOG"
  restore_collect_now "$now" "$(echo "$RESTORE_ITEMS" | tr ' ' ',')"

  # The rows come after every tool was read, the ones that match first, on one line.
  for c in $RESTORE_ITEMS; do
    if list_has "$(echo "$FAILED" | tr ' ' ',')" "$c"; then
      printf '+A %s\n' "$(safe_text "$(head -c 200 "$b/$c/.summary" 2>/dev/null)")" > "$RESTORE_PLAN/$c"
    elif [ ! -d "$now/$c" ]; then
      status_changes "$2/empty" "$b/$c" > "$RESTORE_PLAN/$c"
    else
      # What the backup has and this machine does not: what a restore brings back.
      # Extra things installed here since are left alone, so they do not count.
      status_changes "$now/$c" "$b/$c" | grep -v '^-' > "$RESTORE_PLAN/$c"
    fi
    if [ -s "$RESTORE_PLAN/$c" ]; then
      RESTORE_DIFF="$RESTORE_DIFF $c"
    else
      same="$same $c"
      RESTORE_DETAIL="$RESTORE_DETAIL$c|$(t "same as the backup")"$'\n'
    fi
  done
  RESTORE_DIFF=${RESTORE_DIFF# }
  same=${same# }
  [ -n "$same" ] && step_row ok "$(t "matching")" "${same// /, }"
  for c in $RESTORE_DIFF; do
    if list_has "$(echo "$FAILED" | tr ' ' ',')" "$c"; then
      line=$(t "could not be read on this machine")
      step_row warn "$c" "$line"
    elif [ ! -d "$now/$c" ]; then
      line=$(t "not on this machine")
      step_row missing "$c" "$line"
    else
      line=$(restore_diff_summary "$RESTORE_PLAN/$c")
      step_row diff "$c" "$line"
    fi
    RESTORE_DETAIL="$RESTORE_DETAIL$c|$line"$'\n'
  done
  n=$(echo "$RESTORE_DIFF" | wc -w | tr -d ' ')
  if [ "$n" -eq 0 ]; then
    phase_done "$(t "everything matches this machine")"
  else
    phase_done "$(tn "%d tool differs from this machine" "%d tools differ from this machine" "$n")"
  fi
}

# "3 items missing, 1 file changed": what differs in a tool, by kind.
restore_diff_summary() { # <plan file>
  local out="" n
  n=$(grep -c '^+L' "$1")
  [ "$n" -gt 0 ] && out="$out, $(tn "%d item missing" "%d items missing" "$n")"
  n=$(grep -c '^+D' "$1")
  [ "$n" -gt 0 ] && out="$out, $(tn "%d preference missing" "%d preferences missing" "$n")"
  n=$(grep -c '^+F' "$1")
  [ "$n" -gt 0 ] && out="$out, $(tn "%d file missing" "%d files missing" "$n")"
  n=$(grep -c '^~F' "$1")
  [ "$n" -gt 0 ] && out="$out, $(tn "%d file changed" "%d files changed" "$n")"
  n=$(grep -c '^.V' "$1")
  [ "$n" -gt 0 ] && out="$out, $(tn "%d setting differs" "%d settings differ" "$n")"
  printf '%s' "${out#, }"
}

# One planned change, as what the restore does: "+ install v20.19.6", "~ replace ~/.zshrc".
restore_action() { # <status_changes line>
  local text mark="${GREEN}+${NC}" what
  set -- "$(safe_text "$1")"
  text=${1#?? }
  case "$1" in
    +L*) what=$(t "install %s" "$text") ;;
    +D*) what=$(t "apply %s" "$text") ;;
    +F*) what=$(t "create %s" "$text") ;;
    +V*) what=$(t "set %s" "$text") ;;
    +A*) what=$(t "restore everything in the backup (%s)" "$text") ;;
    ~F*) mark="${YELLOW}~${NC}"; what=$(t "replace %s" "$text") ;;
    *) mark="${YELLOW}~${NC}"; what=$(t "change %s" "$text") ;;
  esac
  printf '    %s %s\n' "$mark" "$what"
}

# What the restore of <tools> will do, tool by tool: settings first, then packages, then files.
restore_show_plan() { # <tools>
  local c n shown change replaced=""
  section "$(t "What will be done")" "$(t "nothing is removed from this machine")"
  for c in $1; do
    printf '  %s%s%s\n' "$BOLD" "$c" "$NC"
    if [ ! -s "$RESTORE_PLAN/$c" ]; then
      printf '    %s= %s%s\n' "$GRAY" "$(t "already matches the backup, applied again")" "$NC"
      continue
    fi
    grep -q '^~F' "$RESTORE_PLAN/$c" && replaced=1
    n=$(grep -c . "$RESTORE_PLAN/$c")
    shown=0
    while IFS= read -r change; do
      shown=$((shown + 1))
      if [ $shown -gt 8 ]; then
        printf '      %s%s%s\n' "$GRAY" "$(t "… and %d more" $((n - 8)))" "$NC"
        break
      fi
      restore_action "$change"
    done < <(grep '^.[AV]' "$RESTORE_PLAN/$c"; grep '^.[LD]' "$RESTORE_PLAN/$c"; grep '^.F' "$RESTORE_PLAN/$c")
  done
  [ -n "$replaced" ] && section_done "$(t "replaced files are kept next to them as .dudu-bak")"
  return 0
}

# Lets the user pick what to restore, with the tools that differ already checked.
# Sets RESTORE_TODO. Returns 1 on cancel.
restore_choose() { # <preselected tools>
  local c i=0 detail
  CL_KIND=()
  CL_LABEL=()
  CL_DETAIL=()
  CL_ON=()
  CL_LOCKED=()
  for c in $RESTORE_ITEMS; do
    detail=$(printf '%s' "$RESTORE_DETAIL" | sed -n "s/^$c|//p" | head -1)
    CL_KIND[i]=i
    CL_LABEL[i]=$c
    CL_DETAIL[i]=$detail
    CL_ON[i]=0
    list_has "$(echo "$1" | tr ' ' ',')" "$c" && CL_ON[i]=1
    i=$((i + 1))
  done
  CL_FLAT=1 CL_ACTION=$(t "Restore") CL_NOTE="$GRAY$(t "Checked: what differs from this machine")$NC" \
    checklist_select "$(t "What to restore on %s?" "$(dudu_host)")" || return 1
  RESTORE_TODO=""
  i=0
  for c in $RESTORE_ITEMS; do
    [ "${CL_ON[$i]}" = 1 ] && RESTORE_TODO="$RESTORE_TODO $c"
    i=$((i + 1))
  done
  RESTORE_TODO=${RESTORE_TODO# }
}

cmd_restore() {
  parse_common_opts "$@"
  config_load
  [ -n "$DUDU_DRY_RUN" ] || dudu_lock || return 1
  local work c todo n started=$SECONDS
  work=$(mktemp -d)
  tmp_register "$work"
  mkdir -p "$work/backup"
  printf '\n=== restore %s ===\n' "$(now_stamp)" >> "$DUDU_LOG"

  restore_fetch "$work/backup" || { rm -rf "$work"; return 1; }
  if [ ! -f "$work/backup/manifest.json" ]; then
    err "$(t "This does not look like a dudu backup (no manifest.json)")"
    rm -rf "$work"
    return 1
  fi
  restore_check_contents "$work/backup"
  restore_compare "$work/backup" "$work"
  if [ -z "$RESTORE_ITEMS" ]; then
    echo
    warn "$(t "Nothing to restore")"
    rm -rf "$work"
    return 0
  fi

  # --only names what to restore, even when it already matches.
  todo=$RESTORE_DIFF
  [ -n "$DUDU_ONLY" ] && todo=$RESTORE_ITEMS
  if [ -z "$todo" ]; then
    echo
    printf '%s%s✓ %s%s\n' "$GREEN" "$BOLD" "$(t "This machine already matches the backup from %s" "$RESTORE_CREATED")" "$NC"
    dim "  $(t "Nothing to restore. To reinstall a tool anyway: dudu restore --only <name>")"
    rm -rf "$work"
    return 0
  fi
  if [ -z "$DUDU_DRY_RUN" ] && [ -z "$DUDU_YES" ] && [ ! -t 0 ]; then
    restore_show_plan "$todo"
    echo
    err "$(t "No terminal to confirm in: run dudu restore -y to restore without asking")"
    rm -rf "$work"
    return 1
  fi
  restore_show_plan "$todo"
  if [ -z "$DUDU_DRY_RUN" ] && [ -z "$DUDU_YES" ]; then
    local key
    echo
    printf '%s%s%s ' "$GRAY" "$(t "Enter Restore · E Choose items · Q Cancel")" "$NC"
    while :; do
      key=$(read_key)
      case "$key" in
        ENTER|CHAR:[yYsS]) echo; break ;;
        CHAR:[eE])
          restore_choose "$todo" || { rm -rf "$work"; return 0; }
          todo=$RESTORE_TODO
          if [ -z "$todo" ]; then
            warn "$(t "Nothing selected, nothing was changed.")"
            rm -rf "$work"
            return 0
          fi
          # The checklist cleared the screen: show the plan for the new choice. Its Enter
          # already said "Restore", so no second question.
          printf '%s%s%s\n' "$BOLD" "$(t "Restoring %s" "$(manifest_field "$work/backup" host)")" "$NC"
          restore_show_plan "$todo"
          break
          ;;
        QUIT|ESC|CHAR:[qQnN]) echo; rm -rf "$work"; return 0 ;;
      esac
    done
  fi

  n=$(echo "$todo" | wc -w | tr -d ' ')
  phase "3/3" "$(t "Restoring")" "${todo// /, }"
  local failed=""
  for c in $todo; do
    title "── $c"
    if ! "${c}_restore" "$work/backup/$c"; then
      failed="$failed $c"
      err "$(t "%s did not finish" "$c")"
    fi
  done
  # One line per tool at the end: the output above can be long.
  echo
  for c in $todo; do
    if list_has "$(echo "$failed" | tr ' ' ',')" "$c"; then
      step_row fail "$c" "$(t "did not finish, see %s" "$(tilde "$DUDU_LOG")")"
    elif [ -n "$DUDU_DRY_RUN" ]; then
      step_row ok "$c" "$(t "would be restored")"
    else
      step_row ok "$c" "$(t "restored")"
    fi
  done

  local stats
  stats="$(tn "%d tool" "%d tools" "$n") · $(fmt_secs $((SECONDS - started)))"
  echo
  if [ -n "$DUDU_DRY_RUN" ]; then
    dim "$(t "Dry run: nothing was changed.")"
  elif [ -n "$failed" ]; then
    printf '%s%s⚠ %s%s   %s%s%s\n' "$YELLOW" "$BOLD" "$(t "Restore finished with problems in:%s" "$failed")" "$NC" "$GRAY" "$stats" "$NC"
    dim "  $(t "Run dudu restore --only <name> to retry.")"
  else
    printf '%s%s✓ %s%s   %s%s%s\n' "$GREEN" "$BOLD" "$(t "Restore finished")" "$NC" "$GRAY" "$stats" "$NC"
    # Only these change what a new shell loads (dotfiles, PATH of runtimes).
    case " $todo " in
      *" shell "*|*" node "*|*" python "*|*" ruby "*|*" go "*|*" cargo "*|*" bun "*)
        dim "  $(t "Open a new terminal to load your shell config.")" ;;
    esac
  fi
  # Keys left out of the backup are still on the machine that made it: the reminder is for
  # another machine.
  if [ "$(manifest_field "$work/backup" machine)" != "$(machine_id)" ] &&
     [ -f "$work/backup/RESTORE.md" ] && grep -q '^## Not backed up' "$work/backup/RESTORE.md"; then
    warn "$(t "Remember the keys/credentials that were not backed up:")"
    sed -n '/^## Not backed up/,/^## /p' "$work/backup/RESTORE.md" | grep '^- ' | sed 's/^- /    /' | LC_ALL=C tr -d '\000-\010\013-\037\177'
  fi
  rm -rf "$work"
  [ -z "$failed" ] || return 2
}
