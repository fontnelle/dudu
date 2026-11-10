#!/usr/bin/env bats
# dudu schedule writes a launchd agent (macOS) or a systemd user timer (Linux). launchctl and
# systemctl are stand-ins here, so nothing is really scheduled.

load helpers

setup() {
  load_dudu
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for t in launchctl systemctl; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$t" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/$t"
    chmod +x "$BATS_TEST_TMPDIR/bin/$t"
  done
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  DUDU_DESTINATION=local
  mkdir -p "$DUDU_CONFIG_DIR"; printf 'destination=local\n' > "$DUDU_CONFIG_FILE"
}

@test "schedule rejects a bad time" {
  run cmd_schedule on 25:00
  [ "$status" -eq 1 ]
}

@test "macOS: a valid launchd agent that runs dudu backup --scheduled" {
  is_macos || skip "macOS only"
  cmd_schedule on 7:05 < /dev/null
  plutil -lint "$(schedule_plist)"
  grep -q -- '--scheduled' "$(schedule_plist)"
  [ "$(schedule_time)" = "07:05" ]
  grep -q "launchctl bootstrap" "$BATS_TEST_TMPDIR/calls"
  cmd_schedule off
  [ ! -f "$(schedule_plist)" ]
  run ! schedule_time
}

@test "Linux: a systemd user timer" {
  # shellcheck disable=SC2317,SC2329
  is_macos() { return 1; }
  # shellcheck disable=SC2317,SC2329
  is_windows() { return 1; }
  cmd_schedule on 23:30 < /dev/null
  grep -q '^OnCalendar=\*-\*-\* 23:30:00$' "$(schedule_unit_dir)/dudu.timer"
  grep -q 'backup --scheduled' "$(schedule_unit_dir)/dudu.service"
  [ "$(schedule_time)" = "23:30" ]
  grep -q "systemctl --user enable --now dudu.timer" "$BATS_TEST_TMPDIR/calls"
  cmd_schedule off
  [ ! -f "$(schedule_unit_dir)/dudu.timer" ]
}

@test "a Homebrew install schedules the path that survives brew upgrade" {
  # shellcheck disable=SC2317,SC2329
  is_macos() { return 1; }
  # shellcheck disable=SC2317,SC2329
  is_windows() { return 1; }
  DUDU_ROOT=/opt/homebrew/Cellar/dudu/0.2.0/libexec
  cmd_schedule on 08:00 < /dev/null
  grep -qF 'ExecStart="/opt/homebrew/opt/dudu/libexec/dudu" backup --scheduled' "$(schedule_unit_dir)/dudu.service"
  run ! grep -q "^ExecStart=.*Cellar" "$(schedule_unit_dir)/dudu.service"
}

@test "encrypted backups need a stored password before scheduling" {
  DUDU_ENCRYPT=on
  printf 'destination=local\nencrypt=on\n' > "$DUDU_CONFIG_FILE"
  crypto_stored_password() { return 1; }
  run cmd_schedule on 12:00
  [ "$status" -eq 1 ]
  [[ "$output" == *"no password is stored"* ]] || false
}

@test "Windows: a Task Scheduler task that starts dudu hidden" {
  # shellcheck disable=SC2317,SC2329
  is_macos() { return 1; }
  # shellcheck disable=SC2317,SC2329
  is_windows() { return 0; }
  # shellcheck disable=SC2317,SC2329
  win_path() { printf 'C:%s' "$1"; }
  # shellcheck disable=SC2317,SC2329
  has() { case "$1" in wscript.exe | conhost.exe | cygpath) return 1 ;; esac; command -v "$1" >/dev/null 2>&1; }
  # The stand-in keeps the task file it is given (UTF-16), as readable text.
  cat > "$BATS_TEST_TMPDIR/bin/schtasks" <<SH
#!/bin/sh
echo "schtasks \$* NOCONV=\$MSYS_NO_PATHCONV" >> "$BATS_TEST_TMPDIR/calls"
case "\$1" in
  /Create) while [ \$# -gt 1 ]; do [ "\$1" = /XML ] && xml=\${2#C:}; shift; done
           head -c 2 "\$xml" | od -An -tx1 | tr -d ' \n' > "$BATS_TEST_TMPDIR/bom"
           tail -c +3 "\$xml" | iconv -f UTF-16LE -t UTF-8 > "$BATS_TEST_TMPDIR/task" ;;
  /Delete) rm -f "$BATS_TEST_TMPDIR/task" ;;
  /Query) [ -f "$BATS_TEST_TMPDIR/task" ] || exit 1
          cat "$BATS_TEST_TMPDIR/task" ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/schtasks"
  DUDU_ROOT="/c/Users/O'Brien/dudu"
  USERNAME=joe USERDOMAIN=PC MSYSTEM=MINGW64
  cmd_schedule on 6:45 < /dev/null
  grep -q '^schtasks /Create /F /TN dudu backup /XML C:.* NOCONV=1$' "$BATS_TEST_TMPDIR/calls"
  task="$BATS_TEST_TMPDIR/task"
  [ "$(cat "$BATS_TEST_TMPDIR/bom")" = fffe ]
  grep -q 'T06:45:00</StartBoundary>' "$task"
  # A laptop: on battery too, and later when the time was missed.
  grep -qF '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' "$task"
  grep -qF '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>' "$task"
  grep -qF '<StartWhenAvailable>true</StartWhenAvailable>' "$task"
  grep -qF '<UserId>PC\joe</UserId>' "$task"
  grep -qF '<Command>wscript.exe</Command>' "$task"
  grep -q '<Arguments>"C:.*scheduled-backup.vbs"</Arguments>' "$task"
  vbs=$(tail -c +3 "$(schedule_vbs)" | iconv -f UTF-16LE -t UTF-8)
  [[ "$vbs" == *"-lc \"\"'/c/Users/O'\\''Brien/dudu/dudu' backup --scheduled\"\"\", 0, False"* ]] || false
  [[ "$vbs" == *'("MSYSTEM") = "MINGW64"'* ]] || false
  [ "$(schedule_time)" = "06:45" ]
  cmd_schedule off
  [ ! -f "$(schedule_vbs)" ]
  run ! schedule_time
}

@test "Windows: without the script host the task runs in a hidden console" {
  # shellcheck disable=SC2317,SC2329
  is_macos() { return 1; }
  # shellcheck disable=SC2317,SC2329
  is_windows() { return 0; }
  # shellcheck disable=SC2317,SC2329
  win_path() { printf 'C:%s' "$1"; }
  # shellcheck disable=SC2317,SC2329
  has() { case "$1" in wscript.exe | cygpath) return 1 ;; conhost.exe) return 0 ;; esac; command -v "$1" >/dev/null 2>&1; }
  out=$(schedule_task_xml 12:30 conhost.exe '--headless "C:\Git\bin\bash.exe" -lc "x & y"')
  [[ "$out" == *'<Command>conhost.exe</Command>'* ]] || false
  [[ "$out" == *'-lc "x &amp; y"</Arguments>'* ]] || false
}
