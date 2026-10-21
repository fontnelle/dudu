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
