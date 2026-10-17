#!/usr/bin/env bash
# Colors, banner, messages and spinner.

if [ -z "${NO_COLOR:-}" ] && [ -t 1 ] && [ "${TERM:-}" != dumb ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
  PURPLE=$'\033[35m'; CYAN=$'\033[36m'; GRAY=$'\033[90m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; PURPLE=""; CYAN=""; GRAY=""; BOLD=""; NC=""
fi

step() { printf '%s•%s %s\n' "$BLUE" "$NC" "$*"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%s⚠%s %s\n' "$YELLOW" "$NC" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; }
die()  { err "$*"; exit 1; }
dim()  { printf '%s%s%s\n' "$GRAY" "$*" "$NC"; }
title() { printf '\n%s%s%s\n' "$BOLD" "$*" "$NC"; }

hide_cursor() { [ -t 1 ] && printf '\033[?25l'; return 0; }
show_cursor() { [ -t 1 ] && printf '\033[?25h'; return 0; }
clear_screen() { [ -t 1 ] && printf '\033[H\033[2J'; return 0; }

show_banner() {
  printf '%s%s%s\n' "$GREEN" ' ____            _' "$NC"
  printf '%s%s%s\n' "$GREEN" '|  _ \ _   _  __| |_   _' "$NC"
  printf '%s%s%s   %s%s%s\n' "$GREEN" '| | | | | | |/ _` | | | |' "$NC" "$PURPLE" "$DUDU_HOMEPAGE" "$NC"
  printf '%s%s%s   %s%s%s\n' "$GREEN" '| |_| | |_| | (_| | |_| |' "$NC" "$GREEN" "Your dev setup, backed up." "$NC"
  printf '%s%s%s\n' "$GREEN" '|____/ \__,_|\__,_|\__,_|' "$NC"
}

child_pids() { # <pid>
  if has pgrep; then pgrep -P "$1" 2>/dev/null; else ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '$2 == p { print $1 }'; fi
}

# Every process under <pid>, deepest first.
pid_tree() { # <pid>
  local child
  for child in $(child_pids "$1"); do pid_tree "$child"; done
  printf '%s\n' "$1"
}

# Kills a process and everything it started (a shim like corepack spawns node): TERM first,
# KILL for whatever is still there after 3 seconds.
kill_tree() { # <pid>
  local pids p i=0 alive
  pids=$(pid_tree "$1")
  for p in $pids; do kill "$p" 2>/dev/null; done
  while [ $i -lt 30 ]; do
    alive=""
    for p in $pids; do kill -0 "$p" 2>/dev/null && alive=1; done
    [ -n "$alive" ] || return 0
    sleep 0.1
    i=$((i + 1))
  done
  for p in $pids; do kill -9 "$p" 2>/dev/null; done
  return 0
}

# The log keeps the last ~1 MB, in two files.
log_rotate() {
  [ -f "$DUDU_LOG" ] || return 0
  [ "$(wc -c < "$DUDU_LOG" | tr -d ' ')" -gt 1048576 ] && mv -f "$DUDU_LOG" "$DUDU_LOG.1"
  return 0
}

# Temp dirs and the running step, cleaned up however dudu ends (Ctrl-C included).
DUDU_TMP_DIRS=""
SPIN_PID=""
tmp_register() { DUDU_TMP_DIRS="$DUDU_TMP_DIRS $1"; }
dudu_cleanup() {
  local d
  [ -n "$SPIN_PID" ] && kill_tree "$SPIN_PID"
  SPIN_PID=""
  for d in $DUDU_TMP_DIRS; do
    case "$d" in /*) rm -rf "$d" ;; esac
  done
  DUDU_TMP_DIRS=""
  dudu_unlock
  show_cursor
}

# One dudu at a time changes backups or files: a second run waits for no one, it stops.
DUDU_LOCKED=""
dudu_lock() {
  local lock="$DUDU_CACHE_DIR/lock" pid
  [ -n "$DUDU_LOCKED" ] && return 0
  mkdir -p "$DUDU_CACHE_DIR"
  if ! mkdir "$lock" 2>/dev/null; then
    pid=$(cat "$lock/pid" 2>/dev/null)
    if [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null; then
      err "Another dudu is running (pid $pid). Wait for it to finish."
      return 1
    fi
    # Left behind by a run that was killed.
    rm -rf "$lock"
    mkdir "$lock" 2>/dev/null || { err "Could not take the lock $lock"; return 1; }
  fi
  printf '%s\n' "$$" > "$lock/pid"
  DUDU_LOCKED=1
}
dudu_unlock() {
  [ -n "$DUDU_LOCKED" ] || return 0
  [ "$(cat "$DUDU_CACHE_DIR/lock/pid" 2>/dev/null)" = "$$" ] && rm -rf "$DUDU_CACHE_DIR/lock"
  DUDU_LOCKED=""
}

# Runs "$@" with a spinner labeled $1; output goes to the log. Returns the command status,
# or 124 when it runs longer than DUDU_STEP_TIMEOUT seconds (default 300).
# stdin is closed, so a tool that wants to ask something fails instead of hanging:
# never use it for anything that must prompt (sudo, installers).
# The frame is drawn by $SPIN_DRAW <label> <elapsed> <tick> <frame> and wiped by $SPIN_CLEAR,
# so callers can show more than one line (see spin_draw_progress).
spin() {
  local label=$1
  shift
  local timeout=${DUDU_STEP_TIMEOUT:-300} show=1 i=0 rc start elapsed
  local draw=${SPIN_DRAW:-spin_draw_line} wipe=${SPIN_CLEAR:-spin_clear_line}
  { [ -t 1 ] && [ -z "${DUDU_NO_SPINNER:-}" ] && [ "${TERM:-}" != dumb ]; } || show=""
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  # The explicit subshell matters: nvm misbehaves when a function itself is the background job.
  printf -- '--- %s %s\n' "$(date '+%H:%M:%S')" "$label" >> "$DUDU_LOG"
  ( "$@" ) >>"$DUDU_LOG" 2>&1 </dev/null &
  local pid=$!
  SPIN_PID=$pid
  start=$SECONDS
  [ -n "$show" ] && hide_cursor
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$((SECONDS - start))
    if [ "$elapsed" -ge "$timeout" ]; then
      kill_tree "$pid"
      wait "$pid" 2>/dev/null
      SPIN_PID=""
      printf -- '--- %s timed out after %ss\n' "$label" "$timeout" >> "$DUDU_LOG"
      [ -n "$show" ] && { "$wipe"; show_cursor; }
      return 124
    fi
    [ -n "$show" ] && "$draw" "$label" "$elapsed" "$i" "${frames[i % 10]}"
    i=$((i + 1))
    sleep 0.1
  done
  wait "$pid"
  rc=$?
  SPIN_PID=""
  # 99 = tool not on this machine, not worth a log line.
  [ $rc -ne 0 ] && [ $rc -ne 99 ] && printf -- '--- %s rc=%s\n' "$label" "$rc" >> "$DUDU_LOG"
  [ -n "$show" ] && { "$wipe"; show_cursor; }
  return $rc
}

spin_draw_line() { # <label> <elapsed> <tick> <frame>
  if [ "$2" -ge 3 ]; then
    printf '\r\033[2K%s%s%s %s %s%s%s' "$CYAN" "$4" "$NC" "$1" "$GRAY" "$(fmt_secs "$2")" "$NC"
  else
    printf '\r\033[2K%s%s%s %s' "$CYAN" "$4" "$NC" "$1"
  fi
}

spin_clear_line() { printf '\r\033[2K'; }

# 12s, 3m05s
fmt_secs() {
  if [ "$1" -lt 60 ]; then printf '%ss' "$1"; else printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); fi
}

term_cols() {
  local c
  c=$( { stty size </dev/tty; } 2>/dev/null | awk '{ print $2 }')
  [ -n "$c" ] && [ "$c" -gt 20 ] 2>/dev/null || c=80
  printf '%s' "$c"
}

# Indeterminate bar: a highlight sliding back and forth on a track, for work with no percentage.
bounce_bar() { # <tick> <width>
  local w=$2 seg=6 span pos k out
  span=$((w - seg))
  pos=$(($1 % (2 * span)))
  [ $pos -gt $span ] && pos=$((2 * span - pos))
  out=$GRAY
  for ((k = 0; k < pos; k++)); do out+="━"; done
  out+=$CYAN
  for ((k = 0; k < seg; k++)); do out+="━"; done
  out+=$GRAY
  for ((k = pos + seg; k < w; k++)); do out+="━"; done
  printf '%s%s' "$out" "$NC"
}

# Determinate bar: <done> of <total>, <width> cells.
progress_bar() { # <done> <total> <width>
  local filled=0 k out
  [ "$2" -gt 0 ] && filled=$(($1 * $3 / $2))
  out=$GREEN
  for ((k = 0; k < filled; k++)); do out+="█"; done
  out+=$GRAY
  for ((k = filled; k < $3; k++)); do out+="░"; done
  printf '%s%s' "$out" "$NC"
}

# The overall line: bar, count, percent, total time.
# Uses PROG_DONE, PROG_TOTAL, PROG_START and PROG_COLS (terminal width, read once).
progress_line() {
  local width=30 pct=0
  [ "${PROG_COLS:-80}" -lt 70 ] && width=16
  [ "$PROG_TOTAL" -gt 0 ] && pct=$((PROG_DONE * 100 / PROG_TOTAL))
  printf '\033[2K  %s  %s%d/%d%s %s· %d%% · %s%s' "$(progress_bar "$PROG_DONE" "$PROG_TOTAL" $width)" \
    "$BOLD" "$PROG_DONE" "$PROG_TOTAL" "$NC" "$GRAY" "$pct" "$(fmt_secs $((SECONDS - PROG_START)))" "$NC"
}

# Three lines: the running item with an animated bar, a gap, then the overall progress.
# The cursor goes back up so the next frame redraws in place.
spin_draw_progress() { # <label> <elapsed> <tick> <frame>
  local bar=""
  [ "${PROG_COLS:-80}" -ge 70 ] && bar="$(bounce_bar "$3" 18)  "
  printf '\r\033[2K  %s%s%s %-34s %s%s%s%s\n' "$CYAN" "$4" "$NC" "$1" "$bar" "$GRAY" "$(fmt_secs "$2")" "$NC"
  printf '\033[2K\n'
  progress_line
  printf '\r\033[2A'
}

spin_clear_progress() { printf '\r\033[J'; }

# Resets the overall progress for a new phase of <total> steps.
progress_start() {
  PROG_TOTAL=$1
  PROG_DONE=0
  PROG_START=$SECONDS
  PROG_COLS=$(term_cols)
}

# "1/2 Collecting  what's installed on this machine"
phase() { # <n/total> <name> <detail>
  printf '\n%s%s%s %s%s%s  %s%s%s\n' "$GRAY" "$1" "$NC" "$BOLD" "$2" "$NC" "$GRAY" "$3" "$NC"
}

# A titled block of results, like phase without the step number.
section() { # <name> <detail>
  printf '\n%s%s%s  %s%s%s\n' "$BOLD" "$1" "$NC" "$GRAY" "$2" "$NC"
}

# Closes a section: "  └ 2 keys · fill them in again on a new machine".
section_done() { printf '  %s└ %s%s\n' "$GRAY" "$1" "$NC"; }

# Closes a phase with a one-line summary in place of the progress bar.
phase_done() { # <summary>
  printf '  %s└ %s · %s%s\n' "$GRAY" "$1" "$(secs_short $((SECONDS - PROG_START)))" "$NC"
}

# A finished step inside a phase: ok/warn/fail, name, detail, optional time on the right.
step_row() { # <ok|warn|fail> <name> <detail> [time]
  local mark
  case "$1" in
    ok) mark="${GREEN}✓${NC}" ;;
    warn) mark="${YELLOW}⚠${NC}" ;;
    *) mark="${RED}✗${NC}" ;;
  esac
  if [ "$1" = fail ]; then
    printf '  %s %-14s %s%s%s\n' "$mark" "$2" "$RED" "$3" "$NC"
  else
    printf '  %s %-14s %s%s%s%s\n' "$mark" "$2" "$GRAY" "$3" "${4:+  $4}" "$NC"
  fi
}

# Seconds for a quick step: "<1s", "3s", "1m05s".
secs_short() {
  if [ "$1" -lt 1 ]; then printf '<1s'; else fmt_secs "$1"; fi
}

# Prints "name   detail" with the name padded, for aligned result lists.
row() {
  printf '%s %-10s %s%s%s\n' "$1" "$2" "$GRAY" "$3" "$NC"
}

# y/N question answered with a single key (Enter means no).
confirm() {
  local answer
  printf '%s %s[y/N]%s ' "$1" "$GRAY" "$NC"
  if [ -t 0 ]; then
    IFS= read -rsn1 answer
  else
    read -r answer
  fi
  case "$answer" in
    y|Y|s|S) printf '%syes%s\n' "$GREEN" "$NC"; return 0 ;;
  esac
  printf '%sno%s\n' "$GRAY" "$NC"
  return 1
}
