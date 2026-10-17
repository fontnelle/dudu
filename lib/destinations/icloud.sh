#!/usr/bin/env bash
# iCloud Drive (macOS): ~/Library/Mobile Documents/com~apple~CloudDocs/dudu

icloud_root() { printf '%s' "$HOME/Library/Mobile Documents/com~apple~CloudDocs/dudu"; }
icloud_available() { is_macos && [ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; }
icloud_where() { printf 'iCloud Drive/dudu'; }
icloud_save() { folder_save "$(icloud_root)" "$1" "$2"; }
icloud_load() { folder_load "$(icloud_root)" "$1" "$2"; }
icloud_hosts() { folder_hosts "$(icloud_root)"; }
