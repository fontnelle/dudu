#!/usr/bin/env bats
# Saved backups must never be lost or half-written, and a tool that fails must not quietly
# drop out of the backup.

load helpers

setup() {
  load_dudu
  root="$BATS_TEST_TMPDIR/backups"
  src="$BATS_TEST_TMPDIR/src"
  mkdir -p "$root/mac" "$src"
  DUDU_LOG="$BATS_TEST_TMPDIR/dudu.log"
}

# A complete (or partial) backup folder named <stamp>, with checksums.
make_bundle() { # <dir> <stamp> [partial]
  mkdir -p "$1/$2/git"
  echo "data $2" > "$1/$2/git/list.txt"
  printf '{\n  "host": "mac",\n  "partial": %s\n}\n' "${3:-false}" > "$1/$2/manifest.json"
  bundle_sums "$1/$2"
}

@test "stamps are unique and valid, old local-time stamps still read" {
  a=$(backup_stamp); b=$(backup_stamp)
  valid_stamp "$a"
  valid_stamp "2025-01-02_030405"
  run ! valid_stamp "../2025-01-02_030405"
  [ "$a" != "$b" ] || [ "${a%-*}" = "${b%-*}" ]
}

@test "keep=1 keeps the newest complete backup and the one just saved" {
  for s in 2025-01-01_000000Z-aaaa 2025-01-02_000000Z-aaaa 2025-01-03_000000Z-aaaa; do make_bundle "$root/mac" "$s"; done
  make_bundle "$src" 2025-01-04_000000Z-aaaa
  DUDU_KEEP=1 folder_save "$root" "$src/2025-01-04_000000Z-aaaa" mac
  [ -d "$root/mac/2025-01-04_000000Z-aaaa" ]
  [ "$(cat "$root/mac/latest")" = 2025-01-04_000000Z-aaaa ]
  [ "$(folder_stamps "$root/mac" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "keep=0 is never taken literally" {
  for s in 2025-01-01_000000Z-aaaa 2025-01-02_000000Z-aaaa; do make_bundle "$root/mac" "$s"; done
  DUDU_KEEP=0 folder_prune "$root/mac"
  [ -d "$root/mac/2025-01-02_000000Z-aaaa" ]
}

@test "a partial backup does not become latest and does not push out the complete one" {
  make_bundle "$root/mac" 2025-01-01_000000Z-aaaa
  echo 2025-01-01_000000Z-aaaa > "$root/mac/latest"
  make_bundle "$src" 2025-01-02_000000Z-aaaa true
  DUDU_KEEP=1 folder_save "$root" "$src/2025-01-02_000000Z-aaaa" mac
  [ "$(cat "$root/mac/latest")" = 2025-01-01_000000Z-aaaa ]
  [ -d "$root/mac/2025-01-01_000000Z-aaaa" ]
  [ "$(folder_latest "$root" mac)" = 2025-01-01_000000Z-aaaa ]
}

@test "an interrupted save (.partial) is never used, and the same stamp is never merged" {
  make_bundle "$root/mac" 2025-01-01_000000Z-aaaa
  make_bundle "$root/mac" .2025-01-02_000000Z-aaaa.partial
  [ "$(folder_latest "$root" mac)" = 2025-01-01_000000Z-aaaa ]
  make_bundle "$src" 2025-01-01_000000Z-aaaa
  run folder_save "$root" "$src/2025-01-01_000000Z-aaaa" mac
  [ "$status" -ne 0 ]
  [ "$(cat "$root/mac/2025-01-01_000000Z-aaaa/git/list.txt")" = "data 2025-01-01_000000Z-aaaa" ]
}

@test "a damaged newest backup falls back to the previous one" {
  make_bundle "$root/mac" 2025-01-01_000000Z-aaaa
  make_bundle "$root/mac" 2025-01-02_000000Z-aaaa
  echo 2025-01-02_000000Z-aaaa > "$root/mac/latest"
  echo tampered >> "$root/mac/2025-01-02_000000Z-aaaa/git/list.txt"
  out="$BATS_TEST_TMPDIR/out"; mkdir -p "$out"
  run folder_load "$root" mac "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"newest backup was damaged"* ]] || false
  [ "$(cat "$out/git/list.txt")" = "data 2025-01-01_000000Z-aaaa" ]
}

@test "a missing file listed in SHA256SUMS fails verification" {
  make_bundle "$root/mac" 2025-01-01_000000Z-aaaa
  rm "$root/mac/2025-01-01_000000Z-aaaa/git/list.txt"
  run ! bundle_verify "$root/mac/2025-01-01_000000Z-aaaa"
}

# A fake tool, to drive collect_all.
fake_detect() { return 0; }
fake_backup() {
  case "$FAKE" in
    fail) return 1 ;;
    empty) : > "$1/list.txt" ;;
    *) echo "pkg-$FAKE" > "$1/list.txt" ;;
  esac
  summary "$1" "ok"
}

@test "a tool that fails keeps its last good copy (carry-forward)" {
  DUDU_COLLECTORS=fake DUDU_CARRY=1
  mkdir -p "$(carry_dir)/fake"; echo pkg-old > "$(carry_dir)/fake/list.txt"
  FAKE=fail collect_all "$src/b" quiet
  [ "$CARRIED" = fake ] && [ -z "$FAILED" ]
  [ "$(cat "$src/b/fake/list.txt")" = pkg-old ]
}

@test "an empty list where there used to be items is not trusted" {
  DUDU_COLLECTORS=fake DUDU_CARRY=1
  mkdir -p "$(carry_dir)/fake"; echo pkg-old > "$(carry_dir)/fake/list.txt"
  FAKE=empty collect_all "$src/b" quiet
  [ "$CARRIED" = fake ]
  [ "$(cat "$src/b/fake/list.txt")" = pkg-old ]
}

@test "a tool that fails with no earlier copy is reported, not hidden" {
  DUDU_COLLECTORS=fake DUDU_CARRY=1
  FAKE=fail collect_all "$src/b" quiet
  [ "$FAILED" = fake ] && [ -z "$COLLECTED" ]
  [ ! -d "$src/b/fake" ]
}

@test "--only backs up the chosen tools and keeps the others from the last backup" {
  DUDU_COLLECTORS="fake git" DUDU_CARRY=1 DUDU_ONLY=fake
  mkdir -p "$(carry_dir)/git"; echo old > "$(carry_dir)/git/list.txt"
  FAKE=new collect_all "$src/b" quiet
  [ "$(cat "$src/b/fake/list.txt")" = pkg-new ]
  [ "$(cat "$src/b/git/list.txt")" = old ]
  [[ " $CARRIED " == *" git "* ]] || false
}

@test "collectors report failure when their tool fails" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for t in cargo pnpm; do printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/$t"; chmod +x "$BATS_TEST_TMPDIR/bin/$t"; done
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run ! cargo_backup "$src"
  run ! pnpm_backup "$src"
}

@test "go never scans /bin when GOPATH is empty" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/go"; chmod +x "$BATS_TEST_TMPDIR/bin/go"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run ! go_bin_dir
  run ! go_backup "$src"
}

@test "another machine with the same name gets its own folder" {
  DUDU_DESTINATION=local DUDU_PATH="$root"
  h=$(dudu_host)
  mkdir -p "$root/$h/2025-01-01_000000Z-aaaa"
  printf '{\n  "machine": "000000000000"\n}\n' > "$root/$h/2025-01-01_000000Z-aaaa/manifest.json"
  [ "$(backup_host)" = "$h-$(machine_id | cut -c1-4)" ]
  printf '{\n  "machine": "%s"\n}\n' "$(machine_id)" > "$root/$h/2025-01-01_000000Z-aaaa/manifest.json"
  [ "$(backup_host)" = "$h" ]
}

@test "restore warns about tools the manifest lists but the backup lacks" {
  mkdir -p "$src/git"
  printf '{\n  "collectors": ["git", "npm"],\n  "carried": [],\n  "failed": ["cargo"]\n}\n' > "$src/manifest.json"
  run restore_check_contents "$src"
  [[ "$output" == *"missing from it: npm"* ]] || false
  [[ "$output" == *"failed when it was made): cargo"* ]] || false
}

# rclone stand-in: "r:" is a local folder.
rclone_stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/remote"
  cat > "$BATS_TEST_TMPDIR/bin/rclone" <<STUB
#!/bin/bash
R="$BATS_TEST_TMPDIR/remote"
p() { case "\$1" in r:*) printf '%s' "\$R/\${1#r:}" ;; *) printf '%s' "\$1" ;; esac; }
case "\$1" in
  copy) mkdir -p "\$(p "\$3")"; cp -R "\$(p "\$2")/." "\$(p "\$3")/" ;;
  check) diff -r "\$2" "\$(p "\$3")" >/dev/null ;;
  rcat) cat > "\$(p "\$2")" ;;
  cat) cat "\$(p "\$2")" ;;
  lsf) for d in "\$(p "\$3")"/*/; do [ -d "\$d" ] && basename "\$d" | sed 's|\$|/|'; done ;;
  purge) rm -rf "\$(p "\$2")" ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/rclone"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  DUDU_RCLONE_REMOTE="r:dudu"
}

@test "rclone: keeps the just-saved backup with keep=1 in dudu-<host>, round-trips and verifies" {
  rclone_stub
  make_bundle "$src" 2025-01-01_000000Z-aaaa
  make_bundle "$src" 2025-01-02_000000Z-aaaa
  DUDU_KEEP=1 gdrive_save "$src/2025-01-01_000000Z-aaaa" mac >/dev/null
  DUDU_KEEP=1 gdrive_save "$src/2025-01-02_000000Z-aaaa" mac >/dev/null
  [ -d "$BATS_TEST_TMPDIR/remote/dudu/dudu-mac/2025-01-02_000000Z-aaaa" ]
  [ ! -d "$BATS_TEST_TMPDIR/remote/dudu/dudu-mac/2025-01-01_000000Z-aaaa" ]
  out="$BATS_TEST_TMPDIR/out"; mkdir -p "$out"
  gdrive_load mac "$out"
  [ "$(cat "$out/git/list.txt")" = "data 2025-01-02_000000Z-aaaa" ]
  echo x >> "$BATS_TEST_TMPDIR/remote/dudu/dudu-mac/2025-01-02_000000Z-aaaa/git/list.txt"
  rm -rf "$out"; mkdir -p "$out"
  run ! gdrive_load mac "$out"
}

@test "a second dudu stops while one is running, a stale lock is taken over" {
  mkdir -p "$DUDU_CACHE_DIR/lock"
  sleep 30 & other=$!
  echo "$other" > "$DUDU_CACHE_DIR/lock/pid"
  run dudu_lock
  [ "$status" -eq 1 ]
  [[ "$output" == *"Another dudu is running"* ]] || false
  kill "$other"; wait "$other" 2>/dev/null || true
  dudu_lock
  [ "$(cat "$DUDU_CACHE_DIR/lock/pid")" = "$$" ]
  dudu_unlock
  [ ! -d "$DUDU_CACHE_DIR/lock" ]
}

@test "kill_tree stops a step and everything it started" {
  bash -c 'sleep 60 & sleep 60; wait' & pid=$!
  sleep 0.3
  kids=$(pid_tree "$pid")
  kill_tree "$pid"
  for p in $kids; do run ! kill -0 "$p"; done
}

@test "cleanup removes registered temp dirs" {
  d=$(mktemp -d); tmp_register "$d"
  dudu_cleanup
  [ ! -d "$d" ]
}

@test "restore without a terminal needs -y" {
  run bash -c "'$DUDU_ROOT/dudu' restore --file /nonexistent < /dev/null"
  [ "$status" -ne 0 ]
}
