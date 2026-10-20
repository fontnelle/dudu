#!/usr/bin/env bash
# Languages: English in the code, Português (Brasil) and Español from lib/i18n/<lang>.sh.
#
# A message is written in English and looked up at run time, gettext style:
#   ok "$(t "Backup saved to %s" "$where")"
#   dim "$(tn "%d tool" "%d tools" "$n")"
# A message missing from a catalog shows in English. Keep the English text a printf
# format with no "$" inside: values go in as arguments, so one text fits every value.
# Translations must keep the same %s/%d in the same order (bash printf has no %1$s).

DUDU_LANGS="en pt-BR es"
# The menu reloads every library between commands: keep what i18n_init chose.
DUDU_LANG_ACTIVE=${DUDU_LANG_ACTIVE:-en}
DUDU_LANG_SOURCE=${DUDU_LANG_SOURCE:-default}
I18N_CATALOG=${I18N_CATALOG:-}
I18N_MSG=""

# en | pt-BR | es for a locale (pt_BR.UTF-8), a language tag (pt-BR) or a code (es).
# Nothing for an empty value, C or POSIX: those say nothing about the language.
i18n_normalize() { # <value>
  local v=${1%%[.@]*}
  case "$v" in
    ''|C|POSIX) return 1 ;;
    pt|pt[-_]*) printf 'pt-BR' ;;
    es|es[-_]*) printf 'es' ;;
    *) printf 'en' ;;
  esac
}

i18n_name() { # <lang>
  case "$1" in
    pt-BR) printf 'Português (Brasil)' ;;
    es) printf 'Español' ;;
    *) printf 'English' ;;
  esac
}

# language= from the config file, read on its own: this runs before any command loads it.
i18n_config_value() {
  [ -f "$DUDU_CONFIG_FILE" ] || return 0
  sed -n 's/^[[:space:]]*language[[:space:]]*=[[:space:]]*["'\'']*\([A-Za-z_-]*\).*/\1/p' "$DUDU_CONFIG_FILE" | tail -1
}

# The first language macOS is set to (System Settings › Language & Region). It covers runs
# with no LANG at all: launchd jobs and some SSH sessions.
i18n_apple_language() {
  is_macos || return 1
  defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^A-Za-z_-]//gp'
}

# The Windows display locale (Settings › Time & language), e.g. pt-BR. Git Bash usually
# sets LANG from it already; this covers scheduled tasks, which start with no LANG.
i18n_windows_language() {
  is_windows || return 1
  win_reg 'HKCU\Control Panel\International' LocaleName
}

# The language the system asks for: LANGUAGE, LC_ALL, LC_MESSAGES, LANG (gettext's order),
# then macOS. Prints the language and returns 1 when nothing says.
i18n_system_language() {
  local entry l v
  # LANGUAGE is a list (fr:pt_BR:en): the first entry dudu speaks wins.
  local IFS=:
  for entry in ${LANGUAGE:-}; do
    l=$(i18n_normalize "$entry") || continue
    case "$entry" in en|en[-_]*) printf 'en'; return 0 ;; esac
    [ "$l" != en ] && { printf '%s' "$l"; return 0; }
  done
  unset IFS
  for v in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
    l=$(i18n_normalize "$v") && { printf '%s' "$l"; return 0; }
  done
  v=$(i18n_apple_language) && l=$(i18n_normalize "$v") && { printf '%s' "$l"; return 0; }
  v=$(i18n_windows_language) && l=$(i18n_normalize "$v") && { printf '%s' "$l"; return 0; }
  return 1
}

# Sets DUDU_LANG_ACTIVE and DUDU_LANG_SOURCE (env, config, system or default) and loads
# that language's catalog.
i18n_init() {
  local l cfg
  if [ -n "${DUDU_LANG:-}" ] && [ "$DUDU_LANG" != auto ] && l=$(i18n_normalize "$DUDU_LANG"); then
    DUDU_LANG_SOURCE="env"
  else
    cfg=$(i18n_config_value)
    if [ -n "$cfg" ] && [ "$cfg" != auto ] && l=$(i18n_normalize "$cfg"); then
      DUDU_LANG_SOURCE=config
    elif l=$(i18n_system_language); then
      DUDU_LANG_SOURCE=system
    else
      l=en
      DUDU_LANG_SOURCE=default
    fi
  fi
  DUDU_LANG_ACTIVE=$l
  I18N_CATALOG=""
  if [ "$l" != en ] && [ -f "$DUDU_ROOT/lib/i18n/$l.sh" ]; then
    # shellcheck source=/dev/null
    . "$DUDU_ROOT/lib/i18n/$l.sh"
    I18N_CATALOG="i18n_catalog_${l//-/_}"
  fi
  i18n_utf8
}

# Accented text is counted in characters only under a UTF-8 locale; without one (launchd,
# LANG=C) columns drift. Tries the usual names until one works.
i18n_utf8() {
  local s="é" c
  [ "${#s}" -eq 1 ] && return 0
  [ -n "${LC_ALL:-}" ] && return 0
  for c in C.UTF-8 en_US.UTF-8 UTF-8; do
    LC_CTYPE=$c
    [ "${#s}" -eq 1 ] && return 0
  done
  unset LC_CTYPE
}

# Sets I18N_MSG to the translation of <msgid>, or to <msgid> itself.
i18n_lookup() {
  I18N_MSG=$1
  [ -n "$I18N_CATALOG" ] && "$I18N_CATALOG" "$1"
  return 0
}

# Prints a translated message: t <english format> [args...]
t() {
  i18n_lookup "$1"
  shift
  # shellcheck disable=SC2059
  printf -- "$I18N_MSG" "$@"
}

# Singular or plural, by <n>: tn <singular> <plural> <n> [more args...]
# The format gets <n> and the args after it, so "%d tool" / "%d tools" print the number.
tn() {
  local one=$1 many=$2
  shift 2
  if [ "$1" = 1 ]; then i18n_lookup "$one"; else i18n_lookup "$many"; fi
  # shellcheck disable=SC2059
  printf -- "$I18N_MSG" "$@"
}

# <text> padded with spaces to <width> characters. printf %-Ns counts bytes, so an
# accented label would come out one column short for each accent.
pad() { # <text> <width>
  local n=$(($2 - ${#1}))
  [ $n -lt 0 ] && n=0
  printf '%s%*s' "$1" "$n" ''
}
