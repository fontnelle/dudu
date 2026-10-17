#!/usr/bin/env bats

load helpers

setup() { load_dudu; }

@test "version_gt compares x.y.z" {
  version_gt 0.2.0 0.1.9
  version_gt 1.0.0 0.9.9
  version_gt v0.10.0 0.9.0
  run ! version_gt 0.1.0 0.1.0
  run ! version_gt 0.1.0 0.2.0
}

@test "list_has matches whole names only" {
  list_has "brew,node" node
  run ! list_has "brew,nodejs" node
  run ! list_has "" node
}

@test "collector_enabled honors --only, include and exclude" {
  DUDU_INCLUDE="" DUDU_EXCLUDE="macos" DUDU_ONLY=""
  collector_enabled brew
  run ! collector_enabled macos
  DUDU_ONLY="node"
  collector_enabled node
  run ! collector_enabled brew
}

@test "config round trip expands ~ in path" {
  DUDU_DESTINATION=local DUDU_PATH="~/backups" DUDU_INCLUDE="" DUDU_EXCLUDE="ruby" DUDU_KEEP=3 DUDU_RCLONE_REMOTE=""
  config_save
  config_load
  [ "$DUDU_DESTINATION" = local ]
  [ "$DUDU_PATH" = "$HOME/backups" ]
  [ "$DUDU_EXCLUDE" = ruby ]
  [ "$DUDU_KEEP" = 3 ]
}

@test "missing_from lists what is not installed" {
  printf 'a\nb\nc\n' > "$BATS_TEST_TMPDIR/wanted"
  run bash -c ". '$DUDU_ROOT/lib/core/common.sh'; printf 'b\nz\n' | missing_from '$BATS_TEST_TMPDIR/wanted'"
  [ "$output" = "$(printf 'a\nc')" ]
}

@test "json_deps reads package.json dependencies" {
  cat > "$BATS_TEST_TMPDIR/package.json" <<'EOF'
{
  "dependencies": {
    "@vue/cli": "^5.0.0",
    "typescript": "^5.4.0"
  }
}
EOF
  run json_deps "$BATS_TEST_TMPDIR/package.json"
  [ "$output" = "$(printf '@vue/cli\ntypescript')" ]
}

@test "npm_list_modules handles scoped packages and skips npm itself" {
  local nm="$BATS_TEST_TMPDIR/node_modules"
  mkdir -p "$nm/npm" "$nm/corepack" "$nm/typescript" "$nm/@angular/cli" "$nm/.bin"
  run npm_list_modules "$nm"
  [ "$output" = "$(printf '@angular/cli\ntypescript')" ]
}

@test "notes pack/unpack round trip is exact" {
  local b="$BATS_TEST_TMPDIR/2026-01-01_000000"
  mkdir -p "$b/shell/home" "$b/terminal/defaults"
  printf 'export A=1\n\tindented\n<html> & stuff\n' > "$b/shell/home/.zshrc"
  head -c 512 /dev/urandom > "$b/terminal/defaults/x.plist"
  echo "# readme" > "$b/RESTORE.md"
  notes_pack "$b" | notes_html "title" | sed -e 's/<[^>]*>//g' -e 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g' > "$BATS_TEST_TMPDIR/note.txt"
  mkdir "$BATS_TEST_TMPDIR/out"
  notes_unpack "$BATS_TEST_TMPDIR/out" < "$BATS_TEST_TMPDIR/note.txt"
  diff -r "$b" "$BATS_TEST_TMPDIR/out"
}

@test "folder destination keeps the newest N backups and a latest pointer" {
  DUDU_KEEP=2
  local root="$BATS_TEST_TMPDIR/dest" s
  for s in 2026-01-01_000000 2026-01-02_000000 2026-01-03_000000; do
    mkdir -p "$BATS_TEST_TMPDIR/stage/$s" && echo "$s" > "$BATS_TEST_TMPDIR/stage/$s/manifest.json"
    folder_save "$root" "$BATS_TEST_TMPDIR/stage/$s" host >/dev/null
  done
  [ "$(cat "$root/host/latest")" = 2026-01-03_000000 ]
  [ ! -d "$root/host/2026-01-01_000000" ]
  [ -d "$root/host/2026-01-02_000000" ]
  [ "$(folder_hosts "$root")" = host ]
  mkdir "$BATS_TEST_TMPDIR/load"
  folder_load "$root" host "$BATS_TEST_TMPDIR/load"
  [ "$(cat "$BATS_TEST_TMPDIR/load/manifest.json")" = 2026-01-03_000000 ]
}

@test "config tolerates spaces, CRLF and quotes, and rejects keep=0" {
  mkdir -p "$DUDU_CONFIG_DIR"
  printf 'destination = icloud\r\npath="~/my backups"\r\nkeep=0\r\n' > "$DUDU_CONFIG_FILE"
  config_load
  [ "$DUDU_DESTINATION" = icloud ]
  [ "$DUDU_PATH" = "$HOME/my backups" ]
  [ "$DUDU_KEEP" = 5 ]
}

@test "a config without a destination is never overwritten" {
  mkdir -p "$DUDU_CONFIG_DIR"
  printf '# mine\ndestinaton=icloud\n' > "$DUDU_CONFIG_FILE"
  run ensure_configured </dev/null
  [ "$status" -ne 0 ]
  [ "$(cat "$DUDU_CONFIG_FILE")" = "$(printf '# mine\ndestinaton=icloud')" ]
}

@test "version_gt handles pre-releases" {
  version_gt 1.2.0 1.1.9
  version_gt 1.2.0 1.2.0-rc1
  version_gt 1.2.0-rc2 1.2.0-rc1
  run ! version_gt 1.2.0-rc1 1.2.0
  run ! version_gt 1.2.0 1.2.0
  run ! version_gt v0.9.0 0.10.0
}

@test "a Homebrew install is updated by brew" {
  DUDU_ROOT=/opt/homebrew/Cellar/dudu/0.1.0/libexec
  [ "$(update_command)" = "brew upgrade dudu" ]
  DUDU_ROOT=$HOME/.local/lib/dudu
  [ "$(update_command)" = "dudu update" ]
}

@test "the highlight path survives brew upgrades" {
  DUDU_ROOT=/opt/homebrew/Cellar/dudu/0.1.0/libexec
  [ "$(stable_root)" = "/opt/homebrew/opt/dudu/libexec" ]
}
