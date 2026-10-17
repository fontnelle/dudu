#!/usr/bin/env bats
# Encrypted backups: round trip, wrong password, tampering.

load helpers

setup() {
  load_dudu
  has openssl || skip "openssl not installed"
  b="$BATS_TEST_TMPDIR/bundle"
  mkdir -p "$b/shell/home"
  printf '{\n  "host": "test",\n  "created": "2026-01-01T00:00:00Z"\n}\n' > "$b/manifest.json"
  echo 'alias ll="ls"' > "$b/shell/home/.zshrc"
  echo "full restore notes" > "$b/RESTORE.md"
  export DUDU_PASSWORD="correct horse battery"
}

@test "seal leaves only ciphertext, a MAC and a readable manifest" {
  crypto_seal "$b"
  [ "$(ls "$b" | LC_ALL=C sort | tr '\n' ' ')" = "RESTORE.md backup.enc backup.mac manifest.json " ]
  grep -q '"encrypted": true' "$b/manifest.json"
  grep -q '"created": "2026-01-01T00:00:00Z"' "$b/manifest.json"
  run ! grep -rq 'alias ll' "$b"
}

@test "open restores the original bundle" {
  crypto_seal "$b"
  CRYPTO_PW=""
  crypto_open "$b"
  [ "$(cat "$b/shell/home/.zshrc")" = 'alias ll="ls"' ]
  [ "$(cat "$b/RESTORE.md")" = "full restore notes" ]
  [ ! -e "$b/backup.enc" ]
}

@test "a wrong password is refused" {
  crypto_seal "$b"
  CRYPTO_PW=""
  DUDU_PASSWORD="wrong password!" run crypto_open "$b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Wrong password, or the backup was modified"* ]] || false
}

@test "a single changed byte is caught before decrypting" {
  crypto_seal "$b"
  printf 'X' | dd of="$b/backup.enc" bs=1 seek=40 conv=notrunc 2>/dev/null
  CRYPTO_PW=""
  run crypto_open "$b"
  [ "$status" -ne 0 ]
  [ -e "$b/backup.enc" ]
}

@test "a missing or forged MAC file is refused" {
  crypto_seal "$b"
  echo "dudu-mac-v1 ../../x deadbeef" > "$b/backup.mac"
  CRYPTO_PW=""
  run crypto_open "$b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"integrity file is missing or damaged"* ]] || false
}

@test "encrypted backup and restore through the CLI" {
  printf 'destination=local\npath=%s\nencrypt=on\n' "$BATS_TEST_TMPDIR/backups" > "$XDG_CONFIG_HOME/dudu/config" 2>/dev/null ||
    { mkdir -p "$XDG_CONFIG_HOME/dudu"; printf 'destination=local\npath=%s\nencrypt=on\n' "$BATS_TEST_TMPDIR/backups" > "$XDG_CONFIG_HOME/dudu/config"; }
  echo 'alias gs="git status"' > "$HOME/.zshrc"
  DUDU_NO_UPDATE_CHECK=1 ZSH="" run dudu backup --only shell
  [ "$status" -eq 0 ]
  run ! grep -rq 'alias gs' "$BATS_TEST_TMPDIR/backups"
  DUDU_NO_UPDATE_CHECK=1 ZSH="" run dudu restore --dry-run --only shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"= ~/.zshrc"* ]] || false
}
