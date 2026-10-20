#!/usr/bin/env bats
# Folder settings must be full paths: a link or a word pasted there must never become a
# folder relative to wherever dudu runs.

load helpers

setup() {
  load_dudu
  mkdir -p "$DUDU_CONFIG_DIR"
}

@test "folder_path_error accepts full paths and refuses links and relative ones" {
  run ! folder_path_error /Users/me/dudu-backups
  run ! folder_path_error "$HOME/x"
  [[ "$(folder_path_error 'https://drive.google.com/drive/folders/1AbCdEfGhIjK')" == *"Google Drive link"* ]] || false
  [[ "$(folder_path_error 'https://example.com/x')" == *"is a link"* ]] || false
  [[ "$(folder_path_error q)" == *"not a full path"* ]] || false
  [[ "$(folder_path_error 'backups/mac')" == *"not a full path"* ]] || false
}

@test "dudu config set path refuses a link" {
  printf 'destination=local\n' > "$DUDU_CONFIG_FILE"
  run dudu config set path 'https://drive.google.com/drive/folders/1AbCdEfGhIjK'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Google Drive link"* ]] || false
  run ! grep -q 'https' "$DUDU_CONFIG_FILE"
  run dudu config set gdrive_path q
  [ "$status" -ne 0 ]
  run dudu config set path '~/meus-backups'
  [ "$status" -eq 0 ]
  grep -qx "path=$HOME/meus-backups" "$DUDU_CONFIG_FILE"
}

@test "a link or a word already in the config is ignored, with a warning" {
  printf 'destination=local,gdrive\npath=https://drive.google.com/drive/folders/1AbCdEfGhIjK?hl=pt-br\ngdrive_path=q\n' > "$DUDU_CONFIG_FILE"
  run --separate-stderr config_load
  config_load 2>/dev/null
  [ -z "$DUDU_PATH" ]
  [ -z "$DUDU_GDRIVE_PATH" ]
  [ "$(local_root)" = "$HOME/dudu-backups" ]
  # shellcheck disable=SC2154 # $stderr is set by run --separate-stderr
  [[ "$stderr" == *"path="*"Google Drive link"* ]] || false
  [[ "$stderr" == *"gdrive_path="*"not a full path"* ]] || false
}

@test "gdrive_root does not take a relative gdrive_path" {
  DUDU_GDRIVE_PATH=q
  run gdrive_root
  [[ "$output" != q ]] || false
  DUDU_GDRIVE_PATH="$HOME/GDrive/dudu"
  mkdir -p "$HOME/GDrive"
  [ "$(gdrive_root)" = "$HOME/GDrive/dudu" ]
}

@test "folder_save never writes under a relative root" {
  local b="$BATS_TEST_TMPDIR/2026-10-20_120000Z-abcd"
  mkdir -p "$b" && echo x > "$b/manifest.json"
  cd "$BATS_TEST_TMPDIR"
  run folder_save q "$b" Mac-1
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/q" ]
}
