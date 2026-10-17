# Loads dudu's libraries into the test shell, with an isolated HOME.

DUDU_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

bats_require_minimum_version 1.5.0

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
