#!/usr/bin/env bats
# Several destinations at once: each backup goes to all of them, restore takes the newest.

load helpers

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
  export NO_COLOR=1 DUDU_NO_SPINNER=1 DUDU_NO_UPDATE_CHECK=1 ZSH=""
  mkdir -p "$HOME/.config/dudu"
  printf '[user]\n\tname = Dudu\n' > "$HOME/.gitconfig"
  A="$BATS_TEST_TMPDIR/local"
  B="$BATS_TEST_TMPDIR/drive"
}

configure() { # <destinations>
  printf 'destination=%s\npath=%s\ngdrive_path=%s\n' "$1" "$A" "$B" > "$HOME/.config/dudu/config"
}

@test "a backup is saved to every destination" {
  configure local,gdrive
  run dudu backup --only git
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ Backup complete"* ]] || false
  [[ "$output" == *"Local folder"* && "$output" == *"Google Drive"* ]] || false
  [ -f "$A/$(ls "$A")/$(cat "$A"/*/latest)/manifest.json" ]
  [ -f "$B/$(ls "$B")/$(cat "$B"/*/latest)/manifest.json" ]
}

@test "an unavailable destination is reported and the others still get the backup" {
  configure local,icloud
  run dudu backup --only git
  [ "$status" -eq 2 ]
  [[ "$output" == *"Backup partly saved"* && "$output" == *"1 of 2 saved"* ]] || false
  [[ "$output" == *"not available on this machine"* ]] || false
  [ -f "$A/$(ls "$A")/$(cat "$A"/*/latest)/manifest.json" ]
}

@test "restore and status use the newest backup across destinations" {
  configure local
  dudu backup --only git
  sleep 1
  printf '[user]\n\tname = Newer\n' > "$HOME/.gitconfig"
  configure gdrive
  dudu backup --only git
  configure local,gdrive
  echo changed > "$HOME/.gitconfig"
  run dudu restore --only git --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"From Google Drive"* ]] || false
  grep -q 'name = Newer' "$HOME/.gitconfig"
}

@test "config set destination validates every item" {
  configure local
  run dudu config set destination local,dropbox
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown destination: dropbox"* ]] || false
  run dudu config set destination local,notes
  [ "$status" -eq 0 ]
  grep -q '^destination=local,notes$' "$HOME/.config/dudu/config"
}

@test "a 0.1.0 config with gdrive in path= keeps working" {
  printf 'destination=gdrive\npath=%s\n' "$B" > "$HOME/.config/dudu/config"
  run dudu backup --only git
  [ "$status" -eq 0 ]
  [ -f "$B/$(ls "$B")/latest" ]
}
