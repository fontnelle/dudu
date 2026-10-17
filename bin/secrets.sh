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

  title "Secrets on $(dudu_host)"
  dim "Masked or left out of every backup: their values never leave this machine"
  echo
  collect_all "$work/scan" quiet
  secrets_report_skipped
  ok "Checked this machine: $(echo "$COLLECTED" | wc -w | tr -d ' ') tools"

  n=$(sort -u "$DUDU_REDACT_LOG" | grep -c .)
  if [ "$n" -gt 0 ]; then
    section "Keys in config files" "masked in every backup"
    secrets_list_found "$DUDU_REDACT_LOG" 0 2
    section_done "$n key$([ "$n" -gt 1 ] && echo s) · fill them in again on a new machine"
  fi
  k=$(sort -u "$DUDU_SKIP_LOG" | grep -c .)
  if [ "$k" -gt 0 ]; then
    section "Key files" "kept on this machine"
    sort -u "$DUDU_SKIP_LOG" | while IFS= read -r f; do
      printf '  %s●%s %-28s %s%s%s\n' "$GREEN" "$NC" "$(secret_kind "$f")" "$GRAY" "$f" "$NC"
    done
    section_done "$k file$([ "$k" -gt 1 ] && echo s) · copy them to the new machine yourself"
  fi

  movable="$work/movable"
  if [ "$n" -gt 0 ]; then secrets_movable "$DUDU_REDACT_LOG" > "$movable"; else : > "$movable"; fi
  m=$(grep -c . "$movable")
  echo
  if [ "$m" -gt 0 ]; then
    printf '%s%s⚠ %d key%s can move out of your dotfiles%s\n' "$YELLOW" "$BOLD" "$m" "$([ "$m" -gt 1 ] && echo s)" "$NC"
    dim "  To $(tilde "$DUDU_SECRETS_FILE"), never backed up. Your shell loads it from the same spot."
    grep -q '^~/.npmrc:' "$movable" &&
      dim "  npm tokens become \${NPM_TOKEN} in ~/.npmrc, which npm reads from your shell."
    if [ -n "${DUDU_DRY_RUN:-}" ]; then
      secrets_move "$movable"
    elif [ -t 0 ] && [ -t 1 ]; then
      echo
      if confirm "Move $([ "$m" -gt 1 ] && echo them || echo it) to $(tilde "$DUDU_SECRETS_FILE")?"; then
        echo
        dudu_lock || return 1
        secrets_move "$movable"
        dim "    Delete the .dudu-bak once you have checked, it still has the key."
      fi
    fi
  elif [ "$n" -gt 0 ]; then
    printf '%s%s✓ Your keys are masked in every backup%s\n' "$GREEN" "$BOLD" "$NC"
  else
    printf '%s%s✓ No keys in your config files%s\n' "$GREEN" "$BOLD" "$NC"
  fi
  rm -rf "$work"
  return 0
}
