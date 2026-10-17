#!/usr/bin/env bash
# Optional encryption of backups with a password (config: encrypt=on).
# The bundle becomes backup.enc (tar.gz, AES-256-CBC, PBKDF2 with 200k rounds) and
# backup.mac (a SHA-256 MAC of backup.enc, keyed from the password the same way), so a
# changed byte is caught before anything is decrypted. manifest.json stays readable (host,
# date, tools) to pick the newest backup; everything else is inside backup.enc.
# The password never goes on a command line (visible in ps): only env vars and stdin.
# It is kept in the macOS Keychain, the Secret Service (secret-tool) or a 600 file.

CRYPTO_ITER=200000
CRYPTO_SERVICE="dudu-backup"
CRYPTO_PW=""

crypto_key_file() { printf '%s/key' "$DUDU_CONFIG_DIR"; }

sha256_stdin() {
  if has shasum; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi
}

crypto_store_password() { # <password>
  local pw=$1
  if is_macos && has security; then
    # security -i reads the command from stdin, so the password is not in ps.
    pw=${pw//\\/\\\\}
    pw=${pw//\"/\\\"}
    printf 'add-generic-password -U -a "%s" -s "%s" -l "dudu backup password" -w "%s"\n' \
      "$USER" "$CRYPTO_SERVICE" "$pw" | security -i >/dev/null 2>&1 && return 0
  fi
  if has secret-tool && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    printf '%s' "$1" | secret-tool store --label="dudu backup password" service "$CRYPTO_SERVICE" 2>/dev/null && return 0
  fi
  mkdir -p "$DUDU_CONFIG_DIR"
  ( umask 077; printf '%s' "$1" > "$(crypto_key_file)" )
}

crypto_stored_password() {
  local pw=""
  if is_macos && has security; then
    pw=$(security find-generic-password -a "$USER" -s "$CRYPTO_SERVICE" -w 2>/dev/null)
  fi
  if [ -z "$pw" ] && has secret-tool && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    pw=$(secret-tool lookup service "$CRYPTO_SERVICE" 2>/dev/null)
  fi
  [ -z "$pw" ] && [ -f "$(crypto_key_file)" ] && pw=$(cat "$(crypto_key_file)")
  [ -n "$pw" ] && printf '%s' "$pw"
}

crypto_forget_password() {
  if is_macos && has security; then security delete-generic-password -a "$USER" -s "$CRYPTO_SERVICE" >/dev/null 2>&1; fi
  if has secret-tool; then secret-tool clear service "$CRYPTO_SERVICE" >/dev/null 2>&1; fi
  rm -f "$(crypto_key_file)"
  return 0
}

crypto_ask() { # <prompt> -> password on stdout (empty when no terminal)
  local pw
  [ -r /dev/tty ] || return 1
  printf '%s' "$1" > /dev/tty
  IFS= read -rs pw < /dev/tty || return 1
  printf '\n' > /dev/tty
  printf '%s' "$pw"
}

# Sets CRYPTO_PW: DUDU_PASSWORD, the stored password, or a prompt.
crypto_password() {
  [ -n "$CRYPTO_PW" ] && return 0
  CRYPTO_PW=${DUDU_PASSWORD:-}
  [ -n "$CRYPTO_PW" ] || CRYPTO_PW=$(crypto_stored_password)
  [ -n "$CRYPTO_PW" ] || CRYPTO_PW=$(crypto_ask "Backup password: ")
  [ -n "$CRYPTO_PW" ]
}

# Asks for a new password twice and stores it.
crypto_set_password() {
  local a b
  has openssl || { err "Encryption needs openssl, install it first"; return 1; }
  a=$(crypto_ask "New backup password (12+ characters): ") || { err "A password can only be set from a terminal"; return 1; }
  if [ "${#a}" -lt 12 ]; then err "Too short: use at least 12 characters (a passphrase of a few words works well)"; return 1; fi
  b=$(crypto_ask "Repeat it: ")
  [ "$a" = "$b" ] || { err "The passwords do not match"; return 1; }
  crypto_store_password "$a" || { err "Could not store the password"; return 1; }
  CRYPTO_PW=$a
}

crypto_mac_key() { # <salt hex>
  DUDU_PASSPHRASE=$CRYPTO_PW openssl enc -aes-256-cbc -pbkdf2 -iter "$CRYPTO_ITER" -S "$1" -P \
    -pass env:DUDU_PASSPHRASE 2>/dev/null | sed -n 's/^key=//p'
}

# SHA256(key || SHA256(key || file)): the outer hash stops length extension.
crypto_mac() { # <file> <key hex>
  local inner
  inner=$( { printf '%s' "$2"; cat "$1"; } | sha256_stdin)
  printf '%s%s' "$2" "$inner" | sha256_stdin
}

# Replaces the contents of <bundle> with backup.enc + backup.mac, keeping manifest.json and
# a RESTORE.md that only says how to decrypt.
crypto_seal() { # <bundle>
  local b=$1 tmp salt key
  crypto_password || { err "No backup password: run dudu config set encrypt on"; return 1; }
  tmp=$(mktemp -d)
  tmp_register "$tmp"
  tar -C "$b" -czf "$tmp/payload.tgz" . || { rm -rf "$tmp"; return 1; }
  DUDU_PASSPHRASE=$CRYPTO_PW openssl enc -aes-256-cbc -pbkdf2 -iter "$CRYPTO_ITER" -salt \
    -pass env:DUDU_PASSPHRASE -in "$tmp/payload.tgz" -out "$tmp/backup.enc" || { rm -rf "$tmp"; return 1; }
  salt=$(openssl rand -hex 8)
  key=$(crypto_mac_key "$salt")
  [ -n "$key" ] || { rm -rf "$tmp"; return 1; }
  printf 'dudu-mac-v1 %s %s\n' "$salt" "$(crypto_mac "$tmp/backup.enc" "$key")" > "$tmp/backup.mac"
  awk 'NR == 1 { print; print "  \"encrypted\": true,"; next } { print }' "$b/manifest.json" > "$tmp/manifest.json"
  find "$b" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  mv "$tmp/backup.enc" "$tmp/backup.mac" "$tmp/manifest.json" "$b/"
  rm -rf "$tmp"
  {
    echo "# dudu backup (encrypted)"
    echo
    echo "Everything is inside backup.enc, encrypted with your backup password."
    echo "Restore it on a new machine with:"
    echo
    echo "    curl -fsSL https://raw.githubusercontent.com/$DUDU_REPO/main/install.sh | bash"
    echo "    dudu config     # pick the same destination"
    echo "    dudu restore    # asks for the password"
  } > "$b/RESTORE.md"
}

crypto_is_sealed() { [ -f "$1/backup.enc" ]; }

# Checks the MAC, then decrypts <dir>/backup.enc in place. Returns 1 on a wrong password
# or a modified backup (they cannot be told apart, on purpose).
crypto_open() { # <dir>
  local d=$1 tag salt mac key tries=0
  crypto_is_sealed "$d" || return 0
  has openssl || { err "This backup is encrypted and needs openssl"; return 1; }
  read -r tag salt mac < "$d/backup.mac" 2>/dev/null
  if [ "$tag" != dudu-mac-v1 ] || ! printf '%s' "$salt" | grep -Eq '^[0-9a-fA-F]{16}$'; then
    err "The backup's integrity file is missing or damaged"
    return 1
  fi
  while :; do
    crypto_password || { err "This backup is encrypted: a password is needed"; return 1; }
    key=$(crypto_mac_key "$salt")
    [ -n "$key" ] && [ "$(crypto_mac "$d/backup.enc" "$key")" = "$mac" ] && break
    CRYPTO_PW=""
    tries=$((tries + 1))
    if [ -n "${DUDU_PASSWORD:-}" ] || [ ! -r /dev/tty ] || [ $tries -ge 3 ]; then
      err "Wrong password, or the backup was modified after it was saved"
      return 1
    fi
    warn "Wrong password, try again"
  done
  DUDU_PASSPHRASE=$CRYPTO_PW openssl enc -d -aes-256-cbc -pbkdf2 -iter "$CRYPTO_ITER" \
    -pass env:DUDU_PASSPHRASE -in "$d/backup.enc" | tar -xzf - -C "$d" || {
    err "Could not decrypt the backup"
    return 1
  }
  rm -f "$d/backup.enc" "$d/backup.mac"
}
