#!/usr/bin/env bash
# dudu installer.
#   curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/main/install.sh | bash
#   ... | bash -s -- 0.1.0                 a specific version
#   ... | bash -s -- main                  the development branch
#   ... | bash -s -- --prefix ~/.local/bin install the command somewhere else

set -euo pipefail

REPO="fontnelle/dudu"

if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[34m'; NC=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; BLUE=""; NC=""
fi
step() { printf '%s•%s %s\n' "$BLUE" "$NC" "$*"; }
ok() { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%s⚠%s %s\n' "$YELLOW" "$NC" "$*"; }
die() { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] && die "Do not run the installer as root, dudu works on your user's files."
command -v curl >/dev/null || die "curl is required"
command -v tar >/dev/null || die "tar is required"

version=""
bin_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) bin_dir=$2; shift ;;
    --prefix=*) bin_dir=${1#*=} ;;
    -h|--help) sed -n '2,6p' "$0" 2>/dev/null; exit 0 ;;
    *) version=${1#v} ;;
  esac
  shift
done

if [ -z "$bin_dir" ]; then
  if [ -w /usr/local/bin ] && [ -w /usr/local/lib ]; then bin_dir=/usr/local/bin; else bin_dir="$HOME/.local/bin"; fi
fi
case "$bin_dir" in "~"/*) bin_dir="$HOME/${bin_dir#\~/}" ;; esac
if [ "$bin_dir" = /usr/local/bin ]; then
  lib_dir=/usr/local/lib/dudu
else
  lib_dir="${XDG_DATA_HOME:-$HOME/.local/share}/dudu"
fi

if [ -z "$version" ]; then
  version=$(curl -fsSL --max-time 10 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -1 || true)
  # Never fall back to unreleased code on its own: main is only installed when asked for.
  [ -n "$version" ] || die "Could not find the latest release (offline, or GitHub rate limit). Retry later, or pass a version: bash -s -- 0.1.0"
fi

if [ "$version" != main ] && [ -x "$lib_dir/dudu" ]; then
  installed=$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$lib_dir/dudu" | head -1)
  if [ "$installed" = "$version" ]; then
    ok "Already on the latest version ($version)"
    exit 0
  fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ "$version" = main ]; then
  step "Downloading dudu (main)"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" -o "$tmp/dudu.tar.gz"
else
  step "Downloading dudu $version"
  base="https://github.com/$REPO/releases/download/v$version"
  curl -fsSL "$base/dudu-$version.tar.gz" -o "$tmp/dudu.tar.gz" || die "Version $version not found"
  curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS" || die "Checksums not found for $version"
  expected=$(awk -v f="dudu-$version.tar.gz" '$2 == f || $2 == "*"f { print $1 }' "$tmp/SHA256SUMS")
  if command -v shasum >/dev/null; then
    actual=$(shasum -a 256 "$tmp/dudu.tar.gz" | awk '{ print $1 }')
  else
    actual=$(sha256sum "$tmp/dudu.tar.gz" | awk '{ print $1 }')
  fi
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || die "Checksum mismatch, aborting"
  ok "Checksum verified"
fi

mkdir -p "$tmp/src"
tar -xzf "$tmp/dudu.tar.gz" -C "$tmp/src" --strip-components=1
for f in dudu lib/core/common.sh lib/core/scrub.awk lib/core/secrets.sh bin/backup.sh; do
  [ -f "$tmp/src/$f" ] || die "Unexpected archive layout (missing $f)"
done
chmod +x "$tmp/src/dudu"
"$tmp/src/dudu" --version >/dev/null || die "The downloaded dudu does not run, nothing was changed"

# Swap in one step: a failed copy never leaves a half-installed dudu (or one without its
# secrets scrubber) behind.
mkdir -p "$bin_dir" "$(dirname "$lib_dir")"
rm -rf "$lib_dir.new" "$lib_dir.old"
cp -R "$tmp/src" "$lib_dir.new" || die "Could not copy dudu to $lib_dir"
[ -d "$lib_dir" ] && mv "$lib_dir" "$lib_dir.old"
mv "$lib_dir.new" "$lib_dir" || { [ -d "$lib_dir.old" ] && mv "$lib_dir.old" "$lib_dir"; die "Could not install dudu"; }
rm -rf "$lib_dir.old"
ln -sf "$lib_dir/dudu" "$bin_dir/dudu"

ok "dudu $("$lib_dir/dudu" --version | awk '{ print $2 }') installed in $bin_dir/dudu"
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) warn "$bin_dir is not in your PATH. Add it: echo 'export PATH=\"$bin_dir:\$PATH\"' >> ~/.zshrc" ;;
esac
echo
echo "Run ${GREEN}dudu${NC} to start, or ${GREEN}dudu backup${NC} to save your setup now."
