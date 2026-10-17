#!/usr/bin/env bash
# Arrow-key menu in pure bash (works on bash 3.2).

# Prints one of: UP, DOWN, ENTER, ESC, QUIT, CHAR:<c>
read_key() {
  local k rest
  IFS= read -rsn1 k || { echo QUIT; return; }
  case "$k" in
    $'\033')
      IFS= read -rsn2 -t 1 rest
      case "$rest" in
        '[A'|'OA') echo UP ;;
        '[B'|'OB') echo DOWN ;;
        '') echo ESC ;;
        *) echo OTHER ;;
      esac
      ;;
    ''|$'\n'|$'\r') echo ENTER ;;
    *) echo "CHAR:$k" ;;
  esac
}

# menu_select <header_fn> "Label|Description" ...
# Sets MENU_CHOICE to the chosen index. A key listed in MENU_HOTKEYS sets MENU_CHOICE=-1
# and MENU_KEY to that key. Returns 1 when the user quits.
# Optional globals: MENU_FOOTER, MENU_HOTKEYS.
menu_select() {
  local header_fn=$1
  shift
  local count=$# sel=0 key i label desc item width=0
  local footer=${MENU_FOOTER:-"↑↓  |  Enter  |  $(t "Q Back")"}
  # Label column as wide as the longest label, plus a gap before the description.
  for item in "$@"; do
    label=${item%%|*}
    [ "${#label}" -gt "$width" ] && width=${#label}
  done
  width=$((width + 3))
  MENU_CHOICE=""
  MENU_KEY=""

  hide_cursor
  clear_screen
  while true; do
    printf '\033[H'
    [ -n "$header_fn" ] && "$header_fn"
    i=0
    for item in "$@"; do
      label=${item%%|*}
      desc=${item#*|}
      [ "$desc" = "$item" ] && desc=""
      printf '\033[2K'
      if [ $i -eq $sel ]; then
        printf '%s➤ %d. %s%*s%s%s\n' "$CYAN" $((i + 1)) "$label" $((width - ${#label})) '' "$desc" "$NC"
      else
        printf '  %d. %s%*s%s%s%s\n' $((i + 1)) "$label" $((width - ${#label})) '' "$GRAY" "$desc" "$NC"
      fi
      i=$((i + 1))
    done
    printf '\033[2K\n\033[2K%s%s%s\033[J' "$GRAY" "$footer" "$NC"

    key=$(read_key)
    case "$key" in
      UP|CHAR:k) sel=$(( (sel - 1 + count) % count )) ;;
      DOWN|CHAR:j) sel=$(( (sel + 1) % count )) ;;
      ENTER) MENU_CHOICE=$sel; break ;;
      QUIT|ESC|CHAR:q|CHAR:Q) show_cursor; echo; return 1 ;;
      CHAR:[1-9])
        i=${key#CHAR:}
        if [ "$i" -le "$count" ]; then MENU_CHOICE=$((i - 1)); break; fi
        ;;
      CHAR:*)
        i=$(printf '%s' "${key#CHAR:}" | tr '[:upper:]' '[:lower:]')
        case ",${MENU_HOTKEYS:-}," in
          *",$i,"*) MENU_CHOICE=-1; MENU_KEY=$i; break ;;
        esac
        ;;
    esac
  done
  show_cursor
  echo
  return 0
}
