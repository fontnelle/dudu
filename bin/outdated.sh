#!/usr/bin/env bash
# dudu outdated: one view of the updates available across package managers, then (when
# someone is at the keyboard) update all of them or pick some from a checklist.
# Each collector provides <c>_outdated ("name current latest" per line), <c>_upgrade <name>
# and <c>_upgrade_hint.

OUTDATED_LIMIT=10

cmd_outdated() {
  parse_common_opts "$@"
  config_load
  read_only_mode

  local c n rc total=0 hints="" shown name cur new work skipped=0
  work=$(mktemp -d)
  tmp_register "$work"
  title "Updates available"
  dim "Read-only check: nothing is installed or updated without asking."
  echo

  for c in $DUDU_COLLECTORS; do
    collector_enabled "$c" || continue
    declare -F "${c}_outdated" >/dev/null || continue
    # 99 = tool not on this machine. Some tools exit non-zero when they find updates.
    spin "Checking $c" eval '"${c}_detect" || exit 99; "${c}_outdated" > "$work/$c"; exit 0'
    rc=$?
    [ $rc -eq 99 ] && continue
    if [ $rc -eq 124 ]; then
      row "${YELLOW}⚠${NC}" "$c" "could not check (took too long)"
      skipped=$((skipped + 1))
      continue
    fi
    n=$(grep -c . "$work/$c" 2>/dev/null)
    if [ "${n:-0}" -eq 0 ]; then
      row "${GREEN}✓${NC}" "$c" "up to date"
      rm -f "$work/$c"
      continue
    fi
    total=$((total + n))
    row "${YELLOW}↑${NC}" "$c" "$n update$([ "$n" -gt 1 ] && echo s)"
    shown=0
    while read -r name cur new; do
      shown=$((shown + 1))
      if [ -z "$DUDU_ALL" ] && [ $shown -gt $OUTDATED_LIMIT ]; then
        printf '             %s… and %d more (dudu outdated --all)%s\n' "$GRAY" $((n - OUTDATED_LIMIT)) "$NC"
        break
      fi
      printf '             %-24s %s%s%s → %s%s%s\n' "$name" "$GRAY" "$cur" "$NC" "$GREEN" "$new" "$NC"
    done < "$work/$c"
    declare -F "${c}_upgrade_hint" >/dev/null && hints="$hints$c|$("${c}_upgrade_hint")"$'\n'
  done

  echo
  if [ $total -eq 0 ] && [ $skipped -gt 0 ]; then
    printf '%s%s⚠ No updates found, %d tool%s could not be checked%s\n' "$YELLOW" "$BOLD" "$skipped" "$([ $skipped -gt 1 ] && echo s)" "$NC"
    rm -rf "$work"
    return 2
  fi
  if [ $total -eq 0 ]; then
    printf '%s%s✓ Everything is up to date%s\n' "$GREEN" "$BOLD" "$NC"
    rm -rf "$work"
    return 0
  fi
  printf '%s%s↑ %d update%s available%s\n' "$YELLOW" "$BOLD" "$total" "$([ $total -gt 1 ] && echo s)" "$NC"

  if [ -t 0 ] && [ -t 1 ]; then
    outdated_offer "$work" "$total"
  else
    echo
    dim "To update, run each tool's own command, then dudu backup:"
    printf '%s' "$hints" | while IFS='|' read -r c cmd; do
      [ -n "$c" ] && printf '  %-10s %s%s%s\n' "$c" "$CYAN" "$cmd" "$NC"
    done
  fi
  rm -rf "$work"
  return 0
}

# Fills the CL_* arrays from the per-collector result files in <dir>.
outdated_build_list() { # <dir>
  local c name cur new i=0
  CL_KIND=(); CL_LABEL=(); CL_DETAIL=(); CL_ON=(); CL_COLLECTOR=()
  for c in $DUDU_COLLECTORS; do
    [ -s "$1/$c" ] || continue
    declare -F "${c}_upgrade" >/dev/null || continue
    CL_KIND[i]=g; CL_LABEL[i]=$c; CL_DETAIL[i]=""; CL_ON[i]=0; CL_COLLECTOR[i]=$c
    i=$((i + 1))
    while read -r name cur new; do
      [ -n "$name" ] || continue
      CL_KIND[i]=i; CL_LABEL[i]=$name; CL_DETAIL[i]="$cur → $new"; CL_ON[i]=0; CL_COLLECTOR[i]=$c
      i=$((i + 1))
    done < "$1/$c"
  done
}

outdated_offer() { # <dir> <total>
  local key count
  outdated_build_list "$1"
  [ ${#CL_KIND[@]} -gt 0 ] || return 0
  echo
  printf '%sa%s Update all   %ss%s Choose   %sn%s Not now  ' "$CYAN" "$NC" "$CYAN" "$NC" "$CYAN" "$NC"
  IFS= read -rsn1 key
  echo
  case "$key" in
    a|A)
      checklist_toggle_all
      count=$(checklist_selected_count)
      confirm "Update all $count packages?" || return 0
      ;;
    s|S)
      checklist_select "Choose what to update" || { dim "Nothing was updated."; return 0; }
      count=$(checklist_selected_count)
      if [ "$count" -eq 0 ]; then dim "Nothing selected, nothing was updated."; return 0; fi
      ;;
    *) dim "Nothing was updated."; return 0 ;;
  esac
  outdated_run_upgrades
}

# Upgrades every checked item, one at a time: the running one animates, finished ones turn
# into ✓/✗ lines, and an overall progress bar stays at the bottom.
outdated_run_upgrades() {
  local i n=${#CL_KIND[@]} c last="" failed_n=0 rc label
  local DUDU_STEP_TIMEOUT=1800 # a big cask or a Node install can take minutes
  local SPIN_DRAW=spin_draw_progress SPIN_CLEAR=spin_clear_progress
  PROG_TOTAL=$(checklist_selected_count)
  PROG_DONE=0
  PROG_START=$SECONDS
  PROG_COLS=$(term_cols)
  # Updating needs the network that read_only_mode turned off.
  unset COREPACK_ENABLE_NETWORK HOMEBREW_NO_AUTO_UPDATE
  printf '\n=== upgrade %s ===\n' "$(now_stamp)" >> "$DUDU_LOG"

  title "Updating $PROG_TOTAL package$([ "$PROG_TOTAL" -gt 1 ] && echo s)"
  for ((i = 0; i < n; i++)); do
    { [ "${CL_KIND[$i]}" = i ] && [ "${CL_ON[$i]}" = 1 ]; } || continue
    c=${CL_COLLECTOR[$i]}
    if [ "$c" != "$last" ]; then
      printf '\n%s%s%s\n' "$CYAN" "$c" "$NC"
      last=$c
    fi
    label="$(printf '%-20s %s' "${CL_LABEL[$i]}" "${CL_DETAIL[$i]}")"
    if [ "$c" = syspkgs ]; then
      # sudo may ask for a password: no animation here.
      printf '  %s…%s %s %s(may ask for your password)%s\n' "$CYAN" "$NC" "$label" "$GRAY" "$NC"
      "${c}_upgrade" "${CL_LABEL[$i]}" >>"$DUDU_LOG" 2>&1
      rc=$?
      printf '\033[1A\033[2K'
    else
      spin "$label" "${c}_upgrade" "${CL_LABEL[$i]}"
      rc=$?
    fi
    PROG_DONE=$((PROG_DONE + 1))
    if [ $rc -eq 0 ]; then
      printf '  %s✓%s %-20s %s%s%s\n' "$GREEN" "$NC" "${CL_LABEL[$i]}" "$GREEN" "${CL_DETAIL[$i]##* }" "$NC"
    else
      failed_n=$((failed_n + 1))
      printf '  %s✗%s %-20s %s%s%s\n' "$RED" "$NC" "${CL_LABEL[$i]}" "$RED" \
        "$([ $rc -eq 124 ] && echo "timed out" || echo failed)" "$NC"
    fi
  done
  read_only_mode

  echo
  [ -t 1 ] && { progress_line; echo; echo; }
  local ok_n=$((PROG_DONE - failed_n))
  if [ $failed_n -eq 0 ]; then
    printf '%s%s✓ %d updated%s  %sin %s%s\n' "$GREEN" "$BOLD" "$ok_n" "$NC" "$GRAY" "$(fmt_secs $((SECONDS - PROG_START)))" "$NC"
  else
    printf '%s%s✓ %d updated%s  %s%s✗ %d failed%s  %ssee %s%s\n' "$GREEN" "$BOLD" "$ok_n" "$NC" \
      "$RED" "$BOLD" "$failed_n" "$NC" "$GRAY" "$(tilde "$DUDU_LOG")" "$NC"
  fi
  if [ $ok_n -gt 0 ]; then
    echo
    confirm "Your setup changed. Back up now?" && { echo; cmd_backup; }
  fi
  return 0
}
