#!/usr/bin/env bash
# dudu schedule on [HH:MM] | off | status: a daily backup, by launchd (macOS), a systemd
# user timer (Linux) or a Task Scheduler task (Windows). The scheduled run has no terminal: it uses the stored password, and
# a failure shows a notification.

SCHEDULE_LABEL="com.fontnelle.dudu"
SCHEDULE_DEFAULT="12:30"

schedule_plist() { printf '%s' "$HOME/Library/LaunchAgents/$SCHEDULE_LABEL.plist"; }
schedule_unit_dir() { printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; }
SCHEDULE_TASK="dudu backup"
# The task starts this script hidden: bash.exe alone would keep a console window open.
schedule_vbs() { printf '%s' "$DUDU_CONFIG_DIR/scheduled-backup.vbs"; }

# schtasks takes /Options: Git Bash must not turn them into paths.
schtasks_run() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' schtasks "$@"; }

schedule_valid_time() { printf '%s\n' "$1" | grep -Eq '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'; }

# The time a schedule is set for (HH:MM), or nothing.
schedule_time() {
  local h m f
  if is_macos; then
    f=$(schedule_plist)
    [ -f "$f" ] || return 1
    h=$(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:Hour' "$f" 2>/dev/null) || return 1
    m=$(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:Minute' "$f" 2>/dev/null) || return 1
    printf '%02d:%02d' "$h" "$m"
  elif is_windows; then
    # <StartBoundary>2026-10-20T12:30:00</StartBoundary>; the XML may come as UTF-16.
    schtasks_run /Query /TN "$SCHEDULE_TASK" /XML 2>/dev/null | tr -d '\000\r' |
      sed -n 's/.*<StartBoundary>[^T]*T\([0-9][0-9]:[0-9][0-9]\).*/\1/p' | head -1 | grep . || return 1
  else
    f="$(schedule_unit_dir)/dudu.timer"
    [ -f "$f" ] || return 1
    sed -n 's/^OnCalendar=\*-\*-\* \([0-9]*:[0-9]*\):00$/\1/p' "$f" | head -1
  fi
}

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# The job runs the stable path (opt/dudu with Homebrew), not this version's Cellar folder,
# which brew upgrade removes.
schedule_on_macos() { # <HH:MM>
  local f bin path
  f=$(schedule_plist)
  bin=$(printf '%s' "$(stable_root)/dudu" | xml_escape)
  path=$(printf '%s' "$PATH" | xml_escape)
  mkdir -p "$(dirname "$f")"
  cat > "$f.tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$SCHEDULE_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$bin</string><string>backup</string><string>--scheduled</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$((10#${1%%:*}))</integer><key>Minute</key><integer>$((10#${1##*:}))</integer></dict>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$path</string></dict>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>$(printf '%s' "$DUDU_LOG" | xml_escape)</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
  plutil -lint "$f.tmp" >/dev/null || { rm -f "$f.tmp"; err "$(t "Could not write %s" "$(tilde "$f")")"; return 1; }
  launchctl bootout "gui/$(id -u)" "$f" >/dev/null 2>&1
  mv "$f.tmp" "$f"
  launchctl bootstrap "gui/$(id -u)" "$f" || { err "$(t "launchctl could not load %s" "$(tilde "$f")")"; return 1; }
}

schedule_on_linux() { # <HH:MM>
  local d
  has systemctl || { err "$(t "No systemd here: add \"%s\" to your crontab instead" "dudu backup --scheduled")"; return 1; }
  d=$(schedule_unit_dir)
  mkdir -p "$d"
  cat > "$d/dudu.service" <<EOF
[Unit]
Description=dudu backup

[Service]
Type=oneshot
Environment="PATH=$PATH"
ExecStart="$(stable_root)/dudu" backup --scheduled
EOF
  cat > "$d/dudu.timer" <<EOF
[Unit]
Description=Daily dudu backup

[Timer]
OnCalendar=*-*-* $1:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  if ! systemctl --user daemon-reload || ! systemctl --user enable --now dudu.timer >/dev/null 2>&1; then
    err "$(t "systemctl could not enable %s" "dudu.timer")"
    return 1
  fi
}

# A daily task for this user, which runs only while they are logged on (no password needed).
schedule_on_windows() { # <HH:MM>
  local bash vbs dudu
  bash=$(win_path "$(command -v bash)")
  case "$bash" in *.exe) ;; *) bash="$bash.exe" ;; esac
  # Single-quoted for bash -c ('\'' for a quote in the path); Windows paths have no ".
  dudu="'$(stable_root | sed "s/'/'\\\\''/g")/dudu'"
  vbs=$(schedule_vbs)
  mkdir -p "$(dirname "$vbs")"
  # "" is a quote inside a VBScript string. bash -l sets up Git Bash's PATH as a terminal does.
  printf 'CreateObject("WScript.Shell").Run """%s"" -lc ""%s backup --scheduled""", 0, False\r\n' \
    "$bash" "$dudu" > "$vbs"
  if ! schtasks_run /Create /F /SC DAILY /TN "$SCHEDULE_TASK" /ST "$1" \
       /TR "wscript.exe \"$(win_path "$vbs")\"" >/dev/null; then
    err "$(t "Task Scheduler could not create the task %s" "$SCHEDULE_TASK")"
    return 1
  fi
}

schedule_off() {
  if is_macos; then
    launchctl bootout "gui/$(id -u)" "$(schedule_plist)" >/dev/null 2>&1
    rm -f "$(schedule_plist)"
  elif is_windows; then
    schtasks_run /Delete /F /TN "$SCHEDULE_TASK" >/dev/null 2>&1
    rm -f "$(schedule_vbs)"
  else
    has systemctl && systemctl --user disable --now dudu.timer >/dev/null 2>&1
    rm -f "$(schedule_unit_dir)/dudu.service" "$(schedule_unit_dir)/dudu.timer"
    has systemctl && systemctl --user daemon-reload >/dev/null 2>&1
  fi
  return 0
}

# Shown when a scheduled backup fails: there is no terminal to read the error in.
schedule_notify() { # <message>
  if is_macos; then
    osascript - "$1" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title "dudu backup"
end run
APPLESCRIPT
  elif is_windows && has powershell.exe; then
    # A toast under PowerShell's name: Windows shows toasts only for apps it knows.
    DUDU_MSG=$1 powershell.exe -NoProfile -NonInteractive -Command '
      $m = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
      $x = $m::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
      $t = $x.GetElementsByTagName("text")
      [void]$t.Item(0).AppendChild($x.CreateTextNode("dudu backup"))
      [void]$t.Item(1).AppendChild($x.CreateTextNode($env:DUDU_MSG))
      $id = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
      $m::CreateToastNotifier($id).Show([Windows.UI.Notifications.ToastNotification]::new($x))
    ' >/dev/null 2>&1
  elif has notify-send; then
    notify-send "dudu backup" "$1" >/dev/null 2>&1
  fi
  return 0
}

schedule_status() {
  local t
  if t=$(schedule_time) && [ -n "$t" ]; then
    ok "$(t "Daily backup at %s" "$t")"
    dim "  $(t "Turn it off with: %s" "dudu schedule off")"
  else
    dim "$(t "No scheduled backup. Turn it on with: %s" "dudu schedule on [HH:MM]")"
  fi
}

cmd_schedule() {
  config_load
  case "${1:-status}" in
    on)
      local t=${2:-$SCHEDULE_DEFAULT}
      schedule_valid_time "$t" || { err "$(t "Use a time like 12:30")"; return 1; }
      t=$(printf '%02d:%02d' "$((10#${t%%:*}))" "$((10#${t##*:}))")
      ensure_configured || return 1
      if [ "$DUDU_ENCRYPT" = on ] && [ -z "$(crypto_stored_password)" ]; then
        err "$(t "Backups are encrypted but no password is stored: run dudu config set encrypt on first")"
        return 1
      fi
      if is_macos; then schedule_on_macos "$t" || return 1
      elif is_windows; then schedule_on_windows "$t" || return 1
      else schedule_on_linux "$t" || return 1; fi
      ok "$(t "Daily backup at %s" "$t")"
      dim "  $(t "It runs without a terminal: failures show a notification and go to %s." "$(tilde "$DUDU_LOG")")"
      # Notes asks for permission once; a scheduled run cannot answer that prompt.
      if list_has "$DUDU_DESTINATION" notes && [ -t 0 ] && [ -t 1 ]; then
        echo
        confirm "$(t "Run a backup now (so macOS can ask for the Notes permission)?")" && { echo; cmd_backup; }
      fi
      return 0
      ;;
    off) schedule_off; ok "$(t "Scheduled backup turned off")" ;;
    status) schedule_status ;;
    *) err "$(t "Usage: %s" "dudu schedule on [HH:MM] | off | status")"; return 1 ;;
  esac
}
