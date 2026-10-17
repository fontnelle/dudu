#!/usr/bin/env bash
# Checks the translation catalogs against the code:
#   - every t "..." / tn "..." "..." message has an entry in each catalog;
#   - no catalog keeps an entry the code no longer uses;
#   - a translation has the same %s/%d, in the same order, as the English text;
#   - English texts have no "$" (values go in as printf arguments);
#   - no text has "|", the menu's label separator.
# Usage: tests/i18n_check.sh   (exit 1 with a list of problems)

set -o pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

# The messages of a file, one per line, as written between the double quotes.
extract() {
  awk '
    function quoted(s, i,   c, out) {
      out = ""
      for (; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
        if (c == "\"") { END_AT = i; return out }
        out = out c
      }
      END_AT = 0
      return ""
    }
    /^[[:space:]]*#/ { next }
    {
      line = $0
      while (match(line, /(^|[(;&| \t])tn? "/)) {
        start = RSTART + RLENGTH
        plural = substr(line, RSTART, RLENGTH) ~ /tn "$/
        print quoted(line, start)
        if (!END_AT) break
        rest = substr(line, END_AT + 1)
        if (plural && match(rest, /^[ \t]+"/)) {
          print quoted(rest, RLENGTH + 1)
          if (!END_AT) break
          rest = substr(rest, END_AT + 1)
        }
        line = rest
      }
    }' "$@"
}

# The English texts a catalog translates.
catalog_keys() { sed -n 's/^    "\(.*\)") I18N_MSG=.*/\1/p' "$1"; }

specs() { printf '%s' "$1" | sed 's/%%//g' | grep -oE '%[-0-9.*]*[sdxXf]' | tr '\n' ' '; }

problems=0
fail() { printf '%s\n' "$*"; problems=$((problems + 1)); }

files=$(ls dudu bin/*.sh lib/core/*.sh lib/collectors/*.sh lib/destinations/*.sh)
# shellcheck disable=SC2086
msgids=$(extract $files | sort -u)

while IFS= read -r m; do
  [ -n "$m" ] || continue
  case "$m" in *'$'*|*'`'*) fail "has \$ or \`, pass the value as an argument: $m" ;; esac
  case "$m" in *'|'*) fail "has |, the menu separator: $m" ;; esac
done <<< "$msgids"

DUDU_ROOT=$ROOT
for f in lib/i18n/*.sh; do
  lang=$(basename "$f" .sh)
  fn="i18n_catalog_${lang//-/_}"
  # shellcheck source=/dev/null
  . "$f"
  keys=$(catalog_keys "$f" | sort)
  dups=$(printf '%s\n' "$keys" | uniq -d)
  [ -z "$dups" ] || fail "$lang: entries written twice: $dups"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    printf '%s\n' "$keys" | grep -qxF -- "$m" || { fail "$lang: missing: $m"; continue; }
    eval "id=\"$m\""
    # shellcheck disable=SC2154
    I18N_MSG=""
    "$fn" "$id" || { fail "$lang: entry not found by lookup (quoting?): $m"; continue; }
    [ "$(specs "$id")" = "$(specs "$I18N_MSG")" ] || fail "$lang: %s/%d differ: $m -> $I18N_MSG"
    case "$I18N_MSG" in *'|'*) fail "$lang: has |, the menu separator: $I18N_MSG" ;; esac
  done <<< "$msgids"
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    printf '%s\n' "$msgids" | grep -qxF -- "$k" || fail "$lang: not used by the code anymore: $k"
  done <<< "$keys"
done

if [ $problems -gt 0 ]; then
  printf '\n%d translation problem(s)\n' "$problems"
  exit 1
fi
printf 'i18n: %d messages, every catalog complete\n' "$(printf '%s\n' "$msgids" | grep -c .)"
