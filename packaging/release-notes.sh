#!/usr/bin/env bash
# The GitHub release of a version, from CHANGELOG.md:
#   packaging/release-notes.sh --title 0.2.2   ->  v0.2.2 · dudu update with Homebrew
#   packaging/release-notes.sh 0.2.2           ->  the notes, then how to install
# Exits 1 when CHANGELOG.md has no "## v<version>" section, so a release cannot go out
# without notes.

set -o pipefail
cd "$(dirname "$0")/.." || exit 1

title=""
[ "${1:-}" = --title ] && { title=1; shift; }
v=${1#v}
[ -n "$v" ] || { echo "usage: $0 [--title] <version>" >&2; exit 2; }

heading=$(grep -m1 -E "^## v${v//./\\.}( |$)" CHANGELOG.md) || {
  echo "CHANGELOG.md has no \"## v$v\" section: write the release notes first" >&2
  exit 1
}

if [ -n "$title" ]; then
  printf '%s\n' "${heading#\#\# }"
  exit 0
fi

# The section body, without the blank lines around it.
awk -v h="$heading" '
  $0 == h { on = 1; next }
  on && /^## / { exit }
  on { lines[++n] = $0 }
  END {
    s = 1; while (s <= n && lines[s] == "") s++
    e = n; while (e >= s && lines[e] == "") e--
    for (i = s; i <= e; i++) print lines[i]
  }' CHANGELOG.md

prev=$(git tag --sort=-v:refname 2>/dev/null | grep -v "^v$v$" | awk -v v="v$v" '
  BEGIN { split(substr(v, 2), a, ".") }
  { split(substr($0, 2), b, "."); if (b[1] < a[1] || (b[1] == a[1] && (b[2] < a[2] || (b[2] == a[2] && b[3] < a[3])))) { print; exit } }')

cat <<NOTES

## Install or update

\`\`\`bash
brew install fontnelle/tap/dudu            # new install
brew update && brew upgrade dudu           # update
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/main/install.sh | bash   # without Homebrew
\`\`\`

NOTES
if [ -n "$prev" ]; then
  printf '**Full Changelog**: https://github.com/fontnelle/dudu/compare/%s...v%s\n' "$prev" "$v"
else
  printf '**Full Changelog**: https://github.com/fontnelle/dudu/commits/v%s\n' "$v"
fi
