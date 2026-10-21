#!/usr/bin/env bash
# Scoop: buckets and the apps installed from them.

scoop_detect() { is_windows && has scoop; }

# "bucket source" lines or "bucket/app" lines from `scoop export`'s JSON: one object per
# bucket (Name, Source, Manifests) and per app (Name, Source = its bucket, Version).
scoop_parse_export() { # <export.json> <buckets|apps>
  tr -d '\r\n' < "$1" | tr '{' '\n' | awk -v want="$2" '
    function field(k,   v) {
      if (!match($0, "\"" k "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")) return ""
      v = substr($0, RSTART, RLENGTH); sub(/^[^:]*:[[:space:]]*"/, "", v); sub(/"$/, "", v)
      return v
    }
    { n = field("Name"); s = field("Source") }
    n == "" { next }
    /"Version"/ { if (want == "apps") print (s != "" && s !~ /[\/\\:]/ ? s "/" : "") n; next }
    want == "buckets" { print n, s }' | sort -u
}

scoop_backup() {
  scoop export > "$1/scoop.json" 2>/dev/null || return 1
  scoop_parse_export "$1/scoop.json" apps > "$1/apps.txt"
  scoop_parse_export "$1/scoop.json" buckets > "$1/buckets.txt"
  summary "$1" "$(tn "%d %s package" "%d %s packages" "$(count_lines "$1/apps.txt")" scoop)"
}

scoop_restore() {
  local have name src app n=0
  have=$(mktemp)
  scoop export > "$have" 2>/dev/null
  while read -r name src; do
    [ -n "$(printf '%s\n' "$name" | pkg_filter)" ] || continue
    scoop_parse_export "$have" buckets | awk '{ print $1 }' | grep -qx "$name" && continue
    case "$src" in https://*) act scoop bucket add "$name" "$src" ;; *) act scoop bucket add "$name" ;; esac ||
      warn "$(t "could not install %s" "$name")"
  done < "$1/buckets.txt"
  while IFS= read -r app; do
    act scoop install "$app" || warn "$(t "could not install %s" "$app")"
    n=$((n + 1))
  # Installed apps are compared by name: the bucket they came from does not matter.
  done < <(scoop_parse_export "$have" apps | sed 's|.*/||' | missing_from_names "$1/apps.txt")
  rm -f "$have"
  [ $n -gt 0 ] || dim "  $(t "all packages already installed")"
}

# Lines of <wanted> ("bucket/app" or "app") whose app name is not on stdin.
missing_from_names() { # <wanted>
  local have
  have=$(mktemp)
  sort -u > "$have"
  pkg_filter < "$1" | awk -v have="$have" '
    BEGIN { while ((getline l < have) > 0) h[l] = 1 }
    { n = $0; sub(/.*\//, "", n); if (!(n in h)) print }'
  rm -f "$have"
}

scoop_outdated() {
  # "Name  Installed Version  Latest Version  Missing Dependencies  Info" after a ---- line.
  scoop status 2>/dev/null | tr -d '\r' | awk '/^-+/ { on = 1; next } on && NF >= 3 && $3 ~ /^[0-9v]/ { print $1, $2, $3 }'
}

scoop_upgrade_hint() { echo "scoop update *"; }
scoop_upgrade() { scoop update "$1"; }
