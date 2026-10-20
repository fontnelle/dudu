#!/usr/bin/env bash
# Linux system packages installed by hand (apt, dnf, pacman), plus flatpak and snap apps.

syspkgs_detect() { ! is_macos && [ -n "$(linux_pm)" ]; }

syspkgs_list_manual() {
  case "$1" in
    apt) apt-mark showmanual 2>/dev/null ;;
    dnf) dnf repoquery --userinstalled --qf '%{name}\n' 2>/dev/null ;;
    pacman) pacman -Qqe 2>/dev/null ;;
  esac
}

syspkgs_list_installed() {
  case "$1" in
    apt) dpkg-query -W -f='${Package}\n' 2>/dev/null ;;
    dnf) rpm -qa --qf '%{NAME}\n' 2>/dev/null ;;
    pacman) pacman -Qq 2>/dev/null ;;
  esac
}

syspkgs_install() {
  case "$1" in
    apt) shift; as_root apt-get install -y "$@" ;;
    dnf) shift; as_root dnf install -y "$@" ;;
    pacman) shift; as_root pacman -S --needed --noconfirm "$@" ;;
  esac
}

syspkgs_backup() {
  local pm
  pm=$(linux_pm)
  echo "$pm" > "$1/manager"
  syspkgs_list_manual "$pm" | sort -u > "$1/packages.txt" || return 1
  if has flatpak; then flatpak list --app --columns=application 2>/dev/null | sort -u > "$1/flatpak.txt" || return 1; fi
  if has snap; then
    snap list 2>/dev/null | awk 'NR > 1 && $1 !~ /^(core[0-9]*|snapd|bare|gtk-common-themes|gnome-.*|snapd-desktop-integration)$/ { print $1 }' > "$1/snap.txt" || return 1
  fi
  summary "$1" "$(tn "%d %s package" "%d %s packages" "$(count_lines "$1/packages.txt")" "$pm")"
}

# Installs the packages of <list> this system does not have yet, in one batch if it can.
syspkgs_install_missing() { # <pm> <list>
  local pkgs p
  pkgs=$(syspkgs_list_installed "$1" | missing_pkgs "$2")
  if [ -z "$pkgs" ]; then
    dim "  $(t "all packages already installed")"
    return 0
  fi
  [ "$1" = apt ] && as_root apt-get update
  # shellcheck disable=SC2086
  if ! syspkgs_install "$1" $pkgs; then
    warn "$(t "Batch install failed, installing one by one")"
    for p in $pkgs; do syspkgs_install "$1" "$p" || warn "$(t "could not install %s" "$p")"; done
  fi
}

# Installs the Flathub apps of <list> that are missing.
syspkgs_flatpak_missing() { # <list>
  local app
  while IFS= read -r app; do
    act flatpak install -y --noninteractive flathub "$app" || warn "$(t "could not install %s" "$app")"
  done < <(flatpak list --app --columns=application 2>/dev/null | missing_pkgs "$1")
}

syspkgs_restore() {
  if is_macos; then dim "  $(t "Linux only, skipped")"; return 0; fi
  local pm saved
  pm=$(linux_pm)
  saved=$(cat "$1/manager" 2>/dev/null)
  if [ "$pm" != "$saved" ]; then
    warn "$(t "Backup came from %s, this machine uses %s. Trying the same package names." "$saved" "$pm")"
  fi
  syspkgs_install_missing "$pm" "$1/packages.txt"
  if [ -s "$1/flatpak.txt" ] && has flatpak; then syspkgs_flatpak_missing "$1/flatpak.txt"; fi
  if [ -s "$1/snap.txt" ] && has snap; then
    local s
    while IFS= read -r s; do
      as_root snap install "$s" || warn "$(t "could not install %s" "$s")"
    done < <(snap list 2>/dev/null | awk 'NR > 1 { print $1 }' | missing_pkgs "$1/snap.txt")
  fi
}

syspkgs_outdated() {
  case "$(linux_pm)" in
    # "curl/noble-updates 8.5.0-2ubuntu10.6 amd64 [upgradable from: 8.5.0-2ubuntu10.4]"
    apt) apt list --upgradable 2>/dev/null | grep -v '^Listing' |
           sed -E 's|^([^/]+)/[^ ]+ ([^ ]+) .*from: ([^]]+)\]$|\1 \3 \2|' ;;
    dnf) dnf check-update -q 2>/dev/null | awk 'NF == 3 { sub(/\.[^.]+$/, "", $1); print $1, "?", $2 }' ;;
    pacman) has checkupdates && checkupdates 2>/dev/null | awk '{ print $1, $2, $4 }' ;;
  esac
}

syspkgs_upgrade_hint() {
  case "$(linux_pm)" in
    apt) echo "sudo apt upgrade" ;;
    dnf) echo "sudo dnf upgrade" ;;
    pacman) echo "sudo pacman -Syu" ;;
  esac
}

# Needs sudo: run in the foreground, never under the spinner.
syspkgs_upgrade() {
  case "$(linux_pm)" in
    apt) as_root apt-get install -y --only-upgrade "$@" ;;
    dnf) as_root dnf upgrade -y "$@" ;;
    pacman) as_root pacman -S --needed --noconfirm "$@" ;;
  esac
}
