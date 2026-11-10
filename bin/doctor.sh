#!/usr/bin/env bash
# dudu doctor: checks what dudu needs on this machine, and says in plain words what to do
# about each thing that is missing. Returns 1 when something keeps dudu from working.

DOCTOR_BAD=0

doctor_row() { # <ok|warn|fail|skip> <name> <detail>
  [ "$1" = fail ] && DOCTOR_BAD=$((DOCTOR_BAD + 1))
  step_row "$1" "$(pad "$2" 16)" "$3"
}

# The Credential Manager really keeps a password: one is stored, read back and removed.
doctor_vault() {
  (
    CRYPTO_SERVICE="dudu-doctor-$$"
    DUDU_PW=probe crypto_win_vault store >/dev/null || exit 1
    [ "$(crypto_win_vault read)" = probe ] || exit 1
    crypto_win_vault forget >/dev/null
    exit 0
  )
}

doctor_windows() {
  local pms="" p
  for p in winget scoop choco; do has "$p" && pms="$pms, $p"; done
  if [ -n "$pms" ]; then doctor_row ok "$(t "Packages")" "${pms#, }"
  else doctor_row warn "$(t "Packages")" "$(t "no winget, scoop or Chocolatey: winget comes with App Installer, in the Microsoft Store")"; fi

  if win_is_admin; then doctor_row ok "$(t "Administrator")" "$(t "yes")"
  else doctor_row skip "$(t "Administrator")" "$(t "no (only Chocolatey needs it)")"; fi

  if [ -f "$DUDU_ROOT/dudu.cmd" ] && MSYS_NO_PATHCONV=1 cmd.exe /c where dudu.cmd >/dev/null 2>&1; then
    doctor_row ok "PowerShell, cmd" "$(t "the dudu command is in the PATH")"
  else
    doctor_row warn "PowerShell, cmd" "$(t "the dudu command is not in the PATH: run the installer again (see %s)" "$DUDU_HOMEPAGE")"
  fi

  if legacy_console; then
    doctor_row warn "$(t "Terminal")" "$(t "the old Windows console: some symbols may show as boxes. Use Windows Terminal, or dudu from the Start menu")"
  else
    doctor_row ok "$(t "Terminal")" "${WT_SESSION:+Windows Terminal}${TERM_PROGRAM:-}"
  fi

  if doctor_vault; then doctor_row ok "$(t "Password store")" "$(t "Windows Credential Manager")"
  else doctor_row warn "$(t "Password store")" "$(t "the Windows Credential Manager does not answer: a backup password would be kept in a file")"; fi
}

doctor_destinations() {
  local d root
  if [ -z "$DUDU_DESTINATION" ]; then
    doctor_row warn "$(t "Destination")" "$(t "none yet: run %s" "dudu config")"
    return
  fi
  for d in $(dest_list); do
    if ! "${d}_available" 2>/dev/null; then
      doctor_row fail "$(dest_label "$d")" "$(t "not available on this machine")"
      continue
    fi
    # Only looked at: a folder that is not there yet is made by the first backup.
    root=$(dest_folder_root "$d" 2>/dev/null)
    if [ -n "$root" ] && [ -d "$root" ] && [ ! -w "$root" ]; then
      doctor_row fail "$(dest_label "$d")" "$(t "cannot write to %s" "$(tilde "$root")")"
    else
      doctor_row ok "$(dest_label "$d")" "$(tilde "$("${d}_where" 2>/dev/null)")"
    fi
  done
}

cmd_doctor() {
  local tool missing="" tm latest
  DOCTOR_BAD=0
  config_load
  printf '%s%s%s\n' "$BOLD" "$(t "Checking what dudu needs on this machine")" "$NC"
  doctor_row ok dudu "$VERSION · $(tilde "$DUDU_ROOT")"
  doctor_row ok "$(t "System")" "$(os_pretty) · bash ${BASH_VERSION%%(*}"
  for tool in curl tar openssl awk; do has "$tool" || missing="$missing, $tool"; done
  if [ -z "$missing" ]; then doctor_row ok "$(t "Tools")" "curl, tar, openssl"
  elif is_windows; then doctor_row fail "$(t "Tools")" "$(t "missing: %s. Install Git for Windows again, it brings them" "${missing#, }")"
  else doctor_row fail "$(t "Tools")" "$(t "missing: %s" "${missing#, }")"; fi

  is_windows && doctor_windows
  doctor_destinations

  if [ "$DUDU_ENCRYPT" = on ]; then
    if [ -n "$(crypto_stored_password)" ]; then doctor_row ok "$(t "Encryption")" "$(t "on, password stored")"
    else doctor_row warn "$(t "Encryption")" "$(t "on, but no password is stored: scheduled backups cannot run")"; fi
  else
    doctor_row skip "$(t "Encryption")" "$(t "off")"
  fi
  if tm=$(schedule_time) && [ -n "$tm" ]; then doctor_row ok "$(t "Schedule")" "$(t "daily at %s" "$tm")"
  else doctor_row skip "$(t "Schedule")" "$(t "off (turn it on with %s)" "dudu schedule on")"; fi
  if latest=$(update_available); then doctor_row warn "$(t "Update")" "$(t "%s is out: %s" "$latest" "$(update_command)")"; fi

  echo
  if [ "$DOCTOR_BAD" -gt 0 ]; then
    printf '%s%s✗ %s%s\n' "$RED" "$BOLD" "$(tn "%d problem keeps dudu from working" "%d problems keep dudu from working" "$DOCTOR_BAD")" "$NC"
    return 1
  fi
  printf '%s%s✓ %s%s\n' "$GREEN" "$BOLD" "$(t "dudu is ready to use")" "$NC"
}
