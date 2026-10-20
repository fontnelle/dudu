#!/usr/bin/env bash
# Integrity of backups: a SHA256SUMS file in every backup, checked after every save and
# before every restore, plus a stable machine id so two Macs named alike never mix.

# Backup folder names: UTC with a random suffix, so two runs in the same second never
# share (and merge into) one folder. The old local-time form is still read.
STAMP_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}(Z-[0-9a-f]{4})?$'

backup_stamp() {
  # Two random bytes, read with a fixed size: "tr < /dev/urandom | head" never ends where
  # SIGPIPE is ignored.
  printf '%sZ-%s' "$(date -u +%Y-%m-%d_%H%M%S)" "$(od -An -N2 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
}

valid_stamp() { printf '%s\n' "$1" | grep -Eq "$STAMP_RE"; }

sha256_file() {
  if has shasum; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi
}

# Writes <dir>/SHA256SUMS: "hash  path" for every file, sorted, paths relative to <dir>.
bundle_sums() { # <dir>
  local f tmp
  (
    cd "$1" || exit 1
    tmp=$(mktemp)
    find . -type f ! -name SHA256SUMS ! -name .dudu-source | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(sha256_file "$f")" "${f#./}"
    done > "$tmp" && cat "$tmp" > SHA256SUMS
    rm -f "$tmp"
  )
}

# True when every file listed in <dir>/SHA256SUMS is there with the same content, and no
# listed file is missing. Backups made before SHA256SUMS existed pass (nothing to check).
bundle_verify() { # <dir>
  local hash path bad=0
  [ -f "$1/SHA256SUMS" ] || return 0
  while IFS= read -r line; do
    hash=${line%%  *}
    path=${line#*  }
    case "$path" in /*|*..*) bad=1; break ;; esac
    if [ ! -f "$1/$path" ] || [ "$(sha256_file "$1/$path")" != "$hash" ]; then
      bad=1
      printf 'checksum mismatch: %s\n' "$path" >> "$DUDU_LOG"
      break
    fi
  done < "$1/SHA256SUMS"
  return $bad
}

# Short, stable id of this machine (hashed, so the hardware id itself is never stored).
machine_id() {
  local raw=""
  if is_macos; then
    raw=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | sed -n 's/.*"IOPlatformUUID" = "\(.*\)"/\1/p')
  elif is_windows; then
    raw=$(win_reg 'HKLM\SOFTWARE\Microsoft\Cryptography' MachineGuid)
  fi
  [ -n "$raw" ] || raw=$(cat /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null | head -1)
  [ -n "$raw" ] || raw=$(uname -n)
  printf 'dudu:%s' "$raw" | sha256_stdin | cut -c1-12
}

manifest_value() { # <manifest.json> <field>
  sed -n "s/.*\"$2\": *\"\\([^\"]*\\)\".*/\\1/p" "$1" 2>/dev/null | head -1
}

manifest_is_partial() { grep -q '"partial": *true' "$1" 2>/dev/null; }

# Folder root of a folder-based destination (local, icloud, gdrive without rclone).
dest_folder_root() { # <dest>
  case "$1" in
    local) local_root ;;
    icloud) icloud_root ;;
    gdrive) [ -z "$DUDU_RCLONE_REMOTE" ] && gdrive_root ;;
    *) return 1 ;;
  esac
}

# The name this machine's backups are kept under: its host name, or host-<id> when the
# newest backup under that name came from another machine (two Macs both named
# "Joaos-MacBook-Pro", or a new Mac set up with Migration Assistant).
backup_host() {
  local h id d root s m other=""
  h=$(dudu_host)
  id=$(machine_id)
  for d in $(dest_list); do
    root=$(dest_folder_root "$d" 2>/dev/null) || continue
    [ -n "$root" ] || continue
    s=$(folder_latest "$root" "$h") || continue
    m=$(manifest_value "$root/$h/$s/manifest.json" machine)
    [ -n "$m" ] && [ "$m" != "$id" ] && other=1
  done
  if [ -n "$other" ]; then printf '%s-%s' "$h" "$(printf '%s' "$id" | cut -c1-4)"; else printf '%s' "$h"; fi
}
