#!/usr/bin/env bash
# Google Drive: the Drive for desktop folder on macOS, a mounted folder or rclone on Linux.
# config: gdrive_path=<folder> overrides detection; rclone_remote=<remote:path> uses rclone.

gdrive_root() {
  if [ -n "$DUDU_GDRIVE_PATH" ]; then printf '%s' "$DUDU_GDRIVE_PATH"; return 0; fi
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
  return 1
}

gdrive_available() {
  [ -n "$DUDU_RCLONE_REMOTE" ] && has rclone && return 0
  gdrive_root >/dev/null
}

gdrive_where() {
  if [ -n "$DUDU_RCLONE_REMOTE" ]; then printf 'rclone %s' "$DUDU_RCLONE_REMOTE"; else gdrive_root; fi
}

gdrive_save() {
  if [ -n "$DUDU_RCLONE_REMOTE" ]; then
    local remote stamp d n=0
    remote=$(rclone_join "$DUDU_RCLONE_REMOTE" "$2")
    stamp=$(basename "$1")
    rclone copy "$1" "$remote/$stamp" || return 1
    # Checked against the local bundle before "latest" moves and anything old is removed.
    rclone check "$1" "$remote/$stamp" --one-way >/dev/null 2>&1 || { err "$(t "The copy on %s does not match" "$remote")"; return 1; }
    if ! manifest_is_partial "$1/manifest.json"; then
      printf '%s\n' "$stamp" | rclone rcat "$remote/latest" || return 1
    fi
    for d in $(rclone lsf --dirs-only "$remote" | tr -d '/' | grep -E "$STAMP_RE" | LC_ALL=C sort -r); do
      n=$((n + 1))
      [ "$d" = "$stamp" ] && continue
      [ $n -gt "$(( ${DUDU_KEEP:-5} < 1 ? 1 : ${DUDU_KEEP:-5} ))" ] && rclone purge "$remote/$d"
    done
    printf '%s\n' "$remote/$stamp"
    return 0
  fi
  local root
  root=$(gdrive_root) || { err "$(t "Google Drive folder not found. Set it with: %s" "dudu config gdrive")"; return 1; }
  folder_save "$root" "$1" "$2"
}

gdrive_load() {
  if [ -n "$DUDU_RCLONE_REMOTE" ]; then
    local remote latest stamp first=""
    remote=$(rclone_join "$DUDU_RCLONE_REMOTE" "$1")
    latest=$(rclone cat "$remote/latest" 2>/dev/null | head -1 | tr -d '\r')
    valid_stamp "$latest" || latest=""
    # "latest" first, then the others newest first: a damaged copy falls back to the next.
    for stamp in $latest $(rclone lsf --dirs-only "$remote" 2>/dev/null | tr -d '/' | grep -E "$STAMP_RE" |
                           LC_ALL=C sort -r | grep -vxF -- "${latest:-none}"); do
      [ -z "$first" ] && first=$stamp
      rm -rf "${2:?}"/* "$2"/.[!.]* 2>/dev/null
      if rclone copy "$remote/$stamp" "$2" && bundle_verify "$2"; then
        [ "$stamp" != "$first" ] && warn "$(t "The newest backup was damaged, using %s" "$stamp")" >&2
        return 0
      fi
      printf 'damaged backup skipped: %s/%s\n' "$remote" "$stamp" >> "$DUDU_LOG"
    done
    return 1
  fi
  folder_load "$(gdrive_root)" "$1" "$2"
}

gdrive_hosts() {
  if [ -n "$DUDU_RCLONE_REMOTE" ]; then
    rclone lsf --dirs-only "${DUDU_RCLONE_REMOTE%/}" 2>/dev/null | tr -d '/'
    return 0
  fi
  local root
  root=$(gdrive_root) || return 0
  folder_hosts "$root"
}
