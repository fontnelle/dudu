#!/usr/bin/env bats
# The real Windows APIs, no stand-ins: registry, Credential Manager, Task Scheduler.
# Runs only on Windows with DUDU_REAL_WINDOWS=1 (CI), since it creates and removes a real
# scheduled task and a real credential.

load helpers

setup() {
  { case "$(uname -s)" in MINGW* | MSYS*) true ;; *) false ;; esac && [ -n "${DUDU_REAL_WINDOWS:-}" ]; } ||
    skip "real Windows only (DUDU_REAL_WINDOWS=1)"
  load_dudu
}

@test "real: Git Bash is detected as windows" {
  [ "$(dudu_os)" = windows ]
  is_windows
}

@test "real: registry, OS name and machine id" {
  [ -n "$(win_reg 'HKLM\SOFTWARE\Microsoft\Cryptography' MachineGuid)" ]
  [[ "$(os_pretty)" == Windows* ]] || false
  [ ${#COMPUTERNAME} -gt 0 ]
  [ -n "$(dudu_host)" ]
  id=$(machine_id)
  [ ${#id} -eq 12 ]
}

@test "real: Windows and Git Bash paths round trip" {
  w=$(win_path "$HOME")
  [[ "$w" == ?:\\* ]] || false
  [ "$(unix_path "$w")" = "$HOME" ]
  [ -d "$(win_localappdata)" ] || [ -n "${LOCALAPPDATA:-}" ]
}

@test "real: the Credential Manager stores, reads and forgets the password" {
  CRYPTO_SERVICE="dudu-ci-test-$$"
  DUDU_PW='pässwörd "with" quotes' crypto_win_vault store
  [ "$(crypto_win_vault read)" = 'pässwörd "with" quotes' ]
  crypto_win_vault forget
  [ -z "$(crypto_win_vault read)" ]
}

@test "real: crypto_store_password uses the Credential Manager, not a file" {
  CRYPTO_SERVICE="dudu-ci-test2-$$"
  crypto_store_password 'another secret 123'
  [ ! -f "$(crypto_key_file)" ]
  [ "$(crypto_stored_password)" = 'another secret 123' ]
  crypto_forget_password
  [ -z "$(crypto_win_vault read)" ]
}

@test "real: dudu schedule creates, reads and removes a Task Scheduler task" {
  SCHEDULE_TASK="dudu ci test $$"
  DUDU_DESTINATION=local
  mkdir -p "$DUDU_CONFIG_DIR"; printf 'destination=local\n' > "$DUDU_CONFIG_FILE"
  cmd_schedule on 07:15 < /dev/null
  schtasks_run /Query /TN "$SCHEDULE_TASK" >/dev/null
  [ "$(schedule_time)" = 07:15 ]
  schtasks_run /Query /TN "$SCHEDULE_TASK" /XML | tr -d '\000' | grep -q 'wscript.exe'
  grep -q -- '--scheduled' "$(schedule_vbs)"
  cmd_schedule off
  run ! schtasks_run /Query /TN "$SCHEDULE_TASK"
  [ ! -f "$(schedule_vbs)" ]
}

@test "real: winget's tables parse" {
  has winget || skip "no winget on this runner"
  winget export -o "$(win_path "$BATS_TEST_TMPDIR/w.json")" --accept-source-agreements --disable-interactivity >/dev/null 2>&1 || true
  run winget_outdated
  [ "$status" -eq 0 ]
  # Every row is "id current latest", with no table leftovers.
  if [ -n "$output" ]; then
    printf '%s\n' "$output" | awk 'NF != 3 { exit 1 }'
  fi
}

@test "real: a scheduled-task notification does not fail" {
  schedule_notify "dudu CI test"
}
