#!/usr/bin/env bash
# Google Drive without Drive for desktop: dudu talks to Drive through rclone, set up here in
# four steps (rclone, folder or link, Google account, checks) on macOS and Linux alike.
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

# Why <text> is not a folder link, for people; nothing (and 1) when it is one.
gdrive_link_problem() { # <text>
  local host
  gdrive_folder_id "$1" >/dev/null && return 1
  case "$1" in
    '') t "Nothing was pasted." ;;
    *[[:space:]]*) t "The link has spaces: paste only the link." ;;
    https://*)
      host=${1#https://}
      host=${host%%/*}
      case "$host" in
        drive.google.com)
          case "$1" in
            */file/*|*/open\?*) t "This is the link of a file: open the folder in Drive and copy its link." ;;
            *) t "This is not the link of a folder: it has %s in it." "/drive/folders/" ;;
          esac ;;
        docs.google.com|sheets.google.com|slides.google.com) t "This is the link of a document: open the folder in Drive and copy its link." ;;
        *) t "This is not a Google Drive link (%s)." "$(safe_text "$host")" ;;
      esac ;;
    *) t "The link starts with %s." "https://drive.google.com/" ;;
  esac
  return 0
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

# One key of a numbered choice; a whole line when stdin is not a terminal (tests, pipes).
gdrive_read_choice() {
  local k
  if [ -t 0 ]; then IFS= read -rsn1 k || k=q; else IFS= read -r k || k=q; fi
  printf '%s' "$k"
}

# Step 2: how dudu reaches the Drive. Sets GS_SCOPE, GS_FOLDER_ID and GS_REMOTE.
#   1. the Google account: dudu makes its folder dudu-<host> in My Drive and, with
#      drive.file access, sees only the files it creates;
#   2. the link of a folder the user already has: that folder, with access to the Drive.
gdrive_setup_folder() { # <host>
  local k answer id problem tries=0
  printf '    %s1%s  %s  %s%s%s\n' "$BOLD" "$NC" "$(t "Connect my Google account")" "$GRAY" "$(t "dudu creates the folder %s in My Drive and sees only what it creates" "$(gdrive_host_dir "$1")")" "$NC"
  printf '    %s2%s  %s  %s%s%s\n' "$BOLD" "$NC" "$(t "Paste the link of a folder")" "$GRAY" "$(t "a folder you already have in Drive, dudu gets access to your Drive")" "$NC"
  while :; do
    printf '  %s %s[1/2]%s ' "$(t "Choose")" "$GRAY" "$NC"
    k=$(gdrive_read_choice)
    case "$k" in
      ''|1) echo 1; break ;;
      2) echo 2; break ;;
      q|Q|$'\e') echo; return 1 ;;
    esac
    echo
  done
  if [ "${k:-1}" = 1 ]; then
    GS_SCOPE=drive.file
    GS_FOLDER_ID=""
    GS_REMOTE="$GDRIVE_REMOTE:"
    step_row ok "$(t "Folder")" "$(t "My Drive › %s, made by dudu" "$(gdrive_host_dir "$1")")"
    return 0
  fi
  dim "  $(t "In Drive: right-click the folder › Share › Copy link. It looks like:")"
  dim "  https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOpQrStUvWxYz"
  while :; do
    printf '  %s ' "$(t "Folder link:")"
    IFS= read -r answer || return 1
    # A paste often brings a space or a line end around it.
    answer=$(printf '%s' "$answer" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if id=$(gdrive_folder_id "$answer"); then
      GS_SCOPE=drive
      GS_FOLDER_ID=$id
      GS_REMOTE="$GDRIVE_REMOTE:"
      step_row ok "$(t "Folder")" "$(t "valid link · folder %s" "$id")"
      return 0
    fi
    problem=$(gdrive_link_problem "$answer")
    step_row fail "$(t "Folder link")" "$problem"
    tries=$((tries + 1))
    [ $tries -lt 3 ] || return 1
  done
}

# The value of <key> in dudu's rclone remote, empty when the remote or the key is not there.
gdrive_remote_value() { # <key>
  rclone config show "$GDRIVE_REMOTE" 2>/dev/null | sed -n "s/^$1 = //p" | head -1
}

# Step 3: dudu's remote, signed in to Google for <scope> (and <folder id>). A remote set up
# for another folder or scope is made again: the sign-in grants one scope.
# The page the browser shows once Google sends it back, in dudu's language, instead of
# rclone's plain "Success!". rclone fills it in (Go template): .OK, and .Name and
# .Description on an error. It is kept in dudu's config folder, a path that survives
# updates, because rclone reads it again on a reconnect.
gdrive_signin_page() { # <scope>  (prints the file)
  local f="$DUDU_CONFIG_DIR/google-signin.html" access
  if [ "$1" = drive.file ]; then
    access=$(t "dudu sees only the files it creates in your Drive, nothing else.")
  else
    access=$(t "dudu can reach the folder you chose and the rest of your Drive.")
  fi
  mkdir -p "$DUDU_CONFIG_DIR"
  cat > "$f" <<PAGE
<!doctype html>
<html lang="$DUDU_LANG_ACTIVE">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{ if .OK }}dudu · $(t "Google Drive connected"){{ else }}dudu · $(t "Could not connect"){{ end }}</title>
<style>
  :root { --bg: #f6f7f9; --card: #fff; --text: #1d2129; --muted: #5f6672; --ok: #1a7f37; --bad: #c62828; --code: #eef0f3; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #16181d; --card: #20232a; --text: #e8eaee; --muted: #a0a6b1; --ok: #4ac26b; --bad: #ff6b6b; --code: #2b2f37; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px;
         background: var(--bg); color: var(--text);
         font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Ubuntu, sans-serif; }
  main { width: 100%; max-width: 460px; background: var(--card); border-radius: 16px; padding: 32px;
         box-shadow: 0 1px 3px rgba(0,0,0,.08), 0 8px 24px rgba(0,0,0,.06); }
  .brand { font: 600 14px/1 ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--muted); }
  .icon { width: 56px; height: 56px; border-radius: 50%; display: grid; place-items: center;
          font-size: 30px; font-weight: 700; color: #fff; margin: 20px 0 16px; }
  .ok .icon { background: var(--ok); }
  .bad .icon { background: var(--bad); }
  h1 { font-size: 22px; margin: 0 0 8px; }
  p { margin: 0 0 12px; color: var(--muted); }
  p.next { color: var(--text); font-weight: 500; }
  code { background: var(--code); padding: 2px 6px; border-radius: 6px; font-size: 14px; }
  .error { font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; background: var(--code);
           padding: 10px 12px; border-radius: 8px; white-space: pre-wrap; word-break: break-word; }
</style>
</head>
<body>
{{ if .OK }}
<main class="ok">
  <div class="brand">dudu · Google Drive</div>
  <div class="icon">✓</div>
  <h1>$(t "Google Drive connected")</h1>
  <p class="next">$(t "You can close this tab and go back to the terminal: dudu carries on with the checks.")</p>
  <p>${access}</p>
</main>
{{ else }}
<main class="bad">
  <div class="brand">dudu · Google Drive</div>
  <div class="icon">!</div>
  <h1>$(t "Could not connect")</h1>
  <p class="next">$(t "Go back to the terminal and run %s again." "<code>dudu config gdrive</code>")</p>
  <div class="error">{{ .Name }}{{ if .Description }}: {{ .Description }}{{ end }}</div>
</main>
{{ end }}
</body>
</html>
PAGE
  printf '%s' "$f"
}

gdrive_setup_account() { # <scope> [folder id]
  local scope=$1 folder=${2:-} page
  page=$(gdrive_signin_page "$scope")
  if rclone listremotes 2>/dev/null | grep -qxF "$GDRIVE_REMOTE:" &&
     { [ "$(gdrive_remote_value scope)" != "$scope" ] || [ "$(gdrive_remote_value root_folder_id)" != "$folder" ]; }; then
    rclone config delete "$GDRIVE_REMOTE" >/dev/null 2>&1
  fi
  if ! rclone listremotes 2>/dev/null | grep -qxF "$GDRIVE_REMOTE:"; then
    dim "  $(t "A browser opens to sign in to Google. Come back here when it says Google Drive connected.")"
    if ! rclone config create "$GDRIVE_REMOTE" drive scope="$scope" ${folder:+root_folder_id="$folder"} \
         config_template_file="$page" >> "$DUDU_LOG" 2>&1; then
      step_row fail "$(t "Google account")" "$(t "sign-in did not finish, see %s" "$(tilde "$DUDU_LOG")")"
      return 1
    fi
  elif ! rclone about "$GDRIVE_REMOTE:" >/dev/null 2>&1; then
    # Signed in before, but the token expired or was revoked.
    dim "  $(t "A browser opens to sign in to Google. Come back here when it says Google Drive connected.")"
    rclone config update "$GDRIVE_REMOTE" config_template_file="$page" >/dev/null 2>&1
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
gdrive_setup_checks() { # <remote> <host>
  local probe want got conf hosts link
  # Inside this machine's folder: the test also creates it.
  probe=$(rclone_join "$1" "$(gdrive_host_dir "$2")/.dudu-check")
  want="dudu check $(now_stamp) $$"
  if printf '%s' "$want" | rclone rcat "$probe" >> "$DUDU_LOG" 2>&1 &&
     got=$(rclone cat "$probe" 2>> "$DUDU_LOG") && [ "$got" = "$want" ]; then
    rclone deletefile "$probe" >/dev/null 2>&1
    step_row ok "$(t "Test file")" "$(t "a test file was saved, read back and removed")"
    link=$(gdrive_folder_link "$1" "$2")
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

  hosts=$(rclone_hosts "$1" | paste -sd, - | sed 's/,/, /g')
  step_row ok "$(t "Backups")" "${hosts:-$(t "none yet")}"

  if [ "$DUDU_ENCRYPT" = on ]; then
    step_row ok "$(t "Encryption")" "$(t "on, with a password")"
  else
    step_row warn "$(t "Encryption")" "$(t "off: your config files go to Google as they are (keys and tokens are masked)")"
    if confirm "    $(t "Turn on encryption now?")"; then
      config_encrypt_on || warn "$(t "Encryption stays off, turn it on with: %s" "dudu config set encrypt on")"
    fi
  fi
  [ -n "$link" ] && GS_LINK=$link
  return 0
}

# The four steps. Sets DUDU_RCLONE_REMOTE (the caller saves the config) and returns 1 when
# one fails or is cancelled, leaving the settings as they were.
gdrive_setup() {
  local GS_SCOPE="" GS_FOLDER_ID="" GS_REMOTE="" GS_LINK="" host
  host=$(backup_host)
  title "Google Drive"
  dim "$(t "dudu saves straight to your Drive, without Drive for desktop.")"
  phase "1/4" rclone "$(t "the tool dudu uses to reach Google Drive")"
  gdrive_setup_rclone || return 1
  phase "2/4" "$(t "Folder")" "$(t "connect your account, or paste the link of a folder")"
  gdrive_setup_folder "$host" || return 1
  phase "3/4" "$(t "Google account")" "$(t "sign in once, rclone keeps the token")"
  gdrive_setup_account "$GS_SCOPE" "$GS_FOLDER_ID" || return 1
  phase "4/4" "$(t "Checks")" "$(t "before the first backup")"
  gdrive_setup_checks "$GS_REMOTE" "$host" || return 1
  DUDU_RCLONE_REMOTE=$GS_REMOTE
  DUDU_GDRIVE_PATH=""
  echo
  ok "$(t "Google Drive ready, backups of this machine go to:")"
  printf '    %s%s%s\n' "$CYAN" "${GS_LINK:-$(rclone_join "$GS_REMOTE" "$(gdrive_host_dir "$host")")}" "$NC"
}
