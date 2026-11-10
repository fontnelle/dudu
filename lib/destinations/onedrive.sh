#!/usr/bin/env bash
# OneDrive: the folder its app syncs, which Windows comes with. %OneDrive% names it there
# (a personal account first, then a work one); elsewhere it is ~/OneDrive when that exists.

onedrive_base() {
  local d=""
  if is_windows; then
    d=${OneDriveConsumer:-${OneDrive:-${ONEDRIVE:-${OneDriveCommercial:-}}}}
    [ -n "$d" ] && d=$(unix_path "$d")
  fi
  [ -n "$d" ] || d="$HOME/OneDrive"
  printf '%s' "${d%/}"
}
onedrive_root() { printf '%s' "$(onedrive_base)/dudu"; }
onedrive_available() { [ -d "$(onedrive_base)" ]; }
onedrive_where() { printf 'OneDrive/dudu'; }
onedrive_save() { folder_save "$(onedrive_root)" "$1" "$2"; }
onedrive_load() { folder_load "$(onedrive_root)" "$1" "$2"; }
onedrive_hosts() { folder_hosts "$(onedrive_root)"; }
