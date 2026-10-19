#!/usr/bin/env bats
# backup → restore through the real CLI, in a throwaway HOME, limited to shell and git
# so nothing gets installed.

load helpers

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
  export NO_COLOR=1 DUDU_NO_SPINNER=1 DUDU_NO_UPDATE_CHECK=1 ZSH=""
  mkdir -p "$HOME/.config/dudu"
  printf 'destination=local\npath=%s\n' "$BATS_TEST_TMPDIR/backups" > "$HOME/.config/dudu/config"
  printf 'alias ll="ls -la"\nexport NPM_TOKEN=abcdef0123456789\n' > "$HOME/.zshrc"
  printf '[user]\n\tname = Dudu\n' > "$HOME/.gitconfig"
  mkdir -p "$HOME/.ssh" && echo "PRIVATE" > "$HOME/.ssh/id_ed25519"
}

@test "backup writes a manifest, masks secrets and skips keys" {
  run dudu backup --only shell,git
  [ "$status" -eq 0 ]
  local dir="$BATS_TEST_TMPDIR/backups/$(ls "$BATS_TEST_TMPDIR/backups")"
  local b="$dir/$(cat "$dir/latest")"
  [ -f "$b/manifest.json" ]
  grep -q '"shell"' "$b/manifest.json"
  grep -q 'NPM_TOKEN=<redacted-by-dudu>' "$b/shell/home/.zshrc"
  [[ "$output" == *"key file kept local"*"SSH"* ]] || false
  run ! grep -rq abcdef0123456789 "$b"
  run ! grep -rq PRIVATE "$b"
  grep -q '~/.ssh/id_ed25519' "$b/RESTORE.md"
}

@test "restore --dry-run changes nothing" {
  dudu backup --only shell,git
  echo 'changed' > "$HOME/.gitconfig"
  run dudu restore --dry-run --only git
  [ "$status" -eq 0 ]
  [[ "$output" == *"→ write ~/.gitconfig"* ]] || false
  [ "$(cat "$HOME/.gitconfig")" = changed ]
}

@test "restore brings files back and keeps a .dudu-bak" {
  dudu backup --only shell,git
  echo 'changed' > "$HOME/.gitconfig"
  run dudu restore --only git --yes
  [ "$status" -eq 0 ]
  grep -q 'name = Dudu' "$HOME/.gitconfig"
  [ "$(cat "$HOME/.gitconfig.dudu-bak")" = changed ]
}

@test "restore does not overwrite a file whose only difference is the masked secret" {
  dudu backup --only shell
  run dudu restore --only shell --yes
  grep -q 'NPM_TOKEN=abcdef0123456789' "$HOME/.zshrc"
  [ ! -f "$HOME/.zshrc.dudu-bak" ]
}

@test "restore says so when this machine already matches the backup" {
  dudu backup --only shell,git
  run dudu restore --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Local folder"*"restoring this one"* ]] || false
  [[ "$output" == *"already matches the backup"* ]] || false
  [ ! -f "$HOME/.gitconfig.dudu-bak" ]
  [ ! -f "$HOME/.zshrc.dudu-bak" ]
}

@test "restore brings back only the tool that differs" {
  dudu backup --only shell,git
  echo 'changed' > "$HOME/.gitconfig"
  run dudu restore --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"matching"*"shell"* ]] || false
  [[ "$output" == *"git"*"1 file changed"* ]] || false
  [[ "$output" == *"What will be done"*"replace ~/.gitconfig"* ]] || false
  [[ "$output" == *"✓ git"*"restored"* ]] || false
  grep -q 'name = Dudu' "$HOME/.gitconfig"
  [ ! -f "$HOME/.zshrc.dudu-bak" ]
}

@test "restore --dry-run compares and changes nothing" {
  dudu backup --only shell,git
  rm "$HOME/.gitconfig"
  run dudu restore --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Comparing"*"git"* ]] || false
  [[ "$output" == *"Dry run: nothing was changed."* ]] || false
  [ ! -f "$HOME/.gitconfig" ]
}

@test "status reports a new dotfile" {
  dudu backup --only shell,git
  echo 'set -g mouse on' > "$HOME/.tmux.conf"
  run dudu status --only shell,git
  [ "$status" -eq 3 ]
  [[ "$output" == *".tmux.conf"* ]] || false
}

@test "zsh highlighting marks subcommands and typos" {
  command -v zsh >/dev/null || skip "zsh not installed"
  dudu completion highlight > "$BATS_TEST_TMPDIR/hl.zsh"
  run zsh -fc "source '$BATS_TEST_TMPDIR/hl.zsh'
    _zsh_highlight_add_highlight() { print -r -- \"\$1 \$2 \$3\"; }
    for BUFFER in 'dudu backup' 'dudu bakcup' 'echo dudu backup'; do _zsh_highlight_highlighter_dudu_paint; done"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '5 11 dudu-subcommand\n5 11 dudu-unknown')" ]
}
