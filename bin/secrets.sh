#!/usr/bin/env bash
# dudu secrets: lists the keys found in the config files dudu backs up, and moves the ones
# in shell files to ~/.secrets, a file that stays on this machine.

cmd_secrets() {
  parse_common_opts "$@"
  config_load
  read_only_mode
  local work movable n m k
  work=$(mktemp -d)
  tmp_register "$work"
  DUDU_REDACT_LOG="$work/redacted"
  DUDU_SKIP_LOG="$work/skipped"
  : > "$DUDU_REDACT_LOG"
  : > "$DUDU_SKIP_LOG"

  title "$(t "Secrets on %s" "$(dudu_host)")"
  dim "$(t "Masked or left out of every backup: their values never leave this machine")"
  echo
  collect_all "$work/scan" quiet
  secrets_report_skipped
  ok "$(t "Checked this machine: %s tools" "$(echo "$COLLECTED" | wc -w | tr -d ' ')")"

  n=$(sort -u "$DUDU_REDACT_LOG" | grep -c .)
  if [ "$n" -gt 0 ]; then
    section "$(t "Keys in config files")" "$(t "masked in every backup")"
    secrets_list_found "$DUDU_REDACT_LOG" 0 2
    section_done "$(tn "%d key · fill them in again on a new machine" "%d keys · fill them in again on a new machine" "$n")"
  fi
  k=$(sort -u "$DUDU_SKIP_LOG" | grep -c .)
  if [ "$k" -gt 0 ]; then
    section "$(t "Key files")" "$(t "kept on this machine")"
    sort -u "$DUDU_SKIP_LOG" | while IFS= read -r f; do
      printf '  %s●%s %s %s%s%s\n' "$GREEN" "$NC" "$(pad "$(secret_kind "$f")" 28)" "$GRAY" "$f" "$NC"
    done
    section_done "$(tn "%d file · copy them to the new machine yourself" "%d files · copy them to the new machine yourself" "$k")"
  fi

  movable="$work/movable"
  if [ "$n" -gt 0 ]; then secrets_movable "$DUDU_REDACT_LOG" > "$movable"; else : > "$movable"; fi
  m=$(grep -c . "$movable")
  echo
  if [ "$m" -gt 0 ]; then
    printf '%s%s⚠ %s%s\n' "$YELLOW" "$BOLD" "$(tn "%d key can move out of your dotfiles" "%d keys can move out of your dotfiles" "$m")" "$NC"
    dim "  $(t "To %s, never backed up. Your shell loads it from the same spot." "$(tilde "$DUDU_SECRETS_FILE")")"
    grep -q '^~/.npmrc:' "$movable" &&
      dim "  $(t "npm tokens become %s in ~/.npmrc, which npm reads from your shell." "\${NPM_TOKEN}")"
    if [ -n "${DUDU_DRY_RUN:-}" ]; then
      secrets_move "$movable"
    elif [ -t 0 ] && [ -t 1 ]; then
      echo
      local where
      where=$(tilde "$DUDU_SECRETS_FILE")
      if confirm "$(if [ "$m" -gt 1 ]; then t "Move them to %s?" "$where"; else t "Move it to %s?" "$where"; fi)"; then
        echo
        dudu_lock || return 1
        secrets_move "$movable"
        dim "    $(t "Delete the .dudu-bak once you have checked, it still has the key.")"
      fi
    fi
  elif [ "$n" -gt 0 ]; then
    printf '%s%s✓ %s%s\n' "$GREEN" "$BOLD" "$(t "Your keys are masked in every backup")" "$NC"
  else
    printf '%s%s✓ %s%s\n' "$GREEN" "$BOLD" "$(t "No keys in your config files")" "$NC"
  fi
  rm -rf "$work"
  return 0
}
