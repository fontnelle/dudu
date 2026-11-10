#!/usr/bin/env bats
# A Mac's backup restored on Linux: what applies, and the Brewfile turned into apt/Flathub.
# The OS and the package manager are faked, so these run on macOS too.
# shellcheck disable=SC2317,SC2329 # the stubs are called by dudu's functions

load helpers

FIXTURE="$DUDU_ROOT/tests/fixtures/mac-bundle"

setup() {
  load_dudu
  is_macos() { return 1; }
  dudu_os() { echo linux; }
  linux_pm() { echo apt; }
  # The repositories have git and fd-find; nothing is installed yet; no Homebrew here.
  apt-cache() { printf 'git\nfd-find\npostgresql\n'; }
  syspkgs_list_installed() { :; }
  flatpak() { :; }
  has() { [ "$1" != brew ] && command -v "$1" >/dev/null 2>&1; }
  brew_load_shellenv() { return 1; }
  B="$BATS_TEST_TMPDIR/bundle"
  cp -R "$FIXTURE" "$B"
  LEFT="$BATS_TEST_TMPDIR/left-out"
  : > "$LEFT"
}

@test "collector_applies: macOS defaults only on macOS, system packages only on Linux" {
  run ! collector_applies macos
  collector_applies syspkgs
  collector_applies shell
}

@test "a backup from the other OS is told apart by its manifest" {
  crossos_bundle "$B"
  dudu_os() { echo macos; }
  run ! crossos_bundle "$B"
}

@test "crossos_brew_plan maps formulae and casks to this system" {
  run crossos_brew_plan "$B/brew/Brewfile" apt
  [ "$status" -eq 0 ]
  [[ "$output" == *"native|git|git"* ]] || false
  [[ "$output" == *"native|fd-find|fd"* ]] || false
  [[ "$output" == *"native|postgresql|postgresql@16"* ]] || false
  [[ "$output" == *"flatpak|com.slack.Slack|slack (cask)"* ]] || false
  [[ "$output" == *"none|magnet (cask)"* ]] || false
  [[ "$output" == *"none|Xcode (App Store)"* ]] || false
  # The system has coreutils, the node collector installs nvm, vscode lines are extensions.
  [[ "$output" != *coreutils* ]] || false
  [[ "$output" != *nvm* ]] || false
  [[ "$output" != *prettier* ]] || false
}

@test "crossos_brew_plan: a formula the repositories do not have has no equivalent" {
  apt-cache() { printf 'fd-find\n'; }
  run crossos_brew_plan "$B/brew/Brewfile" apt
  [[ "$output" == *"none|git"* ]] || false
  # With Homebrew on this Linux, it goes to brew instead.
  run crossos_brew_plan "$B/brew/Brewfile" apt brew
  [[ "$output" == *"brew|git|git"* ]] || false
}

@test "crossos_localize turns a Mac backup into this Linux's one" {
  crossos_localize "$B" "$LEFT"
  # Editor settings and Ghostty move to ~/.config, nothing is left under ~/Library.
  [ -f "$B/vscode/home/.config/Code/User/settings.json" ]
  [ -f "$B/terminal/home/.config/ghostty/config" ]
  [ ! -d "$B/terminal/defaults" ]
  [ -z "$(find "$B" -path '*/home/Library*')" ]
  # The Brewfile became apt and Flathub lists.
  [ ! -f "$B/brew/Brewfile" ]
  grep -qx git "$B/brew/linux/apt.txt"
  grep -qx fd-find "$B/brew/linux/apt.txt"
  grep -qx com.slack.Slack "$B/brew/linux/flatpak.txt"
  grep -qx 'terminal|Terminal.app profiles' "$LEFT"
  grep -qx 'brew|magnet (cask)' "$LEFT"
  grep -qx 'brew|Xcode (App Store)' "$LEFT"
}

@test "crossos_localize keeps only what this machine is missing" {
  syspkgs_list_installed() { echo git; }
  crossos_localize "$B" "$LEFT"
  run ! grep -qx git "$B/brew/linux/apt.txt"
  grep -qx fd-find "$B/brew/linux/apt.txt"
}

@test "crossos_localize leaves a backup from this OS alone" {
  dudu_os() { echo macos; }
  crossos_localize "$B" "$LEFT"
  [ -f "$B/brew/Brewfile" ]
  [ -d "$B/terminal/defaults" ]
  [ ! -s "$LEFT" ]
}

@test "the plan shows the translated packages with their source" {
  crossos_localize "$B" "$LEFT"
  run status_changes "$BATS_TEST_TMPDIR/empty" "$B/brew"
  [[ "$output" == *"+L git (apt)"* ]] || false
  [[ "$output" == *"+L com.slack.Slack (flatpak)"* ]] || false
}

@test "brew_restore of a Mac backup on Linux installs apt packages, never Homebrew" {
  crossos_localize "$B" "$LEFT"
  DUDU_DRY_RUN=1
  run brew_restore "$B/brew"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt-get install -y fd-find git postgresql"* ]] || false
  [[ "$output" == *"flatpak install -y --noninteractive flathub com.slack.Slack"* ]] || false
  [[ "$output" != *Homebrew* ]] || false
}

@test "the left out list is grouped by tool" {
  printf 'brew|magnet (cask)\nmacos|1 preference\nbrew|Xcode (App Store)\n' > "$LEFT"
  run crossos_show_left_out "$LEFT"
  [[ "$output" == *"Left out"* ]] || false
  [[ "$output" == *"brew"*"magnet (cask)"*"Xcode (App Store)"*"macos"*"1 preference"* ]] || false
}

@test "restore of a Mac backup on Linux skips macOS defaults and lists what is left out" {
  [ "$(uname -s)" = Linux ] || skip "Linux only"
  run "$DUDU_ROOT/dudu" restore --file "$FIXTURE" --dry-run -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"Made on macOS"* ]] || false
  [[ "$output" == *"macos"*"macOS only, not restored here"* ]] || false
  [[ "$output" == *"Left out"* ]] || false
  [[ "$output" == *"Xcode (App Store)"* ]] || false
  [[ "$output" == *"~/.config/Code/User/settings.json"* ]] || false
}

# A backup as dudu for Windows makes it.
windows_bundle() {
  W="$BATS_TEST_TMPDIR/win-bundle"
  mkdir -p "$W/winget" "$W/scoop" "$W/git/home/AppData/Roaming/GitHub CLI" \
    "$W/vscode/home/AppData/Roaming/Code/User/snippets" "$W/shell/home/Documents/PowerShell" \
    "$W/terminal/home/AppData/Local/Microsoft/Windows Terminal"
  cat > "$W/manifest.json" <<'JSON'
{
  "dudu": "0.2.0",
  "created": "2026-11-09T15:30:27Z",
  "host": "Test-PC",
  "machine": "000000000000",
  "os": "windows",
  "os_version": "Windows 11",
  "arch": "x86_64",
  "partial": false,
  "collectors": ["winget", "scoop", "shell", "git", "terminal", "vscode"],
  "carried": [],
  "failed": []
}
JSON
  printf 'Git.Git\n' > "$W/winget/packages.txt"; printf '1 package' > "$W/winget/.summary"
  printf 'ripgrep\n' > "$W/scoop/apps.txt"; printf '1 app' > "$W/scoop/.summary"
  printf '[user]\n\tname = Test\n' > "$W/git/home/.gitconfig"
  printf 'editor: vim\n' > "$W/git/home/AppData/Roaming/GitHub CLI/config.yml"
  printf '{"editor.fontSize": 14}\n' > "$W/vscode/home/AppData/Roaming/Code/User/settings.json"
  printf '{}\n' > "$W/vscode/home/AppData/Roaming/Code/User/snippets/go.json"
  printf 'Set-Alias g git\n' > "$W/shell/home/Documents/PowerShell/profile.ps1"
  printf '{}\n' > "$W/terminal/home/AppData/Local/Microsoft/Windows Terminal/settings.json"
}

@test "winget, scoop and Chocolatey are Windows' tools, restored nowhere else" {
  for c in winget scoop choco; do
    run ! collector_applies "$c"
    [ "$(collector_os "$c")" = Windows ]
  done
  [ "$(os_label windows)" = Windows ]
}

@test "a Windows backup on Linux: editor settings move, Windows' own files are set aside" {
  windows_bundle
  crossos_localize "$W" "$LEFT"
  [ -f "$W/vscode/home/.config/Code/User/settings.json" ]
  [ -f "$W/vscode/home/.config/Code/User/snippets/go.json" ]
  [ ! -e "$W/vscode/home/AppData" ]
  [ -f "$W/git/home/.gitconfig" ]
  [ ! -e "$W/git/home/AppData" ]
  [ ! -e "$W/shell/home/Documents" ]
  [ ! -e "$W/terminal/home/AppData" ]
  grep -qxF 'git|~/AppData/Roaming/GitHub CLI/config.yml' "$LEFT"
  grep -qxF 'shell|~/Documents/PowerShell/profile.ps1' "$LEFT"
  grep -qxF 'terminal|~/AppData/Local/Microsoft/Windows Terminal/settings.json' "$LEFT"
  run ! grep -q '^vscode|' "$LEFT"
}

@test "a Windows backup on a Mac: editor settings go to Application Support" {
  is_macos() { return 0; }
  dudu_os() { echo macos; }
  windows_bundle
  crossos_localize "$W" "$LEFT"
  [ -f "$W/vscode/home/Library/Application Support/Code/User/settings.json" ]
  [ ! -e "$W/vscode/home/AppData" ]
  [ ! -e "$W/git/home/AppData" ]
  grep -qxF 'shell|~/Documents/PowerShell/profile.ps1' "$LEFT"
}

@test "restore of a Windows backup lists winget and scoop as Windows only" {
  windows_bundle
  run "$DUDU_ROOT/dudu" restore --file "$W" --dry-run -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"Made on Windows: what only exists there"* ]] || false
  [[ "$output" == *"winget"*"Windows only, not restored here"* ]] || false
  [[ "$output" == *"scoop"*"Windows only, not restored here"* ]] || false
  [[ "$output" == *"Left out"* ]] || false
  [[ "$output" == *"~/Documents/PowerShell/profile.ps1"* ]] || false
  [[ "$output" == *"Code/User/settings.json"* ]] || false
  [[ "$output" != *"ignored unexpected file"* ]] || false
}
