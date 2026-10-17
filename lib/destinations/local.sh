#!/usr/bin/env bash
# Folder-based storage, shared by local, icloud and gdrive.
# Layout: <root>/<host>/<YYYY-MM-DD_HHMMSS>/ plus <root>/<host>/latest (a text file,
# because cloud drives do not sync symlinks well).
#
# Every destination implements: <d>_available, <d>_where, <d>_save <bundle> <host>,
# <d>_load <host> <out>, <d>_hosts.

folder_free_kb() { df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4 }'; }

# Copies the bundle to <root>/<host>/.<stamp>.partial, checks every file against SHA256SUMS,
# then renames it: a stamp folder only ever exists complete. "latest" moves only after that,
# and never to a partial backup (--only without data for the other tools).
folder_save() { # <root> <bundle> <host>
  local dir="$1/$3" stamp tmp need free
  stamp=$(basename "$2")
  valid_stamp "$stamp" || return 1
  mkdir -p "$dir" || return 1
  chmod 700 "$1" "$dir" 2>/dev/null
  need=$(du -sk "$2" | awk '{ print $1 * 2 + 1024 }')
  free=$(folder_free_kb "$dir")
  if [ -n "$free" ] && [ "$free" -lt "$need" ]; then
    err "$(t "Not enough free space in %s" "$dir")"
    return 1
  fi
  [ -e "$dir/$stamp" ] && { err "$(t "%s already exists" "$dir/$stamp")"; return 1; }
  tmp="$dir/.$stamp.partial"
  rm -rf "$tmp"
  if ! cp -R "$2" "$tmp" || ! bundle_verify "$tmp"; then
    rm -rf "$tmp"
    err "$(t "The copy in %s does not match the backup" "$dir")"
    return 1
  fi
  chmod -R go-rwx "$tmp" 2>/dev/null
  mv "$tmp" "$dir/$stamp" || { rm -rf "$tmp"; return 1; }
  if ! manifest_is_partial "$dir/$stamp/manifest.json"; then
    printf '%s\n' "$stamp" > "$dir/.latest.tmp" && mv "$dir/.latest.tmp" "$dir/latest"
  fi
  folder_prune "$dir" "$stamp"
  printf '%s\n' "$dir/$stamp"
}

# Keeps the newest DUDU_KEEP backups (at least 1). Never deletes the backup just saved, the
# one "latest" points to, or the newest complete one. Leftover .partial folders older than
# a day (an interrupted save) are removed.
folder_prune() { # <dir> [stamp just saved]
  local dir=$1 keep=${DUDU_KEEP:-5} n=0 d latest="" complete=""
  [ "$keep" -ge 1 ] 2>/dev/null || keep=1
  [ -f "$dir/latest" ] && latest=$(head -1 "$dir/latest" | tr -d '\r')
  for d in $(folder_stamps "$dir"); do
    if [ -z "$complete" ] && [ -f "$dir/$d/manifest.json" ] && ! manifest_is_partial "$dir/$d/manifest.json"; then
      complete=$d
      continue
    fi
    n=$((n + 1))
    [ "$d" = "${2:-}" ] || [ "$d" = "$latest" ] && continue
    [ $n -ge "$keep" ] && rm -rf "${dir:?}/$d"
  done
  find "$dir" -maxdepth 1 -name '.*.partial' -type d -mtime +0 -exec rm -rf {} + 2>/dev/null
  return 0
}

folder_stamps() { # <dir>, newest first
  ls -1 "$1" 2>/dev/null | grep -E "$STAMP_RE" | LC_ALL=C sort -r
}

# Backups of <host> to try, best first: the one "latest" names, then the others newest
# first. Only folders with a manifest count; placeholders and partial copies never do.
folder_candidates() { # <root> <host>
  local dir="$1/$2" stamp="" d
  [ -f "$dir/latest" ] && stamp=$(head -1 "$dir/latest" | tr -d '\r')
  valid_stamp "$stamp" && [ -f "$dir/$stamp/manifest.json" ] && printf '%s\n' "$stamp"
  for d in $(folder_stamps "$dir"); do
    [ "$d" = "$stamp" ] && continue
    [ -f "$dir/$d/manifest.json" ] && printf '%s\n' "$d"
  done
  return 0
}

folder_latest() { # <root> <host>
  local s
  # No "| head -1": folder_candidates would write into a closed pipe.
  s=$(folder_candidates "$1" "$2")
  s=${s%%$'\n'*}
  [ -n "$s" ] && printf '%s' "$s"
}

# iCloud keeps files in the cloud until read: ask for them and wait for the placeholders
# (.name.icloud) to turn into real files.
folder_materialize() { # <dir>
  has brctl || return 0
  brctl download "$1" >/dev/null 2>&1 || true
  local waited=0
  while find "$1" -name '.*.icloud' 2>/dev/null | grep -q .; do
    [ $waited -ge 120 ] && return 1
    sleep 2
    waited=$((waited + 2))
  done
  return 0
}

# Loads the newest backup that passes its checksums; a damaged one falls back to the next.
folder_load() { # <root> <host> <out>
  local stamp first=""
  for stamp in $(folder_candidates "$1" "$2"); do
    [ -z "$first" ] && first=$stamp
    if ! folder_materialize "$1/$2/$stamp"; then
      warn "$(t "iCloud did not download %s in time, trying an older backup" "$stamp")" >&2
      continue
    fi
    if bundle_verify "$1/$2/$stamp"; then
      [ "$stamp" != "$first" ] && warn "$(t "The newest backup was damaged, using %s" "$stamp")" >&2
      cp -R "$1/$2/$stamp/." "$3/" && return 0
    fi
    printf 'damaged backup skipped: %s/%s/%s\n' "$1" "$2" "$stamp" >> "$DUDU_LOG"
  done
  return 1
}

folder_hosts() {
  local d
  for d in "$1"/*/; do
    [ -d "$d" ] && [ -n "$(folder_latest "$1" "$(basename "$d")")" ] && basename "$d"
  done
  return 0
}

local_root() { printf '%s' "${DUDU_PATH:-$HOME/dudu-backups}"; }
local_available() { return 0; }
local_where() { local_root; }
local_save() { folder_save "$(local_root)" "$1" "$2"; }
local_load() { folder_load "$(local_root)" "$1" "$2"; }
local_hosts() { folder_hosts "$(local_root)"; }
