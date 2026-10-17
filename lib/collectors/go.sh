#!/usr/bin/env bash
# Go: binaries installed with go install (module paths are read from the binaries).

go_detect() { has go; }

go_bin_dir() {
  local d p
  d=$(go env GOBIN 2>/dev/null) || return 1
  if [ -z "$d" ]; then
    p=$(go env GOPATH 2>/dev/null) || return 1
    [ -n "$p" ] || return 1 # never "/bin"
    d="${p%%:*}/bin"
  fi
  printf '%s' "$d"
}

go_tools() {
  local d f
  d=$(go_bin_dir) || return 1
  for f in "$d"/*; do
    [ -f "$f" ] || continue
    go version -m "$f" 2>/dev/null | awk '$1 == "path" { print $2; exit }'
  done
  return 0
}

go_backup() {
  go_tools | sort -u > "$1/tools.txt" || return 1
  summary "$1" "$(tn "%d tool" "%d tools" "$(count_lines "$1/tools.txt")")"
}

go_restore() {
  [ -s "$1/tools.txt" ] || return 0
  has go || [ -n "${DUDU_DRY_RUN:-}" ] || { warn "$(t "%s is not installed (it is usually in the Brewfile), skipping" go)"; return 0; }
  local t
  while IFS= read -r t; do
    act go install "$t@latest" || warn "$(t "could not install %s" "$t")"
  done < <(go_tools | missing_pkgs "$1/tools.txt")
}
