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
  is_macos() { return 1; }
  cmd_schedule on 23:30 < /dev/null
  grep -q '^OnCalendar=\*-\*-\* 23:30:00$' "$(schedule_unit_dir)/dudu.timer"
  grep -q 'backup --scheduled' "$(schedule_unit_dir)/dudu.service"
  [ "$(schedule_time)" = "23:30" ]
  grep -q "systemctl --user enable --now dudu.timer" "$BATS_TEST_TMPDIR/calls"
  cmd_schedule off
  [ ! -f "$(schedule_unit_dir)/dudu.timer" ]
}

@test "encrypted backups need a stored password before scheduling" {
  DUDU_ENCRYPT=on
  printf 'destination=local\nencrypt=on\n' > "$DUDU_CONFIG_FILE"
  crypto_stored_password() { return 1; }
  run cmd_schedule on 12:00
  [ "$status" -eq 1 ]
  [[ "$output" == *"no password is stored"* ]] || false
}
