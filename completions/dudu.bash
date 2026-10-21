# bash completion for dudu

_dudu() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  local prev=${COMP_WORDS[COMP_CWORD-1]}
  local commands="backup restore status outdated secrets schedule config update completion --help --version"
  local collectors="brew syspkgs winget scoop choco shell git terminal node npm pnpm yarn bun python ruby cargo go vscode cursor macos"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    return
  fi
  case "$prev" in
    --only) COMPREPLY=($(compgen -W "$collectors" -- "$cur")); return ;;
    --file) COMPREPLY=($(compgen -d -- "$cur")); return ;;
  esac
  case "${COMP_WORDS[1]}" in
    backup|status|secrets) COMPREPLY=($(compgen -W "--dry-run --only" -- "$cur")) ;;
    restore) COMPREPLY=($(compgen -W "--dry-run --only --from --file --yes" -- "$cur")) ;;
    config) COMPREPLY=($(compgen -W "show gdrive set" -- "$cur")) ;;
    schedule) COMPREPLY=($(compgen -W "on off status" -- "$cur")) ;;
    completion) COMPREPLY=($(compgen -W "zsh bash highlight" -- "$cur")) ;;
  esac
}

complete -F _dudu dudu
