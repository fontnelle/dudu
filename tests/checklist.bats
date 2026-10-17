#!/usr/bin/env bats

load helpers

setup() {
  load_dudu
  CL_KIND=(g i i g i); CL_LABEL=(brew aom curl npm vercel); CL_DETAIL=("" a b "" c); CL_ON=(0 0 0 0 0)
}

@test "toggling a group checks all its items, toggling again clears them" {
  checklist_toggle 0
  [ "${CL_ON[*]}" = "0 1 1 0 0" ]
  checklist_toggle 0
  [ "${CL_ON[*]}" = "0 0 0 0 0" ]
}

@test "a partly checked group becomes fully checked" {
  checklist_toggle 1
  [ "$(checklist_group_count 0)" = 1/2 ]
  checklist_toggle 0
  [ "$(checklist_group_count 0)" = 2/2 ]
}

@test "toggle all checks everything, then clears" {
  checklist_toggle_all
  [ "$(checklist_selected_count)" = 3 ]
  checklist_toggle_all
  [ "$(checklist_selected_count)" = 0 ]
}

@test "outdated output is normalized to name current latest" {
  brew() { printf 'git (2.50.0) < 2.51.0\nfont-x (1.0, 1.1) != 1.2\n'; }
  run brew_outdated
  [ "$output" = "$(printf 'git 2.50.0 2.51.0\nfont-x 1.1 1.2')" ]
}

@test "the update list groups packages under their tool" {
  local d="$BATS_TEST_TMPDIR/out"
  mkdir -p "$d"
  printf 'aom 1 2\ncurl 3 4\n' > "$d/brew"
  printf 'vercel 5 6\n' > "$d/npm"
  outdated_build_list "$d"
  [ "${CL_KIND[*]}" = "g i i g i" ]
  [ "${CL_LABEL[*]}" = "brew aom curl npm vercel" ]
  [ "${CL_DETAIL[1]}" = "1 → 2" ]
  [ "${CL_COLLECTOR[4]}" = npm ]
}
