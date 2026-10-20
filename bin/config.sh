#!/usr/bin/env bash
# dudu config: destinations, folders, collectors to skip, how many backups to keep, language.

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
      CL_DETAIL[i]=$(t "select to connect, a browser opens")
    else
      CL_DETAIL[i]=$(t "not available on this machine")
      CL_LOCKED[i]=1
      CL_ON[i]=0
    fi
    i=$((i + 1))
  done
  local CL_FLAT=1 CL_ACTION
  CL_ACTION=$(t "Save")
  checklist_select "$(t "Where should dudu keep your backups? Check one or more.")" || return 1

  for ((i = 0; i < ${#CL_DEST[@]}; i++)); do
    [ "${CL_ON[$i]}" = 1 ] && chosen="$chosen,${CL_DEST[$i]}"
  done
  chosen=${chosen#,}
  if [ -z "$chosen" ]; then
    warn "$(t "Nothing selected, keeping: %s" "$(dest_labels)")"
    return 1
  fi

  local path
  if list_has "$chosen" local; then
    printf '%s ' "$(t "Local folder [%s]:" "$(tilde "${DUDU_PATH:-$HOME/dudu-backups}")")"
    read -r path
    DUDU_PATH=$(expand_home "${path:-${DUDU_PATH:-$HOME/dudu-backups}}")
  fi
  if list_has "$chosen" gdrive && ! gdrive_available 2>/dev/null && ! gdrive_setup; then
    warn "$(t "Leaving Google Drive out. Try again with %s, or use a synced folder: %s" "dudu config gdrive" "dudu config set gdrive_path <folder>")"
    chosen=$(printf '%s' "$chosen" | tr ',' '\n' | grep -vx gdrive | paste -sd, -)
    [ -n "$chosen" ] || return 1
  fi

  DUDU_DESTINATION=$chosen
  config_save
  echo
  ok "$(t "Each backup goes to:")"
  for d in $(dest_list); do
    printf '    %s %s%s%s\n' "$(pad "$(dest_label "$d")" 14)" "$GRAY" "$(tilde "$("${d}_where" 2>/dev/null)")" "$NC"
  done
  list_has "$chosen" notes && dim "  $(t "The first save to Notes asks permission to control Notes, allow it.")"
  return 0
}

# "  label          value", the label padded by characters (it may be translated).
config_row() { # <label> <value>
  printf '  %s %s\n' "$(pad "$1" 14)" "$2"
}

# What language= is set to, for display: "auto (Português (Brasil))" or "Español".
config_language_label() {
  case "${DUDU_LANGUAGE:-auto}" in
    auto) printf '%s' "$(t "automatic, from the system (%s)" "$(i18n_name "$DUDU_LANG_ACTIVE")")" ;;
    *) i18n_name "$DUDU_LANGUAGE" ;;
  esac
}

config_show() {
  local d
  title "$(t "dudu config")"
  dim "$(tilde "$DUDU_CONFIG_FILE")"
  echo
  if [ -z "$DUDU_DESTINATION" ]; then
    row "" "$(t "destinations")" "$(t "not set, run: dudu config")"
  else
    printf '  %s\n' "$(t "destinations")"
    for d in $(dest_list); do
      if "${d}_available" 2>/dev/null; then
        printf '    %s✓%s %s %s%s%s\n' "$GREEN" "$NC" "$(pad "$(dest_label "$d")" 14)" "$GRAY" "$(tilde "$("${d}_where" 2>/dev/null)")" "$NC"
      else
        printf '    %s✗%s %s %s%s%s\n' "$RED" "$NC" "$(pad "$(dest_label "$d")" 14)" "$RED" "$(t "not available on this machine")" "$NC"
      fi
    done
  fi
  config_row "$(t "include")" "${GRAY}${DUDU_INCLUDE:-$(t "all detected")}${NC}"
  config_row "$(t "exclude")" "${GRAY}${DUDU_EXCLUDE:-$(t "none")}${NC}"
  config_row "$(t "keep")" "${GRAY}$(tn "%d backup per machine" "%d backups per machine" "$DUDU_KEEP")${NC}"
  if [ "$DUDU_ENCRYPT" = on ]; then
    config_row "$(t "encryption")" "${GREEN}✓${NC} ${GRAY}$(t "with a password")${NC}"
  else
    config_row "$(t "encryption")" "${GRAY}$(t "off, turn on with: dudu config set encrypt on")${NC}"
  fi
  local tm
  if tm=$(schedule_time) && [ -n "$tm" ]; then
    config_row "$(t "schedule")" "${GREEN}✓${NC} ${GRAY}$(t "daily at %s" "$tm")${NC}"
  else
    config_row "$(t "schedule")" "${GRAY}$(t "off, turn on with: dudu schedule on")${NC}"
  fi
  config_row "$(t "language")" "${GRAY}$(config_language_label)${NC}"
}

# Asks for a password and turns encryption on. Returns 1 when no password was set.
config_encrypt_on() {
  title "$(t "Encrypt backups with a password")"
  dim "$(t "Backups are encrypted before they leave this machine (AES-256). The password is")"
  dim "$(t "kept in your keychain here; on a new machine, restore asks for it.")"
  warn "$(t "Without the password, encrypted backups cannot be restored. Save it in your password manager.")"
  echo
  crypto_set_password || return 1
  DUDU_ENCRYPT=on
}

# Saves language= and switches the running dudu to it.
config_set_language() { # <auto|en|pt-BR|es>
  local l=$1
  case "$l" in
    auto|en|es) ;;
    pt-BR|pt_BR|pt-br|pt) l=pt-BR ;;
    *) return 1 ;;
  esac
  DUDU_LANGUAGE=$l
  config_save
  i18n_init
}

# Settings › Language: a list with the current choice marked.
config_pick_language() {
  local l cur=${DUDU_LANGUAGE:-auto} items=() mark
  for l in auto $DUDU_LANGS; do
    mark=""
    [ "$l" = "$cur" ] && mark="  ✓"
    if [ "$l" = auto ]; then
      items+=("$(t "Automatic")|$(t "follow the system (%s)" "$(i18n_name "$(i18n_system_language || echo en)")")$mark")
    else
      items+=("$(i18n_name "$l")|$l$mark")
    fi
  done
  local MENU_FOOTER MENU_HOTKEYS=""
  MENU_FOOTER="↑↓  |  Enter  |  $(t "Q Back")"
  menu_select config_header_language "${items[@]}" || return 1
  # shellcheck disable=SC2086
  l=$(set -- auto $DUDU_LANGS; shift "$MENU_CHOICE"; printf '%s' "$1")
  config_set_language "$l"
  clear_screen
  ok "$(t "Language: %s" "$(config_language_label)")"
}

config_header_language() { title "$(t "Language")"; echo; }
config_header() { title "$(t "Settings")"; echo; }

# Settings › Scheduled backup: on (asking the time) or off.
config_toggle_schedule() {
  local tm
  if tm=$(schedule_time) && [ -n "$tm" ]; then
    confirm "$(t "Daily backup at %s. Turn it off?" "$tm")" && cmd_schedule off
  else
    printf '%s ' "$(t "Back up every day at [%s]:" "$SCHEDULE_DEFAULT")"
    read -r tm
    cmd_schedule on "${tm:-$SCHEDULE_DEFAULT}"
  fi
}

# Settings › Encryption: on (asking a password) or off.
config_toggle_encrypt() {
  if [ "$DUDU_ENCRYPT" = on ]; then
    warn "$(t "New backups will be saved unencrypted. Backups made so far keep their password.")"
    confirm "$(t "Turn encryption off?")" || return 0
    DUDU_ENCRYPT=off
    crypto_forget_password
    config_save
    ok "$(t "Encryption turned off")"
  else
    config_encrypt_on || return 1
    config_save
    ok "$(t "Encryption on")"
  fi
}

# The Settings menu: destinations, language, encryption, schedule, and the whole config.
config_menu() {
  local tm sched enc
  while true; do
    config_load
    if tm=$(schedule_time) && [ -n "$tm" ]; then sched=$(t "daily at %s" "$tm"); else sched=$(t "off"); fi
    if [ "$DUDU_ENCRYPT" = on ]; then enc=$(t "on, with a password"); else enc=$(t "off"); fi
    local MENU_FOOTER MENU_HOTKEYS=""
    MENU_FOOTER="↑↓  |  Enter  |  $(t "Q Back")"
    menu_select config_header \
      "$(t "Destinations")|${DUDU_DESTINATION:+$(dest_labels)}" \
      "$(t "Language")|$(config_language_label)" \
      "$(t "Encryption")|$enc" \
      "$(t "Scheduled backup")|$sched" \
      "$(t "View settings")|$(tilde "$DUDU_CONFIG_FILE")" || { clear_screen; return 0; }
    clear_screen
    case "$MENU_CHOICE" in
      0) config_pick_destination && { echo; dim "$(t "Skip collectors with: dudu config set exclude macos,ruby")"; } ;;
      1) config_pick_language || continue ;;
      2) config_toggle_encrypt ;;
      3) config_toggle_schedule ;;
      4) config_load; config_show ;;
    esac
    printf '\n%s%s%s' "$GRAY" "$(t "Press any key to go back…")" "$NC"
    read -rsn1 _
  done
}

cmd_config() {
  config_load
  [ "${1:-}" = show ] || dudu_lock || return 1
  case "${1:-}" in
    show) config_show ;;
    gdrive)
      gdrive_setup || return 1
      list_has "$DUDU_DESTINATION" gdrive || DUDU_DESTINATION=${DUDU_DESTINATION:+$DUDU_DESTINATION,}gdrive
      config_save
      dim "  $(t "Each backup goes to: %s" "$(dest_labels)")"
      ;;
    set)
      [ $# -eq 3 ] || die "$(t "Usage: dudu config set <%s> <value>" "destination|path|gdrive_path|include|exclude|keep|encrypt|language|rclone_remote")"
      case "$2" in
        destination)
          local d
          for d in $(printf '%s' "$3" | tr ',' ' '); do
            list_has "$(echo "$DUDU_DESTINATIONS" | tr ' ' ',')" "$d" ||
              die "$(t "Unknown destination: %s (use one or more of: %s)" "$d" "$(echo "$DUDU_DESTINATIONS" | tr ' ' ',')")"
          done
          DUDU_DESTINATION=$3 ;;
        path) DUDU_PATH=$(expand_home "$3") ;;
        gdrive_path) DUDU_GDRIVE_PATH=$(expand_home "$3") ;;
        include) DUDU_INCLUDE=$3 ;;
        exclude) DUDU_EXCLUDE=$3 ;;
        keep)
          case "$3" in ''|*[!0-9]*|0) die "$(t "keep must be a number of backups, 1 or more")" ;; esac
          DUDU_KEEP=$3 ;;
        encrypt)
          case "$3" in
            on) config_encrypt_on || exit 1 ;;
            off) DUDU_ENCRYPT=off; crypto_forget_password ;;
            *) die "$(t "Usage: %s" "dudu config set encrypt on|off")" ;;
          esac ;;
        language)
          config_set_language "$3" || die "$(t "Unknown language: %s (use auto, en, pt-BR or es)" "$3")"
          ok "$(t "Language: %s" "$(config_language_label)")"
          return 0 ;;
        rclone_remote) DUDU_RCLONE_REMOTE=$3 ;;
        *) die "$(t "Unknown key: %s" "$2")" ;;
      esac
      config_save
      ok "$2 = $3"
      ;;
    "")
      if [ -t 0 ] && [ -t 1 ]; then
        config_menu
      else
        config_show
      fi
      ;;
    *) die "$(t "Usage: %s" "dudu config [show|gdrive|set <key> <value>]")" ;;
  esac
}
