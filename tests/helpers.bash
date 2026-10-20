# Loads dudu's libraries into the test shell, with an isolated HOME.

DUDU_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

bats_require_minimum_version 1.5.0

# The tests read dudu's English output, whatever language this machine is set to.
export DUDU_LANG=en

load_dudu() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$HOME"
  VERSION="test"
  export NO_COLOR=1
  set -o pipefail # as in dudu itself
  local f
  for f in "$DUDU_ROOT"/lib/core/*.sh "$DUDU_ROOT"/lib/collectors/*.sh \
           "$DUDU_ROOT"/lib/destinations/*.sh "$DUDU_ROOT"/bin/*.sh; do
    # shellcheck source=/dev/null
    . "$f"
  done
  NO_COLOR=1
  DUDU_NO_SPINNER=1
  mkdir -p "$DUDU_CACHE_DIR"
}

dudu() {
  "$DUDU_ROOT/dudu" "$@"
}

# Pretends to run in Git Bash on Windows: uname says MINGW64, reg answers from REG_<Value>.
# shellcheck disable=SC2317,SC2329 # the stubs are called by the code under test
fake_windows() {
  uname() { if [ "${1:-}" = -s ]; then echo MINGW64_NT-10.0-26100; else command uname "$@"; fi; }
  reg() {
    local name="" v
    while [ $# -gt 0 ]; do [ "$1" = //v ] && name=$2; shift; done
    v=$(eval "printf '%s' \"\${REG_$name:-}\"")
    [ -n "$v" ] || return 1
    printf '\r\nHKEY_X\r\n    %s    REG_SZ    %s\r\n\r\n' "$name" "$v"
  }
}
