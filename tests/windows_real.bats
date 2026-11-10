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
  xml=$(schtasks_run /Query /TN "$SCHEDULE_TASK" /XML | tr -d '\000\r')
  [[ "$xml" == *wscript.exe* ]] || false
  # A laptop: on battery too, and later when the time was missed.
  [[ "$xml" == *'<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>'* ]] || false
  [[ "$xml" == *'<StartWhenAvailable>true</StartWhenAvailable>'* ]] || false
  tr -d '\000' < "$(schedule_vbs)" | grep -q -- '--scheduled'
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

@test "real: Documents is a folder that exists" {
  # From the real profile folder (USERPROFILE), not the test's HOME.
  d=$(win_documents)
  [ -d "$d" ]
  case "$d" in /*) ;; *) false ;; esac
}

@test "real: the PATH refresh keeps Windows' own folders and adds new ones" {
  # Only what is needed to ask Windows: its own folders must come back from the registry.
  PATH="/usr/bin:/bin:$(dirname "$(command -v powershell.exe)")"
  run ! has reg
  win_refresh_path
  printf '%s' "$PATH" | tr ':' '\n' | grep -qix '/c/windows/system32'
  has reg
}

@test "real: an administrator terminal is told from a plain one" {
  # GitHub's runners are administrators.
  win_is_admin
}

@test "real: a pasted Windows folder becomes a Git Bash path" {
  w=$(cygpath -w "$BATS_TEST_TMPDIR")
  [ "$(folder_path_normalize "\"$w\"")" = "$(cygpath -u "$w")" ]
}

@test "real: the scheduled task takes folders with an accent" {
  SCHEDULE_TASK="dudu ci accent $$"
  DUDU_DESTINATION=local
  mkdir -p "$DUDU_CONFIG_DIR"; printf 'destination=local\n' > "$DUDU_CONFIG_FILE"
  DUDU_CONFIG_DIR="$BATS_TEST_TMPDIR/João Silva/dudu"
  DUDU_ROOT="$BATS_TEST_TMPDIR/João Silva/app"
  cmd_schedule on 07:20 < /dev/null
  # Task Scheduler took the task file, with the .vbs in that folder.
  xml=$(schtasks_run /Query /TN "$SCHEDULE_TASK" /XML | tr -d '\000\r')
  schtasks_run /Delete /F /TN "$SCHEDULE_TASK" >/dev/null
  [[ "$xml" == *'Silva\dudu\scheduled-backup.vbs'* ]] || false
  # wscript reads a .vbs with this mark as UTF-16, accents included.
  [ "$(head -c 2 "$(schedule_vbs)" | od -An -tx1 | tr -d ' \n')" = fffe ]
  vbs=$(tail -c +3 "$(schedule_vbs)" | iconv -f UTF-16LE -t UTF-8)
  [[ "$vbs" == *"João Silva/app/dudu' backup --scheduled"* ]] || false
}

@test "real: Go's folder is a Git Bash path" {
  has go || skip "no go on this runner"
  d=$(go_bin_dir)
  case "$d" in /*) ;; *) false ;; esac
}

@test "real: dudu.cmd runs dudu from cmd and gives its exit code back" {
  w=$(cygpath -w "$DUDU_ROOT/dudu.cmd")
  out=$(MSYS_NO_PATHCONV=1 cmd.exe /c "$w" --version | tr -d '\r')
  [[ "$out" == dudu\ [0-9]* ]] || false
  # An unknown command fails in dudu, and cmd sees it.
  run env MSYS_NO_PATHCONV=1 cmd.exe /c "$w" no-such-command
  [ "$status" -ne 0 ]
}

@test "real: dudu.cmd works from a folder with an accent and a space" {
  d="$BATS_TEST_TMPDIR/João Silva/dudu"
  mkdir -p "$d"
  cp -R "$DUDU_ROOT/dudu" "$DUDU_ROOT/dudu.cmd" "$DUDU_ROOT/lib" "$DUDU_ROOT/bin" "$d/"
  out=$(MSYS_NO_PATHCONV=1 cmd.exe /c "$(cygpath -w "$d/dudu.cmd")" --version | tr -d '\r')
  [[ "$out" == dudu\ [0-9]* ]] || false
}

@test "real: dudu doctor finds nothing that keeps dudu from working" {
  DUDU_NO_UPDATE_CHECK=1
  DUDU_DESTINATION=local
  mkdir -p "$DUDU_CONFIG_DIR"; printf 'destination=local\n' > "$DUDU_CONFIG_FILE"
  run cmd_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Windows Credential Manager"* ]] || false
  [[ "$output" == *"dudu is ready to use"* ]] || false
}

@test "real: the Credential Manager probe leaves nothing behind" {
  doctor_vault
  CRYPTO_SERVICE="dudu-doctor-$$"
  [ -z "$(crypto_win_vault read)" ]
}

@test "real: OneDrive's folder comes from Windows, as a Git Bash path" {
  d="$BATS_TEST_TMPDIR/One Drive"
  mkdir -p "$d"
  OneDriveConsumer="" OneDriveCommercial="" ONEDRIVE=""
  OneDrive=$(cygpath -w "$d")
  onedrive_available
  [ "$(onedrive_root)" = "$(cygpath -u "$OneDrive")/dudu" ]
}
