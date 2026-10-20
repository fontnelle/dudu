#!/usr/bin/env bats
# The update question on opening the menu, with the update and the restart faked.
# shellcheck disable=SC2317,SC2329 # the stubs are called by update_prompt

load helpers

setup() {
  load_dudu
  VERSION=0.4.0
  printf '0.5.0\n' > "$DUDU_LATEST_CACHE"
  show_banner() { :; }
  sleep() { :; }
  cmd_update() { echo UPDATING; }
  update_restart() { echo RESTARTED; }
}

@test "Enter updates and restarts dudu" {
  run update_prompt <<< ''
  [[ "$output" == *"dudu 0.5.0 is out, you have 0.4.0"* ]] || false
  [[ "$output" == *UPDATING*RESTARTED* ]] || false
}

@test "y updates too" {
  run update_prompt <<< 'y'
  [[ "$output" == *RESTARTED* ]] || false
}

@test "n is remembered for that version and not asked again" {
  run update_prompt <<< 'n'
  [[ "$output" != *UPDATING* ]] || false
  [[ "$output" == *"Update later with"* ]] || false
  [ "$(cat "$DUDU_UPDATE_DECLINED")" = 0.5.0 ]
  run update_prompt <<< ''
  [ -z "$output" ]
  # A newer release asks again.
  printf '0.6.0\n' > "$DUDU_LATEST_CACHE"
  run update_prompt <<< 'n'
  [[ "$output" == *"dudu 0.6.0 is out"* ]] || false
}

@test "nothing is asked when this is the latest version" {
  printf '0.4.0\n' > "$DUDU_LATEST_CACHE"
  run update_prompt <<< ''
  [ -z "$output" ]
  rm -f "$DUDU_LATEST_CACHE"
  run update_prompt <<< ''
  [ -z "$output" ]
}

@test "a failed update opens the current version, without restarting" {
  cmd_update() { return 1; }
  run update_prompt <<< ''
  [[ "$output" == *"The update did not finish, opening dudu 0.4.0"* ]] || false
  [[ "$output" != *RESTARTED* ]] || false
}

@test "just after an update, dudu does not ask again" {
  DUDU_JUST_UPDATED=1 run update_prompt <<< ''
  [ -z "$output" ]
}
