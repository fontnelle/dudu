#!/usr/bin/env bats

load helpers

setup() {
  load_dudu
  f="$BATS_TEST_TMPDIR/file"
  export DUDU_REDACT_LOG="$BATS_TEST_TMPDIR/redacted"
  : > "$DUDU_REDACT_LOG"
}

@test "masks KEY=value assignments" {
  printf 'export OPENAI_API_KEY="sk-abc"\nexport PATH=/usr/bin\n' > "$f"
  secrets_scrub "$f" "~/.zshrc"
  run cat "$f"
  [ "${lines[0]}" = 'export OPENAI_API_KEY="<redacted-by-dudu>"' ]
  [ "${lines[1]}" = 'export PATH=/usr/bin' ]
  [ "$(cat "$DUDU_REDACT_LOG")" = "~/.zshrc:1:OPENAI_API_KEY" ]
}

@test "masks npm auth tokens" {
  echo '//registry.npmjs.org/:_authToken=npm_aaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$f"
  secrets_scrub "$f" "~/.npmrc"
  [ "$(cat "$f")" = '//registry.npmjs.org/:_authToken=<redacted-by-dudu>' ]
  [ "$(cat "$DUDU_REDACT_LOG")" = "~/.npmrc:1:npm token registry.npmjs.org" ]
}

@test "masks JSON values and keeps the comma" {
  echo '  "github.token": "abcdef123456",' > "$f"
  secrets_scrub "$f"
  [ "$(cat "$f")" = '  "github.token": "<redacted-by-dudu>",' ]
}

@test "masks known token shapes anywhere" {
  echo 'alias gh-login="gh auth login --with-token ghp_0123456789abcdefghijABCDEFGHIJ"' > "$f"
  secrets_scrub "$f" "~/.aliases"
  run grep -c ghp_ "$f"
  [ "$output" = 0 ]
  [ "$(cat "$DUDU_REDACT_LOG")" = "~/.aliases:1:GitHub token" ]
}

@test "keeps references, booleans and numbers" {
  printf 'export GITHUB_TOKEN=$(security find-generic-password -w)\nAPI_KEY="$MY_KEY"\npassword_auth: true\ntoken_ttl=3600\n' > "$f"
  cp "$f" "$f.orig"
  secrets_scrub "$f"
  cmp "$f" "$f.orig"
  [ ! -s "$DUDU_REDACT_LOG" ]
}

@test "leaves files without secrets byte-identical (no trailing newline added)" {
  printf 'set -g mouse on' > "$f"
  cp "$f" "$f.orig"
  secrets_scrub "$f"
  cmp "$f" "$f.orig"
}

@test "a masked backup matches the real file it came from" {
  printf 'export TOKEN=supersecretvalue\nalias ll="ls -la"\n' > "$f"
  cp "$f" "$f.real"
  secrets_scrub "$f"
  secrets_same_masked "$f" "$f.real"
  echo 'alias gs="git status"' >> "$f.real"
  run ! secrets_same_masked "$f" "$f.real"
}

@test "moves exported keys of shell files to ~/.secrets and sources it in place" {
  export HOME="$BATS_TEST_TMPDIR/home" && mkdir -p "$HOME"
  DUDU_SECRETS_FILE="$HOME/.secrets"
  printf 'alias ll="ls"\nexport API_KEY="sk-aaaaaaaaaaaaaaaaaaaaaaaa"\necho hi\nexport TOKEN=abcdef123456\n' > "$HOME/.zshrc"
  cp "$HOME/.zshrc" "$f"
  secrets_scrub "$f" "~/.zshrc"
  secrets_movable "$DUDU_REDACT_LOG" > "$BATS_TEST_TMPDIR/movable"
  [ "$(grep -c . "$BATS_TEST_TMPDIR/movable")" = 2 ]
  secrets_move "$BATS_TEST_TMPDIR/movable"
  run cat "$HOME/.zshrc"
  [ "${lines[1]}" = '[ -f ~/.secrets ] && source ~/.secrets  # keys kept out of backups (dudu secrets)' ]
  [ "${#lines[@]}" = 3 ]
  grep -q '^export API_KEY="sk-' "$HOME/.secrets"
  grep -q '^export TOKEN=abcdef123456' "$HOME/.secrets"
  [ -f "$HOME/.zshrc.dudu-bak" ]
}

@test "moves npm tokens to ~/.secrets and leaves \${VAR} in .npmrc" {
  export HOME="$BATS_TEST_TMPDIR/home" SHELL=/bin/zsh && mkdir -p "$HOME"
  DUDU_SECRETS_FILE="$HOME/.secrets"
  printf 'registry=http://localhost:4873/\n//localhost:4873/:_authToken=abcdef1234567890\n' > "$HOME/.npmrc"
  cp "$HOME/.npmrc" "$f"
  secrets_scrub "$f" "~/.npmrc"
  [ "$(cat "$DUDU_REDACT_LOG")" = "~/.npmrc:2:npm token localhost:4873" ]
  secrets_movable "$DUDU_REDACT_LOG" > "$BATS_TEST_TMPDIR/movable"
  secrets_move "$BATS_TEST_TMPDIR/movable"
  [ "$(sed -n 2p "$HOME/.npmrc")" = '//localhost:4873/:_authToken=${NPM_TOKEN_LOCALHOST_4873}' ]
  grep -q "^export NPM_TOKEN_LOCALHOST_4873='abcdef1234567890'" "$HOME/.secrets"
  grep -qF 'source ~/.secrets' "$HOME/.zshrc"
}

# Each case from the security audit: the value must not survive, and the log must not hold it.
scrub_case() { # <line> <secret that must disappear>
  printf '%s\n' "$1" > "$f"
  secrets_scrub "$f" "~/x"
  ! grep -qF -- "$2" "$f" || { echo "leaked in file: $(cat "$f")"; return 1; }
  ! grep -qF -- "$2" "$DUDU_REDACT_LOG" || { echo "leaked in log: $(cat "$DUDU_REDACT_LOG")"; return 1; }
}

@test "the key log never holds a value" {
  scrub_case '{"password":"MyRealPassw0rd","token":"abc123xyz"}' MyRealPassw0rd
  scrub_case 'DB_PASS=SuperSecret1;GH_TOKEN=xyzsecret' SuperSecret1
  grep -q ':DB_PASS$' "$DUDU_REDACT_LOG"
}

@test "masks every secret on a line and keeps the rest" {
  printf 'export A_TOKEN=first1234; export PATH=/usr/bin\n{"token":"x1y2z3","b":1}\n' > "$f"
  secrets_scrub "$f"
  [ "$(sed -n 1p "$f")" = 'export A_TOKEN=<redacted-by-dudu>; export PATH=/usr/bin' ]
  [ "$(sed -n 2p "$f")" = '{"token":"<redacted-by-dudu>","b":1}' ]
  scrub_case 'token=$(cat f); export X_TOKEN=realsecret' realsecret
}

@test "masks passwords in URLs, headers, fish, npm _auth and new token shapes" {
  scrub_case '[url "https://user:TOKEN123456@github.com/"]' TOKEN123456
  scrub_case 'index-url = https://bob:s3cr3t@artifactory.local/simple' s3cr3t
  scrub_case 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefghijkl' eyJhbGci
  scrub_case 'extraheader = AUTHORIZATION: basic dXNlcjpwYXNz' dXNlcjpwYXNz
  scrub_case 'set -gx HF_TOKEN hf_aaaaaaaaaaaaaaaaaaaaaaaa' hf_aaaa
  scrub_case '//host/:_auth=dXNlcjpwYXNzd29yZA==' dXNlcjpwYXNzd29yZA
  live="sk_""live_" # split so secret scanners do not flag this fake key
  scrub_case "stripe=${live}aaaaaaaaaaaaaaaaaaaaaaaa" "${live}aaaa"
}

@test "masks PEM private keys and YAML block values" {
  printf 'a: 1\n-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----\nb: 2\n' > "$f"
  secrets_scrub "$f"
  run ! grep -q b3BlbnNz "$f"
  [ "$(cat "$f")" = "$(printf 'a: 1\n<redacted-by-dudu>\nb: 2')" ]
  printf 'api_key: |\n  line-one-secret\n  line-two\nother: ok\n' > "$f"
  secrets_scrub "$f"
  run ! grep -q line-one "$f"
  grep -q '^other: ok$' "$f"
}

@test "does not mask settings that only look like secrets" {
  printf 'set -gx EDITOR vim\ntoken_limit: 4096\nbypass: yes\ncredential.helper=osxkeychain\nexport PATH=$HOME/bin:$PATH\n' > "$f"
  cp "$f" "$f.orig"
  secrets_scrub "$f"
  cmp -s "$f" "$f.orig"
}

@test "Latin-1 text is still masked (not taken for binary)" {
  printf 'export API_TOKEN=abcdef123456 # caf\351\n' > "$f"
  secrets_scrub "$f"
  run ! grep -q abcdef123456 "$f"
}

@test "fails closed: a file the scrubber cannot read is left out" {
  printf 'export API_TOKEN=abcdef123456\n' > "$f"
  export DUDU_SKIP_LOG="$BATS_TEST_TMPDIR/skipped"
  DUDU_ROOT="$BATS_TEST_TMPDIR/missing" run secrets_scrub "$f" "~/.zshrc"
  [ "$status" -ne 0 ]
  [ ! -e "$f" ]
  grep -q '~/.zshrc (could not be checked' "$DUDU_SKIP_LOG"
}

move_setup() {
  export HOME="$BATS_TEST_TMPDIR/home" SHELL=/bin/zsh && mkdir -p "$HOME"
  DUDU_SECRETS_FILE="$HOME/.secrets"
}

scan_and_move() { # <file label>
  : > "$DUDU_REDACT_LOG"
  cp "$(expand_home "$1")" "$f"
  secrets_scrub "$f" "$1"
  secrets_movable "$DUDU_REDACT_LOG" > "$BATS_TEST_TMPDIR/movable"
}

@test "move finds keys by name even if lines shifted after the scan" {
  move_setup
  printf 'alias ll="ls"\nexport API_TOKEN=abcdef123456\n' > "$HOME/.zshrc"
  scan_and_move "~/.zshrc"
  printf '# added by an installer\nexport PATH=/x:$PATH\n' | cat - "$HOME/.zshrc" > "$HOME/z" && mv "$HOME/z" "$HOME/.zshrc"
  secrets_move "$BATS_TEST_TMPDIR/movable"
  grep -q '^export PATH=/x:\$PATH$' "$HOME/.zshrc"
  run ! grep -q abcdef123456 "$HOME/.zshrc"
  grep -q '^export API_TOKEN=abcdef123456$' "$HOME/.secrets"
}

@test "keys inside blocks, continued or with open quotes are not moved" {
  move_setup
  printf 'if true; then\n  export A_TOKEN=abcdef123456\nfi\nexport B_TOKEN="abc \\\nxyz123456"\n' > "$HOME/.zshrc"
  scan_and_move "~/.zshrc"
  [ ! -s "$BATS_TEST_TMPDIR/movable" ]
}

@test "moving twice does not duplicate exports, and a commented source line does not count" {
  move_setup
  printf '# source ~/.secrets\nexport API_TOKEN=abcdef123456\n' > "$HOME/.zshrc"
  scan_and_move "~/.zshrc"
  secrets_move "$BATS_TEST_TMPDIR/movable"
  grep -q '^\[ -f ~/.secrets \] && source ~/.secrets' "$HOME/.zshrc"
  echo 'export API_TOKEN=abcdef123456' >> "$HOME/.zshrc"
  scan_and_move "~/.zshrc"
  secrets_move "$BATS_TEST_TMPDIR/movable"
  [ "$(grep -c '^export API_TOKEN=' "$HOME/.secrets")" = 1 ]
  [ "$(grep -c 'source ~/.secrets' "$HOME/.zshrc")" = 2 ]
  ls "$HOME"/.zshrc.dudu-bak.* >/dev/null
}

@test "npm tokens with quotes are escaped, and same-name registries get distinct vars" {
  move_setup
  printf "//a.example/:_authToken=it'sabcdef123456\n//a.example/other/:_authToken=zzzzzz123456\n" > "$HOME/.npmrc"
  printf 'export NPM_TOKEN_A_EXAMPLE=different\n' > "$HOME/.secrets"
  scan_and_move "~/.npmrc"
  secrets_move "$BATS_TEST_TMPDIR/movable" 2>&1 || true
  run bash -c "source '$HOME/.secrets'; printf '%s' \"\$NPM_TOKEN_A_EXAMPLE_2\""
  [ "$output" = "it'sabcdef123456" ]
  [ "$(grep -c '^export NPM_TOKEN_A_EXAMPLE=different$' "$HOME/.secrets")" = 1 ]
}

@test "key shapes inside base64 blobs or longer words are left alone" {
  f="$BATS_TEST_TMPDIR/blob"
  k="AKIA""ABCDEFGHIJKLMNOP" # split so secret scanners do not flag this fake key
  printf '\t%sQRS+abc/de==\nx%s\nid %s\n' "$k" "$k" "$k" > "$f"
  secrets_scrub "$f" "~/blob"
  grep -q "${k}QRS+abc/de==" "$f"
  grep -q "x$k" "$f"
  grep -q '^id <redacted-by-dudu>$' "$f"
}
