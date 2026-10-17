#!/usr/bin/env bash
# dudu config: destinations, folders, collectors to skip, how many backups to keep.

# Checklist of destinations: every checked one gets each backup.
config_pick_destination() {
  local d i=0 chosen=""
  CL_KIND=(); CL_LABEL=(); CL_DETAIL=(); CL_ON=(); CL_LOCKED=(); CL_DEST=()
  for d in $DUDU_DESTINATIONS; do
    CL_KIND[i]=i
    CL_LABEL[i]=$(dest_label "$d")
    CL_DEST[i]=$d
    CL_ON[i]=0
    CL_LOCKED[i]=0
    list_has "$DUDU_DESTINATION" "$d" && CL_ON[i]=1
    if "${d}_available" 2>/dev/null; then
      CL_DETAIL[i]=$(tilde "$("${d}_where" 2>/dev/null)")
    elif [ "$d" = gdrive ]; then
      CL_DETAIL[i]="not found, select to set its folder"
    else
      CL_DETAIL[i]="not available on this machine"
      CL_LOCKED[i]=1
      CL_ON[i]=0
    fi
    i=$((i + 1))
  done
  local CL_FLAT=1 CL_ACTION=Save
  checklist_select "Where should dudu keep your backups? Check one or more." || return 1

  for ((i = 0; i < ${#CL_DEST[@]}; i++)); do
    [ "${CL_ON[$i]}" = 1 ] && chosen="$chosen,${CL_DEST[$i]}"
  done
  chosen=${chosen#,}
  if [ -z "$chosen" ]; then
    warn "Nothing selected, keeping: $(dest_labels)"
    return 1
  fi

  local path
  if list_has "$chosen" local; then
    printf 'Local folder [%s]: ' "$(tilde "${DUDU_PATH:-$HOME/dudu-backups}")"
    read -r path
    DUDU_PATH=$(expand_home "${path:-${DUDU_PATH:-$HOME/dudu-backups}}")
  fi
  if list_has "$chosen" gdrive && ! gdrive_available 2>/dev/null; then
    if has rclone; then
      printf 'Google Drive folder not found. rclone remote (e.g. gdrive:dudu), or a folder path: '
    else
      printf 'Google Drive folder not found. Path of a synced Google Drive folder: '
    fi
    read -r path
    case "$path" in
      "") warn "No Google Drive folder given, leaving Google Drive out"; chosen=$(printf '%s' "$chosen" | tr ',' '\n' | grep -vx gdrive | paste -sd, -) ;;
      *:*) DUDU_RCLONE_REMOTE=$path; DUDU_GDRIVE_PATH="" ;;
      *) DUDU_GDRIVE_PATH=$(expand_home "$path"); DUDU_RCLONE_REMOTE="" ;;
    esac
    [ -n "$chosen" ] || return 1
  fi

  DUDU_DESTINATION=$chosen
  config_save
  echo
  ok "Each backup goes to:"
  for d in $(dest_list); do
    printf '    %-14s %s%s%s\n' "$(dest_label "$d")" "$GRAY" "$(tilde "$("${d}_where" 2>/dev/null)")" "$NC"
  done
  list_has "$chosen" notes && dim "  The first save to Notes asks permission to control Notes, allow it."
  return 0
}

config_show() {
  local d
  title "dudu config"
  dim "$(tilde "$DUDU_CONFIG_FILE")"
  echo
  if [ -z "$DUDU_DESTINATION" ]; then
    row "" "destinations" "not set, run: dudu config"
  else
    printf '  %-14s\n' "destinations"
    for d in $(dest_list); do
      if "${d}_available" 2>/dev/null; then
        printf '    %s✓%s %-14s %s%s%s\n' "$GREEN" "$NC" "$(dest_label "$d")" "$GRAY" "$(tilde "$("${d}_where" 2>/dev/null)")" "$NC"
      else
        printf '    %s✗%s %-14s %snot available on this machine%s\n' "$RED" "$NC" "$(dest_label "$d")" "$RED" "$NC"
      fi
    done
  fi
  printf '  %-14s %s%s%s\n' "include" "$GRAY" "${DUDU_INCLUDE:-all detected}" "$NC"
  printf '  %-14s %s%s%s\n' "exclude" "$GRAY" "${DUDU_EXCLUDE:-none}" "$NC"
  printf '  %-14s %s%s backups per machine%s\n' "keep" "$GRAY" "$DUDU_KEEP" "$NC"
  if [ "$DUDU_ENCRYPT" = on ]; then
    printf '  %-14s %s✓%s %swith a password%s\n' "encryption" "$GREEN" "$NC" "$GRAY" "$NC"
  else
    printf '  %-14s %soff, turn on with: dudu config set encrypt on%s\n' "encryption" "$GRAY" "$NC"
  fi
  local t
  if t=$(schedule_time) && [ -n "$t" ]; then
    printf '  %-14s %s✓%s %sdaily at %s%s\n' "schedule" "$GREEN" "$NC" "$GRAY" "$t" "$NC"
  else
    printf '  %-14s %soff, turn on with: dudu schedule on%s\n' "schedule" "$GRAY" "$NC"
  fi
}

cmd_config() {
  config_load
  [ "${1:-}" = show ] || dudu_lock || return 1
  case "${1:-}" in
    show) config_show ;;
    set)
      [ $# -eq 3 ] || die "Usage: dudu config set <destination|path|gdrive_path|include|exclude|keep|encrypt|rclone_remote> <value>"
      case "$2" in
        destination)
          local d
          for d in $(printf '%s' "$3" | tr ',' ' '); do
            list_has "$(echo "$DUDU_DESTINATIONS" | tr ' ' ',')" "$d" ||
              die "Unknown destination: $d (use one or more of: $(echo "$DUDU_DESTINATIONS" | tr ' ' ','))"
          done
          DUDU_DESTINATION=$3 ;;
        path) DUDU_PATH=$(expand_home "$3") ;;
        gdrive_path) DUDU_GDRIVE_PATH=$(expand_home "$3") ;;
        include) DUDU_INCLUDE=$3 ;;
        exclude) DUDU_EXCLUDE=$3 ;;
        keep)
          case "$3" in ''|*[!0-9]*|0) die "keep must be a number of backups, 1 or more" ;; esac
          DUDU_KEEP=$3 ;;
        encrypt)
          case "$3" in
            on)
              title "Encrypt backups with a password"
              dim "Backups are encrypted before they leave this machine (AES-256). The password is"
              dim "kept in your keychain here; on a new machine, restore asks for it."
              warn "Without the password, encrypted backups cannot be restored. Save it in your password manager."
              echo
              crypto_set_password || exit 1
              DUDU_ENCRYPT=on ;;
            off) DUDU_ENCRYPT=off; crypto_forget_password ;;
            *) die "Usage: dudu config set encrypt on|off" ;;
          esac ;;
        rclone_remote) DUDU_RCLONE_REMOTE=$3 ;;
        *) die "Unknown key: $2" ;;
      esac
      config_save
      ok "$2 = $3"
      ;;
    "")
      if [ -t 0 ] && [ -t 1 ]; then
        config_pick_destination && { echo; config_show; echo; dim "Skip collectors with: dudu config set exclude macos,ruby"; }
      else
        config_show
      fi
      ;;
    *) die "Usage: dudu config [show|set <key> <value>]" ;;
  esac
}
