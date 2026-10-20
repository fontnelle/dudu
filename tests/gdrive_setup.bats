#!/usr/bin/env bats
# dudu config gdrive: the four steps, against a fake rclone that keeps its state in files.
# shellcheck disable=SC2317,SC2329 # the helpers are called by bats

load helpers

setup() {
  load_dudu
  FAKE="$BATS_TEST_TMPDIR/fake"
  mkdir -p "$FAKE" "$BATS_TEST_TMPDIR/bin"
  : > "$FAKE/remotes"
  printf '[x]\n' > "$FAKE/rclone.conf"
  chmod 644 "$FAKE/rclone.conf"
  cat > "$BATS_TEST_TMPDIR/bin/rclone" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$1 ${2:-}" in
  "version "*) echo "rclone v1.68.0" ;;
  "listremotes "*) cat "$FAKE/remotes" ;;
  "config create")
    echo "$3:" >> "$FAKE/remotes"
    { echo "[$3]"; echo "type = $4"; shift 4; for kv in "$@"; do echo "${kv%%=*} = ${kv#*=}"; done; } > "$FAKE/conf-$3" ;;
  "config show") cat "$FAKE/conf-$3" 2>/dev/null ;;
  "config delete") grep -vxF "$3:" "$FAKE/remotes" > "$FAKE/r" || true; mv "$FAKE/r" "$FAKE/remotes"; rm -f "$FAKE/conf-$3" ;;
  "config file") echo "Configuration file is stored at:"; echo "$FAKE/rclone.conf" ;;
  "config reconnect") ;;
  "about "*) exit "${FAKE_ABOUT_RC:-0}" ;;
  "rcat "*) cat > "$FAKE/obj" ;;
  "cat "*) if [ -n "${FAKE_BAD_CAT:-}" ]; then echo tampered; else cat "$FAKE/obj"; fi ;;
  "deletefile "*) rm -f "$FAKE/obj" ;;
  "lsf "*) printf '%b' "${FAKE_HOSTS:-}" ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/rclone"
  export FAKE PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  DUDU_ENCRYPT=off
}

# gdrive_setup, then the remote it chose.
setup_and_show() {
  gdrive_setup && echo "remote=$DUDU_RCLONE_REMOTE"
}

@test "gdrive_folder_id takes only Google Drive folder links" {
  [ "$(gdrive_folder_id https://drive.google.com/drive/folders/1AbCdEfGhIjK_-xyz)" = 1AbCdEfGhIjK_-xyz ]
  [ "$(gdrive_folder_id 'https://drive.google.com/drive/u/0/folders/1AbCdEfGhIjK?usp=sharing')" = 1AbCdEfGhIjK ]
  run ! gdrive_folder_id http://drive.google.com/drive/folders/1AbCdEfGhIjK
  run ! gdrive_folder_id https://drive.google.com.evil.io/drive/folders/1AbCdEfGhIjK
  run ! gdrive_folder_id https://evil.io/https://drive.google.com/drive/folders/1AbCdEfGhIjK
  run ! gdrive_folder_id https://docs.google.com/document/d/1AbCdEfGhIjK/edit
  run ! gdrive_folder_id https://bit.ly/3xYz
  run ! gdrive_folder_id https://drive.google.com/drive/folders/short
  run ! gdrive_folder_id 'https://drive.google.com/drive/folders/1AbCdEfGhIjK;rm'
  run ! gdrive_folder_id 'https://drive.google.com/drive/folders/1AbCdEfGhIjK x'
  run ! gdrive_folder_id ''
}

@test "rclone_join does not leave a slash after the remote name" {
  [ "$(rclone_join dudu-gdrive: host)" = dudu-gdrive:host ]
  [ "$(rclone_join dudu-gdrive:dudu host)" = dudu-gdrive:dudu/host ]
  [ "$(rclone_join dudu-gdrive:dudu/ host)" = dudu-gdrive:dudu/host ]
}

@test "Enter: a dudu folder with access only to what dudu creates" {
  run setup_and_show <<< $'\nn'
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote=dudu-gdrive:dudu"* ]] || false
  grep -q 'config create dudu-gdrive drive scope=drive.file$' "$FAKE/calls"
  grep -q 'rcat dudu-gdrive:dudu/.dudu-check' "$FAKE/calls"
  grep -q 'deletefile dudu-gdrive:dudu/.dudu-check' "$FAKE/calls"
}

@test "a pasted link: that folder, with access to the Drive" {
  run setup_and_show <<< $'https://drive.google.com/drive/folders/1AbCdEfGhIjK\nn'
  [ "$status" -eq 0 ]
  grep -qx 'remote=dudu-gdrive:' <<< "$output"
  grep -q 'config create dudu-gdrive drive scope=drive root_folder_id=1AbCdEfGhIjK' "$FAKE/calls"
  grep -q 'rcat dudu-gdrive:.dudu-check' "$FAKE/calls"
}

@test "a wrong link is asked again, three times at most" {
  run setup_and_show <<< $'https://bit.ly/x\nhttps://evil.io/a\nnope'
  [ "$status" -ne 0 ]
  [ "$(grep -c 'Not a Google Drive folder link' <<< "$output")" -eq 3 ]
  run ! grep -q 'config create' "$FAKE/calls"
}

@test "a remote for another folder is made again" {
  run setup_and_show <<< $'\nn'
  run setup_and_show <<< $'https://drive.google.com/drive/folders/1AbCdEfGhIjK\nn'
  [ "$status" -eq 0 ]
  grep -q 'config delete dudu-gdrive' "$FAKE/calls"
  [ "$(grep -c 'config create' "$FAKE/calls")" -eq 2 ]
}

@test "the same folder again keeps the sign-in" {
  run setup_and_show <<< $'\nn'
  run setup_and_show <<< $'\nn'
  [ "$status" -eq 0 ]
  [ "$(grep -c 'config create' "$FAKE/calls")" -eq 1 ]
}

@test "a test file that does not read back stops the setup" {
  export FAKE_BAD_CAT=1
  run setup_and_show <<< $'\nn'
  [ "$status" -ne 0 ]
  [[ "$output" != *"remote="* ]] || false
  [[ "$output" == *"could not save and read back a test file"* ]] || false
  grep -q 'deletefile' "$FAKE/calls"
}

@test "Google not answering stops the setup" {
  export FAKE_ABOUT_RC=1
  run setup_and_show <<< $'\nn'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Google Drive did not answer"* ]] || false
}

@test "rclone's config, which holds the Google token, ends up readable only by the user" {
  run setup_and_show <<< $'\nn'
  [ "$status" -eq 0 ]
  [ -n "$(find "$FAKE/rclone.conf" -perm 600)" ]
  [[ "$output" == *"only you can read"* ]] || false
}

@test "encryption off is pointed out, and the machines already there are listed" {
  export FAKE_HOSTS='MacBook-Pro/\nother-pc/\n'
  run setup_and_show <<< $'\nn'
  [[ "$output" == *"Encryption"*"off"* ]] || false
  [[ "$output" == *"MacBook-Pro, other-pc"* ]] || false
}

@test "dudu config gdrive adds Google Drive to the destinations" {
  mkdir -p "$DUDU_CONFIG_DIR"
  printf 'destination=local\npath=%s\n' "$BATS_TEST_TMPDIR/b" > "$DUDU_CONFIG_FILE"
  run dudu config gdrive <<< $'\nn'
  [ "$status" -eq 0 ]
  grep -qx 'destination=local,gdrive' "$DUDU_CONFIG_FILE"
  grep -qx 'rclone_remote=dudu-gdrive:dudu' "$DUDU_CONFIG_FILE"
}
