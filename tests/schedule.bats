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
  cat > "$BATS_TEST_TMPDIR/bin/schtasks" <<SH
#!/bin/sh
echo "schtasks \$* NOCONV=\$MSYS_NO_PATHCONV" >> "$BATS_TEST_TMPDIR/calls"
case "\$1" in
  /Create) touch "$BATS_TEST_TMPDIR/task" ;;
  /Delete) rm -f "$BATS_TEST_TMPDIR/task" ;;
  /Query) [ -f "$BATS_TEST_TMPDIR/task" ] || exit 1
          printf '<Task>\r\n<StartBoundary>2026-10-20T06:45:00</StartBoundary>\r\n</Task>\r\n' ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/schtasks"
  DUDU_ROOT="/c/Users/O'Brien/dudu"
  cmd_schedule on 6:45 < /dev/null
  grep -q '^schtasks /Create /F /SC DAILY /TN dudu backup /ST 06:45 /TR wscript.exe "C:.*scheduled-backup.vbs" NOCONV=1$' "$BATS_TEST_TMPDIR/calls"
  grep -qF -- "-lc \"\"'/c/Users/O'\\''Brien/dudu/dudu' backup --scheduled\"\"\", 0, False" "$(schedule_vbs)"
  [ "$(schedule_time)" = "06:45" ]
  cmd_schedule off
  [ ! -f "$(schedule_vbs)" ]
  run ! schedule_time
}
