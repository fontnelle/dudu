#!/usr/bin/env bash
# Google Drive: straight through rclone (dudu config gdrive), or the Drive for desktop folder.
# config: rclone_remote=<remote:path> uses rclone; gdrive_path=<folder> overrides detection.

gdrive_root() {
  # A folder set by hand counts only when it is a full path whose parent exists.
  if [ -n "$DUDU_GDRIVE_PATH" ] && ! folder_path_error "$DUDU_GDRIVE_PATH" >/dev/null &&
     [ -d "$(dirname "$DUDU_GDRIVE_PATH")" ]; then
    printf '%s' "$DUDU_GDRIVE_PATH"
    return 0
  fi
  local base d
  for base in "$HOME"/Library/CloudStorage/GoogleDrive-*; do
    [ -d "$base" ] || continue
    for d in "My Drive" "Meu Drive" "Mi unidad" "Mon Drive" "Meine Ablage" "Il mio Drive"; do
      [ -d "$base/$d" ] && { printf '%s' "$base/$d/dudu"; return 0; }
    done
  done
  for d in "$HOME/GoogleDrive" "$HOME/Google Drive" "$HOME/gdrive"; do
    [ -d "$d" ] && { printf '%s' "$d/dudu"; return 0; }
  done
  # Drive for desktop on Windows: a drive letter (G: by default) with My Drive in it, or
  # the mirrored folder in the user's folder.
  if is_windows; then
    # shellcheck disable=SC2086 # a list of folders
    for base in "$HOME" ${GDRIVE_LETTERS:-/g /h /i /j /k /d /e /f /l /m /n /o /p /q /r /s /t /u /v /w /x /y /z}; do
      for d in "My Drive" "Meu Drive" "Mi unidad" "Mon Drive" "Meine Ablage" "Il mio Drive"; do
        [ -d "$base/$d" ] && { printf '%s' "$base/$d/dudu"; return 0; }
      done
    done
  fi
  return 1
}

gdrive_available() {
  [ -n "$DUDU_RCLONE_REMOTE" ] && has rclone && return 0
  gdrive_root >/dev/null
}

gdrive_where() {
  if [ -n "$DUDU_RCLONE_REMOTE" ]; then printf 'rclone %s' "$DUDU_RCLONE_REMOTE"; else gdrive_root; fi
}

# Through rclone each machine has its folder "dudu-<host>", made by dudu, so it stays visible
# with drive.file access. Folders named just <host> (Drive for desktop, dudu 0.4 and 0.5) are
# read too.
gdrive_host_dir() { printf 'dudu-%s' "$1"; }

# The machines with a backup under <remote>: the folders that hold a "latest" file.
rclone_hosts() { # <remote>
  rclone lsf -R --max-depth 2 --files-only --include '/*/latest' "$1" 2>/dev/null |
    sed -n 's|^\([^/]*\)/latest$|\1|p' | sed 's/^dudu-//' | grep -E '^[A-Za-z0-9._-]+$' | LC_ALL=C sort -u
}

# The web address of <host>'s backup folder under <remote>, or nothing.
gdrive_folder_link() { # <remote> <host>
  local id
  id=$(rclone lsjson --stat "$(rclone_join "$1" "$(gdrive_host_dir "$2")")" 2>/dev/null |
       sed -n 's/.*"ID":"\([A-Za-z0-9_-]*\)".*/\1/p' | head -1)
  [ -n "$id" ] && printf 'https://drive.google.com/drive/folders/%s' "$id"
}

# Each backup goes up as one "<stamp>.tar.gz": Google Drive takes about a second per file
# and per folder it creates, so a tree of small files took minutes where one archive takes
# seconds. Older backups saved as folders are still read, and dropped by "keep".
gdrive_save() {
  if [ -n "$DUDU_RCLONE_REMOTE" ]; then
    local remote stamp tmp entry n=0
    remote=$(rclone_join "$DUDU_RCLONE_REMOTE" "$(gdrive_host_dir "$2")")
    stamp=$(basename "$1")
    tmp=$(mktemp -d)
    tar -czf "$tmp/$stamp.tar.gz" -C "$(dirname "$1")" "$stamp" || { rm -rf "$tmp"; return 1; }
    if ! rclone_upload "$tmp/$stamp.tar.gz" "$remote/$stamp.tar.gz"; then rm -rf "$tmp"; return 1; fi
    # Checked against the local archive before "latest" moves and anything old is removed.
    if [ "$(rclone_md5 "$remote/$stamp.tar.gz")" != "$(rclone_md5 "$tmp/$stamp.tar.gz")" ]; then
      rm -rf "$tmp"
      err "$(t "The copy on %s does not match" "$remote")"
      return 1
    fi
    rm -rf "$tmp"
    if ! manifest_is_partial "$1/manifest.json"; then
      printf '%s\n' "$stamp" | rclone rcat "$remote/latest" || return 1
    fi
    for entry in $(rclone_backups "$remote"); do
      [ "$entry" = "$stamp.tar.gz" ] && { n=$((n + 1)); continue; }
      # The same backup as a folder (an older save) is now a copy of the archive.
      if [ "$entry" != "$stamp/" ]; then
        n=$((n + 1))
        [ $n -gt "$(( ${DUDU_KEEP:-5} < 1 ? 1 : ${DUDU_KEEP:-5} ))" ] || continue
      fi
      case "$entry" in
        # purge is refused with drive.file access (appNotAuthorizedToChild), and files in
        # the trash keep their folder from being removed: delete them for good, then the folders.
        */) rclone delete --drive-use-trash=false --rmdirs "$remote/${entry%/}" &&
              rclone rmdir --drive-use-trash=false "$remote/${entry%/}" ;;
        *) rclone deletefile "$remote/$entry" ;;
      esac
    done
    printf '%s\n' "$remote/$stamp.tar.gz"
    return 0
  fi
  local root
  root=$(gdrive_root) || { err "$(t "Google Drive folder not found. Set it with: %s" "dudu config gdrive")"; return 1; }
  folder_save "$root" "$1" "$2"
}

# The backups in one machine folder, newest first: "<stamp>.tar.gz", or "<stamp>/" when
# saved as a folder by dudu 0.5 and older (the archive first when a stamp has both).
rclone_backups() { # <remote machine folder>
  rclone lsf "$1" 2>/dev/null | tr -d '\r' | while IFS= read -r e; do
    case "$e" in
      */) valid_stamp "${e%/}" && printf '%s 1 %s\n' "${e%/}" "$e" ;;
      *.tar.gz) valid_stamp "${e%.tar.gz}" && printf '%s 2 %s\n' "${e%.tar.gz}" "$e" ;;
    esac
  done | LC_ALL=C sort -r | cut -d' ' -f3
}

rclone_md5() { rclone md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

# Uploads one file, writing "<percent> <time left>" to $DUDU_SPIN_STATUS once a second for
# the spinner. rclone's own lines still go to the log.
rclone_upload() { # <file> <remote file>
  local line status="${DUDU_SPIN_STATUS:-}"
  rclone copyto "$1" "$2" --stats 1s --stats-one-line --stats-log-level NOTICE 2>&1 |
    while IFS= read -r line; do
      if [[ "$line" =~ ([0-9]+)%,.*ETA\ ([0-9a-z]+) ]]; then
        [ -n "$status" ] && printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" > "$status"
      else
        printf '%s\n' "$line"
      fi
    done
  return "${PIPESTATUS[0]}"
}

# Loads the newest backup in one machine folder of rclone; a damaged copy falls back to the
# next one, "latest" first and then the others newest first.
gdrive_rclone_load() { # <remote machine folder> <out>
  local latest entry all first="" tmp
  latest=$(rclone cat "$1/latest" 2>/dev/null | head -1 | tr -d '\r')
  valid_stamp "$latest" || latest=""
  all=$(rclone_backups "$1")
  for entry in $(printf '%s\n' "$all" | grep -xF -e "$latest.tar.gz" -e "$latest/" 2>/dev/null | head -1) \
               $(printf '%s\n' "$all" | grep -vxF -e "${latest:-none}.tar.gz" -e "${latest:-none}/"); do
    [ -z "$first" ] && first=$entry
    rm -rf "${2:?}"/* "$2"/.[!.]* 2>/dev/null
    case "$entry" in
      */) rclone copy "$1/${entry%/}" "$2" && bundle_verify "$2" && break ;;
      *)
        tmp=$(mktemp -d)
        if rclone copyto "$1/$entry" "$tmp/b.tar.gz" &&
           tar -xzf "$tmp/b.tar.gz" -C "$2" --strip-components 1 && bundle_verify "$2"; then
          rm -rf "$tmp"
          break
        fi
        rm -rf "$tmp" ;;
    esac
    printf 'damaged backup skipped: %s/%s\n' "$1" "$entry" >> "$DUDU_LOG"
    entry=""
  done
  [ -n "$entry" ] || return 1
  [ "$entry" != "$first" ] && warn "$(t "The newest backup was damaged, using %s" "$(basename "$entry" .tar.gz)")" >&2
  return 0
}

gdrive_load() {
  if [ -n "$DUDU_RCLONE_REMOTE" ]; then
    local d
    for d in "$(gdrive_host_dir "$1")" "$1"; do
      gdrive_rclone_load "$(rclone_join "$DUDU_RCLONE_REMOTE" "$d")" "$2" && return 0
    done
    return 1
  fi
  folder_load "$(gdrive_root)" "$1" "$2"
}

gdrive_hosts() {
  if [ -n "$DUDU_RCLONE_REMOTE" ]; then
    rclone_hosts "$DUDU_RCLONE_REMOTE"
    return 0
  fi
  local root
  root=$(gdrive_root) || return 0
  folder_hosts "$root"
}
