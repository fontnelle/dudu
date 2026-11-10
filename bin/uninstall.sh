#!/usr/bin/env bash
# dudu uninstall [-y] [--purge]: removes dudu from this computer. Backups are never touched.
# --purge also deletes dudu's settings and the stored backup password.

# The Start menu entry and the PATH entries install.ps1 made (also the folder 0.1 used).
uninstall_windows_bits() {
  has powershell.exe || return 0
  DUDU_LIB=$(win_path "$DUDU_ROOT") powershell.exe -NoProfile -NonInteractive -Command '
    $menu = [Environment]::GetFolderPath("Programs")
    if (-not $menu) { $menu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs" }
    Remove-Item (Join-Path $menu "dudu.lnk") -ErrorAction SilentlyContinue
    $old = Join-Path $env:LOCALAPPDATA "dudu"
    $drop = @($env:DUDU_LIB, (Join-Path $old "bin")) | ForEach-Object { $_.TrimEnd("\") }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    $raw = [string]$key.GetValue("Path", "", "DoNotExpandEnvironmentNames")
    if ($raw) {
      $kind = $key.GetValueKind("Path")
      $new = (@($raw -split ";" | Where-Object { $_ -and ($drop -notcontains $_.TrimEnd("\")) }) -join ";")
      if ($new -ne $raw) {
        $key.SetValue("Path", $new, $kind)
        [Environment]::SetEnvironmentVariable("DUDU_PATH_REFRESH", $null, "User")
      }
    }
    if (Test-Path (Join-Path $old "bin\dudu.cmd")) { Remove-Item -Recurse -Force $old -ErrorAction SilentlyContinue }
  ' >/dev/null 2>&1
  return 0
}

# The dudu command that install.sh put in a bin folder: only when it is this dudu's.
uninstall_commands() {
  local f
  for f in "$HOME/bin/dudu" "$HOME/.local/bin/dudu" /usr/local/bin/dudu; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    if [ -L "$f" ]; then
      [ "$(readlink "$f")" = "$DUDU_ROOT/dudu" ] && rm -f "$f"
    elif grep -qF "exec \"$DUDU_ROOT/dudu\"" "$f" 2>/dev/null; then
      rm -f "$f"
    fi
  done
  return 0
}

# dudu's own folder. Never anything that does not look like it.
uninstall_program() {
  local root=$DUDU_ROOT
  [ -f "$root/dudu" ] && [ -f "$root/lib/core/common.sh" ] || return 1
  case "$root" in "" | / | "$HOME") return 1 ;; esac
  cd / || return 1
  if is_windows && has powershell.exe; then
    # Once this dudu has ended: dudu.cmd is still being read by cmd, which complains when
    # the file goes away under it, and Windows keeps the folder of a running program.
    DUDU_LIB=$(win_path "$root") powershell.exe -NoProfile -NonInteractive -Command '
      Start-Process -WindowStyle Hidden cmd.exe -ArgumentList ("/c ping -n 4 127.0.0.1 >nul & rmdir /s /q `"" + $env:DUDU_LIB + "`"")
    ' >/dev/null 2>&1
    return 0
  fi
  rm -rf "$root" 2>/dev/null
  return 0
}

cmd_uninstall() {
  local yes="" purge="" a managed=""
  for a in "$@"; do
    case "$a" in
      -y | --yes) yes=1 ;;
      --purge) purge=1 ;;
      *) err "$(t "Usage: %s" "dudu uninstall [-y] [--purge]")"; return 1 ;;
    esac
  done
  config_load
  if installed_by_brew; then managed="brew uninstall dudu"
  elif installed_by_scoop; then managed="scoop uninstall dudu"
  elif [ -d "$DUDU_ROOT/.git" ]; then managed=git; fi

  printf '%s%s%s\n' "$BOLD" "$(t "Uninstall dudu from this computer")" "$NC"
  dim "  $(t "Removed: the dudu command, its Start menu entry and the daily backup schedule.")"
  dim "  $(t "Kept: your backups, wherever they are.")"
  if [ -z "$yes" ]; then
    if [ ! -t 0 ]; then
      err "$(t "No terminal to confirm in: run %s" "dudu uninstall -y")"
      return 1
    fi
    echo
    confirm "$(t "Uninstall dudu?")" || { dim "$(t "Nothing was changed.")"; return 0; }
    [ -n "$purge" ] || { confirm "$(t "Also delete dudu's settings and the stored backup password?")" && purge=1; }
  fi

  schedule_off
  step_row ok "$(t "schedule")" "$(t "turned off")"
  if is_windows; then
    uninstall_windows_bits
    step_row ok "$(t "Start menu")" "$(t "entry and PATH removed")"
  fi
  if [ -n "$purge" ]; then
    crypto_forget_password
    rm -rf "$DUDU_CONFIG_DIR" "$DUDU_CACHE_DIR"
    step_row ok "$(t "settings")" "$(t "deleted, with the stored password")"
  else
    step_row skip "$(t "settings")" "$(t "kept in %s" "$(tilde "$DUDU_CONFIG_DIR")")"
  fi
  case "$managed" in
    "")
      uninstall_commands
      if uninstall_program; then step_row ok dudu "$(t "removed")"
      else step_row fail dudu "$(t "could not remove %s" "$(tilde "$DUDU_ROOT")")"; return 1; fi
      ;;
    git) step_row skip dudu "$(t "this is a git checkout: delete %s yourself" "$(tilde "$DUDU_ROOT")")" ;;
    *) step_row skip dudu "$(t "finish with: %s" "$managed")" ;;
  esac
  echo
  ok "$(t "dudu was uninstalled. Your backups were not touched.")"
  # Nothing else runs: this dudu's files are gone.
  trap - EXIT
  show_cursor
  exit 0
}
