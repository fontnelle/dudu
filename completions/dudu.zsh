# zsh syntax highlighting for dudu: valid subcommands in yellow, typos in red.
# Works with fast-syntax-highlighting and zsh-syntax-highlighting, whichever is installed.
# Enable with: eval "$(dudu completion highlight)"   (in ~/.zshrc)

typeset -ga _dudu_commands _dudu_args_config _dudu_args_completion
_dudu_commands=(backup restore status outdated secrets schedule config settings update completion help version)
_dudu_args_config=(show set)
_dudu_args_completion=(zsh bash highlight)

# Is <word> valid after <previous word>? 0 yes, 1 no, 2 not ours to judge.
.dudu-hl-check() { # <position> <word> <subcommand>
  case $1 in
    1) (( ${_dudu_commands[(Ie)$2]} )) ;;
    2) case $3 in
         config|settings) (( ${_dudu_args_config[(Ie)$2]} )) ;;
         completion) (( ${_dudu_args_completion[(Ie)$2]} )) ;;
         *) return 2 ;;
       esac ;;
    *) return 2 ;;
  esac
}

# fast-syntax-highlighting chroma, called once per word after "dudu".
.dudu-chroma() {
  (( next_word = 2 | 8192 ))
  local __first_call=$1 __wrd=$2 __start_pos=$3 __end_pos=$4 __style __ret
  if (( __first_call )); then
    FAST_HIGHLIGHT[chroma-dudu-pos]=0
    FAST_HIGHLIGHT[chroma-dudu-sub]=""
    return 1
  fi
  [[ $__arg_type = 3 ]] && return 2
  if (( in_redirection > 0 || this_word & 128 )) || [[ $__wrd = -* || $__wrd == "<<<" ]]; then
    return 1
  fi
  (( FAST_HIGHLIGHT[chroma-dudu-pos] += 1 ))
  .dudu-hl-check $FAST_HIGHLIGHT[chroma-dudu-pos] "$__wrd" "$FAST_HIGHLIGHT[chroma-dudu-sub]"
  __ret=$?
  (( FAST_HIGHLIGHT[chroma-dudu-pos] == 1 )) && FAST_HIGHLIGHT[chroma-dudu-sub]=$__wrd
  case $__ret in
    0) __style=${FAST_THEME_NAME}subcommand ;;
    1) __style=${FAST_THEME_NAME}incorrect-subtle ;;
    *) return 1 ;;
  esac
  (( __start = __start_pos - ${#PREBUFFER}, __end = __end_pos - ${#PREBUFFER}, __start >= 0 )) &&
    reply+=("$__start $__end ${FAST_HIGHLIGHT_STYLES[$__style]:-fg=yellow}")
  (( this_word = next_word ))
  _start_pos=$_end_pos
  return 0
}

# zsh-syntax-highlighting highlighter: colors the words after each "dudu" in the line.
typeset -gA ZSH_HIGHLIGHT_STYLES
: ${ZSH_HIGHLIGHT_STYLES[dudu-subcommand]:=fg=yellow}
: ${ZSH_HIGHLIGHT_STYLES[dudu-unknown]:=fg=red}
_zsh_highlight_highlighter_dudu_predicate() { _zsh_highlight_buffer_modified; }
_zsh_highlight_highlighter_dudu_paint() {
  local -a words
  local w start=0 pos=0 sub="" in_dudu=0 cmd_pos=1 i ret
  words=(${(z)BUFFER})
  for w in $words; do
    i=${BUFFER[start+1,-1][(ie)$w]}
    (( start += i - 1 ))
    if [[ $w = (';'|'&&'|'||'|'|'|'&') ]]; then
      in_dudu=0 cmd_pos=1
      (( start += ${#w} ))
      continue
    elif (( in_dudu )) && [[ $w != -* ]]; then
      (( pos++ ))
      .dudu-hl-check $pos "$w" "$sub"
      ret=$?
      (( pos == 1 )) && sub=$w
      (( ret == 0 )) && _zsh_highlight_add_highlight $start $((start + ${#w})) dudu-subcommand
      (( ret == 1 )) && _zsh_highlight_add_highlight $start $((start + ${#w})) dudu-unknown
    elif (( cmd_pos )) && [[ $w = dudu ]]; then
      in_dudu=1 pos=0 sub=""
    fi
    cmd_pos=0
    (( start += ${#w} ))
  done
}

typeset -gA FAST_HIGHLIGHT
FAST_HIGHLIGHT[chroma-dudu]=.dudu-chroma
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS
if (( ! ${ZSH_HIGHLIGHT_HIGHLIGHTERS[(Ie)dudu]} )); then
  (( ${#ZSH_HIGHLIGHT_HIGHLIGHTERS} )) || ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)
  ZSH_HIGHLIGHT_HIGHLIGHTERS+=(dudu)
fi
