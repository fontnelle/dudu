#!/usr/bin/env bash
# The GitHub release of a Windows version, from CHANGELOG.windows.md:
#   packaging/release-notes.sh --title 0.1.0   ->  win-v0.1.0 · dudu for Windows
#   packaging/release-notes.sh 0.1.0           ->  the notes, then how to install
# Exits 1 when CHANGELOG.windows.md has no "## win-v<version>" section, so a release cannot
# go out without notes.

set -o pipefail
cd "$(dirname "$0")/.." || exit 1

CHANGELOG=CHANGELOG.windows.md
P=win-v
title=""
[ "${1:-}" = --title ] && { title=1; shift; }
v=${1#v}
[ -n "$v" ] || { echo "usage: $0 [--title] <version>" >&2; exit 2; }

heading=$(grep -m1 -E "^## $P${v//./\\.}( |$)" "$CHANGELOG") || {
  echo "$CHANGELOG has no \"## $P$v\" section: write the release notes first" >&2
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
  }' "$CHANGELOG"

prev=$(git tag --list "$P*" --sort=-v:refname 2>/dev/null | grep -v "^$P$v$" | awk -v v="$v" -v p="$P" '
  BEGIN { split(v, a, ".") }
  { split(substr($0, length(p) + 1), b, "."); if (b[1] < a[1] || (b[1] == a[1] && (b[2] < a[2] || (b[2] == a[2] && b[3] < a[3])))) { print; exit } }')

cat <<NOTES

## Install or update

In PowerShell (installs Git for Windows first if needed):

\`\`\`powershell
irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
\`\`\`

Or in Git Bash:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/windows/install.sh | bash
\`\`\`

Already installed: \`dudu update\`.

NOTES
if [ -n "$prev" ]; then
  printf '**Full Changelog**: https://github.com/fontnelle/dudu/compare/%s...%s%s\n' "$prev" "$P" "$v"
else
  printf '**Full Changelog**: https://github.com/fontnelle/dudu/commits/%s%s\n' "$P" "$v"
fi
