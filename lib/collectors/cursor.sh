#!/usr/bin/env bash
# Cursor: extensions, settings, keybindings and snippets (helpers in vscode.sh).

cursor_detect() { editor_cli cursor Cursor >/dev/null || [ -d "$(editor_user_dir Cursor)" ]; }
cursor_backup() { editor_backup cursor Cursor Cursor "$1"; }
cursor_restore() { editor_restore cursor Cursor "$1"; }
