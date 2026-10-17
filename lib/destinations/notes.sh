#!/usr/bin/env bash
# Apple Notes (macOS): one note per machine, "dudu backup - <host>", in a "dudu" folder.
# The note starts with a readable summary (RESTORE.md) and ends with the whole backup as a
# base64 tar.gz between markers, so restore is exact and binary plists survive.

NOTES_FOLDER="dudu"
NOTES_PREFIX="dudu backup - "
NOTES_BEGIN="=== dudu:payload ==="
NOTES_END="=== dudu:end ==="

# Not over SSH: Notes needs the logged-in desktop, and its permission prompt would hang.
notes_available() { is_macos && has osascript && [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; }
notes_where() { printf 'Apple Notes › %s' "$NOTES_FOLDER"; }

b64_decode() { base64 -d 2>/dev/null || base64 -D; }

# Plain text note content for a bundle dir (stdout). The archive is built first, so a tar
# failure is an error instead of an empty payload saved over the previous backup.
notes_pack() { # <bundle>
  local tgz
  tgz=$(mktemp)
  if ! tar -czf "$tgz" -C "$(dirname "$1")" "$(basename "$1")" || [ ! -s "$tgz" ]; then
    rm -f "$tgz"
    return 1
  fi
  [ -f "$1/RESTORE.md" ] && cat "$1/RESTORE.md"
  echo
  echo "$NOTES_BEGIN"
  base64 < "$tgz" | tr -d '\n' | fold -w 76
  echo
  echo "$NOTES_END"
  rm -f "$tgz"
}

# Extracts the bundle from note text (stdin) into <out>.
notes_unpack() { # <out>
  local tmp
  tmp=$(mktemp)
  tr '\r' '\n' | awk -v b="$NOTES_BEGIN" -v e="$NOTES_END" '
    $0 == b { on = 1; next }
    $0 == e { on = 0 }
    on { gsub(/[^A-Za-z0-9+\/=]/, ""); printf "%s", $0 }
  ' > "$tmp"
  if [ ! -s "$tmp" ]; then rm -f "$tmp"; return 1; fi
  local dir
  dir=$(mktemp -d)
  tmp_register "$dir"
  if b64_decode < "$tmp" | tar -xzf - -C "$dir"; then
    cp -R "$dir"/*/. "$1/"
    rm -rf "$tmp" "$dir"
    return 0
  fi
  rm -rf "$tmp" "$dir"
  return 1
}

# Notes bodies are HTML: one <div> per line, escaped.
notes_html() { # <title>
  printf '<div><h1>%s</h1></div>\n' "$1"
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
      -e 's|^$|<br>|' -e 's|^\(.*\)$|<div>\1</div>|'
}

# Saves the bundle as the machine's note. The note it replaces is kept as
# "<name> (previous)", and the new one is read back and checked before it counts as saved.
notes_save() { # <bundle> <host>
  local name="${NOTES_PREFIX}$2" html text check
  html=$(mktemp)
  text=$(mktemp)
  if ! notes_pack "$1" > "$text"; then
    rm -f "$html" "$text"
    err "Could not pack the backup for Notes"
    return 1
  fi
  notes_html "$name" < "$text" > "$html"
  rm -f "$text"
  osascript - "$name" "$html" "$NOTES_FOLDER" >/dev/null <<'APPLESCRIPT' || { rm -f "$html"; return 1; }
on run argv
  set noteName to item 1 of argv
  set htmlBody to read (POSIX file (item 2 of argv)) as «class utf8»
  set folderName to item 3 of argv
  with timeout of 300 seconds
  set acct to my pickAccount()
  tell application "Notes"
    tell acct
      if not (exists folder folderName) then make new folder with properties {name:folderName}
      set matches to (notes of folder folderName whose name is noteName)
      if (count of matches) > 0 then
        set oldBody to body of item 1 of matches
        set prevName to noteName & " (previous)"
        -- Notes rewrites the title's HTML, so the name is replaced wherever it appears (only
        -- the title holds it). If that fails, no copy is made: two notes must never share a name.
        set prevBody to my replaceText(oldBody, noteName, prevName)
        if prevBody is not oldBody then
          set prevs to (notes of folder folderName whose name is prevName)
          if (count of prevs) > 0 then
            set body of item 1 of prevs to prevBody
          else
            make new note at folder folderName with properties {body:prevBody}
          end if
        end if
        set body of item 1 of matches to htmlBody
      else
        make new note at folder folderName with properties {body:htmlBody}
      end if
    end tell
  end tell
  end timeout
end run

-- The iCloud account when there is one: the default account may be a mail server (Gmail,
-- Exchange) or "On My Mac", which never leaves the machine.
on pickAccount()
  tell application "Notes"
    if exists account "iCloud" then return account "iCloud"
    return default account
  end tell
end pickAccount

on replaceText(theText, find, replacement)
  set saved to AppleScript's text item delimiters
  set AppleScript's text item delimiters to find
  set parts to text items of theText
  set AppleScript's text item delimiters to replacement
  set theText to parts as text
  set AppleScript's text item delimiters to saved
  return theText
end replaceText
APPLESCRIPT
  rm -f "$html"
  check=$(mktemp -d)
  tmp_register "$check"
  if ! notes_read "$name" | notes_unpack "$check" || ! bundle_verify "$check"; then
    rm -rf "$check"
    err "The note was saved but does not read back intact (the previous one is kept)"
    return 1
  fi
  rm -rf "$check"
  printf '%s\n' "Notes › $NOTES_FOLDER › $name"
}

notes_read() { # <note name>
  osascript - "$1" "$NOTES_FOLDER" <<'APPLESCRIPT'
on run argv
  set noteName to item 1 of argv
  set folderName to item 2 of argv
  with timeout of 300 seconds
  set acct to my pickAccount()
  tell application "Notes"
    tell acct
      if not (exists folder folderName) then return ""
      set matches to (notes of folder folderName whose name is noteName)
      if (count of matches) = 0 then return ""
      return plaintext of item 1 of matches
    end tell
  end tell
  end timeout
end run

-- The iCloud account when there is one: the default account may be a mail server (Gmail,
-- Exchange) or "On My Mac", which never leaves the machine.
on pickAccount()
  tell application "Notes"
    if exists account "iCloud" then return account "iCloud"
    return default account
  end tell
end pickAccount
APPLESCRIPT
}

# The machine's note, or the previous one when the newest does not pass its checksums.
notes_load() { # <host> <out>
  local name tmp
  for name in "${NOTES_PREFIX}$1" "${NOTES_PREFIX}$1 (previous)"; do
    tmp=$(mktemp -d)
    tmp_register "$tmp"
    if notes_read "$name" | notes_unpack "$tmp" && bundle_verify "$tmp"; then
      cp -R "$tmp/." "$2/"
      rm -rf "$tmp"
      return 0
    fi
    rm -rf "$tmp"
  done
  return 1
}

notes_hosts() {
  osascript - "$NOTES_FOLDER" <<'APPLESCRIPT' | tr ',' '\n' | sed 's/^ *//' | grep "^$NOTES_PREFIX" | grep -v ' (previous)$' | sed "s/^$NOTES_PREFIX//"
on run argv
  set folderName to item 1 of argv
  with timeout of 300 seconds
  set acct to my pickAccount()
  tell application "Notes"
    tell acct
      if not (exists folder folderName) then return ""
      return name of notes of folder folderName
    end tell
  end tell
  end timeout
end run

-- The iCloud account when there is one: the default account may be a mail server (Gmail,
-- Exchange) or "On My Mac", which never leaves the machine.
on pickAccount()
  tell application "Notes"
    if exists account "iCloud" then return account "iCloud"
    return default account
  end tell
end pickAccount
APPLESCRIPT
}
