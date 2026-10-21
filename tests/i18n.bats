#!/usr/bin/env bats
# Languages: how dudu picks one, and what it prints in each.

load helpers

setup() {
  load_dudu
  unset DUDU_LANG LANGUAGE LC_ALL LC_MESSAGES LANG
  # macOS and Windows answer from their settings: keep this machine's own choice out of the tests.
  # shellcheck disable=SC2317,SC2329 # called by i18n_init
  i18n_apple_language() { return 1; }
  # shellcheck disable=SC2317,SC2329 # called by i18n_init
  i18n_windows_language() { return 1; }
}

lang_of() { i18n_init; printf '%s %s' "$DUDU_LANG_ACTIVE" "$DUDU_LANG_SOURCE"; }

@test "locale names map to the three languages" {
  [ "$(i18n_normalize pt_BR.UTF-8)" = pt-BR ]
  [ "$(i18n_normalize pt_PT)" = pt-BR ]
  [ "$(i18n_normalize pt-BR)" = pt-BR ]
  [ "$(i18n_normalize es_MX.UTF-8@euro)" = es ]
  [ "$(i18n_normalize es)" = es ]
  [ "$(i18n_normalize fr_FR.UTF-8)" = en ]
  run i18n_normalize C.UTF-8
  [ "$status" -eq 1 ]
  run i18n_normalize POSIX
  [ "$status" -eq 1 ]
}

@test "nothing set means English" {
  [ "$(lang_of)" = "en default" ]
}

@test "LANG, then LC_MESSAGES, then LC_ALL, then LANGUAGE" {
  LANG=pt_BR.UTF-8
  [ "$(lang_of)" = "pt-BR system" ]
  LC_MESSAGES=es_AR.UTF-8
  [ "$(lang_of)" = "es system" ]
  LC_ALL=en_US.UTF-8
  [ "$(lang_of)" = "en system" ]
  LANGUAGE=pt_BR:en
  [ "$(lang_of)" = "pt-BR system" ]
}

@test "LANGUAGE skips languages dudu does not speak, C means nothing" {
  LANGUAGE=fr:de:es
  [ "$(lang_of)" = "es system" ]
  LANGUAGE=fr:en:es
  [ "$(lang_of)" = "en system" ]
  unset LANGUAGE
  LC_ALL=C LANG=pt_BR.UTF-8
  [ "$(lang_of)" = "pt-BR system" ]
}

@test "with no locale at all, macOS's language is used" {
  # shellcheck disable=SC2317,SC2329
  i18n_apple_language() { printf 'es-419'; }
  [ "$(lang_of)" = "es system" ]
}

@test "the config beats the system, DUDU_LANG beats both" {
  LANG=pt_BR.UTF-8
  mkdir -p "$DUDU_CONFIG_DIR"
  printf 'destination=local\nlanguage=es\n' > "$DUDU_CONFIG_FILE"
  [ "$(lang_of)" = "es config" ]
  DUDU_LANG=en
  [ "$(lang_of)" = "en env" ]
  DUDU_LANG=auto
  [ "$(lang_of)" = "es config" ]
  printf 'destination=local\nlanguage=auto\n' > "$DUDU_CONFIG_FILE"
  [ "$(lang_of)" = "pt-BR system" ]
}

@test "messages are translated, unknown ones stay in English" {
  DUDU_LANG=pt-BR
  i18n_init
  [ "$(t "Backup")" = "Backup" ]
  [ "$(t "Restore")" = "Restaurar" ]
  [ "$(t "a message no catalog has %s" x)" = "a message no catalog has x" ]
  DUDU_LANG=es
  i18n_init
  [ "$(t "Restore")" = "Restaurar" ]
  [ "$(t "Settings")" = "Configuración" ]
}

@test "plural forms follow the count" {
  [ "$(tn "%d tool" "%d tools" 1)" = "1 tool" ]
  [ "$(tn "%d tool" "%d tools" 0)" = "0 tools" ]
  [ "$(tn "%d tool" "%d tools" 2)" = "2 tools" ]
}

@test "pad counts characters, not bytes" {
  i18n_init # as dudu does: picks a UTF-8 locale when the system has none set
  local s="é"
  [ "${#s}" -eq 1 ] || skip "no UTF-8 locale on this machine"
  [ "$(pad "Configurações" 16)|" = "Configurações   |" ]
  [ "$(pad "Settings" 16)|" = "Settings        |" ]
  [ "$(pad "a long label here" 4)|" = "a long label here|" ]
}

@test "config set language saves it and refuses unknown ones" {
  mkdir -p "$DUDU_CONFIG_DIR"
  printf 'destination=local\n' > "$DUDU_CONFIG_FILE"
  run dudu config set language pt-BR
  [ "$status" -eq 0 ]
  grep -qx 'language=pt-BR' "$DUDU_CONFIG_FILE"
  run dudu config set language fr
  [ "$status" -ne 0 ]
  grep -qx 'language=pt-BR' "$DUDU_CONFIG_FILE"
  run dudu config set language auto
  grep -qx 'language=auto' "$DUDU_CONFIG_FILE"
}

@test "help in Portuguese and Spanish" {
  run env DUDU_LANG=pt-BR "$DUDU_ROOT/dudu" --help
  [[ "$output" == *"Menu interativo"* ]] || false
  [[ "$output" == *"Português (Brasil)"* ]] || false
  run env DUDU_LANG=es "$DUDU_ROOT/dudu" --help
  [[ "$output" == *"Menú interactivo"* ]] || false
}

@test "every message has a translation in each catalog" {
  run bash "$DUDU_ROOT/tests/i18n_check.sh"
  echo "$output"
  [ "$status" -eq 0 ]
}
