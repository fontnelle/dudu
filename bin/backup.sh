#!/usr/bin/env bash
# dudu backup: runs every detected collector into a staging folder, then hands it to the destination.

# Runs the collectors into <bundle>. Prints one result line per collector unless quiet.
# Sets COLLECTED to the list of collectors that succeeded.
# Last good copy of each collector, used when a tool fails, times out or suddenly lists
# nothing: a backup never silently loses a tool's data (and pruning never removes the last
# copy of it). Updated only after a backup was saved somewhere.
carry_dir() { printf '%s/last' "$DUDU_CACHE_DIR"; }

# Lists (package names, extensions...) came back empty while the last good copy had some.
collector_looks_empty() { # <new dir> <last good dir>
  [ -d "$2" ] || return 1
  local now before
  now=$(cat "$1"/*.txt "$1"/Brewfile 2>/dev/null | grep -c .)
  before=$(cat "$2"/*.txt "$2"/Brewfile 2>/dev/null | grep -c .)
  [ "$now" -eq 0 ] && [ "$before" -gt 0 ]
}

# Puts the last good copy of <collector> in the bundle. Returns 1 when there is none.
collector_carry() { # <bundle> <collector>
  [ -n "${DUDU_CARRY:-}" ] && [ -d "$(carry_dir)/$2" ] || return 1
  rm -rf "${1:?}/$2"
  cp -R "$(carry_dir)/$2" "$1/$2" || return 1
  CARRIED="$CARRIED $2"
  COLLECTED="$COLLECTED $2"
}

carry_date() { friendly_date "$(cat "$(carry_dir)/.created" 2>/dev/null)"; }

collect_all() { # <bundle> [quiet]
  local bundle=$1 quiet=${2:-} c rc why
  # Visible runs get the two-bar animation; status runs it quietly with a plain spinner.
  local SPIN_DRAW="" SPIN_CLEAR=""
  COLLECTED=""
  CARRIED=""
  FAILED=""
  TROUBLE="" # failed or timed out now, whether or not an earlier copy stands in
  if [ -z "$quiet" ]; then
    SPIN_DRAW=spin_draw_progress
    SPIN_CLEAR=spin_clear_progress
    progress_start "$(for c in $DUDU_COLLECTORS; do collector_enabled "$c" && echo "$c"; done | grep -c .)"
  fi
  for c in $DUDU_COLLECTORS; do
    if ! collector_enabled "$c"; then
      # --only backs up some tools: the others come from the last good copy, so the new
      # backup stays complete. Tools excluded in the config stay out.
      [ -n "${DUDU_ONLY:-}" ] && DUDU_ONLY="" collector_enabled "$c" && collector_carry "$bundle" "$c"
      continue
    fi
    mkdir -p "$bundle/$c"
    # Detection runs under the spinner too: probing a tool can be slow or hang.
    rc=0
    spin "$c" collector_backup "$c" "$bundle/$c" || rc=$?
    PROG_DONE=$((PROG_DONE + 1))
    [ $rc -eq 0 ] && [ -n "${DUDU_CARRY:-}" ] && collector_looks_empty "$bundle/$c" "$(carry_dir)/$c" && rc=98
    case $rc in
      0)
        COLLECTED="$COLLECTED $c"
        [ -n "$quiet" ] || step_row ok "$c" "$(cat "$bundle/$c/.summary" 2>/dev/null)"
        continue
        ;;
      99) rm -rf "${bundle:?}/$c"; continue ;;
      98) why="listed nothing" ;;
      124) why="took longer than ${DUDU_STEP_TIMEOUT:-300}s" ;;
      *) why="failed (see $(tilde "$DUDU_LOG"))" ;;
    esac
    printf '%s: %s\n' "$c" "$why" >> "$DUDU_LOG"
    TROUBLE="$TROUBLE $c"
    if collector_carry "$bundle" "$c"; then
      [ -n "$quiet" ] || step_row warn "$c" "$why, kept the copy from $(carry_date)"
    else
      rm -rf "${bundle:?}/$c"
      FAILED="$FAILED $c"
      [ -n "$quiet" ] || step_row warn "$c" "$why, not in this backup"
    fi
  done
  COLLECTED=${COLLECTED# }
  CARRIED=${CARRIED# }
  FAILED=${FAILED# }
  TROUBLE=${TROUBLE# }
}

# After a backup was saved: its freshly collected tools become the last good copies.
carry_update() { # <copies made before encryption>
  local c last
  last=$(carry_dir)
  mkdir -p "$last"
  for c in "$1"/*; do
    [ -d "$c" ] || continue
    rm -rf "${last:?}/$(basename "$c")"
    mv "$c" "$last/"
  done
  date -u +%Y-%m-%dT%H:%M:%SZ > "$last/.created"
}

# Detects and backs up one collector. Returns 99 when the tool is not on this machine.
collector_backup() { # <collector> <dir>
  "${1}_detect" 2>/dev/null || return 99
  "${1}_backup" "$2"
}

# "a", "b" from words, for a JSON array.
json_list() {
  local out="" x
  for x in "$@"; do out="$out\"$x\", "; done
  printf '%s' "${out%, }"
}

# shellcheck disable=SC2086 # COLLECTED, CARRIED and FAILED are word lists
write_manifest() { # <bundle>
  local partial=false
  [ -n "$FAILED" ] && [ -n "${DUDU_ONLY:-}" ] && partial=true
  cat > "$1/manifest.json" <<EOF
{
  "dudu": "$VERSION",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "host": "$DUDU_BACKUP_HOST",
  "machine": "$(machine_id)",
  "os": "$(dudu_os)",
  "os_version": "$(os_pretty)",
  "arch": "$(uname -m)",
  "partial": $partial,
  "collectors": [$(json_list $COLLECTED)],
  "carried": [$(json_list $CARRIED)],
  "failed": [$(json_list $FAILED)]
}
EOF
}

write_restore_md() { # <bundle>
  local c
  {
    echo "# dudu backup: $DUDU_BACKUP_HOST"
    echo
    echo "$(os_pretty) ($(uname -m)), $(date '+%Y-%m-%d %H:%M'), dudu $VERSION"
    echo
    echo "## Contents"
    for c in $COLLECTED; do
      echo "- $c: $(cat "$1/$c/.summary" 2>/dev/null)"
    done
    echo
    echo "## Restore on a new machine"
    echo
    echo "    curl -fsSL https://raw.githubusercontent.com/$DUDU_REPO/main/install.sh | bash"
    echo "    dudu config     # pick the same destination"
    echo "    dudu restore --from $DUDU_BACKUP_HOST"
    if [ -s "$DUDU_REDACT_LOG" ]; then
      echo
      echo "## Secrets masked (fill these in by hand)"
      sort -u -t: -k1,1 -k2,2n "$DUDU_REDACT_LOG" | awk -F: '{ printf "- %s line %s: %s\n", $1, $2, $3 }'
    fi
    if [ -s "$DUDU_SKIP_LOG" ]; then
      echo
      echo "## Not backed up on purpose (keys and credentials, copy them securely)"
      sort -u "$DUDU_SKIP_LOG" | sed 's/^/- /'
    fi
  } > "$1/RESTORE.md"
}

# Parses the options shared by backup, restore and status.
parse_common_opts() {
  DUDU_DRY_RUN=""
  DUDU_ONLY=""
  DUDU_FROM=""
  DUDU_FILE=""
  DUDU_YES=""
  DUDU_ALL=""
  DUDU_SCHEDULED=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--dry-run) DUDU_DRY_RUN=1 ;;
      --only) DUDU_ONLY=$2; shift ;;
      --only=*) DUDU_ONLY=${1#*=} ;;
      --from) DUDU_FROM=$2; shift ;;
      --from=*) DUDU_FROM=${1#*=} ;;
      --file) DUDU_FILE=$2; shift ;;
      --file=*) DUDU_FILE=${1#*=} ;;
      -y|--yes) DUDU_YES=1 ;;
      -a|--all) DUDU_ALL=1 ;;
      # Run by dudu schedule: no prompts, no animation.
      --scheduled) DUDU_SCHEDULED=1 DUDU_YES=1 DUDU_NO_SPINNER=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

cmd_backup() {
  parse_common_opts "$@"
  ensure_configured || return 1
  dudu_lock || return 1
  local d usable=""
  for d in $(dest_list); do "${d}_available" 2>/dev/null && usable="$usable $d"; done
  if [ -z "$usable" ]; then
    err "None of your destinations ($(dest_labels)) is available on this machine. Pick another with: dudu config"
    return 1
  fi

  read_only_mode
  local work stamp bundle started=$SECONDS
  work=$(mktemp -d)
  tmp_register "$work"
  stamp=$(backup_stamp)
  DUDU_BACKUP_HOST=$(backup_host)
  DUDU_CARRY=1
  bundle="$work/$stamp"
  mkdir -p "$bundle"
  DUDU_REDACT_LOG="$work/redacted"
  DUDU_SKIP_LOG="$work/skipped"
  : > "$DUDU_REDACT_LOG"
  : > "$DUDU_SKIP_LOG"
  printf '\n=== backup %s ===\n' "$stamp" >> "$DUDU_LOG"

  printf '\n%sBacking up %s%s\n' "$BOLD" "$DUDU_BACKUP_HOST" "$NC"
  [ "$DUDU_BACKUP_HOST" != "$(dudu_host)" ] &&
    warn "Another machine already backs up as $(dudu_host): this one uses $DUDU_BACKUP_HOST"
  local nd
  nd=$(dest_list | wc -w | tr -d ' ')
  dim "To $nd destination$([ "$nd" -gt 1 ] && echo s): $(dest_labels)"
  if [ -n "$DUDU_DRY_RUN" ]; then
    echo
    local c
    for c in $DUDU_COLLECTORS; do
      collector_enabled "$c" && spin "$c" "${c}_detect" && row "${BLUE}•${NC}" "$c" "would be backed up"
    done
    rm -rf "$work"
    echo
    dim "Dry run: nothing was written."
    return 0
  fi

  phase "1/2" "Collecting" "what's installed on this machine"
  collect_all "$bundle"
  phase_done "$(echo "$COLLECTED" | wc -w | tr -d ' ') tools found"
  if [ -z "$COLLECTED" ]; then
    err "Nothing was collected"
    rm -rf "$work"
    return 1
  fi
  secrets_report_skipped
  write_manifest "$bundle"
  write_restore_md "$bundle"
  # Fresh copies of the tools collected now, kept as "last good" once the backup is saved.
  local c
  mkdir -p "$work/carry"
  for c in $COLLECTED; do
    list_has "$(echo "$CARRIED" | tr ' ' ',')" "$c" || cp -R "$bundle/$c" "$work/carry/$c"
  done
  if [ "$DUDU_ENCRYPT" = on ]; then
    if ! crypto_seal "$bundle"; then
      err "Could not encrypt the backup, nothing was saved"
      rm -rf "$work"
      return 1
    fi
    step_row ok "encrypted" "AES-256 with your backup password"
  fi
  bundle_sums "$bundle"

  local n_dest
  n_dest=$(dest_list | wc -w | tr -d ' ')
  phase "2/2" "Saving" "to $n_dest destination$([ "$n_dest" -gt 1 ] && echo s)"
  save_all "$bundle" "$stamp"
  local saved=$SAVED_COUNT
  phase_done "$saved of $n_dest saved"
  [ "$saved" -gt 0 ] && carry_update "$work/carry"

  backup_done_summary "$bundle" "$saved" $((SECONDS - started))
  rm -rf "$work"
  # 0 = all saved, 1 = nothing saved, 2 = saved with problems.
  [ "$saved" -gt 0 ] || return 1
  [ "$saved" -eq "$n_dest" ] && [ -z "$TROUBLE" ] || return 2
  return 0
}

# Saves <bundle> to every destination; one failing does not stop the others.
# Sets SAVED_COUNT and SAVED_RESULTS ("ok|<dest>|<where>" or "fail|<dest>|<reason>" lines).
save_all() { # <bundle> <stamp>
  local d dir t0 SPIN_DRAW=spin_draw_progress SPIN_CLEAR=spin_clear_progress
  SAVED_COUNT=0
  SAVED_RESULTS=""
  progress_start "$(dest_list | wc -w | tr -d ' ')"
  for d in $(dest_list); do
    t0=$SECONDS
    if ! "${d}_available" 2>/dev/null; then
      PROG_DONE=$((PROG_DONE + 1))
      step_row fail "$(dest_label "$d")" "not available on this machine"
      SAVED_RESULTS="${SAVED_RESULTS}fail|$d"$'\n'
      continue
    fi
    if ! DUDU_STEP_TIMEOUT=${DUDU_SAVE_TIMEOUT:-1800} spin "$(dest_label "$d")" "${d}_save" "$1" "$DUDU_BACKUP_HOST"; then
      PROG_DONE=$((PROG_DONE + 1))
      step_row fail "$(dest_label "$d")" "could not save, see $(tilde "$DUDU_LOG")"
      SAVED_RESULTS="${SAVED_RESULTS}fail|$d"$'\n'
      continue
    fi
    PROG_DONE=$((PROG_DONE + 1))
    # Folder destinations are checked on disk, not trusted.
    dir=$(dest_saved_dir "$d" "$2")
    if [ -n "$dir" ] && [ ! -f "$dir/manifest.json" ]; then
      step_row fail "$(dest_label "$d")" "not found after saving"
      SAVED_RESULTS="${SAVED_RESULTS}fail|$d"$'\n'
      continue
    fi
    step_row ok "$(dest_label "$d")" "$(dest_saved_where "$d" "$2")" "$(secs_short $((SECONDS - t0)))"
    SAVED_RESULTS="${SAVED_RESULTS}ok|$d"$'\n'
    SAVED_COUNT=$((SAVED_COUNT + 1))
  done
}

# Where the backup landed on disk, for folder destinations (empty for Notes and rclone).
dest_saved_dir() { # <dest> <stamp>
  local root=""
  case "$1" in
    local) root=$(local_root) ;;
    icloud) root=$(icloud_root) ;;
    gdrive) [ -z "$DUDU_RCLONE_REMOTE" ] && root=$(gdrive_root) ;;
  esac
  [ -n "$root" ] && printf '%s/%s/%s' "$root" "$DUDU_BACKUP_HOST" "$2"
}

# Where the backup landed, for people.
dest_saved_where() { # <dest> <stamp>
  case "$1" in
    icloud) printf 'iCloud Drive › dudu › %s › %s' "$DUDU_BACKUP_HOST" "$2" ;;
    notes) printf 'Notes › %s › %s%s' "$NOTES_FOLDER" "$NOTES_PREFIX" "$DUDU_BACKUP_HOST" ;;
    gdrive)
      if [ -n "$DUDU_RCLONE_REMOTE" ]; then
        printf '%s/%s/%s' "${DUDU_RCLONE_REMOTE%/}" "$DUDU_BACKUP_HOST" "$2"
      else
        tilde "$(dest_saved_dir gdrive "$2")"
      fi
      ;;
    *) tilde "$(dest_saved_dir "$1" "$2")" ;;
  esac
}

# The closing message: one line with the result, privacy notes, a way to see the backup.
backup_done_summary() { # <bundle> <saved count> <seconds>
  local count size total status d first_dir="" has_notes="" stats
  count=$(echo "$COLLECTED" | wc -w | tr -d ' ')
  size=$(du -sh "$1" 2>/dev/null | awk '{ print $1 }')
  total=$(dest_list | wc -w | tr -d ' ')
  stats="$count tool$([ "$count" -ne 1 ] && echo s) · ${size:-?} · $2/$total destination$([ "$total" -ne 1 ] && echo s) · $(fmt_secs "$3")"

  echo
  if [ "$2" -eq "$total" ] && [ -z "$TROUBLE" ]; then
    printf '%s%s✓ Backup complete%s   %s%s%s\n' "$GREEN" "$BOLD" "$NC" "$GRAY" "$stats" "$NC"
  elif [ "$2" -eq "$total" ]; then
    printf '%s%s⚠ Backup saved, could not read: %s%s   %s%s%s\n' "$YELLOW" "$BOLD" "$TROUBLE" "$NC" "$GRAY" "$stats" "$NC"
  elif [ "$2" -gt 0 ]; then
    printf '%s%s⚠ Backup partly saved%s   %s%s%s\n' "$YELLOW" "$BOLD" "$NC" "$GRAY" "$stats" "$NC"
  else
    printf '%s%s✗ Backup not saved%s   %s%s%s\n' "$RED" "$BOLD" "$NC" "$GRAY" "$stats" "$NC"
  fi

  backup_privacy_summary

  while IFS='|' read -r status d; do
    [ "$status" = ok ] || continue
    [ "$d" = notes ] && has_notes=1
    [ -z "$first_dir" ] && first_dir=$(dest_saved_dir "$d" "$(basename "$1")")
  done <<< "$SAVED_RESULTS"
  if is_macos && [ -t 0 ] && [ -t 1 ] && [ -z "${DUDU_YES:-}" ]; then
    if [ -n "$first_dir" ]; then
      echo
      confirm "Show in Finder?" && open "$first_dir"
    elif [ -n "$has_notes" ]; then
      echo
      confirm "Open Notes?" && open -a Notes
    fi
  fi
  return 0
}

# Keys found in config files get their own warning (name and line, never the value);
# key files kept local get one line. The full list is in RESTORE.md, inside the backup.
backup_privacy_summary() {
  local kinds n
  [ -s "$DUDU_REDACT_LOG" ] || [ -s "$DUDU_SKIP_LOG" ] || return 0
  if [ -s "$DUDU_SKIP_LOG" ]; then
    n=$(sort -u "$DUDU_SKIP_LOG" | grep -c .)
    kinds=$(sort -u "$DUDU_SKIP_LOG" | while IFS= read -r f; do secret_kind "$f"; done | awk '!seen[$0]++' |
      paste -sd, - | sed 's/,/, /g')
    printf '  %s●%s %-24s %s%s%s\n' "$GREEN" "$NC" "$n key file$([ "$n" -gt 1 ] && echo s) kept local" "$GRAY" "$kinds" "$NC"
    printf '    %sCopy them to the new machine yourself. Full list in RESTORE.md.%s\n' "$GRAY" "$NC"
  fi
  if [ -s "$DUDU_REDACT_LOG" ]; then
    n=$(sort -u "$DUDU_REDACT_LOG" | grep -c .)
    printf '  %s⚠%s %s%d key%s found in your config files, masked in the backup%s\n' "$YELLOW" "$NC" "$BOLD" \
      "$n" "$([ "$n" -gt 1 ] && echo s)" "$NC"
    secrets_list_found "$DUDU_REDACT_LOG" 5
    printf '    %sThe values stay on this machine. To move them out of your dotfiles: %sdudu secrets%s\n' \
      "$GRAY" "$NC$BOLD" "$NC"
  fi
}

# Short human name for a credential file.
secret_kind() {
  case "$1" in
    *"(could not be checked"*) echo "unchecked file" ;;
    *.ssh/*) echo SSH ;;
    *gh/hosts.yml) echo "GitHub CLI" ;;
    *.docker/*) echo Docker ;;
    *.kube/*) echo Kubernetes ;;
    *.aws/*) echo AWS ;;
    *.gnupg) echo GPG ;;
    *.netrc) echo .netrc ;;
    *.pypirc) echo PyPI ;;
    *.gem/*) echo RubyGems ;;
    *.cargo/*) echo Cargo ;;
    *rclone*) echo rclone ;;
    *.secrets) echo "Shell keys" ;;
    *) basename "$1" ;;
  esac
}
