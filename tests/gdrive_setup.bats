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
  "lsf "*) case "$*" in *--include*) printf '%b' "${FAKE_LATEST:-}" ;; *) printf '%b' "${FAKE_HOSTS:-}" ;; esac ;;
  "lsjson "*) [ -n "${FAKE_NO_ID:-}" ] || echo '{"Path":"x","Name":"x","IsDir":true,"ID":"FOLDERID12345"}' ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/rclone"
  export FAKE PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  DUDU_ENCRYPT=off
  backup_host() { echo Mac-1; }
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

@test "Enter connects the account: dudu-<host> in My Drive, access only to what dudu creates" {
  run setup_and_show <<< $'\nn'
  [ "$status" -eq 0 ]
  grep -qx 'remote=dudu-gdrive:' <<< "$output"
  grep -q "config create dudu-gdrive drive scope=drive.file config_template_file=$DUDU_CONFIG_DIR/google-signin.html$" "$FAKE/calls"
  grep -q 'rcat dudu-gdrive:dudu-Mac-1/.dudu-check' "$FAKE/calls"
  grep -q 'deletefile dudu-gdrive:dudu-Mac-1/.dudu-check' "$FAKE/calls"
  # Where the backups go, as a link to open in the browser.
  [[ "$output" == *"https://drive.google.com/drive/folders/FOLDERID12345"* ]] || false
}

@test "the page after the Google sign-in is dudu's, with both outcomes" {
  run setup_and_show <<< $'\nn'
  local page="$DUDU_CONFIG_DIR/google-signin.html"
  [ -f "$page" ]
  grep -q '{{ if .OK }}' "$page"
  grep -q 'Google Drive connected' "$page"
  grep -q 'dudu sees only the files it creates' "$page"
  grep -q '{{ .Name }}' "$page"
  grep -q 'dudu config gdrive' "$page"
}

@test "1 is the same as Enter" {
  run setup_and_show <<< $'1\nn'
  [ "$status" -eq 0 ]
  grep -q 'scope=drive.file config_template_file=' "$FAKE/calls"
}

@test "2 and a link: that folder, with access to the Drive" {
  run setup_and_show <<< $'2\n https://drive.google.com/drive/folders/1RBB6DaMcICS9hhEKQ2fv9TJZ_1fz_9cm?hl=pt-br \nn'
  [ "$status" -eq 0 ]
  [[ "$output" == *"valid link · folder 1RBB6DaMcICS9hhEKQ2fv9TJZ_1fz_9cm"* ]] || false
  grep -qx 'remote=dudu-gdrive:' <<< "$output"
  grep -q 'config create dudu-gdrive drive scope=drive root_folder_id=1RBB6DaMcICS9hhEKQ2fv9TJZ_1fz_9cm config_template_file=' "$FAKE/calls"
  grep -q 'rcat dudu-gdrive:dudu-Mac-1/.dudu-check' "$FAKE/calls"
}

@test "a wrong link says why, and is asked again three times at most" {
  run setup_and_show <<< $'2\nhttps://drive.google.com/file/d/1AbCdEfGhIjK/view\nhttps://bit.ly/x\nhttp://drive.google.com/drive/folders/1AbCdEfGhIjK'
  [ "$status" -ne 0 ]
  [[ "$output" == *"This is the link of a file"* ]] || false
  [[ "$output" == *"This is not a Google Drive link (bit.ly)"* ]] || false
  [[ "$output" == *"The link starts with https://drive.google.com/"* ]] || false
  run ! grep -q 'config create' "$FAKE/calls"
}

@test "gdrive_link_problem names the problem" {
  [ "$(gdrive_link_problem '')" = "Nothing was pasted." ]
  [[ "$(gdrive_link_problem 'https://docs.google.com/document/d/1AbCdEfGhIjK/edit')" == *"link of a document"* ]] || false
  [[ "$(gdrive_link_problem 'https://drive.google.com/drive/my-drive')" == *"not the link of a folder"* ]] || false
  [[ "$(gdrive_link_problem 'https://drive.google.com/drive/folders/1Ab Cd')" == *"has spaces"* ]] || false
  run gdrive_link_problem 'https://drive.google.com/drive/folders/1AbCdEfGhIjK?usp=sharing'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a remote for another folder is made again" {
  run setup_and_show <<< $'\nn'
  run setup_and_show <<< $'2\nhttps://drive.google.com/drive/folders/1AbCdEfGhIjK\nn'
  [ "$status" -eq 0 ]
  grep -q 'config delete dudu-gdrive' "$FAKE/calls"
  [ "$(grep -c 'config create' "$FAKE/calls")" -eq 2 ]
}

@test "the same choice again keeps the sign-in" {
  run setup_and_show <<< $'\nn'
  run setup_and_show <<< $'\nn'
  [ "$status" -eq 0 ]
  [ "$(grep -c 'config create' "$FAKE/calls")" -eq 1 ]
}

@test "q cancels at the choice, nothing is set up" {
  run setup_and_show <<< 'q'
  [ "$status" -ne 0 ]
  run ! grep -q 'config create' "$FAKE/calls"
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
  # NTFS has no file modes: on Windows the file stays in the user's private AppData.
  is_windows || [ -n "$(find "$FAKE/rclone.conf" -perm 600)" ]
  [[ "$output" == *"only you can read"* ]] || false
}

@test "encryption off is pointed out, and the machines already there are listed" {
  export FAKE_LATEST='dudu-MacBook-Pro/latest\nother-pc/latest\n'
  run setup_and_show <<< $'\nn'
  [[ "$output" == *"Encryption"*"off"* ]] || false
  [[ "$output" == *"MacBook-Pro, other-pc"* ]] || false
}

@test "rclone_hosts strips the dudu- prefix and keeps old folders" {
  export FAKE_LATEST='dudu-Mac-1/latest\nlinux-pc/latest\ndudu-Mac-1/latest\n'
  run rclone_hosts dudu-gdrive:
  [ "$output" = $'Mac-1\nlinux-pc' ]
}

@test "gdrive saves under dudu-<host>, and loads dudu-<host> or an older <host> folder" {
  DUDU_RCLONE_REMOTE=dudu-gdrive:
  gdrive_rclone_load() { echo "LOAD $1"; return 1; }
  run gdrive_load Mac-1 "$BATS_TEST_TMPDIR/out"
  [ "$output" = $'LOAD dudu-gdrive:dudu-Mac-1\nLOAD dudu-gdrive:Mac-1' ]
}

@test "dudu config gdrive adds Google Drive to the destinations" {
  mkdir -p "$DUDU_CONFIG_DIR"
  printf 'destination=local\npath=%s\n' "$BATS_TEST_TMPDIR/b" > "$DUDU_CONFIG_FILE"
  run dudu config gdrive <<< $'\nn'
  [ "$status" -eq 0 ]
  grep -qx 'destination=local,gdrive' "$DUDU_CONFIG_FILE"
  grep -qx 'rclone_remote=dudu-gdrive:' "$DUDU_CONFIG_FILE"
}
