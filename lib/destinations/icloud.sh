#!/usr/bin/env bash
# iCloud Drive: ~/Library/Mobile Documents/com~apple~CloudDocs/dudu on macOS, and
# %USERPROFILE%\iCloudDrive\dudu with iCloud for Windows.

icloud_base() {
  if is_windows; then printf '%s' "$HOME/iCloudDrive"; else printf '%s' "$HOME/Library/Mobile Documents/com~apple~CloudDocs"; fi
}
icloud_root() { printf '%s' "$(icloud_base)/dudu"; }
icloud_available() { { is_macos || is_windows; } && [ -d "$(icloud_base)" ]; }
icloud_where() { printf 'iCloud Drive/dudu'; }
icloud_save() { folder_save "$(icloud_root)" "$1" "$2"; }
icloud_load() { folder_load "$(icloud_root)" "$1" "$2"; }
icloud_hosts() { folder_hosts "$(icloud_root)"; }
