#!/usr/bin/env bash
# Scrollable multi-select list with groups, in pure bash (works on bash 3.2).
#
# Input arrays (indexed, same length):
#   CL_KIND[i]    "g" for a group header, "i" for an item (items belong to the group above)
#   CL_LABEL[i]   text shown
#   CL_DETAIL[i]  gray text after the label
#   CL_ON[i]      1 when checked (items only)
#   CL_LOCKED[i]  optional, 1 = cannot be checked (shown dimmed)
# Optional: CL_FLAT=1 (no groups, no indent), CL_ACTION (Enter label, default "Update").
# checklist_select <title> returns 0 on Enter (CL_ON holds the choice), 1 on cancel.

checklist_rows() {
  local r
  r=$(stty size </dev/tty 2>/dev/null | awk '{ print $1 }')
  [ -n "$r" ] && [ "$r" -gt 10 ] 2>/dev/null || r=24
  printf '%s' "$r"
}

# Index range of a group's items: sets CL_FROM and CL_TO (inclusive).
checklist_group_range() {
  local i=$(($1 + 1)) n=${#CL_KIND[@]}
  CL_FROM=$i
  while [ $i -lt "$n" ] && [ "${CL_KIND[$i]}" = i ]; do i=$((i + 1)); done
  CL_TO=$((i - 1))
}

# Prints "on/total" of a group's items.
checklist_group_count() {
  local i on=0
  checklist_group_range "$1"
  for ((i = CL_FROM; i <= CL_TO; i++)); do [ "${CL_ON[$i]}" = 1 ] && on=$((on + 1)); done
  printf '%s/%s' "$on" $((CL_TO - CL_FROM + 1))
}

checklist_toggle() {
  local i=$1 j on total value=1
  if [ "${CL_KIND[$i]}" = i ]; then
    [ "${CL_LOCKED[$i]:-}" = 1 ] && return
    if [ "${CL_ON[$i]}" = 1 ]; then CL_ON[i]=0; else CL_ON[i]=1; fi
    return
  fi
  # Not via $(checklist_group_count): CL_FROM/CL_TO must survive, no subshell.
  checklist_group_range "$i"
  on=0
  for ((j = CL_FROM; j <= CL_TO; j++)); do [ "${CL_ON[$j]}" = 1 ] && on=$((on + 1)); done
  total=$((CL_TO - CL_FROM + 1))
  [ "$on" -eq "$total" ] && value=0
  for ((j = CL_FROM; j <= CL_TO; j++)); do [ "${CL_LOCKED[$j]:-}" = 1 ] || CL_ON[j]=$value; done
}

checklist_toggle_all() {
  local i n=${#CL_KIND[@]} value=0
  for ((i = 0; i < n; i++)); do
    [ "${CL_KIND[$i]}" = i ] && [ "${CL_LOCKED[$i]:-}" != 1 ] && [ "${CL_ON[$i]}" != 1 ] && { value=1; break; }
  done
  for ((i = 0; i < n; i++)); do
    [ "${CL_KIND[$i]}" = i ] && [ "${CL_LOCKED[$i]:-}" != 1 ] && CL_ON[i]=$value
  done
}

checklist_selected_count() {
  local i n=${#CL_KIND[@]} c=0
  for ((i = 0; i < n; i++)); do [ "${CL_KIND[$i]}" = i ] && [ "${CL_ON[$i]}" = 1 ] && c=$((c + 1)); done
  printf '%s' "$c"
}

checklist_draw_row() { # <index> <is cursor>
  local i=$1 box count on total pointer="  " color=""
  [ "$2" = 1 ] && { pointer="${CYAN}➤${NC} "; color=$CYAN; }
  if [ "${CL_KIND[$i]}" = g ]; then
    count=$(checklist_group_count "$i")
    on=${count%/*}
    total=${count#*/}
    if [ "$on" -eq 0 ]; then box="[ ]"
    elif [ "$on" -eq "$total" ]; then box="${GREEN}[✓]${NC}"
    else box="${YELLOW}[–]${NC}"
    fi
    printf '\033[2K%s%s %s%s%-12s%s %s%s selected%s\n' "$pointer" "$box" "$BOLD" "$color" "${CL_LABEL[$i]}" "$NC" "$GRAY" "$count" "$NC"
  else
    local indent="    " width=26
    [ -n "${CL_FLAT:-}" ] && { indent=""; width=16; }
    if [ "${CL_LOCKED[$i]:-}" = 1 ]; then
      printf '\033[2K%s%s%s[ ] %-*s %s%s\n' "$pointer" "$indent" "$GRAY" "$width" "${CL_LABEL[$i]}" "${CL_DETAIL[$i]}" "$NC"
      return
    fi
    if [ "${CL_ON[$i]}" = 1 ]; then box="${GREEN}[✓]${NC}"; else box="[ ]"; fi
    printf '\033[2K%s%s%s %s%-*s%s %s%s%s\n' "$pointer" "$indent" "$box" "$color" "$width" "${CL_LABEL[$i]}" "$NC" "$GRAY" "${CL_DETAIL[$i]}" "$NC"
  fi
}

checklist_select() { # <title>
  local title=$1 n=${#CL_KIND[@]} cur=0 top=0 view rows i key last
  [ "$n" -gt 0 ] || return 1

  hide_cursor
  clear_screen
  while true; do
    rows=$(checklist_rows)
    view=$((rows - 6))
    [ $view -lt 3 ] && view=3
    # Keep the cursor inside the visible window.
    [ $cur -lt $top ] && top=$cur
    [ $cur -ge $((top + view)) ] && top=$((cur - view + 1))
    last=$((top + view - 1))
    [ $last -ge "$n" ] && last=$((n - 1))

    printf '\033[H\033[2K%s%s%s\n' "$BOLD" "$title" "$NC"
    if [ $top -gt 0 ]; then printf '\033[2K%s  ↑ %d more%s\n' "$GRAY" "$top" "$NC"; else printf '\033[2K\n'; fi
    for ((i = top; i <= last; i++)); do
      if [ $i -eq $cur ]; then checklist_draw_row "$i" 1; else checklist_draw_row "$i" 0; fi
    done
    if [ $last -lt $((n - 1)) ]; then
      printf '\033[2K%s  ↓ %d more%s\n' "$GRAY" $((n - 1 - last)) "$NC"
    else
      printf '\033[2K\n'
    fi
    printf '\033[2K%s↑↓ Move · Space Select · A All · Enter %s · Q Cancel%s   %s%s selected%s\033[J' \
      "$GRAY" "${CL_ACTION:-Update}" "$NC" "$GREEN" "$(checklist_selected_count)" "$NC"

    key=$(read_key)
    case "$key" in
      UP|CHAR:k) [ $cur -gt 0 ] && cur=$((cur - 1)) ;;
      DOWN|CHAR:j) [ $cur -lt $((n - 1)) ] && cur=$((cur + 1)) ;;
      "CHAR: "|CHAR:x) checklist_toggle "$cur" ;;
      CHAR:a|CHAR:A) checklist_toggle_all ;;
      ENTER) break ;;
      QUIT|ESC|CHAR:q|CHAR:Q) show_cursor; clear_screen; return 1 ;;
    esac
  done
  show_cursor
  clear_screen
  return 0
}
