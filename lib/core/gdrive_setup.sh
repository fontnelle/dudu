#!/usr/bin/env bash
# Google Drive without Drive for desktop: dudu talks to Drive through rclone, set up here in
# four steps (rclone, folder, Google account, checks) on macOS and Linux alike.
# dudu keeps its own rclone remote, so remotes the user already has are never touched.

GDRIVE_REMOTE="dudu-gdrive"

# "a:" + "x" -> "a:x", "a:dudu" + "x" -> "a:dudu/x".
rclone_join() { # <remote[:path]> <name>
  case "$1" in
    *:) printf '%s%s' "$1" "$2" ;;
    *) printf '%s/%s' "${1%/}" "$2" ;;
  esac
}

# The folder id in a Google Drive folder link. Only https://drive.google.com/drive/
# [u/<n>/]folders/<id>[?...] is taken, so a look-alike site or a short link never ends up in
# rclone's config. Returns 1 for anything else.
gdrive_folder_id() { # <link>
  local id
  case "$1" in ''|*[[:space:]]*) return 1 ;; esac
  id=$(printf '%s\n' "$1" | LC_ALL=C sed -nE 's#^https://drive\.google\.com/drive/(u/[0-9]+/)?folders/([A-Za-z0-9_-]{10,100})([?#].*)?$#\2#p')
  [ -n "$id" ] && printf '%s' "$id"
}

# Step 1: rclone, installed with the user's say when missing.
gdrive_setup_rclone() {
  local pm
  if ! has rclone; then
    if is_macos; then
      if ! { has brew || brew_load_shellenv; }; then
        step_row fail rclone "$(t "install it from %s, then run %s again" "https://rclone.org/install/" "dudu config gdrive")"
        return 1
      fi
      confirm "  $(t "dudu reaches Google Drive through rclone. Install it with %s?" "brew install rclone")" || return 1
      brew install rclone
    else
      pm=$(linux_pm)
      if [ -z "$pm" ]; then
        step_row fail rclone "$(t "install it from %s, then run %s again" "https://rclone.org/install/" "dudu config gdrive")"
        return 1
      fi
      confirm "  $(t "dudu reaches Google Drive through rclone. Install it with %s?" "$pm")" || return 1
      syspkgs_install "$pm" rclone
    fi
    if ! has rclone; then
      step_row fail rclone "$(t "could not install %s" rclone)"
      return 1
    fi
  fi
  step_row ok rclone "$(rclone version 2>/dev/null | head -1)"
}

# Step 2: where the backups go. Sets GS_SCOPE, GS_FOLDER_ID and GS_REMOTE.
# By default a "dudu" folder dudu creates itself: with scope drive.file rclone only sees the
# files it made, nothing else of the Drive. A pasted folder link needs the whole Drive.
gdrive_setup_folder() {
  local answer id tries=0
  dim "  $(t "Enter: a folder named dudu in My Drive, made by dudu, which sees nothing else of your Drive")"
  dim "  $(t "Or paste the link of a folder: %s" "https://drive.google.com/drive/folders/…")"
  while :; do
    printf '  %s ' "$(t "Folder:")"
    IFS= read -r answer || return 1
    if [ -z "$answer" ]; then
      GS_SCOPE=drive.file
      GS_FOLDER_ID=""
      GS_REMOTE="$GDRIVE_REMOTE:dudu"
      step_row ok "$(t "Folder")" "$(t "My Drive › dudu, only what dudu creates")"
      return 0
    fi
    if id=$(gdrive_folder_id "$answer"); then
      GS_SCOPE=drive
      GS_FOLDER_ID=$id
      GS_REMOTE="$GDRIVE_REMOTE:"
      step_row ok "$(t "Folder")" "$(t "the folder of the link (%s), with access to your Drive" "$id")"
      return 0
    fi
    tries=$((tries + 1))
    warn "  $(t "Not a Google Drive folder link. It starts with %s" "https://drive.google.com/drive/folders/")"
    [ $tries -lt 3 ] || return 1
  done
}

# The value of <key> in dudu's rclone remote, empty when the remote or the key is not there.
gdrive_remote_value() { # <key>
  rclone config show "$GDRIVE_REMOTE" 2>/dev/null | sed -n "s/^$1 = //p" | head -1
}

# Step 3: dudu's remote, signed in to Google for <scope> (and <folder id>). A remote set up
# for another folder or scope is made again: the sign-in grants one scope.
gdrive_setup_account() { # <scope> [folder id]
  local scope=$1 folder=${2:-}
  if rclone listremotes 2>/dev/null | grep -qxF "$GDRIVE_REMOTE:" &&
     { [ "$(gdrive_remote_value scope)" != "$scope" ] || [ "$(gdrive_remote_value root_folder_id)" != "$folder" ]; }; then
    rclone config delete "$GDRIVE_REMOTE" >/dev/null 2>&1
  fi
  if ! rclone listremotes 2>/dev/null | grep -qxF "$GDRIVE_REMOTE:"; then
    dim "  $(t "A browser opens to sign in to Google. Come back here when it says Success.")"
    if ! rclone config create "$GDRIVE_REMOTE" drive scope="$scope" ${folder:+root_folder_id="$folder"} >> "$DUDU_LOG" 2>&1; then
      step_row fail "$(t "Google account")" "$(t "sign-in did not finish, see %s" "$(tilde "$DUDU_LOG")")"
      return 1
    fi
  elif ! rclone about "$GDRIVE_REMOTE:" >/dev/null 2>&1; then
    # Signed in before, but the token expired or was revoked.
    dim "  $(t "A browser opens to sign in to Google. Come back here when it says Success.")"
    rclone config reconnect "$GDRIVE_REMOTE:" >> "$DUDU_LOG" 2>&1
  fi
  if ! rclone about "$GDRIVE_REMOTE:" >/dev/null 2>&1; then
    step_row fail "$(t "Google account")" "$(t "Google Drive did not answer, see %s" "$(tilde "$DUDU_LOG")")"
    return 1
  fi
  step_row ok "$(t "Google account")" "$(t "connected")"
}

# Step 4: a test file written, read back and removed; rclone's token readable only by the
# user; encryption offered when off; the machines already backed up there.
gdrive_setup_checks() { # <remote>
  local probe want got conf hosts
  probe=$(rclone_join "$1" .dudu-check)
  want="dudu check $(now_stamp) $$"
  if printf '%s' "$want" | rclone rcat "$probe" >> "$DUDU_LOG" 2>&1 &&
     got=$(rclone cat "$probe" 2>> "$DUDU_LOG") && [ "$got" = "$want" ]; then
    rclone deletefile "$probe" >/dev/null 2>&1
    step_row ok "$(t "Test file")" "$(t "a test file was saved, read back and removed")"
  else
    rclone deletefile "$probe" >/dev/null 2>&1
    step_row fail "$(t "Test file")" "$(t "could not save and read back a test file, see %s" "$(tilde "$DUDU_LOG")")"
    return 1
  fi

  # The Google token is in rclone's config: only this user may read it.
  conf=$(rclone config file 2>/dev/null | tail -1)
  if [ -f "$conf" ] && chmod 600 "$conf" && [ -n "$(find "$conf" -prune -perm 600)" ]; then
    step_row ok "$(t "Google token")" "$(t "only you can read %s" "$(tilde "$conf")")"
  else
    step_row warn "$(t "Google token")" "$(t "check who can read %s" "$(tilde "${conf:-rclone.conf}")")"
  fi

  hosts=$(rclone lsf --dirs-only "$1" 2>/dev/null | tr -d '/' | grep -E '^[A-Za-z0-9._-]+$' | paste -sd, - | sed 's/,/, /g')
  if [ -n "$hosts" ]; then
    step_row ok "$(t "Backups")" "$hosts"
  else
    step_row ok "$(t "Backups")" "$(t "none yet")"
    # Drive for desktop's folder was not made by dudu: drive.file does not see it.
    case "$1" in *:dudu)
      dim "    $(t "Backups saved by Drive for desktop are not visible like this: run %s and paste the link of that dudu folder." "dudu config gdrive")" ;;
    esac
  fi

  if [ "$DUDU_ENCRYPT" = on ]; then
    step_row ok "$(t "Encryption")" "$(t "on, with a password")"
  else
    step_row warn "$(t "Encryption")" "$(t "off: your config files go to Google as they are (keys and tokens are masked)")"
    if confirm "    $(t "Turn on encryption now?")"; then
      config_encrypt_on || warn "$(t "Encryption stays off, turn it on with: %s" "dudu config set encrypt on")"
    fi
  fi
  return 0
}

# The four steps. Sets DUDU_RCLONE_REMOTE (the caller saves the config) and returns 1 when
# one fails or is cancelled, leaving the settings as they were.
gdrive_setup() {
  local GS_SCOPE="" GS_FOLDER_ID="" GS_REMOTE=""
  title "Google Drive"
  dim "$(t "dudu saves straight to your Drive, without Drive for desktop.")"
  phase "1/4" rclone "$(t "the tool dudu uses to reach Google Drive")"
  gdrive_setup_rclone || return 1
  phase "2/4" "$(t "Folder")" "$(t "where the backups go")"
  gdrive_setup_folder || return 1
  phase "3/4" "$(t "Google account")" "$(t "sign in once, rclone keeps the token")"
  gdrive_setup_account "$GS_SCOPE" "$GS_FOLDER_ID" || return 1
  phase "4/4" "$(t "Checks")" "$(t "before the first backup")"
  gdrive_setup_checks "$GS_REMOTE" || return 1
  DUDU_RCLONE_REMOTE=$GS_REMOTE
  DUDU_GDRIVE_PATH=""
  echo
  ok "$(t "Google Drive ready: %s" "$GS_REMOTE")"
}
