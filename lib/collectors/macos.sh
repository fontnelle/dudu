#!/usr/bin/env bash
# A curated set of macOS preferences devs usually tweak (Dock, Finder, keyboard, screenshots).

MACOS_DEFAULTS="com.apple.dock autohide
com.apple.dock autohide-delay
com.apple.dock tilesize
com.apple.dock orientation
com.apple.dock show-recents
com.apple.dock mineffect
com.apple.dock magnification
com.apple.dock wvous-tl-corner
com.apple.dock wvous-tr-corner
com.apple.dock wvous-bl-corner
com.apple.dock wvous-br-corner
com.apple.finder AppleShowAllFiles
com.apple.finder ShowPathbar
com.apple.finder ShowStatusBar
com.apple.finder FXPreferredViewStyle
com.apple.finder FXEnableExtensionChangeWarning
com.apple.finder _FXShowPosixPathInTitle
NSGlobalDomain KeyRepeat
NSGlobalDomain InitialKeyRepeat
NSGlobalDomain ApplePressAndHoldEnabled
NSGlobalDomain AppleShowAllExtensions
NSGlobalDomain AppleInterfaceStyle
NSGlobalDomain NSAutomaticSpellingCorrectionEnabled
NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled
NSGlobalDomain NSAutomaticDashSubstitutionEnabled
NSGlobalDomain com.apple.swipescrolldirection
com.apple.screencapture location
com.apple.screencapture type
com.apple.screencapture disable-shadow
com.apple.desktopservices DSDontWriteNetworkStores"

macos_detect() { is_macos; }

macos_backup() {
  local domain key type value
  : > "$1/defaults.txt"
  while read -r domain key; do
    type=$(defaults read-type "$domain" "$key" 2>/dev/null | awk '{ print $3 }') || continue
    case "$type" in boolean|integer|float|string) ;; *) continue ;; esac
    value=$(defaults read "$domain" "$key" 2>/dev/null) || continue
    printf '%s|%s|%s|%s\n' "$domain" "$key" "$type" "$value" >> "$1/defaults.txt"
  done <<< "$MACOS_DEFAULTS"
  summary "$1" "$(tn "%d preference" "%d preferences" "$(count_lines "$1/defaults.txt")")"
}

macos_restore() {
  if ! is_macos; then dim "  $(t "macOS only, skipped")"; return 0; fi
  local domain key type value flag current changed=""
  while IFS='|' read -r domain key type value; do
    # Only the preferences dudu knows, with a plain type: a backup cannot write anything else.
    if ! printf '%s\n' "$MACOS_DEFAULTS" | grep -qxF "$domain $key" ||
       ! case "$type" in boolean|integer|float|string) true ;; *) false ;; esac; then
      warn "$(t "ignored unexpected preference in the backup: %s" "$(safe_text "$domain $key")")"
      continue
    fi
    current=$(defaults read "$domain" "$key" 2>/dev/null)
    [ "$current" = "$value" ] && continue
    case "$type" in
      boolean) flag=-bool; [ "$value" = 1 ] && value=true || value=false ;;
      integer) flag=-int ;;
      float) flag=-float ;;
      *) flag=-string ;;
    esac
    act defaults write "$domain" "$key" "$flag" "$value" && [ -z "${DUDU_DRY_RUN:-}" ] && ok "$domain $key = $value"
    changed=1
  done < "$1/defaults.txt"
  if [ -n "$changed" ]; then
    act killall Dock Finder SystemUIServer 2>/dev/null
  else
    dim "  = $(t "all preferences already set")"
  fi
  return 0
}
