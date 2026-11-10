#!/usr/bin/env bats

# shellcheck disable=SC2317,SC2329 # the stubs are called by the code under test
load helpers

setup() { load_dudu; fake_windows; }

@test "Git Bash, MSYS and Cygwin are windows" {
  [ "$(dudu_os)" = windows ]
  is_windows
  run ! is_macos
  run ! is_linux
  uname() { echo MSYS_NT-10.0; }
  [ "$(dudu_os)" = windows ]
  uname() { echo CYGWIN_NT-10.0; }
  [ "$(dudu_os)" = windows ]
}

@test "macOS and Linux are not windows" {
  uname() { echo Darwin; }
  run ! is_windows
  uname() { echo Linux; }
  run ! is_windows
  [ "$(dudu_os)" = linux ]
}

@test "win_reg reads one value, without the CR" {
  REG_ProductName="Windows 10 Pro"
  [ "$(win_reg 'HKLM\SOFTWARE\X' ProductName)" = "Windows 10 Pro" ]
  run ! test -n "$(win_reg 'HKLM\SOFTWARE\X' Missing)"
}

@test "os_pretty says Windows 11 for builds from 22000" {
  REG_ProductName="Windows 10 Pro" REG_CurrentBuild=26100
  [ "$(os_pretty)" = "Windows 11 Pro" ]
  REG_CurrentBuild=19045
  [ "$(os_pretty)" = "Windows 10 Pro" ]
  REG_ProductName="" REG_CurrentBuild=""
  [ "$(os_pretty)" = "Windows" ]
}

@test "dudu_host is COMPUTERNAME" {
  COMPUTERNAME="DEV-PC 01"
  [ "$(dudu_host)" = "DEV-PC01" ]
}

@test "machine_id comes from MachineGuid" {
  REG_MachineGuid=aaaa-bbbb
  a=$(machine_id)
  REG_MachineGuid=cccc-dddd
  b=$(machine_id)
  [ "$a" != "$b" ]
  [ ${#a} -eq 12 ]
}

@test "the Windows locale picks the language when LANG says nothing" {
  unset LANGUAGE LC_ALL LC_MESSAGES LANG
  REG_LocaleName=pt-BR
  [ "$(i18n_system_language)" = pt-BR ]
  REG_LocaleName=es-MX
  [ "$(i18n_system_language)" = es ]
}

@test "AppData folders default under HOME" {
  unset APPDATA LOCALAPPDATA
  [ "$(win_appdata)" = "$HOME/AppData/Roaming" ]
  [ "$(win_localappdata)" = "$HOME/AppData/Local" ]
}

@test "as_root does not use sudo on Windows" {
  run as_root echo hi
  [ "$output" = hi ]
}

# A fake command in PATH: fake_cmd <name> <script body>
fake_cmd() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "Windows package managers only apply on Windows" {
  collector_applies winget
  collector_applies scoop
  run ! collector_applies syspkgs
  run ! collector_applies macos
  [ "$(collector_os choco)" = Windows ]
  [ "$(os_label windows)" = Windows ]
}

@test "winget backs up package ids from its export" {
  fake_cmd winget 'while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
printf "{\r\n  \"Sources\": [{\"Packages\": [\r\n  {\"PackageIdentifier\": \"Git.Git\"},\r\n  {\"PackageIdentifier\": \"Microsoft.VisualStudioCode\"}\r\n]}]}\r\n" > "$out"'
  win_path() { printf '%s' "$1"; }
  d="$BATS_TEST_TMPDIR/b"; mkdir -p "$d"
  winget_detect
  winget_backup "$d"
  [ "$(cat "$d/packages.txt")" = "$(printf 'Git.Git\nMicrosoft.VisualStudioCode')" ]
  grep -q "2 winget packages" "$d/.summary"
}

@test "winget restores only the missing ids" {
  fake_cmd winget 'case "$1" in
  export) while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done; echo "{\"PackageIdentifier\": \"Git.Git\"}" > "$out" ;;
  install) echo "$3" >> "$BATS_TEST_TMPDIR/installed" ;;
esac'
  win_path() { printf '%s' "$1"; }
  d="$BATS_TEST_TMPDIR/b"; mkdir -p "$d"
  printf 'Git.Git\nNeovim.Neovim\n' > "$d/packages.txt"
  winget_restore "$d"
  [ "$(cat "$BATS_TEST_TMPDIR/installed")" = Neovim.Neovim ]
}

@test "winget's upgrade table is read by column, whatever the language" {
  out=$(printf '%s\r\n' \
    'Nome                Id                  Versão   Disponível Origem' \
    '---------------------------------------------------------------------' \
    'Git                 Git.Git             2.45.1   2.47.0     winget' \
    'Microsoft VS Code   Microsoft.VSCode    1.90.0   1.95.2     winget' \
    '2 atualizações disponíveis.' | winget_table)
  [ "$out" = "$(printf 'Git.Git 2.45.1 2.47.0\nMicrosoft.VSCode 1.90.0 1.95.2')" ]
}

@test "scoop export gives apps with their bucket and the buckets" {
  f="$BATS_TEST_TMPDIR/scoop.json"
  cat > "$f" <<'JSON'
{
  "buckets": [
    { "Name": "extras", "Source": "https://github.com/ScoopInstaller/Extras", "Updated": "2026-10-01", "Manifests": 2000 },
    { "Name": "main", "Source": "https://github.com/ScoopInstaller/Main", "Updated": "2026-10-01", "Manifests": 1400 }
  ],
  "apps": [
    { "Name": "git", "Source": "main", "Updated": "2026-10-01", "Info": "", "Version": "2.47.0" },
    { "Name": "vscode", "Source": "extras", "Updated": "2026-10-01", "Info": "", "Version": "1.95.2" }
  ]
}
JSON
  [ "$(scoop_parse_export "$f" apps)" = "$(printf 'extras/vscode\nmain/git')" ]
  [ "$(scoop_parse_export "$f" buckets)" = "$(printf 'extras https://github.com/ScoopInstaller/Extras\nmain https://github.com/ScoopInstaller/Main')" ]
}

@test "scoop compares apps by name, not by bucket" {
  printf 'main/git\nextras/vscode\njq\n' > "$BATS_TEST_TMPDIR/want"
  [ "$(printf 'git\n' | missing_from_names "$BATS_TEST_TMPDIR/want")" = "$(printf 'extras/vscode\njq')" ]
}

@test "choco lists packages without chocolatey itself" {
  fake_cmd choco 'printf "chocolatey|2.3.0\r\ngit|2.47.0\r\nnodejs-lts|20.18.0\r\n"'
  [ "$(choco_list)" = "$(printf 'git\nnodejs-lts')" ]
}

@test "winget's table keeps versions shown as < x" {
  out=$(printf '%s\n' 'Name  Id  Version  Available  Source' '----' \
    'Some App   Vendor.App   < 1.0   1.2.0   winget' | winget_table)
  [ "$out" = "Vendor.App 1.0 1.2.0" ]
}

@test "editor settings from a Mac or Linux land in AppData on Windows" {
  src="$BATS_TEST_TMPDIR/src" out="$BATS_TEST_TMPDIR/out"
  mkdir -p "$src/Library/Application Support/Code/User/snippets" "$src/.config/Cursor/User"
  echo '{}' > "$src/Library/Application Support/Code/User/settings.json"
  echo '{}' > "$src/Library/Application Support/Code/User/snippets/go.json"
  echo '[]' > "$src/.config/Cursor/User/keybindings.json"
  editor_home_for_this_os "$src" "$out"
  [ -f "$out/AppData/Roaming/Code/User/settings.json" ]
  [ -f "$out/AppData/Roaming/Code/User/snippets/go.json" ]
  [ -f "$out/AppData/Roaming/Cursor/User/keybindings.json" ]
}

@test "Windows editor settings land in Library on a Mac" {
  is_windows() { return 1; }
  is_macos() { return 0; }
  src="$BATS_TEST_TMPDIR/src" out="$BATS_TEST_TMPDIR/out"
  mkdir -p "$src/AppData/Roaming/Code/User"
  echo '{}' > "$src/AppData/Roaming/Code/User/settings.json"
  editor_home_for_this_os "$src" "$out"
  [ -f "$out/Library/Application Support/Code/User/settings.json" ]
}

@test "restore skips Library on Windows and AppData elsewhere" {
  b="$BATS_TEST_TMPDIR/b"
  mkdir -p "$b/Library/Preferences" "$b/AppData/Local/nvim"
  echo x > "$b/Library/Preferences/a.plist"
  echo x > "$b/AppData/Local/nvim/init.lua"
  restore_home "$b"
  [ -f "$HOME/AppData/Local/nvim/init.lua" ]
  [ ! -e "$HOME/Library/Preferences/a.plist" ]
  is_windows() { return 1; }
  rm -rf "$HOME/AppData"
  run restore_home "$b"
  [[ "$output" == *"(Windows only)"* ]] || false
  [ ! -e "$HOME/AppData/Local/nvim/init.lua" ]
}

@test "restore never writes to the Startup folder" {
  b="$BATS_TEST_TMPDIR/b"
  mkdir -p "$b/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
  echo x > "$b/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/evil.bat"
  run restore_home "$b"
  [ ! -e "$HOME/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/evil.bat" ]
}

@test "terminal backs up Windows Terminal settings" {
  wt="$HOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  mkdir -p "$wt"
  echo '{"profiles": {}}' > "$wt/settings.json"
  terminal_detect
  d="$BATS_TEST_TMPDIR/b"; mkdir -p "$d"
  terminal_backup "$d"
  [ -f "$d/home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" ]
}

@test "Google Drive for desktop is found on its drive letter" {
  DUDU_GDRIVE_PATH=""
  GDRIVE_LETTERS="$BATS_TEST_TMPDIR/g"
  mkdir -p "$BATS_TEST_TMPDIR/g/Meu Drive"
  [ "$(gdrive_root)" = "$BATS_TEST_TMPDIR/g/Meu Drive/dudu" ]
}

@test "Google Drive's mirrored folder in the user folder is found too" {
  DUDU_GDRIVE_PATH="" GDRIVE_LETTERS="$BATS_TEST_TMPDIR/none"
  mkdir -p "$HOME/My Drive"
  [ "$(gdrive_root)" = "$HOME/My Drive/dudu" ]
}

@test "iCloud for Windows is a destination when its folder exists" {
  run ! icloud_available
  mkdir -p "$HOME/iCloudDrive"
  icloud_available
  [ "$(icloud_root)" = "$HOME/iCloudDrive/dudu" ]
}

@test "Apple Notes is not available on Windows" {
  run ! notes_available
}

@test "the backup password goes to the Credential Manager when it works" {
  VAULT="$BATS_TEST_TMPDIR/vault"
  crypto_win_vault() {
    case "$1" in
      store) printf '%s' "$DUDU_PW" > "$VAULT" ;;
      read) cat "$VAULT" 2>/dev/null ;;
      forget) rm -f "$VAULT" ;;
    esac
  }
  crypto_store_password 's3cr3t "x"'
  [ "$(cat "$VAULT")" = 's3cr3t "x"' ]
  [ ! -f "$(crypto_key_file)" ]
  [ "$(crypto_stored_password)" = 's3cr3t "x"' ]
  crypto_forget_password
  [ ! -f "$VAULT" ]
}

@test "without the Credential Manager the password goes to a private file" {
  crypto_win_vault() { return 1; }
  crypto_store_password pw
  [ "$(cat "$(crypto_key_file)")" = pw ]
}

# A Mac's backup restored on Windows, with winget and scoop stand-ins.
mac_bundle_on_windows() {
  B="$BATS_TEST_TMPDIR/bundle"
  cp -R "$DUDU_ROOT/tests/fixtures/mac-bundle" "$B"
  LEFT="$BATS_TEST_TMPDIR/left-out"
  : > "$LEFT"
  fake_cmd winget 'case "$1" in
  export) while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done; echo "{\"PackageIdentifier\": \"Git.Git\"}" > "$out" ;;
  install) echo "winget $3" >> "$BATS_TEST_TMPDIR/installed" ;;
esac'
  fake_cmd scoop 'case "$1" in
  list) printf "Installed apps:\n\nName Version\n" ;;
  bucket) [ "$2" = add ] && echo "bucket $3" >> "$BATS_TEST_TMPDIR/installed" ;;
  install) echo "scoop $2" >> "$BATS_TEST_TMPDIR/installed" ;;
esac'
  win_path() { printf '%s' "$1"; }
  brew_load_shellenv() { return 1; }
}

@test "a Mac's Brewfile becomes winget and scoop packages" {
  mac_bundle_on_windows
  run crossos_windows_plan "$B/brew/Brewfile"
  [[ "$output" == *"winget|Git.Git|git"* ]] || false
  [[ "$output" == *"winget|PostgreSQL.PostgreSQL.16|postgresql@16"* ]] || false
  [[ "$output" == *"winget|SlackTechnologies.Slack|slack (cask)"* ]] || false
  # fd has a winget id; coreutils is in Git Bash; nvm is the node collector's.
  [[ "$output" == *"winget|sharkdp.fd|fd"* ]] || false
  [[ "$output" != *coreutils* ]] || false
  [[ "$output" != *nvm* ]] || false
  [[ "$output" == *"none|magnet (cask)"* ]] || false
  [[ "$output" == *"none|Xcode (App Store)"* ]] || false
}

@test "without winget, formulas go to scoop under their own name" {
  mac_bundle_on_windows
  rm "$BATS_TEST_TMPDIR/bin/winget"
  # The real winget too, on a Windows machine.
  has() { [ "$1" != winget ] && command -v "$1" >/dev/null 2>&1; }
  run crossos_windows_plan "$B/brew/Brewfile"
  [[ "$output" == *"scoop|git|git"* ]] || false
  [[ "$output" == *"scoop|slack|slack (cask)"* ]] || false
  [[ "$output" == *"none|postgresql@16"* ]] || false
}

@test "crossos_localize turns a Mac backup into this Windows' one" {
  mac_bundle_on_windows
  crossos_localize "$B" "$LEFT"
  [ -f "$B/vscode/home/AppData/Roaming/Code/User/settings.json" ]
  [ -z "$(find "$B" -path '*/home/Library*')" ]
  [ ! -d "$B/terminal/defaults" ]
  [ ! -f "$B/brew/Brewfile" ]
  # git is installed already: only what is missing stays.
  run ! grep -qx Git.Git "$B/brew/windows/winget.txt"
  grep -qx sharkdp.fd "$B/brew/windows/winget.txt"
  grep -qx SlackTechnologies.Slack "$B/brew/windows/winget.txt"
  grep -qx 'brew|magnet (cask)' "$LEFT"
  grep -q '^terminal|~/Library/' "$LEFT"
}

@test "brew restore on Windows installs the mapped packages" {
  mac_bundle_on_windows
  crossos_localize "$B" "$LEFT"
  brew_restore "$B/brew"
  grep -qx 'winget sharkdp.fd' "$BATS_TEST_TMPDIR/installed"
  grep -qx 'winget SlackTechnologies.Slack' "$BATS_TEST_TMPDIR/installed"
  run ! grep -q 'winget Git.Git' "$BATS_TEST_TMPDIR/installed"
}

@test "a Windows backup on a Mac or Linux sets AppData aside" {
  is_windows() { return 1; }
  dudu_os() { echo linux; }
  B="$BATS_TEST_TMPDIR/bundle" LEFT="$BATS_TEST_TMPDIR/left-out"
  mkdir -p "$B/terminal/home/AppData/Local/Packages/X/LocalState"
  echo '{}' > "$B/terminal/home/AppData/Local/Packages/X/LocalState/settings.json"
  printf '{"os": "windows"}\n' > "$B/manifest.json"
  : > "$LEFT"
  crossos_localize "$B" "$LEFT"
  [ ! -d "$B/terminal/home/AppData" ]
  grep -qx 'terminal|~/AppData/Local/Packages/X/LocalState/settings.json' "$LEFT"
}

@test "updates follow the win-v releases only" {
  out=$(printf '%s\n' '[{"tag_name": "v0.6.0"},' '{"tag_name": "win-v0.2.0"},' '{"tag_name": "win-v0.1.0"}]' | release_tags)
  [ "$out" = "$(printf '0.2.0\n0.1.0')" ]
  curl() { printf '%s\n' '[{"tag_name": "v0.6.0"},' '{"tag_name": "win-v0.2.0"}]'; }
  [ "$(latest_version)" = 0.2.0 ]
}

@test "the release notes come from the Windows changelog" {
  run "$DUDU_ROOT/packaging/release-notes.sh" --title "$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$DUDU_ROOT/dudu")"
  [ "$status" -eq 0 ]
  [[ "$output" == win-v* ]] || false
}

@test "Go tools are found from a Windows GOPATH" {
  fake_cmd go 'case "$1 $2" in
  "env GOBIN") printf "\r\n" ;;
  "env GOPATH") printf "C:\\\\Users\\\\x\\\\go;D:\\\\other\r\n" ;;
esac'
  [ "$(go_bin_dir)" = /c/Users/x/go/bin ]
}

@test "a folder pasted the Windows way is understood" {
  [ "$(folder_path_normalize 'C:\Users\Jo Silva\dudu')" = "/c/Users/Jo Silva/dudu" ]
  # Explorer's "Copy as path" adds the quotes.
  [ "$(folder_path_normalize '  "D:\Backups"  ')" = /d/Backups ]
  [ "$(folder_path_normalize 'D:/Backups/dudu')" = /d/Backups/dudu ]
  [ "$(folder_path_normalize '~/dudu')" = "$HOME/dudu" ]
  run ! folder_path_error "$(folder_path_normalize 'C:\Users\Jo\dudu')"
  run folder_path_error backups
  [ "$status" -eq 0 ]
  [[ "$output" == *'C:\Users\you\dudu'* ]] || false
}

@test "dudu config set path takes a Windows path" {
  mkdir -p "$DUDU_CONFIG_DIR"
  printf 'destination=local\n' > "$DUDU_CONFIG_FILE"
  cmd_config set path 'E:\dudu backups' >/dev/null
  config_load
  [ "$DUDU_PATH" = "/e/dudu backups" ]
}

@test "Documents follows OneDrive" {
  [ "$(win_documents)" = "$HOME/Documents" ]
  REG_Personal='%USERPROFILE%\OneDrive\Documents'
  [ "$(win_documents)" = "$HOME/OneDrive/Documents" ]
  REG_Personal='D:\Docs'
  [ "$(win_documents)" = /d/Docs ]
  # %USERPROFILE% is the Windows profile folder, which HOME may not be.
  REG_Personal='%USERPROFILE%\Documents' USERPROFILE='C:\Users\jo'
  [ "$(win_documents)" = /c/Users/jo/Documents ]
}

@test "PowerShell profiles are saved from, and restored to, a moved Documents" {
  REG_Personal='%USERPROFILE%\OneDrive\Documents'
  mkdir -p "$HOME/OneDrive/Documents/PowerShell"
  echo 'Set-Alias g git' > "$HOME/OneDrive/Documents/PowerShell/profile.ps1"
  d="$BATS_TEST_TMPDIR/b"; mkdir -p "$d"
  shell_backup "$d"
  [ "$(cat "$d/home/Documents/PowerShell/profile.ps1")" = 'Set-Alias g git' ]
  rm -rf "$HOME/OneDrive/Documents/PowerShell"
  shell_restore "$d" >/dev/null
  [ "$(cat "$HOME/OneDrive/Documents/PowerShell/profile.ps1")" = 'Set-Alias g git' ]
  [ ! -e "$HOME/Documents/PowerShell/profile.ps1" ]
}

@test "Oh My Zsh is not installed where there is no zsh" {
  has() { [ "$1" != zsh ] && command -v "$1" >/dev/null 2>&1; }
  curl() { echo called > "$BATS_TEST_TMPDIR/curl"; }
  d="$BATS_TEST_TMPDIR/b"; mkdir -p "$d"
  touch "$d/ohmyzsh"
  echo 'plugins/x https://github.com/x/x' > "$d/omz-custom.txt"
  run shell_restore "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Oh My Zsh left out"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/curl" ]
  [ ! -d "$HOME/.oh-my-zsh" ]
}

@test "another system's .bashrc is set aside, not restored over Git Bash's" {
  mac_bundle_on_windows
  mkdir -p "$B/shell/home"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' > "$B/shell/home/.bashrc"
  echo 'alias ll="ls -l"' > "$B/shell/home/.aliases"
  crossos_localize "$B" "$LEFT"
  [ ! -f "$B/shell/home/.bashrc" ]
  [ -f "$B/shell/home/.aliases" ]
  grep -qx 'shell|~/.bashrc' "$LEFT"
}

@test "npm globals of an nvm backup go to the node in use on Windows" {
  mkdir -p "$BATS_TEST_TMPDIR/npmroot/eslint"
  fake_cmd npm 'case "$1" in
  root) printf "%s\r\n" "$NPM_ROOT" ;;
  install) shift 2; echo "$*" >> "$BATS_TEST_TMPDIR/installed" ;;
esac'
  export NPM_ROOT="$BATS_TEST_TMPDIR/npmroot"
  d="$BATS_TEST_TMPDIR/b"; mkdir -p "$d"
  printf 'v20.11.0 eslint\nv20.11.0 typescript\n' > "$d/globals.txt"
  run npm_restore "$d"
  [ "$status" -eq 0 ]
  [[ "$output" != *"is not installed"* ]] || false
  [ "$(cat "$BATS_TEST_TMPDIR/installed")" = typescript ]
}

@test "the PATH takes in what installers added" {
  powershell.exe() { printf 'C:\\Go\\bin;C:\\Users\\x\\tools\;;C:\\Go\\bin\r\n'; }
  win_refresh_path
  [[ ":$PATH:" == *":/c/Go/bin:"* ]] || false
  [[ ":$PATH:" == *":/c/Users/x/tools:"* ]] || false
  [ "$(printf '%s' "$PATH" | tr ':' '\n' | grep -cx /c/Go/bin)" -eq 1 ]
}

@test "Chocolatey is not started outside an administrator terminal" {
  fake_cmd choco 'case "$1" in
  list) printf "git|2.47.0\r\n" ;;
  install) echo "$*" >> "$BATS_TEST_TMPDIR/installed" ;;
esac'
  win_is_admin() { return 1; }
  win_refresh_path() { :; }
  d="$BATS_TEST_TMPDIR/b"; mkdir -p "$d"
  printf 'git\nneovim\n' > "$d/packages.txt"
  run choco_restore "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"administrator terminal"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/installed" ]
  win_is_admin() { return 0; }
  choco_restore "$d"
  grep -q neovim "$BATS_TEST_TMPDIR/installed"
}

@test "pyenv-win's Windows line ends do not reach the backup" {
  fake_cmd pyenv 'case "$1" in
  versions) printf "3.11.9\r\n3.12.4\r\n" ;;
  global) printf "3.12.4\r\n" ;;
esac'
  has() { case "$1" in pipx | uv | python3 | py) return 1 ;; esac; command -v "$1" >/dev/null 2>&1; }
  d="$BATS_TEST_TMPDIR/b"; mkdir -p "$d"
  run python_backup "$d"
  [ "$status" -eq 0 ]
  [ "$(cat "$d/pyenv.txt")" = "$(printf '3.11.9\n3.12.4')" ]
  [ "$(cat "$d/pyenv-global")" = 3.12.4 ]
}

@test "a password kept in a file on Windows is said out loud" {
  crypto_win_vault() { return 1; }
  run crypto_store_password pw
  [[ "$output" == *"Credential Manager did not take the password"* ]] || false
}

@test "RESTORE.md gives the installer of each system" {
  out=$(restore_install_lines)
  [[ "$out" == *"windows/install.ps1 | iex"* ]] || false
  [[ "$out" == *"main/install.sh | bash"* ]] || false
}

@test "Apple Notes is not offered on Windows" {
  checklist_select() { printf '%s\n' "${CL_DEST[@]}" > "$BATS_TEST_TMPDIR/dests"; return 1; }
  run config_pick_destination
  run ! grep -qx notes "$BATS_TEST_TMPDIR/dests"
  grep -qx local "$BATS_TEST_TMPDIR/dests"
}

@test "OneDrive is a destination where Windows says its folder is" {
  unset OneDrive OneDriveConsumer OneDriveCommercial ONEDRIVE
  run ! onedrive_available
  mkdir -p "$HOME/od personal"
  OneDrive="$HOME/od personal"
  onedrive_available
  [ "$(onedrive_root)" = "$HOME/od personal/dudu" ]
  [ "$(dest_folder_root onedrive)" = "$HOME/od personal/dudu" ]
  [ "$(dest_label onedrive)" = OneDrive ]
  list_has "$(echo "$DUDU_DESTINATIONS" | tr ' ' ',')" onedrive
}

@test "a backup saved to OneDrive is found again" {
  mkdir -p "$HOME/OneDrive"
  unset OneDrive OneDriveConsumer OneDriveCommercial ONEDRIVE
  b="$BATS_TEST_TMPDIR/2026-11-01_101010Z-ab12"; mkdir -p "$b/shell"
  echo x > "$b/shell/.summary"
  printf '{\n  "host": "pc",\n  "created": "2026-11-01T10:10:10Z",\n  "partial": false\n}\n' > "$b/manifest.json"
  bundle_sums "$b"
  onedrive_save "$b" pc >/dev/null
  [ "$(onedrive_hosts)" = pc ]
  out="$BATS_TEST_TMPDIR/out"; mkdir -p "$out"
  onedrive_load pc "$out"
  [ -f "$out/manifest.json" ]
}

@test "dudu installed with scoop is updated and found through scoop" {
  DUDU_ROOT="/c/Users/x/scoop/apps/dudu/0.2.0"
  installed_by_scoop
  [ "$(stable_root)" = /c/Users/x/scoop/apps/dudu/current ]
  [ "$(update_command)" = "scoop update dudu" ]
  DUDU_ROOT="/c/Users/x/.local/share/dudu"
  run ! installed_by_scoop
  [ "$(update_command)" = "dudu update" ]
}

@test "the old Windows console is told from the modern terminals" {
  # A terminal is needed to matter at all: the test's output is not one.
  run ! legacy_console
  unset WT_SESSION TERM_PROGRAM ConEmuPID
  legacy_console_env
  WT_SESSION=abc run ! legacy_console_env
  TERM_PROGRAM=mintty run ! legacy_console_env
}

@test "dudu completion powershell prints a completer" {
  run cmd_completion powershell
  [ "$status" -eq 0 ]
  [[ "$output" == *"Register-ArgumentCompleter -Native -CommandName dudu"* ]] || false
  [[ "$output" == *"'uninstall'"* ]] || false
}

# doctor and uninstall, with Windows' own tools as stand-ins.
windows_tools() {
  win_is_admin() { return 1; }
  cmd.exe() { return 0; }
  crypto_win_vault() {
    case "$1" in
      store) printf '%s' "$DUDU_PW" > "$BATS_TEST_TMPDIR/vault" ;;
      read) cat "$BATS_TEST_TMPDIR/vault" 2>/dev/null ;;
      forget) rm -f "$BATS_TEST_TMPDIR/vault" ;;
    esac
  }
  schtasks() { return 1; }
  # Stands in for Windows: the folder dudu asks to have removed once it has ended goes now.
  powershell.exe() {
    echo "powershell" >> "$BATS_TEST_TMPDIR/ps-calls"
    case "$*" in *rmdir*) rm -rf "$DUDU_LIB" ;; esac
  }
  win_path() { printf '%s' "$1"; }
}

@test "dudu doctor says what is there and what is missing" {
  windows_tools
  DUDU_ROOT="$BATS_TEST_TMPDIR/app"; mkdir -p "$DUDU_ROOT"; touch "$DUDU_ROOT/dudu.cmd"
  mkdir -p "$DUDU_CONFIG_DIR"
  printf 'destination=local\npath=%s\n' "$HOME/backups" > "$DUDU_CONFIG_FILE"
  run cmd_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Windows Credential Manager"* ]] || false
  [[ "$output" == *"only Chocolatey needs it"* ]] || false
  [[ "$output" == *"the dudu command is in the PATH"* ]] || false
  [[ "$output" == *"dudu is ready to use"* ]] || false
  # Looking is all it does.
  [ ! -e "$HOME/backups" ]
}

@test "dudu doctor fails on a destination that is not there" {
  windows_tools
  mkdir -p "$DUDU_CONFIG_DIR"
  printf 'destination=icloud\n' > "$DUDU_CONFIG_FILE"
  run cmd_doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"not available on this machine"* ]] || false
  [[ "$output" == *"1 problem keeps dudu from working"* ]] || false
}

@test "dudu doctor warns when the command is not in the PATH" {
  windows_tools
  cmd.exe() { return 1; }
  crypto_win_vault() { return 1; }
  run cmd_doctor
  [[ "$output" == *"the dudu command is not in the PATH"* ]] || false
  [[ "$output" == *"Credential Manager does not answer"* ]] || false
}

# A dudu installed in the test's HOME, as install.sh leaves it.
installed_copy() {
  DUDU_ROOT="$HOME/.local/share/dudu"
  mkdir -p "$DUDU_ROOT/lib/core" "$HOME/bin" "$DUDU_CONFIG_DIR"
  touch "$DUDU_ROOT/dudu" "$DUDU_ROOT/lib/core/common.sh"
  printf '#!/usr/bin/env bash\nexec "%s/dudu" "$@"\n' "$DUDU_ROOT" > "$HOME/bin/dudu"
  printf 'destination=local\n' > "$DUDU_CONFIG_FILE"
  mkdir -p "$HOME/dudu-backups/pc"
}

@test "dudu uninstall removes dudu and keeps settings and backups" {
  windows_tools; installed_copy
  run cmd_uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/share/dudu" ]
  [ ! -e "$HOME/bin/dudu" ]
  [ -f "$DUDU_CONFIG_FILE" ]
  [ -d "$HOME/dudu-backups/pc" ]
  # The Start menu entry and the PATH are Windows' to change.
  [ -s "$BATS_TEST_TMPDIR/ps-calls" ]
  [[ "$output" == *"Your backups were not touched"* ]] || false
}

@test "dudu uninstall --purge also deletes settings and the stored password" {
  windows_tools; installed_copy
  DUDU_PW=secret crypto_win_vault store
  run cmd_uninstall -y --purge
  [ "$status" -eq 0 ]
  [ ! -e "$DUDU_CONFIG_DIR" ]
  [ ! -e "$BATS_TEST_TMPDIR/vault" ]
  [ -d "$HOME/dudu-backups/pc" ]
}

@test "dudu uninstall asks first, and needs -y without a terminal" {
  windows_tools; installed_copy
  run cmd_uninstall < /dev/null
  [ "$status" -eq 1 ]
  [ -f "$DUDU_ROOT/dudu" ]
}

@test "dudu uninstall never deletes a folder that is not dudu's, or another dudu's command" {
  windows_tools; installed_copy
  printf '#!/usr/bin/env bash\nexec "/opt/other/dudu" "$@"\n' > "$HOME/bin/dudu"
  uninstall_commands
  [ -f "$HOME/bin/dudu" ]
  DUDU_ROOT="$HOME"
  run ! uninstall_program
  [ -d "$HOME/dudu-backups" ]
  DUDU_ROOT="$BATS_TEST_TMPDIR/not-dudu"; mkdir -p "$DUDU_ROOT"; touch "$DUDU_ROOT/keep"
  run ! uninstall_program
  [ -f "$DUDU_ROOT/keep" ]
}

@test "a git checkout is not deleted by dudu uninstall" {
  windows_tools; installed_copy
  mkdir "$DUDU_ROOT/.git"
  run cmd_uninstall -y
  [ "$status" -eq 0 ]
  [ -f "$DUDU_ROOT/dudu" ]
  [[ "$output" == *"git checkout"* ]] || false
}

@test "dudu.cmd is a batch file Windows can run: CRLF, plain ASCII, no folder of its own" {
  f="$DUDU_ROOT/dudu.cmd"
  run ! env LC_ALL=C grep -q '[^[:print:][:space:]]' "$f"
  grep -qF '%~dp0' "$f"
  run ! grep -qi 'C:\\Users' "$f"
  # git gives it CRLF on checkout (.gitattributes), whatever the working copy has here.
  grep -q '^\*\.cmd text eol=crlf' "$DUDU_ROOT/.gitattributes"
}

@test "the scoop manifest names the release's zip and dudu.cmd" {
  m=$(sed -e 's/@VERSION@/9.9.9/g' -e 's/@SHA256@/abc/' "$DUDU_ROOT/packaging/scoop/dudu.json")
  [[ "$m" == *'"version": "9.9.9"'* ]] || false
  [[ "$m" == *'/releases/download/win-v9.9.9/dudu-9.9.9.zip"'* ]] || false
  [[ "$m" == *'"extract_dir": "dudu-9.9.9"'* ]] || false
  [[ "$m" == *'"bin": "dudu.cmd"'* ]] || false
  [[ "$m" != *@* ]] || false
  [ -f "$DUDU_ROOT/dudu.cmd" ]
}
