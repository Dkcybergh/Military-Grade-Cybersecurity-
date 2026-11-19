#!/usr/bin/env bash
# =============================================================================
#   C1DC CYBERSECURITY NETWORK ACADEMY                                  v2.0
#   One self-contained, hands-on networking course for Kali Linux.
# -----------------------------------------------------------------------------
#   HOW TO RUN (as your normal user, NOT as root)
#     bash cybersecurity_network.sh               interactive academy
#     bash cybersecurity_network.sh --check       are the tools installed?
#     bash cybersecurity_network.sh --lab         build the isolated cyber-range
#     bash cybersecurity_network.sh --module 4    jump straight to module 4
#     bash cybersecurity_network.sh --drill       subnetting practice
#     bash cybersecurity_network.sh --tickets     troubleshooting tickets
#     bash cybersecurity_network.sh --cleanup     remove the cyber-range
#     bash cybersecurity_network.sh --self-test   INSTRUCTOR: run every lab
#                                                 unattended (needs sudo -n)
#     Options: --ascii (no Unicode)   --no-color   NO_COLOR=1 is honoured
#
#   SAFETY MODEL
#     * Every active experiment runs inside five Linux network namespaces
#       (c1-student, c1-peer, c1-switch, c1-router, c1-server). They have
#       no link to your real LAN or the Internet.
#     * sudo is used ONLY to create/inspect those namespaces. The host's
#       interfaces, routes and firewall are never modified.
#     * The academy runs only the exact command it displayed. The free lab
#       shells (menu S) are clearly labelled and stay inside a namespace.
#     * Never point these techniques at networks you do not own or have
#       written permission to test.
#
#   TEACHING MODEL (every practical follows the same rhythm)
#     READ the concept -> PREDICT the result -> TYPE the command ->
#     READ the live output with a field guide -> EXPLAIN it in the journal.
#     All predictions, reflections and quiz results are saved to
#     ~/c1dc-network-labs/journal.md as evidence of the student's own work.
#
#   FOR INSTRUCTORS: HOW THIS FILE IS ORGANISED
#     PART 1  settings, colours, text layout helpers
#     PART 2  lesson engine: practical, quiz, reflect, journal, progress
#     PART 3  the cyber-range (build, destroy, services, shells, map)
#     PART 4  modules 01-16
#     PART 5  practice: subnetting drill, tickets, threat hunt, reference
#     PART 6  menu and command-line entry point
#     To add an exercise, copy any `practical` block; each key=value
#     option is documented above the practical() function.
# =============================================================================
set -u
VERSION="2.0.0"

# =============================================================================
# PART 1 · SETTINGS, COLOURS AND TEXT LAYOUT
# =============================================================================
NONINTERACTIVE=0
SELFTEST=0
UTF=0
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF=1 ;; esac
for _a in "$@"; do [[ $_a == --ascii ]] && UTF=0; [[ $_a == --no-color ]] && NO_COLOR=1; done
[[ ${C1DC_ASCII:-0} == 1 ]] && UTF=0
if ((UTF)) && locale -a 2>/dev/null | grep -qix 'c\.utf-\?8'; then export LC_ALL=C.UTF-8
elif ((UTF == 0)); then export LC_ALL=C; fi

RUN_AS="${SUDO_USER:-$(id -un)}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/c1dc-network-academy"
PROGRESS="$STATE_DIR/completed.txt"
SCORES="$STATE_DIR/scores.txt"
WORK="${C1DC_WORK:-$HOME/c1dc-network-labs}"
LABDIR="$WORK/lab"; LOGS="$WORK/logs"; TOOLS="$WORK/tools"; WWW="$WORK/www"
EVID="$WORK/evidence"; RUNDIR="$LABDIR/run"; PKI="$LABDIR/pki"
JOURNAL="$WORK/journal.md"
mkdir -p "$STATE_DIR" "$WORK" "$LABDIR" "$LOGS" "$TOOLS" "$WWW" "$EVID" "$RUNDIR" "$PKI" 2>/dev/null || true

setup_colors(){
  if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    RST=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; ITAL=$'\e[3m'
    RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; BLU=$'\e[34m'; MAG=$'\e[35m'; CYN=$'\e[36m'
    GRY=$'\e[90m'; BRED=$'\e[1;31m'; BGRN=$'\e[1;32m'; BYEL=$'\e[1;33m'; BCYN=$'\e[1;36m'; BMAG=$'\e[1;35m'; BBLU=$'\e[1;34m'
    REV=$'\e[7m'
  else
    RST=''; BOLD=''; DIM=''; ITAL=''; RED=''; GRN=''; YEL=''; BLU=''; MAG=''; CYN=''
    GRY=''; BRED=''; BGRN=''; BYEL=''; BCYN=''; BMAG=''; BBLU=''; REV=''
  fi
}
setup_colors

if ((UTF)); then
  H='─'; HH='━'; V='│'; VV='┃'; TL='┌'; TR='┐'; BL='└'; BR='┘'
  DH='═'; DV='║'; DTL='╔'; DTR='╗'; DBL='╚'; DBR='╝'
  OK='✔'; NO='✘'; DOT='●'; ODOT='○'; ARR='→'; BUL='•'; PROMPT='›'; FULL='█'; LIGHT='░'; ELL='…'
  I_CONCEPT='◆'; I_WHY='★'; I_ANALOGY='≈'; I_SEC='■'; I_DEEP='⚙'; I_TIP='✔'; I_WARN='!'; I_MIST='✘'; I_TURN='▶'; I_THINK='✎'
else
  H='-'; HH='='; V='|'; VV='|'; TL='+'; TR='+'; BL='+'; BR='+'
  DH='='; DV='|'; DTL='+'; DTR='+'; DBL='+'; DBR='+'
  OK='[ok]'; NO='[x]'; DOT='*'; ODOT='o'; ARR='->'; BUL='*'; PROMPT='>'; FULL='#'; LIGHT='.'; ELL='...'
  I_CONCEPT='*'; I_WHY='*'; I_ANALOGY='~'; I_SEC='#'; I_DEEP='%'; I_TIP='+'; I_WARN='!'; I_MIST='x'; I_TURN='>'; I_THINK='?'
fi

# Screen width: clamp to 64..100 so text never becomes a thin column or an unreadable line.
term_width(){
  local c=''
  c=$(tput cols 2>/dev/null) || c=''
  [[ $c =~ ^[0-9]+$ ]] || c=$(stty size 2>/dev/null </dev/tty | awk '{print $2}') || c=''
  [[ $c =~ ^[0-9]+$ ]] || c=${COLUMNS:-80}
  [[ $c =~ ^[0-9]+$ ]] || c=80
  ((c > 100)) && c=100; ((c < 64)) && c=64
  W=$c
}
term_width

rep(){ local s='' i; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }

# Inline markup inside lesson text:  {b}bold{/}  {c}command{/}  {y}..{/}  {g}..{/}  {r}..{/}
markup(){
  local s=$1
  s=${s//\{b\}/$BOLD}; s=${s//\{c\}/$BCYN}; s=${s//\{y\}/$BYEL}; s=${s//\{g\}/$BGRN}
  s=${s//\{r\}/$BRED}; s=${s//\{m\}/$BMAG}; s=${s//\{i\}/$ITAL}; s=${s//\{\/\}/$RST}
  printf '%s' "$s"
}

# wrap FIRST_PREFIX NEXT_PREFIX VISIBLE_PREFIX_WIDTH TEXT
wrap(){
  local p1=$1 p2=$2 pw=$3 text=$4 width line first=1
  width=$((W - pw - 1)); ((width < 24)) && width=24
  while IFS= read -r line || [[ -n $line ]]; do
    if ((first)); then printf '%s%s%s\n' "$p1" "$(markup "$line")" "$RST"; first=0
    else printf '%s%s%s\n' "$p2" "$(markup "$line")" "$RST"; fi
  done < <(printf '%s\n' "$text" | fold -s -w "$width" | sed 's/[[:space:]]*$//')
}

# say "paragraph" ["paragraph" ...]  — normal reading text
say(){ local p; for p in "$@"; do wrap '  ' '  ' 2 "$p"; echo; done; }

# bullets "item" ...
bullets(){ local b; for b in "$@"; do wrap "    $CYN$BUL$RST " '      ' 6 "$b"; done; echo; }

# numbered "item" ...
numbered(){ local i=0 b; for b in "$@"; do ((++i)); wrap "    $BOLD$i.$RST " '       ' 7 "$b"; done; echo; }

# callout KIND "text" ["text"...]
callout(){
  local kind=$1 col label t; shift
  case $kind in
    concept)  col=$CYN; label="$I_CONCEPT CONCEPT" ;;
    why)      col=$YEL; label="$I_WHY WHY IT MATTERS" ;;
    analogy)  col=$MAG; label="$I_ANALOGY ANALOGY" ;;
    security) col=$RED; label="$I_SEC SECURITY LENS" ;;
    deep)     col=$BLU; label="$I_DEEP UNDER THE HOOD" ;;
    tip)      col=$GRN; label="$I_TIP PRO TIP" ;;
    warn)     col=$YEL; label="$I_WARN CAUTION" ;;
    mistake)  col=$RED; label="$I_MIST COMMON MISTAKE" ;;
    turn)     col=$MAG; label="$I_TURN YOUR TURN  (no script: you, a second terminal, and curiosity)" ;;
    *)        col=$CYN; label=$kind ;;
  esac
  printf '  %s%s%s %s%s%s\n' "$col" "$VV" "$RST" "$BOLD$col" "$label" "$RST"
  for t in "$@"; do wrap "  $col$VV$RST " "  $col$VV$RST " 4 "$t"; done
  echo
}

# figure "caption" <<'EOF' ... EOF   — diagrams, tables, sample output
figure(){
  local cap=${1:-} l
  [[ -n $cap ]] && printf '  %s%sFIGURE%s %s%s%s\n' "$DIM" "$BOLD" "$RST" "$DIM" "$cap" "$RST"
  while IFS= read -r l || [[ -n $l ]]; do printf '   %s%s%s\n' "$CYN" "$l" "$RST"; done
  echo
}

# terms "TERM :: definition" ...   — aligned glossary
terms(){
  local line k v w=0 i
  local -a ks=() vs=()
  for line in "$@"; do k=${line%% :: *}; v=${line#* :: }; ks+=("$k"); vs+=("$v"); ((${#k} > w)) && w=${#k}; done
  ((w > 22)) && w=22
  for i in "${!ks[@]}"; do
    wrap "    $BOLD$(printf '%-*s' "$w" "${ks[i]}")$RST  " "    $(rep ' ' "$w")  " $((w + 6)) "${vs[i]}"
  done
  echo
}

# section "Title"  — numbered heading inside a module
section(){
  ((++SEC))
  local label=" ${CUR_MOD}.${SEC}  $1 " fill
  fill=$((W - 6 - ${#label})); ((fill < 3)) && fill=3
  printf '\n  %s%s%s%s%s%s\n\n' "$BCYN" "$HH$HH" "$BOLD" "$label" "$BCYN$(rep "$HH" "$fill")" "$RST"
}

boxline(){ # boxline LEFT FILL RIGHT
  printf '  %s%s%s%s%s\n' "$BCYN" "$1" "$(rep "$2" $((W - 6)))" "$3" "$RST"
}
boxtext(){ # boxtext "plain text" [colour] [border]  (text must be plain: no markup)
  local t=$1 c=${2:-$BOLD} b=${3:-$DV} max=$((W - 8)) pad
  ((${#t} > max)) && t="${t:0:max-1}$ELL"
  pad=$((max - ${#t})); ((pad < 0)) && pad=0
  printf '  %s%s%s %s%s%s%s %s%s%s\n' "$BCYN" "$b" "$RST" "$c" "$t" "$RST" "$(rep ' ' "$pad")" "$BCYN" "$b" "$RST"
}

clear_screen(){ ((NONINTERACTIVE)) && return 0; [[ -t 1 ]] || return 0; printf '\e[H\e[2J'; }

# Readers need breathing space: long theory is split into pages.
pageturn(){
  ((NONINTERACTIVE)) && return 0
  printf '  %s%s %s ENTER to keep reading %s%s' "$DIM" "$(rep "$H" 3)" "$PROMPT" "$(rep "$H" 3)" "$RST"
  read -r -s _ || true
  printf '\r\e[K'
}
pause(){
  ((NONINTERACTIVE)) && return 0
  printf '\n  %sPress ENTER to continue%s ' "$DIM" "$RST"; read -r _ || true
}

info(){ wrap "  $CYN$BUL$RST " '    ' 4 "$*"; }
good(){ wrap "  $BGRN$OK$RST " '    ' 4 "$*"; }
warn(){ wrap "  $BYEL$I_WARN$RST " '    ' 4 "{y}$*{/}"; }
bad(){ wrap "  $BRED$NO$RST " '    ' 4 "$*"; }

progress_bar(){ # progress_bar DONE TOTAL WIDTH
  local d=$1 t=$2 w=$3 f
  ((t == 0)) && t=1
  f=$((d * w / t))
  printf '%s%s%s%s%s' "$BGRN" "$(rep "$FULL" "$f")" "$GRY" "$(rep "$LIGHT" $((w - f)))" "$RST"
}

# =============================================================================
# PART 2 · LESSON ENGINE
# =============================================================================
CUR_MOD='00'; SEC=0; PRAC=0; Q_OK=0; Q_TOTAL=0; P_DONE=0; P_SKIP=0
ST_PASS=0; ST_FAIL=0; ST_FAILS=()
REPLY_TEXT=''
INTERRUPTED=0
trap 'INTERRUPTED=1; printf "\n"' INT

PS_STUDENT=$'\001'"$BGRN"$'\002'"student@c1dc"$'\001'"$RST"$'\002'":"$'\001'"$BBLU"$'\002'"~/c1dc-network-labs"$'\001'"$RST"$'\002'"\$ "

journal(){ printf '%s\n' "$@" >>"$JOURNAL" 2>/dev/null || true; }
journal_init(){
  [[ -f $JOURNAL ]] && return 0
  journal "# C1DC Network Academy — Student Journal" "" \
    "Owner: $RUN_AS   ·   Started: $(date '+%Y-%m-%d %H:%M %Z')" "" \
    "Everything below was written or typed by the student during the course." \
    "Predictions are recorded BEFORE each command runs; compare them with the results." ""
}

ask(){ # ask "prompt" -> REPLY_TEXT
  REPLY_TEXT=''
  if ((NONINTERACTIVE)); then REPLY_TEXT='(self-test)'; return 0; fi
  read -e -r -p "  $1 $PROMPT " REPLY_TEXT || REPLY_TEXT=''
}

squeeze(){
  local s=$*
  s=${s//$'\t'/ }
  while [[ $s == *'  '* ]]; do s=${s//  / }; done
  s=${s# }; s=${s% }
  printf '%s' "$s"
}

show_diff(){
  local want=$1 got=$2 i=0 max
  max=${#want}; ((${#got} > max)) && max=${#got}
  while ((i < max)) && [[ ${want:i:1} == "${got:i:1}" ]]; do ((i++)); done
  printf '  %s%s Not quite.%s The first difference is at character %d:\n' "$BYEL" "$NO" "$RST" $((i + 1))
  printf '    %sexpected :%s %s\n' "$DIM" "$RST" "$want"
  printf '    %syou typed:%s %s\n' "$DIM" "$RST" "$got"
  printf '               %s%s^%s\n' "$(rep ' ' "$i")" "$BRED" "$RST"
}

show_tokens(){
  local -a parts; local i
  read -r -a parts <<<"$1"
  printf '  %sHint: type it piece by piece:%s\n    ' "$BOLD" "$RST"
  for i in "${!parts[@]}"; do printf '%s%d:%s%s  ' "$DIM" $((i + 1)) "$RST" "${parts[i]}"; done
  printf '\n'
}

# The student must type the command. Spacing is forgiven; content is not.
type_gate(){
  local cmd=$1 entered n_c
  if ((NONINTERACTIVE)); then
    printf '  %s%s %s%s  %s(self-test: typed automatically)%s\n' "$BGRN" "student@c1dc\$" "$RST" "$cmd" "$DIM" "$RST"
    return 0
  fi
  printf '  %sType it yourself%s %s(arrow keys work · h = hint · s = skip)%s\n' "$BOLD" "$RST" "$DIM" "$RST"
  n_c=$(squeeze "$cmd")
  while true; do
    entered=''
    INTERRUPTED=0
    read -e -r -p "  $PS_STUDENT" entered || { echo; return 1; }
    ((INTERRUPTED)) && return 1
    if [[ $(squeeze "$entered") == "$n_c" ]]; then history -s -- "$cmd" 2>/dev/null; return 0; fi
    case ${entered,,} in
      s | skip) warn "Skipped. Come back to it later: typing commands is how they move into long-term memory."; return 1 ;;
      h | hint | '?') show_tokens "$cmd"; continue ;;
      '') continue ;;
    esac
    show_diff "$n_c" "$(squeeze "$entered")"
  done
}

frame_output(){
  local max=$1 n=0 line
  while IFS= read -r line || [[ -n $line ]]; do
    ((++n))
    ((n <= max)) && printf '  %s%s%s %s\n' "$GRY" "$V" "$RST" "$line"
  done
  ((n > max)) && printf '  %s%s %s %d more line(s) hidden; run it in your own terminal to see all%s\n' "$GRY" "$V" "$ELL" $((n - max)) "$RST"
  ((n == 0)) && printf '  %s%s (no output: for many commands silence means success)%s\n' "$GRY" "$V" "$RST"
  return 0
}

guide_table(){ # guide_table LABEL COLOUR "token :: meaning\n..."
  local label=$1 col=$2 spec=$3 line tok mean w=0 i
  local -a toks=() means=()
  while IFS= read -r line; do
    [[ -z ${line// /} ]] && continue
    line=${line#"${line%%[![:space:]]*}"}
    tok=${line%% :: *}; mean=${line#* :: }
    toks+=("$tok"); means+=("$mean"); ((${#tok} > w)) && w=${#tok}
  done <<<"$spec"
  ((w > 26)) && w=26
  printf '  %s%s%s %s%s%s\n' "$col" "$VV" "$RST" "$BOLD$col" "$label" "$RST"
  for i in "${!toks[@]}"; do
    wrap "  $col$VV$RST  $col$(printf '%-*s' "$w" "${toks[i]}")$RST  " "  $col$VV$RST  $(rep ' ' "$w")  " $((w + 7)) "${means[i]}"
  done
  echo
}

card_top(){ # card_top "PRACTICAL 4.2" "title"
  local tag=" $1 " fill
  fill=$((W - 6 - ${#tag})); ((fill < 3)) && fill=3
  printf '\n  %s%s%s%s%s%s%s\n' "$BGRN" "$TL$H" "$REV" "$tag" "$RST$BGRN" "$(rep "$H" "$fill")" "$RST"
  wrap "  $BGRN$V$RST $BOLD" "  $BGRN$V$RST $BOLD" 4 "$2"
  printf '  %s%s%s\n' "$BGRN" "$V" "$RST"
}
card_field(){ # card_field LABEL text
  local lbl
  lbl=$(printf '%-8s' "$1")
  wrap "  $BGRN$V$RST $DIM$lbl$RST " "  $BGRN$V$RST $(rep ' ' 8) " 13 "$2"
}
card_cmd(){
  printf '  %s%s%s %s%-8s%s %s$ %s%s\n' "$BGRN" "$V" "$RST" "$DIM" "COMMAND" "$RST" "$BGRN$BOLD" "$1" "$RST"
}
card_end(){ printf '  %s%s%s%s\n' "$BGRN" "$BL" "$(rep "$H" $((W - 4)))" "$RST"; }

# Run a root-level snippet in the foreground / background (lab plumbing).
priv(){ sudo bash -c "$1"; }
priv_bg(){ sudo setsid -f bash -c "exec </dev/null >>$(printf '%q' "$LOGS/background.log") 2>&1; $1"; }

# -----------------------------------------------------------------------------
# practical key=value ...      (the heart of the course)
#   title=    one-line name of the exercise
#   goal=     why we are doing it (1-2 sentences)
#   cmd=      the EXACT command the student types — and the exact one that runs
#   anatomy=  lines "token :: meaning" explaining every part of the command
#   predict=  question answered BEFORE running (saved to the journal)
#   read=     lines "field :: meaning": how to read the output
#   explain=  paragraph "what just happened / under the hood"
#   needs=    commands that must exist (space-separated)
#   lab=1     needs the cyber-range (offers to build it)
#   expect=   ok | fail | any   (fail = the error IS the lesson)
#   maxlines= cap on displayed output lines (default 60)
#   pre=      root-level preparation, shown to the student, run before
#   bg=       root-level traffic generator started 'delay' seconds after the
#             command starts (for captures). Shown to the student.
#   delay=    seconds before bg starts (default 1.5)
#   verify=   root-level check after the command; exit 0 = verified
#   after=    root-level tidy-up after the step (shown)
# -----------------------------------------------------------------------------
practical(){
  local title='' goal='' cmd='' anatomy='' predict='' readg='' explain='' needs='' lab=0
  local expect=ok maxlines=60 pre='' bg='' delay=1.5 verify='' after='' kv k v
  for kv in "$@"; do
    k=${kv%%=*}; v=${kv#*=}
    case $k in
      title) title=$v ;; goal) goal=$v ;; cmd) cmd=$v ;; anatomy) anatomy=$v ;; predict) predict=$v ;;
      read) readg=$v ;; explain) explain=$v ;; needs) needs=$v ;; lab) lab=$v ;; expect) expect=$v ;;
      maxlines) maxlines=$v ;; pre) pre=$v ;; bg) bg=$v ;; delay) delay=$v ;; verify) verify=$v ;; after) after=$v ;;
      *) printf 'BUG in lesson: unknown practical option "%s"\n' "$k" >&2 ;;
    esac
  done
  ((++PRAC))
  local id="${CUR_MOD}.${PRAC}" d missing=''
  card_top "PRACTICAL $id" "$title"
  [[ -n $goal ]] && card_field GOAL "$goal"
  for d in $needs; do command -v "$d" >/dev/null 2>&1 || missing+="$d "; done
  if [[ -n $missing ]]; then
    card_field SKIPPED "Tool(s) not installed: ${missing}. Run menu C for the install command, then come back."
    card_end; ((++P_SKIP)); st_record "$id" skip; return 0
  fi
  if ((lab)) && ! lab_ensure; then
    card_field SKIPPED "This exercise needs the cyber-range (menu L)."
    card_end; ((++P_SKIP)); st_record "$id" skip; return 0
  fi
  card_cmd "$cmd"
  printf '  %s%s%s\n' "$BGRN" "$V" "$RST"
  [[ -n $anatomy ]] && guide_table "ANATOMY OF THE COMMAND" "$YEL" "$anatomy"
  card_end
  local prediction=''
  if [[ -n $predict ]]; then
    wrap "  $BMAG$I_THINK PREDICT FIRST:$RST " '    ' 18 "$predict"
    ask "Your prediction"; prediction=$REPLY_TEXT
  fi
  if ! type_gate "$cmd"; then
    ((++P_SKIP)); journal "- [$id] SKIPPED: \`$cmd\`"; return 0
  fi
  if [[ $cmd == *sudo* || -n $pre || -n $bg || -n $verify || -n $after ]]; then sudo_ready || return 0; fi
  if [[ -n $pre ]]; then
    printf '  %s%s academy prepares:%s %s%s%s\n' "$DIM" "$I_DEEP" "$RST" "$DIM" "$pre" "$RST"
    priv "$pre" >/dev/null 2>&1 || true
  fi
  if [[ -n $bg ]]; then
    printf '  %s%s academy generates traffic after %ss:%s %s%s%s\n' "$DIM" "$I_DEEP" "$delay" "$RST" "$DIM" "$bg" "$RST"
    local wd_ns=''
    [[ $cmd =~ netns\ exec\ ([a-z0-9-]+) ]] && wd_ns=${BASH_REMATCH[1]}
    priv_bg "sleep $delay; $bg"
    # watchdog: a capture must never wait forever
    [[ -n $wd_ns ]] && priv_bg "sleep 20; for p in \$(ip netns pids $wd_ns); do grep -qx tcpdump /proc/\$p/comm 2>/dev/null && kill -INT \$p; done"
  fi
  printf '\n  %s%s%s LIVE OUTPUT %s%s\n' "$GRY" "$TL" "$H" "$(rep "$H" $((W - 18)))" "$RST"
  local rc
  INTERRUPTED=0
  (cd "$WORK" && bash -c "$cmd") </dev/null 2>&1 | frame_output "$maxlines"
  rc=${PIPESTATUS[0]}
  ((INTERRUPTED)) && rc=130
  local status
  if ((rc == 0)); then
    if [[ $expect == fail ]]; then
      status="$BYEL exit status 0 $BUL we expected this to FAIL. Has the lab changed? (menu M shows its state)$RST"; st_record "$id" fail "$title (expected failure, got success)"
    else status="$BGRN exit status 0 $BUL success$RST"; st_record "$id" pass; fi
  else
    if [[ $expect == fail ]]; then
      status="$BGRN exit status $rc $BUL this failure is EXPECTED: the error message is your evidence$RST"; st_record "$id" pass
    elif [[ $expect == any ]]; then
      status="$BCYN exit status $rc $BUL non-zero is normal for this command$RST"; st_record "$id" pass
    else
      status="$BRED exit status $rc $BUL the command reported a problem. Read the message; check spelling, interface names, sudo and the lab state (menu M).$RST"
      st_record "$id" fail "$title (rc=$rc)"
    fi
  fi
  printf '  %s%s%s%s\n\n' "$GRY" "$BL" "$H" "$status"
  if [[ -n $verify ]]; then
    if priv "$verify" >/dev/null 2>&1; then good "Verified by the academy: the expected change is really in place."
    else warn "The academy could not confirm the expected change. Re-read the output above."; st_record "$id" fail "$title (verify failed)"; fi
    echo
  fi
  [[ -n $readg ]] && guide_table "HOW TO READ THIS OUTPUT" "$CYN" "$readg"
  [[ -n $explain ]] && callout deep "$explain"
  if [[ -n $after ]]; then
    printf '  %s%s academy tidies up:%s %s%s%s\n\n' "$DIM" "$I_DEEP" "$RST" "$DIM" "$after" "$RST"
    priv "$after" >/dev/null 2>&1 || true
  fi
  ((++P_DONE))
  journal "- [$id] $title" "  - command: \`$cmd\` (exit $rc)"
  [[ -n $prediction ]] && journal "  - my prediction: $prediction"
  pageturn
}

reflect(){ # reflect "question" "expert answer"
  printf '\n'
  callout "$I_THINK THINK & WRITE" "$1"
  ask "Your answer (own words)"
  journal "- REFLECTION ($CUR_MOD): $1" "  - my answer: ${REPLY_TEXT:-<blank>}"
  wrap "  $BGRN$OK Compare with an expert answer:$RST " '    ' 4 "$2"
  echo
}

# quiz "question" ANSWER_LETTER "why" "option A" "option B" ["option C" ["option D"]]
quiz(){
  local q=$1 ans=$2 why=$3 typed i
  shift 3
  local -a opts=("$@") L=(A B C D E)
  ((++Q_TOTAL))
  printf '\n  %s KNOWLEDGE CHECK %s\n' "$BYEL$REV" "$RST"
  wrap "  $BOLD" "  $BOLD" 2 "$q"
  for i in "${!opts[@]}"; do wrap "     $BYEL${L[i]})$RST " '        ' 8 "${opts[i]}"; done
  if ((NONINTERACTIVE)); then typed=$ans
  else
    while true; do
      read -r -p "  Your answer [A-${L[${#opts[@]} - 1]}] $PROMPT " typed || { typed=''; break; }
      typed=${typed^^}; typed=${typed// /}
      [[ $typed =~ ^[A-E]$ ]] && break
    done
  fi
  if [[ $typed == "$ans" ]]; then
    ((++Q_OK)); wrap "  $BGRN$OK Correct.$RST " '    ' 4 "$why"
  else
    wrap "  $BYEL$NO The answer is $ans.$RST " '    ' 4 "$why"
  fi
  journal "- QUIZ ($CUR_MOD): ${q} -> answered ${typed:-none}, correct $ans"
}

takeaways(){
  printf '\n  %s KEY TAKEAWAYS %s\n' "$BGRN$REV" "$RST"
  local i=0 t
  for t in "$@"; do ((++i)); wrap "   $BGRN$i$RST  " '      ' 6 "$t"; done
  echo
}

objectives(){
  printf '  %sBy the end of this module you will be able to:%s\n' "$BOLD" "$RST"
  local o
  for o in "$@"; do wrap "    $BGRN$OK$RST " '      ' 6 "$o"; done
  echo
}

module_open(){ # module_open NUM "TITLE" MINUTES "TRACK"
  CUR_MOD=$1; SEC=0; PRAC=0; Q_OK=0; Q_TOTAL=0; P_DONE=0; P_SKIP=0
  term_width; clear_screen
  local n=$((10#$1))
  echo
  boxline "$DTL" "$DH" "$DTR"
  boxtext "MODULE $1 of 16  ·  $4  ·  about $3 minutes" "$DIM"
  boxtext "$2" "$BOLD"
  boxline "$DBL" "$DH" "$DBR"
  printf '  %s\n\n' "$(progress_bar "$n" 16 $((W - 4)))"
  journal "" "## Module $1 — $2   ($(date '+%Y-%m-%d %H:%M'))" ""
}

mark_done(){
  local n=$CUR_MOD next
  grep -Fxq "$n" "$PROGRESS" 2>/dev/null || printf '%s\n' "$n" >>"$PROGRESS"
  printf '%s|%s|%s|%s|%s\n' "$n" "$Q_OK" "$Q_TOTAL" "$P_DONE" "$(date '+%F %T')" >>"$SCORES"
  journal "" "**Module $n result:** knowledge checks $Q_OK/$Q_TOTAL · practicals done $P_DONE · skipped $P_SKIP" ""
  next=$((10#$n + 1))
  echo
  boxline "$DTL" "$DH" "$DTR"
  boxtext "MODULE $n COMPLETE  $OK" "$BGRN"
  boxtext "Knowledge checks: $Q_OK/$Q_TOTAL    Practicals done: $P_DONE    Skipped: $P_SKIP"
  boxtext "Journal: ${JOURNAL/#$HOME/\~}" "$DIM"
  ((next <= 16)) && boxtext "Next: $(printf '%02d' "$next")  ${MOD_TITLE[next]}" "$BCYN"
  boxline "$DBL" "$DH" "$DBR"
  echo
  wrap "  $BYEL$I_WARN$RST " '    ' 4 "{b}Competence check:{/} before moving on, explain ONE output from this module out loud to a partner or your instructor. If you cannot, repeat its practical."
  ((P_SKIP > 0)) && warn "You skipped $P_SKIP practical(s). Revisit them: the typing is part of the learning."
  return 0
}

st_record(){ # st_record ID pass|fail|skip "text"
  case $2 in
    pass) ((++ST_PASS)) ;;
    fail) ((++ST_FAIL)); ST_FAILS+=("$1 ${3:-}") ;;
  esac
  return 0
}

# =============================================================================
# PART 3 · THE CYBER-RANGE
# =============================================================================
#   LAN A 10.77.1.0/24 + fd77:1::/64         LAN B 10.77.2.0/24 + fd77:2::/64
#   c1-student .10 ─┐
#                   ├─ c1-switch (br0) ── c1-router eth0 .1 | eth1 .1 ── c1-server .20
#   c1-peer    .11 ─┘
NS_STU=c1-student; NS_PEER=c1-peer; NS_SW=c1-switch; NS_RTR=c1-router; NS_SRV=c1-server
LAB_NS=("$NS_STU" "$NS_PEER" "$NS_SW" "$NS_RTR" "$NS_SRV")
LEGACY_NS=(c1dc_net_student c1dc_net_router c1dc_net_server)   # v1 of this course
STU_IP=10.77.1.10; PEER_IP=10.77.1.11; RTR_A=10.77.1.1; RTR_B=10.77.2.1; SRV_IP=10.77.2.20
STU_MAC=02:c1:dc:01:00:10; PEER_MAC=02:c1:dc:01:00:11; RTR_A_MAC=02:c1:dc:01:00:01
RTR_B_MAC=02:c1:dc:02:00:01; SRV_MAC=02:c1:dc:02:00:20
TICKET_FILE="$STATE_DIR/active_ticket"

if ((EUID == 0)) && ! command -v sudo >/dev/null 2>&1; then
  sudo(){ while [[ ${1:-} == -* ]]; do shift; done; (($#)) && "$@"; }
fi

ns_exists(){ ip netns list 2>/dev/null | grep -Eq "^$1( |\$)"; }
lab_ready(){ local n; for n in "${LAB_NS[@]}"; do ns_exists "$n" || return 1; done; return 0; }
lab_partial(){ local n; for n in "${LAB_NS[@]}" "${LEGACY_NS[@]}"; do ns_exists "$n" && return 0; done; return 1; }

sudo_ready(){
  ((EUID == 0)) && return 0
  command -v sudo >/dev/null 2>&1 || { bad "sudo is not installed; the cyber-range needs it."; return 1; }
  sudo -n true 2>/dev/null && return 0
  if ((NONINTERACTIVE)); then bad "sudo needs a password. For --self-test run 'sudo -v' first (or use passwordless sudo)."; return 1; fi
  info "sudo is used only for the isolated lab (namespaces and captures). The password prompt comes from sudo itself; this script never sees it."
  sudo -v
}

lab_ensure(){
  if lab_ready; then sudo_ready; return; fi
  if ((NONINTERACTIVE)); then lab_build quiet; return; fi
  warn "This exercise needs the isolated cyber-range, and it is not built yet."
  local a; read -r -p "  Build it now (takes ~5 seconds)? [Y/n] $PROMPT " a || a=n
  [[ ${a,,} == n* ]] && return 1
  lab_build
}

# ---------------------------------------------------------------- lab tools --
write_tools(){
  cat >"$TOOLS/c1dc_web.py" <<'PY'
#!/usr/bin/env python3
"""C1DC lab web server: a deliberately tiny HTTP/HTTPS server.

Read this file: every part maps to a networking idea from the course.
  * bind address + port   -> a TCP socket in state LISTEN   (module 06)
  * each client           -> a new ESTABLISHED connection   (module 06)
  * --cert / --key        -> the socket is wrapped in TLS   (module 11)
  * server_version        -> the banner Nmap -sV reads      (module 13)
"""
import argparse, datetime, http.server, os, ssl


class Handler(http.server.SimpleHTTPRequestHandler):
    server_version = "C1DC-Lab/1.0"   # sent in the "Server:" response header
    sys_version = ""                  # hide the Python version: banners leak info

    def do_POST(self):                # e.g. a login form being submitted
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        msg = b"Login received. Was it sent over HTTP or HTTPS?\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(msg)))
        self.end_headers()
        self.wfile.write(msg)

    def log_message(self, fmt, *args):  # one log line per request
        headers = getattr(self, "headers", None)
        ua = headers.get("User-Agent", "-") if headers else "-"
        print(f"{datetime.datetime.now():%H:%M:%S} {self.client_address[0]} "
              f"{fmt % args} UA={ua}", flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bind", default="0.0.0.0")
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--root", default=".")
    p.add_argument("--cert")
    p.add_argument("--key")
    a = p.parse_args()
    os.chdir(a.root)
    srv = http.server.ThreadingHTTPServer((a.bind, a.port), Handler)
    if a.cert:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(a.cert, a.key)
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    print(f"listening on {a.bind}:{a.port} ({'HTTPS' if a.cert else 'HTTP'})", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
PY
  cat >"$TOOLS/c1dc_udp.py" <<'PY'
#!/usr/bin/env python3
"""C1DC UDP listener: prints every datagram it receives and NEVER replies.

UDP has no handshake and no acknowledgement. Data simply arrives (or not).
Because this listener stays silent, an Nmap UDP scan can only say
"open|filtered" for it: silence is ambiguous. (Module 13.)
"""
import argparse, datetime, socket

p = argparse.ArgumentParser()
p.add_argument("--bind", default="0.0.0.0")
p.add_argument("--port", type=int, default=5300)
a = p.parse_args()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind((a.bind, a.port))
print(f"waiting for UDP datagrams on {a.bind}:{a.port}", flush=True)
while True:
    data, addr = s.recvfrom(65535)
    print(f"{datetime.datetime.now():%H:%M:%S} from {addr[0]}:{addr[1]} "
          f"{len(data)} bytes: {data[:80]!r}", flush=True)
PY
  # ---- labctl: a mini "systemctl" for the lab services -----------------------
  {
    printf '#!/usr/bin/env bash\n'
    printf '# labctl — tiny service manager for the C1DC cyber-range (think: a mini systemctl).\n'
    printf '# Usage (as root):  labctl {start|stop|restart|status} {web|tls|dns|udp|dhcp|all}\n'
    printf '# Settings: %s   (edit, then: labctl restart <service>)\n' "$LABDIR/services.conf"
    printf 'CONF=%q; RUN=%q; LOGS=%q; TOOLS=%q; WWW=%q; PKI=%q; RUN_AS=%q\n' \
      "$LABDIR/services.conf" "$RUNDIR" "$LOGS" "$TOOLS" "$WWW" "$PKI" "$RUN_AS"
    cat <<'LABCTL'
[ "$(id -u)" -eq 0 ] || { echo "labctl: run me as root (sudo)" >&2; exit 1; }
[ -r "$CONF" ] && . "$CONF"
WEB_BIND=${WEB_BIND:-10.77.2.20}; WEB_PORT=${WEB_PORT:-8000}
TLS_BIND=${TLS_BIND:-10.77.2.20}; TLS_PORT=${TLS_PORT:-8443}
TLS_CERT=${TLS_CERT:-$PKI/server.crt}; TLS_KEY=${TLS_KEY:-$PKI/server.key}
ALL="web tls dns udp dhcp"
ns_of(){ if [ "$1" = dhcp ]; then echo c1-router; else echo c1-server; fi; }
port_of(){ case $1 in web) echo "t $WEB_PORT";; tls) echo "t $TLS_PORT";; dns) echo "u 53";; udp) echo "u 5300";; dhcp) echo "u 67";; esac; }
drop(){ # run the Python services as the student user, not root (least privilege)
  if [ "$RUN_AS" != root ] && id "$RUN_AS" >/dev/null 2>&1; then
    echo "setpriv --reuid=$(id -u "$RUN_AS") --regid=$(id -g "$RUN_AS") --init-groups"
  fi
}
cmd_of(){
  case $1 in
    web)  echo "$(drop) python3 $TOOLS/c1dc_web.py --bind $WEB_BIND --port $WEB_PORT --root $WWW" ;;
    tls)  echo "$(drop) python3 $TOOLS/c1dc_web.py --bind $TLS_BIND --port $TLS_PORT --root $WWW --cert $TLS_CERT --key $TLS_KEY" ;;
    udp)  echo "$(drop) python3 $TOOLS/c1dc_udp.py --bind 10.77.2.20 --port 5300" ;;
    dns)  echo "dnsmasq --no-daemon --conf-file=/dev/null --no-resolv --no-hosts --listen-address=10.77.2.20 --bind-interfaces --log-queries --log-facility=- --domain=c1dc.lab --local=/c1dc.lab/ --host-record=server.c1dc.lab,10.77.2.20,fd77:2::20 --host-record=intranet.c1dc.lab,10.77.2.20 --host-record=router.c1dc.lab,10.77.2.1 --host-record=mail.c1dc.lab,10.77.2.25 --cname=www.c1dc.lab,intranet.c1dc.lab --mx-host=c1dc.lab,mail.c1dc.lab,10 --txt-record=c1dc.lab,\"v=spf1 mx -all\"" ;;
    dhcp) echo "dnsmasq --no-daemon --conf-file=/dev/null --no-resolv --no-hosts --port=0 --interface=eth0 --bind-interfaces --dhcp-range=10.77.1.100,10.77.1.150,255.255.255.0,10m --dhcp-option=option:router,10.77.1.1 --dhcp-option=option:dns-server,10.77.2.20 --dhcp-option=option:domain-name,c1dc.lab --dhcp-leasefile=$RUN/dhcp.leases --no-ping --log-dhcp --log-facility=-" ;;
  esac
}
running(){ [ -f "$RUN/$1.pid" ] && kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }
listening(){ set -- $(port_of "$1") "$(ns_of "$1")"; ip netns exec "$3" ss -Hln"$1" "sport = :$2" 2>/dev/null | grep -q .; }
start(){
  s=$1; ns=$(ns_of "$s")
  running "$s" && { echo "  $s: already running"; return 0; }
  ip netns list | grep -q "^$ns" || { echo "  $s: namespace $ns does not exist (build the lab)"; return 1; }
  case $s in dns|dhcp) command -v dnsmasq >/dev/null || { echo "  $s: dnsmasq not installed (sudo apt install dnsmasq-base)"; return 1; };; esac
  if [ "$s" = tls ] && [ ! -r "$TLS_CERT" ]; then echo "  tls: certificate $TLS_CERT missing"; return 1; fi
  setsid -f ip netns exec "$ns" bash -c "echo \$\$ > '$RUN/$s.pid'; exec $(cmd_of "$s") >>'$LOGS/svc-$s.log' 2>&1 </dev/null"
  for _ in $(seq 1 30); do listening "$s" && { echo "  $s: started in $ns"; return 0; }; sleep 0.2; done
  echo "  $s: did NOT start. Read $LOGS/svc-$s.log"; return 1
}
stop(){
  if running "$1"; then kill "$(cat "$RUN/$1.pid")" 2>/dev/null; sleep 0.3; echo "  $1: stopped"; fi
  rm -f "$RUN/$1.pid"
}
status(){
  printf '  %-5s %-11s %-8s %s\n' SVC NAMESPACE STATE "LISTENING SOCKET"
  for s in $ALL; do
    st=stopped; running "$s" && st=running
    set -- $(port_of "$s")
    sock=$(ip netns exec "$(ns_of "$s")" ss -Hln"$1" "sport = :$2" 2>/dev/null | awk 'NR==1{print $4" ("$1")"}')
    printf '  %-5s %-11s %-8s %s\n' "$s" "$(ns_of "$s")" "$st" "${sock:--}"
  done
}
action=${1:-status}; shift || true
targets=${*:-all}; [ "$targets" = all ] && targets="web tls dns udp"
case $action in
  start)   for s in $targets; do start "$s"; done ;;
  stop)    [ "${*:-all}" = all ] && targets=$ALL; for s in $targets; do stop "$s"; done ;;
  restart) for s in $targets; do stop "$s"; start "$s"; done ;;
  status)  status ;;
  *) echo "usage: labctl {start|stop|restart|status} {web|tls|dns|udp|dhcp|all}"; exit 2 ;;
esac
LABCTL
  } >"$TOOLS/labctl"
  chmod 755 "$TOOLS/labctl" "$TOOLS/c1dc_web.py" "$TOOLS/c1dc_udp.py"

  [[ -f $LABDIR/services.conf ]] || cat >"$LABDIR/services.conf" <<EOF
# C1DC cyber-range service settings (read by labctl).
# After editing:  sudo $TOOLS/labctl restart web
WEB_BIND=10.77.2.20
WEB_PORT=8000
TLS_BIND=10.77.2.20
TLS_PORT=8443
TLS_CERT=$PKI/server.crt
TLS_KEY=$PKI/server.key
EOF
  cat >"$WWW/index.html" <<'EOF'
<!doctype html>
<html><head><title>C1DC Intranet</title></head>
<body>
<h1>C1DC Intranet</h1>
<p>If you can read this, all seven layers worked: a cable (L1), a frame (L2),
a routed packet (L3), a TCP connection (L4) and an HTTP response (L7).</p>
</body></html>
EOF
  printf 'Quarterly plans: nothing to see here. (Lab file)\n' >"$WWW/notes.txt"
}

ensure_pki(){
  [[ -s $PKI/server.crt && -s $PKI/server.key ]] && return 0
  command -v openssl >/dev/null 2>&1 || return 0
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$PKI/server.key" -out "$PKI/server.crt" -days 365 \
    -subj "/CN=server.c1dc.lab/O=C1DC Lab" -addext "subjectAltName=DNS:server.c1dc.lab,IP:10.77.2.20" >/dev/null 2>&1
  chmod 600 "$PKI/server.key" 2>/dev/null
  return 0
}

gen_build_script(){
  local hosts_extra=''
  command -v dnsmasq >/dev/null 2>&1 || hosts_extra='"10.77.2.20 server.c1dc.lab intranet.c1dc.lab" "10.77.2.1 router.c1dc.lab"'
  cat >"$LABDIR/build-lab.sh" <<EOF
#!/usr/bin/env bash
# =============================================================================
#  C1DC CYBER-RANGE BUILD SCRIPT  (generated by the academy; runs as root)
#  Read it slowly: every line is a real Linux networking command. Together they
#  build a five-host network INSIDE your Kali machine, isolated from your LAN.
#
#    c1-student 10.77.1.10 ─┐
#                           ├── c1-switch (br0) ── c1-router ── c1-server
#    c1-peer    10.77.1.11 ─┘                  .1.1 | .2.1     10.77.2.20
# =============================================================================
set -e
trap 'echo "  [FAILED] line \$LINENO: \$BASH_COMMAND" >&2' ERR
step(){ printf '  [+] %s\n' "\$*"; }

step "1/8  Create five empty network stacks (network namespaces)"
for ns in c1-student c1-peer c1-switch c1-router c1-server; do
  ip netns add "\$ns"
  # quieter IPv6: no router solicitations / duplicate-address probes on new links
  ip netns exec "\$ns" sysctl -qw net.ipv6.conf.default.router_solicitations=0 net.ipv6.conf.default.accept_dad=0
done
# a switch is a layer-2 device: it needs no IP at all
ip netns exec c1-switch sysctl -qw net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1

step "2/8  Plug in virtual cables (veth pairs: what enters one end leaves the other)"
ip link add eth0 netns c1-student address $STU_MAC  type veth peer name sw-student netns c1-switch
ip link add eth0 netns c1-peer    address $PEER_MAC type veth peer name sw-peer    netns c1-switch
ip link add eth0 netns c1-router  address $RTR_A_MAC type veth peer name sw-router  netns c1-switch
ip link add eth1 netns c1-router  address $RTR_B_MAC type veth peer name eth0 netns c1-server address $SRV_MAC

step "3/8  Build the switch: a Linux bridge (br0) with three ports"
ip -n c1-switch link add br0 type bridge
for port in sw-student sw-peer sw-router; do
  ip -n c1-switch link set "\$port" master br0
  ip -n c1-switch link set "\$port" up
done
ip -n c1-switch link set br0 up

step "4/8  Assign IPv4 and IPv6 addresses (address/prefix)"
ip -n c1-student addr add 10.77.1.10/24 dev eth0
ip -n c1-student addr add fd77:1::10/64 dev eth0 nodad
ip -n c1-peer    addr add 10.77.1.11/24 dev eth0
ip -n c1-peer    addr add fd77:1::11/64 dev eth0 nodad
ip -n c1-router  addr add 10.77.1.1/24  dev eth0
ip -n c1-router  addr add fd77:1::1/64  dev eth0 nodad
ip -n c1-router  addr add 10.77.2.1/24  dev eth1
ip -n c1-router  addr add fd77:2::1/64  dev eth1 nodad
ip -n c1-server  addr add 10.77.2.20/24 dev eth0
ip -n c1-server  addr add fd77:2::20/64 dev eth0 nodad

step "5/8  Switch interfaces on (administratively UP), including loopback"
for ns in c1-student c1-peer c1-switch c1-router c1-server; do ip -n "\$ns" link set lo up; done
ip -n c1-student link set eth0 up
ip -n c1-peer    link set eth0 up
ip -n c1-router  link set eth0 up
ip -n c1-router  link set eth1 up
ip -n c1-server  link set eth0 up

step "6/8  Default gateways: 'anything not on my LAN goes to the router'"
ip -n c1-student route add default via 10.77.1.1
ip -n c1-peer    route add default via 10.77.1.1
ip -n c1-server  route add default via 10.77.2.1
ip -n c1-student -6 route add default via fd77:1::1
ip -n c1-peer    -6 route add default via fd77:1::1
ip -n c1-server  -6 route add default via fd77:2::1

step "7/8  Turn c1-router into a router: enable packet forwarding"
ip netns exec c1-router sysctl -qw net.ipv4.ip_forward=1
ip netns exec c1-router sysctl -qw net.ipv6.conf.all.forwarding=1

step "8/8  Lab name files: /etc/netns/<ns>/hosts and resolv.conf (used by 'ip netns exec')"
for ns in c1-student c1-peer c1-router c1-server; do
  mkdir -p "/etc/netns/\$ns"
  printf '%s\n' "127.0.0.1 localhost" "::1 localhost" "10.77.1.10 student.c1dc.lab" "10.77.1.11 peer.c1dc.lab" $hosts_extra > "/etc/netns/\$ns/hosts"
  printf 'nameserver 10.77.2.20\nsearch c1dc.lab\noptions timeout:2 attempts:1\n' > "/etc/netns/\$ns/resolv.conf"
done
echo "  Done. Nothing on your real interfaces, routes or firewall was touched."
EOF
  chmod 755 "$LABDIR/build-lab.sh"
}

lab_build(){ # lab_build [quiet]
  local quiet=${1:-} rc
  command -v ip >/dev/null 2>&1 || { bad "The 'ip' command (iproute2) is missing."; return 1; }
  sudo_ready || return 1
  lab_partial && lab_destroy quiet
  write_tools; ensure_pki; gen_build_script
  if [[ -z $quiet ]]; then
    printf '\n  %sBuilding the cyber-range%s %s(script: %s)%s\n' "$BOLD" "$RST" "$DIM" "${LABDIR/#$HOME/\~}/build-lab.sh" "$RST"
    sudo bash "$LABDIR/build-lab.sh" 2>"$LOGS/build.err" | sed "s/^/  /"; rc=${PIPESTATUS[0]}
  else
    sudo bash "$LABDIR/build-lab.sh" >/dev/null 2>"$LOGS/build.err"; rc=$?
  fi
  if ((rc != 0)); then
    bad "The build failed. Details:"; sed 's/^/    /' "$LOGS/build.err"
    warn "Common causes: a VM/container without network-namespace support, or missing sudo rights. Rolling back."
    lab_destroy quiet; return 1
  fi
  if [[ -z $quiet ]]; then
    printf '\n  %sStarting lab services%s (labctl is a mini systemctl: %s)\n' "$BOLD" "$RST" "${TOOLS/#$HOME/\~}/labctl"
    sudo "$TOOLS/labctl" start all
  else sudo "$TOOLS/labctl" start all >/dev/null 2>&1; fi
  [[ -z $quiet ]] && { echo; good "Cyber-range is up. Menu M shows the map; menu S opens a shell on any lab host."; }
  return 0
}

lab_destroy(){ # lab_destroy [quiet]
  local quiet=${1:-} n
  sudo_ready || return 1
  for n in "${LAB_NS[@]}" "${LEGACY_NS[@]}"; do
    ns_exists "$n" || continue
    priv "for p in \$(ip netns pids $n); do kill \$p; done; sleep 0.3; for p in \$(ip netns pids $n); do kill -9 \$p; done; ip netns del $n" 2>/dev/null
    [[ -z $quiet ]] && good "removed namespace $n (and every virtual cable plugged into it)"
  done
  sudo rm -rf /etc/netns/c1-student /etc/netns/c1-peer /etc/netns/c1-switch /etc/netns/c1-router /etc/netns/c1-server 2>/dev/null
  rm -f "$RUNDIR"/*.pid "$TICKET_FILE" 2>/dev/null
  return 0
}

lab_reset(){ lab_destroy quiet && lab_build quiet; }

section_like(){ echo; boxline "$TL" "$H" "$TR"; boxtext "$1" "$BOLD" "$V"; boxline "$BL" "$H" "$BR"; echo; }

cleanup_lab(){
  section_like "REMOVE THE CYBER-RANGE"
  if ! lab_partial; then info "No C1DC namespaces exist. Nothing to remove."; return 0; fi
  if ((NONINTERACTIVE == 0)); then
    local c; read -r -p "  Delete ONLY the C1DC lab namespaces and services? Type CLEANUP $PROMPT " c || c=''
    [[ $c == CLEANUP ]] || { warn "Cancelled."; return 0; }
  fi
  lab_destroy && good "Done. Your real network configuration was never touched. Evidence files stay in ${WORK/#$HOME/\~}."
}

# --------------------------------------------------------------- lab map ----
lab_map(){
  section_like "CYBER-RANGE MAP & STATUS"
  figure "The lab topology (all of it lives inside your Kali machine)" <<'EOF'
 LAN A  10.77.1.0/24  fd77:1::/64           LAN B  10.77.2.0/24  fd77:2::/64

 [c1-student] .10 ──┐
  "your PC"         │  [c1-switch]       [c1-router]          [c1-server]
                    ├── br0 (L2) ───── eth0 .1 │ eth1 .1 ────── eth0 .20
 [c1-peer]    .11 ──┘  learns MACs     forwards + filters    web :8000  tls :8443
  "colleague PC"       no IP needed    (sysctl + nftables)   dns :53    udp :5300
EOF
  local n st h r i m g
  printf '    %s%-11s %-17s %-15s %-18s %s%s\n' "$BOLD" HOST ROLE IPv4 MAC GATEWAY "$RST"
  for n in "$NS_STU|your workstation|10.77.1.10/24|$STU_MAC|10.77.1.1" \
           "$NS_PEER|colleague PC|10.77.1.11/24|$PEER_MAC|10.77.1.1" \
           "$NS_SW|layer-2 switch|(none)|ports sw-*|-" \
           "$NS_RTR|router+firewall|10.77.1.1/24|$RTR_A_MAC|-" \
           "|  (second NIC)|10.77.2.1/24|$RTR_B_MAC|" \
           "$NS_SRV|intranet server|10.77.2.20/24|$SRV_MAC|10.77.2.1"; do
    IFS='|' read -r h r i m g <<<"$n"
    if [[ -n $h ]]; then if ns_exists "$h"; then st="$BGRN$DOT$RST"; else st="$BRED$ODOT$RST"; fi; else st=' '; fi
    printf '  %s %-11s %-17s %-15s %-18s %s\n' "$st" "$h" "$r" "$i" "$m" "$g"
  done
  echo
  info "IPv6: student fd77:1::10 · peer fd77:1::11 · router fd77:1::1 and fd77:2::1 · server fd77:2::20"
  info "Every MAC starts with 02 (the 'locally administered' bit), so you can recognise each host in a capture."
  if lab_ready; then
    echo; printf '  %sServices%s (from: sudo %s status)\n' "$BOLD" "$RST" "${TOOLS/#$HOME/\~}/labctl"
    sudo_ready && sudo "$TOOLS/labctl" status 2>/dev/null
    [[ -f $TICKET_FILE ]] && { echo; warn "Troubleshooting ticket #$(cat "$TICKET_FILE") is ACTIVE: the lab is deliberately broken. Menu T to continue it, or L to rebuild."; }
  else
    echo; warn "The cyber-range is not running. Build it with menu L (or: bash $(basename "$0") --lab)."
  fi
  echo
  callout tip "Enter any host yourself:  {c}sudo ip netns exec c1-student bash{/}  then try {c}ip -br addr{/}, {c}ip route{/}, {c}ping 10.77.2.20{/}. For 'ip' commands there is a shortcut: {c}sudo ip -n c1-student route{/}."
}

# ---------------------------------------------------------- lab shells -----
lab_shell(){
  local ns=${1:-} c
  lab_ensure || return 0
  if [[ -z $ns ]]; then
    section_like "OPEN A ROOT SHELL INSIDE A LAB HOST"
    printf '    1) c1-student   your workstation   10.77.1.10\n    2) c1-peer      colleague PC       10.77.1.11\n'
    printf '    3) c1-switch    the switch         (layer 2 only)\n    4) c1-router    router + firewall  10.77.1.1 / 10.77.2.1\n'
    printf '    5) c1-server    intranet server    10.77.2.20\n\n'
    read -r -p "  Which host? [1-5] $PROMPT " c || return 0
    case $c in 1) ns=$NS_STU ;; 2) ns=$NS_PEER ;; 3) ns=$NS_SW ;; 4) ns=$NS_RTR ;; 5) ns=$NS_SRV ;; *) return 0 ;; esac
  fi
  local rc="$LABDIR/shellrc-$ns"
  cat >"$rc" <<EOF
PS1='\[\e[1;35m\][lab:$ns]\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] # '
export PATH="/usr/local/sbin:/usr/sbin:/sbin:\$PATH:$TOOLS"
cd "$WORK" 2>/dev/null
echo
echo "  You are ROOT inside the network namespace '$ns'."
echo "  Only this host's interfaces, routes and sockets are visible. Your real network is not."
echo "  Try: ip -br addr | ip route | ip neigh | ss -tulpn | ping -c2 10.77.2.20 | tcpdump -i eth0 -nn -c5"
echo "  Lab services: labctl status      Leave with: exit"
echo
EOF
  echo
  sudo ip netns exec "$ns" bash --rcfile "$rc" -i
  good "Back in the academy."
}

analysis_shell(){
  local rc="$LABDIR/shellrc-analysis"
  cat >"$rc" <<EOF
PS1='\[\e[1;33m\][analysis]\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] \$ '
cd "$EVID" 2>/dev/null
echo
echo "  Analysis shell (your normal user, on the host) in: $EVID"
echo "  Tools: tcpdump -nn -r FILE   tshark -r FILE   sha256sum FILE   wireshark FILE &"
echo "  Leave with: exit"
echo
EOF
  bash --rcfile "$rc" -i
  good "Back in the academy."
}

# ---------------------------------------------------- capture helpers ------
cap_bg(){ # cap_bg NS IFACE FILE COUNT FILTER...   (academy-side capture)
  local ns=$1 ifc=$2 f=$3 c=$4; shift 4
  rm -f "$f"
  priv_bg "ip netns exec $ns timeout 15 tcpdump -i $ifc -nn -U -Z root -c $c -w $(printf '%q' "$f") $*"
}
cap_wait(){ # cap_wait FILE...
  local f i
  for f in "$@"; do
    for i in $(seq 1 80); do pgrep -f -- "-w $f" >/dev/null 2>&1 || break; sleep 0.2; done
    [[ -f $f ]] && sudo chown "$RUN_AS:" "$f" 2>/dev/null
  done
  return 0
}

# hex bytes of the Nth packet matching FILTER in a pcap
pcap_hex(){
  local f=$1 filt=$2 n=${3:-1}
  tcpdump -nn -r "$f" -xx -c "$n" "$filt" 2>/dev/null | awk -v want="$n" '
    /^[^ \t]/ {k++; next}
    k == want && /^[ \t]+0x/ {for (i = 2; i <= NF; i++) h = h $i}
    END {print h}'
}
HEX=''
hx(){ printf '%s' "${HEX:$(($1 * 2)):$(($2 * 2))}"; }
hd(){ local s; s=$(hx "$1" "$2"); printf '%d' "$((16#${s:-0}))"; }
hmac(){ local s; s=$(hx "$1" 6); printf '%s:%s:%s:%s:%s:%s' "${s:0:2}" "${s:2:2}" "${s:4:2}" "${s:6:2}" "${s:8:2}" "${s:10:2}"; }
hip(){ local s; s=$(hx "$1" 4); printf '%d.%d.%d.%d' $((16#${s:0:2})) $((16#${s:2:2})) $((16#${s:4:2})) $((16#${s:6:2})); }
who_mac(){
  case $1 in
    "$STU_MAC") echo "= c1-student" ;; "$PEER_MAC") echo "= c1-peer" ;; "$RTR_A_MAC") echo "= c1-router eth0" ;;
    "$RTR_B_MAC") echo "= c1-router eth1" ;; "$SRV_MAC") echo "= c1-server" ;; ff:ff:ff:ff:ff:ff) echo "= BROADCAST (everyone on the LAN)" ;;
    33:33:*) echo "= IPv6 multicast" ;; *) echo "" ;;
  esac
}
who_ip(){
  case $1 in
    "$STU_IP") echo "= c1-student" ;; "$PEER_IP") echo "= c1-peer" ;; "$RTR_A") echo "= c1-router (LAN A)" ;;
    "$RTR_B") echo "= c1-router (LAN B)" ;; "$SRV_IP") echo "= c1-server" ;; *) echo "" ;;
  esac
}
drow(){ # drow BYTES FIELD HEX MEANING
  local hexs=$3
  ((${#hexs} > 8)) && hexs="${hexs:0:7}$ELL"
  wrap "  $GRY$(printf '%-5s' "$1")$RST $BOLD$(printf '%-17s' "$2")$RST $YEL$(printf '%-9s' "$hexs")$RST " \
       "  $(rep ' ' 33)" 34 "$4"
}
dhead(){ printf '\n  %s%s%s\n' "$BCYN" "$1" "$RST"; }

# decode_packet PCAP "BPF FILTER" "title" — byte-by-byte tour of a real packet
decode_packet(){
  local f=$1 filt=$2 title=$3
  HEX=$(pcap_hex "$f" "$filt" 1)
  if ((${#HEX} < 68)); then warn "Could not read a matching packet from $(basename "$f")."; return 1; fi
  printf '\n  %s DISSECTION: %s %s\n' "$BMAG$REV" "$title" "$RST"
  wrap "  $DIM" "  $DIM" 2 "These are the real bytes of YOUR packet, read from $(basename "$f"). Wireshark does exactly this."
  printf '\n  %s%-5s %-17s %-9s %s%s\n' "$DIM" BYTES FIELD HEX MEANING "$RST"
  local dm sm et
  dm=$(hmac 0); sm=$(hmac 6); et=$(hx 12 2)
  dhead "ETHERNET HEADER (layer 2) · 14 bytes · rewritten at every hop"
  drow "0-5" "Destination MAC" "$(hx 0 6)" "$dm $(who_mac "$dm")"
  drow "6-11" "Source MAC" "$(hx 6 6)" "$sm $(who_mac "$sm")"
  case $et in
    0800) drow "12-13" "EtherType" "$et" "0x0800 = an IPv4 packet follows" ;;
    86dd) drow "12-13" "EtherType" "$et" "0x86DD = an IPv6 packet follows"; echo; return 0 ;;
    0806) drow "12-13" "EtherType" "$et" "0x0806 = ARP follows"; echo; return 0 ;;
    8100) drow "12-13" "EtherType" "$et" "0x8100 = an 802.1Q VLAN tag follows"; echo; return 0 ;;
    *) drow "12-13" "EtherType" "$et" "other protocol"; echo; return 0 ;;
  esac
  local vihl ihl proto ffo src dst o pname
  vihl=$(hx 14 1); ihl=$((16#${vihl:1:1} * 4)); proto=$(hd 23 1); ffo=$(hd 20 2)
  src=$(hip 26); dst=$(hip 30)
  case $proto in 1) pname=ICMP ;; 6) pname=TCP ;; 17) pname=UDP ;; *) pname=other ;; esac
  dhead "IPv4 HEADER (layer 3) · $ihl bytes · stays the same end-to-end (unless NAT)"
  drow "14" "Version + IHL" "$vihl" "version ${vihl:0:1} (IPv4); header length ${vihl:1:1} x 4 = $ihl bytes"
  drow "15" "DSCP / ECN" "$(hx 15 1)" "quality-of-service marking (0 = normal)"
  drow "16-17" "Total length" "$(hx 16 2)" "$(hd 16 2) bytes: IP header + everything inside it"
  drow "18-19" "Identification" "$(hx 18 2)" "$(hd 18 2): groups the fragments of one packet"
  if ((ffo & 0x4000)); then drow "20-21" "Flags + fragment" "$(hx 20 2)" "DF=1 'Don't Fragment' (path-MTU discovery, module 12)"
  else drow "20-21" "Flags + fragment" "$(hx 20 2)" "DF=0: routers may fragment it"; fi
  drow "22" "TTL" "$(hx 22 1)" "$(hd 22 1) hops left. Every router subtracts 1; at 0 the packet dies"
  drow "23" "Protocol" "$(hx 23 1)" "$proto = $pname: what the IP packet carries"
  drow "24-25" "Header checksum" "$(hx 24 2)" "error check of this header; recomputed by each router (TTL changed)"
  drow "26-29" "Source IP" "$(hx 26 4)" "$src $(who_ip "$src")"
  drow "30-33" "Destination IP" "$(hx 30 4)" "$dst $(who_ip "$dst")"
  o=$((14 + ihl))
  case $proto in
    1)
      local t tn; t=$(hd "$o" 1)
      case $t in 8) tn="Echo Request (the ping question)" ;; 0) tn="Echo Reply (the ping answer)" ;; 3) tn="Destination Unreachable" ;; 11) tn="Time Exceeded (TTL reached 0)" ;; *) tn=other ;; esac
      dhead "ICMP MESSAGE · starts at byte $o"
      drow "$o" "Type" "$(hx "$o" 1)" "$t = $tn"
      drow "$((o + 1))" "Code" "$(hx $((o + 1)) 1)" "sub-type (0 for echo)"
      drow "$((o + 2))-$((o + 3))" "Checksum" "$(hx $((o + 2)) 2)" "error check of the ICMP message"
      drow "$((o + 4))-$((o + 5))" "Identifier" "$(hx $((o + 4)) 2)" "$(hd $((o + 4)) 2): which ping process sent it"
      drow "$((o + 6))-$((o + 7))" "Sequence" "$(hx $((o + 6)) 2)" "$(hd $((o + 6)) 2): 1st, 2nd, 3rd ping… (icmp_seq in ping's output)"
      drow "$((o + 8))+" "Data" "$(hx $((o + 8)) 8)" "timestamp + filler; the reply echoes it back unchanged"
      ;;
    6)
      local fl doff names=(FIN SYN RST PSH ACK URG ECE CWR) b line=''
      doff=$(( (16#$(hx $((o + 12)) 1) >> 4) * 4 )); fl=$(( 16#$(hx $((o + 12)) 2) & 0x1FF ))
      dhead "TCP HEADER (layer 4) · $doff bytes · starts at byte $o"
      drow "$o-$((o + 1))" "Source port" "$(hx "$o" 2)" "$(hd "$o" 2): random 'ephemeral' port picked by the client"
      drow "$((o + 2))-$((o + 3))" "Destination port" "$(hx $((o + 2)) 2)" "$(hd $((o + 2)) 2): the service being contacted"
      drow "$((o + 4))-$((o + 7))" "Sequence number" "$(hx $((o + 4)) 4)" "$(hd $((o + 4)) 4): random start, then counts bytes sent"
      drow "$((o + 8))-$((o + 11))" "Ack number" "$(hx $((o + 8)) 4)" "$(hd $((o + 8)) 4): next byte expected from the other side"
      drow "$((o + 12))-$((o + 13))" "Hdr length + flags" "$(hx $((o + 12)) 2)" "header is $doff bytes (options included); flags below"
      drow "$((o + 14))-$((o + 15))" "Window" "$(hx $((o + 14)) 2)" "$(hd $((o + 14)) 2) bytes I can accept (flow control)"
      for b in 7 6 5 4 3 2 1 0; do
        if (((fl >> b) & 1)); then line+="$BGRN${names[b]}=1$RST "; else line+="$GRY${names[b]}=0$RST "; fi
      done
      printf '\n  %s%-23s%s %s\n' "$BOLD" "TCP flag bits" "$RST" "$line"
      ;;
    17)
      dhead "UDP HEADER (layer 4) · just 8 bytes: no handshake, no sequence numbers"
      drow "$o-$((o + 1))" "Source port" "$(hx "$o" 2)" "$(hd "$o" 2)"
      drow "$((o + 2))-$((o + 3))" "Destination port" "$(hx $((o + 2)) 2)" "$(hd $((o + 2)) 2)"
      drow "$((o + 4))-$((o + 5))" "Length" "$(hx $((o + 4)) 2)" "$(hd $((o + 4)) 2) bytes (8-byte header + data)"
      drow "$((o + 6))-$((o + 7))" "Checksum" "$(hx $((o + 6)) 2)" "error check"
      ;;
  esac
  echo
}

# =============================================================================
# PART 4 · THE MODULES
# =============================================================================
MOD_TITLE=("" "Networks, hardware and the data path" "OSI and TCP/IP: layers and encapsulation"
  "Addressing, binary and subnetting" "ARP: how an IP address finds a MAC address"
  "DHCP and DNS: getting online, finding names" "TCP, UDP, ICMP and ports"
  "Packet analysis with tcpdump and Wireshark" "Routing, TTL and NAT"
  "Switching, VLANs and segmentation" "Firewalls with nftables" "HTTP, TLS and certificates"
  "IPv6, Neighbor Discovery and MTU" "Authorized reconnaissance with Nmap"
  "Network forensics and threat hunting" "Troubleshooting like an engineer" "Final practical examination")
MOD_MIN=(0 20 30 50 30 40 50 45 50 35 45 45 40 40 45 40 60)
MOD_TRACK=("" FOUNDATIONS FOUNDATIONS FOUNDATIONS FOUNDATIONS "CORE PROTOCOLS" "CORE PROTOCOLS" "CORE PROTOCOLS"
  INFRASTRUCTURE INFRASTRUCTURE INFRASTRUCTURE "APPLIED & ADVANCED" "APPLIED & ADVANCED" "APPLIED & ADVANCED"
  "APPLIED & ADVANCED" OPERATIONS OPERATIONS)
MOD_LAB=(0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0)

# ----------------------------------------------------------------- 01 -------
module01(){
  module_open 01 "${MOD_TITLE[1]}" "${MOD_MIN[1]}" "${MOD_TRACK[1]}"
  objectives "Explain what a network, a LAN, a WAN and the Internet are" \
    "Say what a NIC, switch, access point, router, firewall and modem each do" \
    "List your own interfaces with {c}ip{/} and tell which one carries your traffic" \
    "Read interface counters (RX/TX, errors, drops) like an engineer"

  section "The big idea"
  say "A {b}network{/} is two or more devices that agree on rules, called {b}protocols{/}, for moving data between them. Your laptop, a printer and a web server on another continent all follow the same published rules. That is the only reason they can talk at all." \
      "Everything in this course answers three questions. {y}WHO{/} is talking? (addresses: MAC, IP, port). {y}HOW{/} does the data get there? (switching and routing). {y}WHAT{/} is being said? (protocols such as DNS, HTTP and TLS). When something breaks, or when an attacker hides, the answer is always in one of those three."
  callout analogy "Think of the postal system. The street address on an envelope is the {b}IP address{/}; the flat number is the {b}port{/}; the local postman who knows every door on the street is the {b}switch{/}; the sorting office that decides which city the letter goes to next is the {b}router{/}. A letter inside an envelope inside a parcel is {b}encapsulation{/} (module 02)."

  section "From your desk to the Internet"
  figure "A typical small office or home network" <<'EOF'
 [Laptop] ))) Wi-Fi ((( [Access Point]
                              │
 [Desktop] ── cable ── [  Switch  ] ── [Router+Firewall] ── [Modem] ══ ISP ══► Internet
                              │          NAT, DHCP, DNS
                         [Printer]

 LAN = everything on your side of the router (Local Area Network)
 WAN = the link to the ISP and beyond (Wide Area Network)
EOF
  terms "LAN :: Local Area Network: devices in one building or site that reach each other directly through switches." \
        "WLAN :: Wireless LAN (Wi-Fi). Same idea, but the 'cable' is radio, which anyone nearby can receive." \
        "WAN :: Wide Area Network: links between sites or to an ISP, usually rented from a provider." \
        "Internet :: The network of networks: tens of thousands of independently run networks (ISPs, clouds, universities) exchanging traffic." \
        "Intranet :: A private network for one organisation, like the C1DC intranet server in our lab."
  pageturn

  section "The devices and their jobs"
  terms "NIC :: Network Interface Card. Turns data into signals (electricity, light, radio) and back. Every NIC has a MAC address." \
        "Hub (L1) :: Repeats every bit out of every port. Obsolete: everyone hears everything." \
        "Switch (L2) :: Learns which MAC address lives behind which port, then sends each frame only where it needs to go (module 09)." \
        "Access point (L2) :: Bridges Wi-Fi clients into the wired LAN. A home 'Wi-Fi router' is an AP + switch + router + firewall + DHCP server in one box." \
        "Router (L3) :: Moves packets BETWEEN different IP networks using a routing table (module 08)." \
        "Firewall (L3-L7) :: Allows or blocks traffic according to a policy (module 10)." \
        "Modem / ONT (L1) :: Converts your traffic to the ISP's medium: DSL, coaxial cable or fibre."
  callout security "Every device is also an attack surface. Switches can be flooded with fake MAC addresses, access points can be impersonated ('evil twin'), routers can be misconfigured to forward what they should not. The defenders who know what {i}normal{/} looks like are the ones who notice {i}abnormal{/}."

  section "Cables, light and radio: the physical layer"
  terms "Copper (Cat5e/6) :: Twisted-pair Ethernet, up to 100 m per run, 1 to 10 Gbit/s. Cheap and everywhere." \
        "Fibre :: Pulses of light in glass. Kilometres of reach, immune to electrical interference, hard to tap unnoticed." \
        "Radio (Wi-Fi) :: A shared medium: clients take turns on a channel, and anyone in range can capture the frames (WPA2/WPA3 encryption protects the content)."
  say "Four words describe the quality of any link. You will use them in every troubleshooting call:"
  terms "Bandwidth :: The capacity of the link (the number of lanes on a motorway), e.g. 1 Gbit/s." \
        "Throughput :: What you actually get right now (the cars really passing per minute)." \
        "Latency :: The time one packet takes to travel (the journey time). {c}ping{/} measures the round trip." \
        "Jitter / loss :: Variation in latency, and packets that never arrive. Both ruin voice and video calls."
  pageturn

  section "Your interfaces: what Linux sees"
  say "Linux gives every network interface a name. Reading the names tells you a lot about a machine before you run a single scan:"
  terms "lo :: Loopback: a virtual interface that only talks to this same machine (127.0.0.1)." \
        "eth0, enp0s3 :: Wired Ethernet. 'enp0s3' is a predictable name: en = Ethernet, p0 = PCI bus 0, s3 = slot 3." \
        "wlan0, wlp2s0 :: Wireless (Wi-Fi)." \
        "docker0, br-… :: Software bridges created by Docker or virtualisation." \
        "tun0, wg0 :: VPN tunnels: traffic is wrapped and encrypted before it leaves." \
        "veth… :: Virtual Ethernet cables, like the ones our cyber-range uses."
  practical title="List your network interfaces" \
    goal="See every interface on THIS Kali machine, its state and its hardware (MAC) address." \
    cmd="ip -br link" \
    anatomy="ip :: the modern Linux networking tool (package iproute2); replaces the old ifconfig
-br :: 'brief': one tidy line per interface
link :: the object to show: layer-2 interfaces (not IP addresses)" \
    predict="How many interfaces will you see, and which one do you think carries your Internet traffic?" \
    read="column 1 :: the interface name (lo, eth0, wlan0…)
column 2 :: state: UP, DOWN, or UNKNOWN (normal for lo and VPN tunnels)
column 3 :: the MAC address (layer-2 hardware address); lo shows all zeros
<…> flags :: UP = switched on by an admin; LOWER_UP = a cable or radio link is detected; NO-CARRIER = switched on but nothing connected" \
    explain="The kernel keeps a list of every interface. UP is a software switch that an administrator controls (ip link set eth0 up). LOWER_UP is a physical fact: the NIC detects a signal. An interface can be UP without LOWER_UP, which is the classic unplugged cable." \
    needs=ip
  practical title="Read the traffic counters of an interface" \
    goal="Every interface counts what it sends and receives. Errors and drops are early warnings of physical problems." \
    cmd="ip -s link show lo" \
    anatomy="-s :: statistics: add the RX/TX counters
show lo :: only the loopback interface (present on every machine, so everyone sees the same thing)" \
    read="RX :: received: bytes, packets, errors, dropped, missed, mcast (multicast)
TX :: transmitted: bytes, packets, errors, dropped, carrier, collisions
errors :: frames that arrived damaged: bad cable, interference, duplex mismatch
dropped :: frames thrown away, often because a buffer was full or the protocol is not handled" \
    explain="These counters start at zero when the machine boots and only go up. One number means little; a number that keeps RISING while a problem is happening is evidence. Loopback never shows physical errors because no cable exists: it is pure software." \
    needs=ip
  callout turn "In a second terminal run {c}ip -s link show{/} followed by YOUR main interface name (for example wlan0 or eth0). Open a website, run it again, and watch the RX bytes grow. Are errors and dropped still 0?"
  practical title="Interfaces are files too" \
    goal="Linux exposes every interface under /sys/class/net. Tools like ip read from the kernel; you can peek directly." \
    cmd="ls /sys/class/net" \
    anatomy="ls :: list a directory
/sys/class/net :: a virtual directory the kernel fills with one entry per network interface" \
    read="each name :: one interface; compare the list with the output of ip -br link" \
    explain="Try cat /sys/class/net/lo/mtu yourself: the kernel answers 65536. This 'everything is a file' design is why so many Linux security tools can inspect a system with simple reads."

  reflect "Your home 'Wi-Fi router' is really several devices in one box. Name at least three of them and what each one does." \
    "An access point (Wi-Fi to wired), a switch (the LAN ports), a router (moves packets between your LAN and the ISP), a firewall with NAT (blocks unsolicited inbound traffic, shares one public IP), and usually a DHCP server (hands out addresses) and a DNS forwarder."
  quiz "A laptop on network 192.168.1.0/24 must reach a server on 10.0.0.0/24. Which device decides where the packet goes next?" C \
    "Moving packets BETWEEN IP networks is the router's job (layer 3). A switch only forwards frames inside one LAN." \
    "The switch" "The access point" "The router" "The NIC"
  quiz "An interface shows UP but not LOWER_UP. What is the most likely cause?" B \
    "UP is the administrative switch; LOWER_UP is the physical link. UP without LOWER_UP usually means no cable, a dead port, or no Wi-Fi association." \
    "The IP address is wrong" "No physical link: cable unplugged or Wi-Fi not associated" "DNS is broken" "The firewall blocks it"
  takeaways "A network is devices following shared protocols; problems and attacks always involve WHO, HOW or WHAT." \
    "Switches work with MAC addresses inside a LAN; routers work with IP addresses between networks." \
    "{c}ip -br link{/} lists interfaces. UP is a setting, LOWER_UP is a physical fact." \
    "Rising error counters point to physical problems before anything else."
  mark_done
}

# ----------------------------------------------------------------- 02 -------
encap_demo(){
  local d=0.7; ((NONINTERACTIVE)) && d=0
  printf '  %sWatch a web request being wrapped on its way OUT of your PC:%s\n\n' "$BOLD" "$RST"
  printf '   %sL7%s  %s[ GET /index.html HTTP/1.1  Host: intranet ]%s              %s<- data%s\n' "$BOLD" "$RST" "$GRN" "$RST" "$DIM" "$RST"; sleep $d
  printf '   %sL4%s  %s[TCP 51514->8000 SEQ ACK]%s%s[ GET /index.html … ]%s         %s<- segment%s\n' "$BOLD" "$RST" "$YEL" "$RST" "$GRN" "$RST" "$DIM" "$RST"; sleep $d
  printf '   %sL3%s  %s[IP .1.10->.2.20 TTL 64]%s%s[TCP]%s%s[ GET … ]%s               %s<- packet%s\n' "$BOLD" "$RST" "$MAG" "$RST" "$YEL" "$RST" "$GRN" "$RST" "$DIM" "$RST"; sleep $d
  printf '   %sL2%s  %s[ETH :10->:01 0800]%s%s[IP]%s%s[TCP]%s%s[ GET … ]%s%s[FCS]%s        %s<- frame%s\n' "$BOLD" "$RST" "$CYN" "$RST" "$MAG" "$RST" "$YEL" "$RST" "$GRN" "$RST" "$CYN" "$RST" "$DIM" "$RST"; sleep $d
  printf '   %sL1%s  %s0110100101110010 1001010110100110 0111010010101 …%s    %s<- bits on the wire%s\n\n' "$BOLD" "$RST" "$GRY" "$RST" "$DIM" "$RST"
  say "The receiver does the reverse ({b}decapsulation{/}): a switch reads only the Ethernet header, a router reads up to the IP header, and only the server's TCP stack and web application open the inner layers."
}

module02(){
  module_open 02 "${MOD_TITLE[2]}" "${MOD_MIN[2]}" "${MOD_TRACK[2]}"
  objectives "Name the 7 OSI layers, their unit of data and one protocol at each" \
    "Map OSI onto the TCP/IP model the Internet actually uses" \
    "Explain encapsulation: how data gets wrapped in headers on the way out" \
    "Find layer-2, layer-3 and layer-4 identifiers on your own machine"

  section "Why networks are built in layers"
  say "Delivering one web page is a huge job: turning text into bits, finding one machine among billions, recovering lost pieces, sharing a cable with other traffic. Engineers split the job into {b}layers{/}. Each layer does one job, uses the layer below it and serves the layer above it." \
      "The benefit: you can swap Wi-Fi for fibre (layer 1) without rewriting your browser (layer 7). The cost: a fault in ANY layer breaks everything above it. That is why troubleshooting goes layer by layer (module 15)."
  callout tip "Remember the layers bottom-up: {b}P{/}lease {b}D{/}o {b}N{/}ot {b}T{/}hrow {b}S{/}ausage {b}P{/}izza {b}A{/}way = Physical, Data link, Network, Transport, Session, Presentation, Application."

  section "The OSI model, layer by layer"
  figure "What each layer carries and how it is addressed" <<'EOF'
 #  LAYER          UNIT (PDU)  ADDRESS      EXAMPLES
 7  Application    data        name / URL   HTTP, DNS, SMTP, SSH
 6  Presentation   data        -            encoding (UTF-8), compression, TLS*
 5  Session        data        session ID   login sessions, RPC
 4  Transport      segment     port         TCP, UDP
 3  Network        packet      IP address   IPv4, IPv6, ICMP
 2  Data link      frame       MAC address  Ethernet, Wi-Fi, ARP, VLAN tags
 1  Physical       bits        -            copper, fibre, radio
 * TLS does not fit in one box: it sits between transport and application.
EOF
  figure "The same layers through a security lens" <<'EOF'
 #  DEVICE AT THIS LAYER    TYPICAL ATTACK               TYPICAL DEFENCE
 7  proxy, WAF              phishing, SQL injection      WAF, input validation
 4  stateful firewall       port scan, SYN flood         firewall, SYN cookies
 3  router                  IP spoofing, route hijack    ingress filtering
 2  switch, access point    ARP spoofing, MAC flooding   DAI, port security
 1  cable, hub              tapping, jamming             physical security
EOF
  pageturn

  section "TCP/IP: the model the Internet really uses"
  figure "OSI (teaching model) next to TCP/IP (implementation model)" <<'EOF'
   OSI                              TCP/IP
 7 Application  ┐
 6 Presentation ├───────────────── Application   HTTP, DNS, TLS, SSH
 5 Session      ┘
 4 Transport    ───────────────── Transport     TCP, UDP
 3 Network      ───────────────── Internet      IP, ICMP
 2 Data link    ┐
 1 Physical     ┴───────────────── Link          Ethernet, Wi-Fi, ARP
EOF
  say "Professionals say 'layer 2', 'layer 3', 'layer 7' using OSI numbers, while the software is written in the four TCP/IP layers. Learn both vocabularies; they describe the same reality."

  section "Encapsulation: envelopes inside envelopes"
  encap_demo
  callout deep "How does a receiver know what is inside each header? Every header contains a {b}pointer to the next one{/}. Ethernet's {b}EtherType{/} field says 0x0800 = 'IPv4 inside'. IP's {b}Protocol{/} field says 6 = TCP, 17 = UDP, 1 = ICMP. TCP's {b}destination port{/} says 8000 = 'give this to the web server'. Following that chain of pointers is exactly how Wireshark decodes a packet, and in module 07 you will follow it byte by byte."
  pageturn

  section "Find the layers on your own machine"
  practical title="Layer 2 and layer 3 together: interfaces with addresses" \
    goal="See which IP addresses (layer 3) sit on which interfaces (layer 2)." \
    cmd="ip -br addr" \
    anatomy="addr :: show the IP addresses assigned to each interface (both IPv4 and IPv6)" \
    predict="Which interface do you expect to hold 127.0.0.1?" \
    read="column 1 :: interface (layer 2 object)
column 2 :: state UP/DOWN/UNKNOWN
the rest :: IP addresses with their /prefix: IPv4 like 192.168.1.20/24, IPv6 like fe80::…/64" \
    explain="One interface can carry several addresses (IPv4 and IPv6 at the same time). The /24 or /64 after the address is NOT part of the address: it says how big the local network is. Module 03 explains exactly how." \
    needs=ip
  practical title="Layer 4: who is talking, and who is listening?" \
    goal="List transport-layer sockets: the conversations (TCP/UDP) your machine is having right now." \
    cmd="ss -tuna" \
    anatomy="ss :: socket statistics (the modern netstat)
-t -u :: show TCP and UDP sockets
-n :: numeric: show 443 instead of 'https', IPs instead of names (faster and more honest)
-a :: all: listening sockets AND active conversations" \
    read="Netid :: tcp or udp
State :: LISTEN = waiting for clients; ESTAB = a live TCP conversation; TIME-WAIT = recently closed; UNCONN = UDP (no connections in UDP)
Local Address:Port :: this machine's end of the conversation
Peer Address:Port :: the other end; *:* or 0.0.0.0:* means 'anyone' (for listeners)" \
    explain="Every line is one socket. A conversation is identified by five values: protocol, local IP, local port, remote IP, remote port (the '5-tuple'). Two browser tabs to the same site differ only in their local port, which is how replies find the right tab." \
    needs=ss maxlines=25
  callout turn "Open a website in your browser and run {c}ss -tn state established{/} in another terminal. Find the lines with :443 as the peer port: those are your HTTPS conversations, right now."

  reflect "A colleague says 'The switch blocked my HTTP request on port 80'. Using layers, explain why that sentence is suspicious." \
    "A plain switch works at layer 2: it reads MAC addresses and knows nothing about ports, which live in the layer-4 TCP header. Filtering by port needs something that reads layer 4, such as a firewall or a switch with layer-3/4 access lists."
  quiz "In which layer's header is a TCP destination port carried?" D "Ports belong to the transport layer (L4) header: TCP or UDP." "Layer 1" "Layer 2" "Layer 3" "Layer 4"
  quiz "What is the unit of data called at layer 3?" B "Frames at L2, packets at L3, segments at L4 (datagrams for UDP)." "Frame" "Packet" "Segment" "Bit"
  quiz "An Ethernet frame arrives with EtherType 0x0800. What does the receiver expect next?" A "0x0800 means IPv4. 0x86DD = IPv6, 0x0806 = ARP, 0x8100 = VLAN tag." "An IPv4 header" "A TCP header" "An HTTP request" "An ARP reply"
  takeaways "Each layer does one job and adds its own header: data → segment → packet → frame → bits." \
    "Headers point to the next header (EtherType → Protocol → Port); that chain is how packets are decoded." \
    "{c}ip -br addr{/} shows L2+L3; {c}ss -tuna{/} shows L4 conversations." \
    "Name the layer of a problem before you try to fix it."
  mark_done
}

# ----------------------------------------------------------------- 03 -------
module03(){
  module_open 03 "${MOD_TITLE[3]}" "${MOD_MIN[3]}" "${MOD_TRACK[3]}"
  objectives "Explain the difference between a MAC address, an IP address and a port" \
    "Convert IPv4 addresses to binary and back" \
    "Calculate network, broadcast, host range and host count for any /prefix" \
    "Recognise private, loopback, link-local and other special ranges" \
    "Predict whether a destination is local or must go through the gateway"

  section "Three addresses, three jobs"
  figure "Every packet carries all three" <<'EOF'
 ADDRESS  LAYER  EXAMPLE              SCOPE               POSTAL ANALOGY
 MAC      L2     02:c1:dc:01:00:10    one link (one hop)  'the house on this street'
 IP       L3     10.77.2.20           end to end          the full postal address
 Port     L4     8000                 one host            the flat / person inside
EOF
  say "A MAC address only matters on the local link: it is {b}rewritten at every router{/}. The IP address stays the same from source to destination (unless NAT changes it). The port picks which program on the destination gets the data."

  section "MAC addresses up close"
  figure "48 bits, written as 6 bytes in hexadecimal" <<'EOF'
     02 : c1 : dc  :  01 : 00 : 10
    └─── OUI ───┘   └── device ──┘
    vendor prefix    chosen by the vendor (or by us in the lab)

    first byte 0x02 = 0000 0010
                             ││
                             │└─ bit 0  I/G: 0 = unicast, 1 = multicast/group
                             └── bit 1  U/L: 1 = locally administered (set by software)
    ff:ff:ff:ff:ff:ff = broadcast: 'everyone on this LAN'
EOF
  callout security "A MAC address is trivial to change ({c}macchanger{/}, or one {c}ip link set{/} command). Never treat a MAC address as proof of identity: MAC filtering on Wi-Fi only stops honest people. Our lab MACs all start with 02 precisely because they were set by software."
  pageturn

  section "An IPv4 address is just a 32-bit number"
  say "Humans write {b}192.168.10.130{/}; the computer sees 32 ones and zeros. Each of the four numbers (an {b}octet{/}) is 8 bits, so it can only be 0 to 255. To convert, use the place values of one byte:"
  figure "Place values of one octet" <<'EOF'
   128   64   32   16    8    4    2    1
  ┌────┬────┬────┬────┬────┬────┬────┬────┐
  │  1 │  1 │  0 │  0 │  0 │  0 │  0 │  0 │  = 128 + 64           = 192
  │  1 │  0 │  1 │  0 │  1 │  0 │  0 │  0 │  = 128 + 32 + 8       = 168
  │  1 │  0 │  0 │  0 │  0 │  0 │  1 │  0 │  = 128 + 2            = 130
  └────┴────┴────┴────┴────┴────┴────┴────┘
EOF
  say "Practise converting in your head: start from 128, take it if it fits, subtract, move right. 200 = 128 + 64 + 8 = 11001000."
  pageturn

  section "Network bits and host bits: the /prefix"
  say "An address alone is not enough: you also need to know which part names the {b}network{/} and which part names the {b}host{/} inside it. The {b}/prefix{/} (CIDR notation) counts the network bits from the left. The rest are host bits. A {b}subnet mask{/} says the same thing as 1s and 0s: /26 = 26 ones = 255.255.255.192." \
      "To find the network a host belongs to, the computer does a bitwise {b}AND{/} of the address and the mask: every host bit becomes 0. Set all host bits to 1 instead and you get the {b}broadcast{/} address. Here is the full calculation for {b}192.168.10.130/26{/}, with network bits in {g}green{/} and host bits in {y}yellow{/}:"
  subnet_explain 192.168.10.130 26
  pageturn

  section "The fast way: block size"
  say "You will not always have time to write 32 bits. The shortcut: find the {b}interesting octet{/} (where the mask is neither 255 nor 0), then {b}block size = 256 - mask value{/}. Networks start at multiples of the block size."
  figure "Example 192.168.10.130/26" <<'EOF'
  mask /26 = 255.255.255.192      interesting octet = 4th, value 192
  block size = 256 - 192 = 64     networks start at  .0  .64  .128  .192
  130 falls in the block that starts at .128
     network   = 192.168.10.128   (first address of the block)
     broadcast = 192.168.10.191   (last address: next block .192 minus 1)
     hosts     = .129 to .190     = 64 - 2 = 62 usable
EOF
  figure "Prefixes you should know without thinking" <<'EOF'
  PREFIX  MASK              ADDRESSES  USABLE HOSTS  TYPICAL USE
  /8      255.0.0.0         16 777 216   16 777 214  huge private range 10.0.0.0/8
  /16     255.255.0.0           65 536       65 534  a campus
  /24     255.255.255.0            256          254  a typical LAN
  /25     255.255.255.128          128          126
  /26     255.255.255.192           64           62
  /27     255.255.255.224           32           30  a small office / DMZ
  /28     255.255.255.240           16           14
  /30     255.255.255.252            4            2  legacy router-to-router link
  /31     255.255.255.254            2            2  point-to-point (RFC 3021)
  /32     255.255.255.255            1            1  a single host route
  Usable = addresses - 2 (network and broadcast are reserved), except /31 and /32.
EOF
  pageturn

  section "Special addresses every analyst must recognise"
  figure "Seeing one of these in a log tells you something immediately" <<'EOF'
  RANGE              MEANING
  10.0.0.0/8         private (RFC 1918): never routed on the Internet
  172.16.0.0/12      private: 172.16.0.0 to 172.31.255.255
  192.168.0.0/16     private: home and small office networks
  127.0.0.0/8        loopback: this very machine
  169.254.0.0/16     link-local (APIPA): DHCP FAILED, the host invented an address
  100.64.0.0/10      carrier-grade NAT (ISPs), also used by Tailscale
  224.0.0.0/4        multicast (one-to-many)
  0.0.0.0            'any address' (servers) or 'no address yet' (DHCP clients)
  255.255.255.255    broadcast on the local link
  192.0.2.0/24       documentation examples (also 198.51.100.0/24, 203.0.113.0/24)
EOF
  callout security "Private addresses arriving as the SOURCE on your Internet-facing firewall are spoofed: they cannot legitimately come from the Internet. A host with 169.254.x.x is a broken DHCP client, or someone's misconfigured device. Recognising ranges at a glance makes log triage much faster."

  section "Local or remote? The decision every host makes"
  say "Before sending anything, a host compares: ({b}destination AND my mask{/}) equals ({b}my address AND my mask{/})?" \
      "If {g}yes{/}: the destination is on my LAN, so I find ITS MAC address (ARP, module 04) and deliver directly. If {y}no{/}: I send the packet to my {b}default gateway{/} (the router) and let it decide. That single comparison is why a wrong mask or a missing gateway breaks connectivity in such confusing ways."
  practical title="Your IPv4 addresses and prefixes" \
    goal="Read the address and prefix of each interface; work out the network each belongs to." \
    cmd="ip -4 -br addr" \
    anatomy="-4 :: IPv4 only (use -6 for IPv6)
-br addr :: brief list of addresses per interface" \
    read="10.0.2.15/24 (example) :: host address 10.0.2.15 on network 10.0.2.0/24
127.0.0.1/8 :: loopback, present everywhere" \
    explain="Take your main address and prefix and calculate the network and broadcast by hand using the block-size method. Then check yourself with the Python calculator below." \
    needs=ip
  practical title="Ask the kernel how it WOULD route a packet" \
    goal="See the local-or-remote decision directly. No packet is sent." \
    cmd="ip route get 1.1.1.1" \
    anatomy="route get :: 'which route would you use for this destination?'
1.1.1.1 :: an Internet address (a public DNS resolver), certainly not on your LAN" \
    predict="Will the answer contain 'via'? What do you think 'via' means?" \
    read="via X :: the next hop: your default gateway (so the destination is remote)
dev Y :: the interface the packet would leave from
src Z :: the source address the kernel would put in the packet
Network is unreachable :: there is no matching route at all (no default gateway)" \
    explain="Try it with an address from your own LAN in a second terminal: the 'via' disappears, because local destinations are delivered directly. This command is the fastest way to answer 'which way does my traffic go?', for example when a VPN is connected." \
    needs=ip expect=any
  practical title="Check your subnet maths with Python" \
    goal="Use Python's ipaddress library as an independent calculator. Do the maths by hand first!" \
    cmd="python3 -c \"import ipaddress as i; n=i.ip_interface('192.168.10.130/26').network; print(n, n.netmask, n.broadcast_address, n.num_addresses)\"" \
    anatomy="python3 -c \"…\" :: run a one-line Python program
ip_interface('…/26') :: a host address together with its prefix
.network :: the network that host belongs to (host bits set to 0)
netmask, broadcast_address, num_addresses :: mask, the all-host-bits-1 address, block size" \
    predict="Before running: network? broadcast? total addresses?" \
    read="192.168.10.128/26 :: the network
255.255.255.192 :: the mask
192.168.10.191 :: the broadcast
64 :: total addresses in the block (62 usable)" \
    needs=python3

  section "Practice: three subnetting questions"
  say "Subnetting is a skill, not a fact: you only get fast by doing it. Answer each field; you get the full binary explanation after each question. More practice any time from the menu ({b}D{/})."
  subnet_drill 3
  quiz "192.168.10.130/26 belongs to which network?" C "A /26 has blocks of 64: .0, .64, .128, .192. 130 is in the .128 block." "192.168.10.0" "192.168.10.64" "192.168.10.128" "192.168.10.192"
  quiz "A Windows PC shows the address 169.254.33.7. What happened?" B "169.254.0.0/16 is link-local (APIPA): the PC asked for DHCP, got no answer, and invented an address." "It is on a VPN" "DHCP failed" "It is a public address" "It is loopback"
  quiz "Host 10.1.1.10/24 wants to reach 10.1.2.10. What does it do?" A "10.1.2.10 is outside 10.1.1.0/24, so the host sends the packet to its default gateway (and ARPs for the GATEWAY's MAC)." "Sends it to its default gateway" "ARPs for 10.1.2.10 directly" "Broadcasts the packet" "Drops it"
  takeaways "MAC = this link, IP = end to end, port = which program." \
    "The /prefix splits network bits from host bits; AND with the mask gives the network, all host bits at 1 give the broadcast." \
    "Block size = 256 - mask octet; usable hosts = 2^(host bits) - 2." \
    "Local destinations are delivered directly; everything else goes to the default gateway."
  mark_done
}

# ----------------------------------------------------------------- 04 -------
lab_map_fig(){
  figure "The C1DC cyber-range" <<'EOF'
 LAN A  10.77.1.0/24                           LAN B  10.77.2.0/24

 [c1-student] .10 ──┐
  "your PC"         │  [c1-switch]       [c1-router]          [c1-server]
                    ├── br0 (L2) ───── eth0 .1 │ eth1 .1 ────── eth0 .20
 [c1-peer]    .11 ──┘  learns MACs     forwards + filters    web :8000  tls :8443
  "colleague PC"                                             dns :53    udp :5300
EOF
}

module04(){
  module_open 04 "${MOD_TITLE[4]}" "${MOD_MIN[4]}" "${MOD_TRACK[4]}"
  objectives "Explain why ARP exists and when a host uses it" \
    "Read the Linux neighbour table and its states" \
    "Capture and explain a real ARP request and reply" \
    "Explain ARP spoofing and how defenders detect it"

  section "Meet the cyber-range"
  say "From this module on you work in an isolated lab inside your Kali machine: five virtual hosts built from Linux {b}network namespaces{/}. Each one has its own interfaces, addresses, routes and firewall, exactly like a real computer, yet none of them can touch your real network."
  lab_map_fig
  callout tip "To run a command INSIDE a lab host, prefix it with {c}sudo ip netns exec c1-student{/} (works for any command), or use the shortcut {c}sudo ip -n c1-student …{/} (for 'ip' commands only). Menu {b}S{/} opens a full root shell inside any host for free exploration. The script that built the lab is saved in ~/c1dc-network-labs/lab/build-lab.sh: read it!"
  pageturn

  section "The problem ARP solves"
  say "IP addresses are end-to-end, but Ethernet delivers frames using {b}MAC{/} addresses. So before the student PC can send anything to 10.77.1.1, it must learn which MAC address owns 10.77.1.1. The {b}Address Resolution Protocol{/} (ARP) asks the whole LAN, and the owner answers."
  figure "An ARP conversation on LAN A" <<'EOF'
  c1-student 10.77.1.10                               c1-router 10.77.1.1
  02:c1:dc:01:00:10                                   02:c1:dc:01:00:01
        │                                                      │
        │ ① REQUEST "Who has 10.77.1.1? Tell 10.77.1.10"       │
        │   to ff:ff:ff:ff:ff:ff (BROADCAST: every host hears) │
        │ ────────────────────────────────────────────────────►│
        │                                                      │
        │ ② REPLY "10.77.1.1 is at 02:c1:dc:01:00:01"          │
        │   to 02:c1:dc:01:00:10 (UNICAST: only the asker)     │
        │◄──────────────────────────────────────────────────── │
        ▼                                                      ▼
  caches 10.77.1.1 = …:01:00:01                caches 10.77.1.10 = …:01:00:10
EOF
  callout concept "ARP only works {b}inside one LAN{/} (one broadcast domain). Routers do not forward ARP. For a remote destination, a host ARPs for its {b}gateway{/}, never for the remote server."
  terms "REACHABLE :: confirmed recently; safe to use." \
        "STALE :: known, but not confirmed lately; re-checked on next use." \
        "DELAY / PROBE :: being re-checked right now." \
        "INCOMPLETE :: request sent, no answer yet." \
        "FAILED :: nobody answered: the host is down or not on this LAN." \
        "PERMANENT :: typed in by an administrator; never expires (or planted by an attacker…)."
  pageturn

  section "See it happen"
  practical title="Look at the student PC's addresses" \
    goal="Confirm where you are: the student host, its interface and its addresses." \
    cmd="sudo ip -n c1-student -br addr" \
    anatomy="sudo :: lab commands need root, only to enter the namespace
ip -n c1-student :: run this ip command inside the c1-student namespace
-br addr :: brief address list" \
    read="lo :: loopback 127.0.0.1/8 and ::1/128
eth0@ifN :: the virtual cable to the switch; @ifN names its other end
10.77.1.10/24 :: our IPv4 address on LAN A
fd77:1::10/64 :: our IPv6 address (module 12)" \
    lab=1 needs=ip
  practical title="Empty the student's neighbour (ARP) cache" \
    goal="Start from a clean slate so we can watch the cache fill up." \
    cmd="sudo ip -n c1-student neigh flush all" \
    anatomy="neigh :: the neighbour table (ARP for IPv4, NDP for IPv6)
flush all :: delete every learned entry" \
    read="(no output) :: Unix tradition: silence means success" \
    lab=1 needs=ip
  practical title="Capture the ARP conversation live" \
    goal="Record the frames on the student's cable while the academy makes the student ping its gateway once." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -e -c 4 arp or icmp" \
    anatomy="ip netns exec c1-student :: run any command inside the student host
tcpdump :: command-line packet capture
-i eth0 :: listen on the student's network interface
-nn :: no name lookups for addresses or ports (show raw numbers)
-e :: also print the Ethernet header: the MAC addresses
-c 4 :: stop after 4 packets
arp or icmp :: capture filter: only ARP and ICMP (ping) packets" \
    predict="What will the very first packet be, and to which MAC address will it be sent?" \
    pre="ip -n c1-student neigh flush all; ip -n c1-router neigh flush all" \
    bg="ip netns exec c1-student ping -c 1 -W 1 10.77.1.1" \
    read="02:c1:dc:01:00:10 > ff:ff:ff:ff:ff:ff :: source MAC > destination MAC; ff:… is broadcast
ethertype ARP (0x0806) :: the frame carries ARP
Request who-has 10.77.1.1 tell 10.77.1.10 :: ① the question, heard by every host on LAN A
Reply 10.77.1.1 is-at 02:c1:dc:01:00:01 :: ② the answer, sent only to the asker
ICMP echo request / reply :: the ping itself, which could only start once the MAC was known" \
    explain="The ping command never mentions MAC addresses, but the kernel cannot build an Ethernet frame without one. So the ICMP packet waited a fraction of a millisecond in a queue while ARP did its work. Notice that the router learned the student's MAC from the request itself, so it did not need to ask back." \
    lab=1 needs=tcpdump
  practical title="Read the cache that ARP just filled" \
    goal="The answer is now stored in the neighbour table." \
    cmd="sudo ip -n c1-student neigh show" \
    anatomy="neigh show :: list the neighbour table" \
    read="10.77.1.1 :: the IP address that was resolved
dev eth0 :: learned on this interface
lladdr 02:c1:dc:01:00:01 :: link-layer (MAC) address of the router
REACHABLE / STALE :: the state (see the table above)" \
    lab=1 needs=ip
  practical title="Ping the server on the OTHER network" \
    goal="Reach 10.77.2.20, which is on LAN B, behind the router." \
    cmd="sudo ip netns exec c1-student ping -c 2 10.77.2.20" \
    anatomy="ping :: send ICMP Echo Requests and wait for Echo Replies
-c 2 :: send exactly two" \
    read="64 bytes from 10.77.2.20 :: a reply arrived
icmp_seq :: which request this reply answers
ttl=63 :: the server sent 64; the router subtracted 1 on the way back
time= :: round-trip time in milliseconds
0% packet loss :: every request got a reply" \
    lab=1 needs=ping
  practical title="Does the server's address appear in the ARP cache?" \
    goal="Test the rule 'ARP only for local destinations'." \
    cmd="sudo ip -n c1-student neigh show" \
    anatomy="neigh show :: list the neighbour table again" \
    predict="Will you see an entry for 10.77.2.20? Why or why not?" \
    read="only 10.77.1.1 :: the gateway is the only neighbour the student needed" \
    explain="The student never sends frames to the server's MAC: the server is not on its LAN. Every packet to 10.77.2.20 goes in a frame addressed to the ROUTER's MAC. The router then uses ITS OWN ARP cache on LAN B. MAC addresses change at every hop; IP addresses do not." \
    lab=1 needs=ip
  callout turn "Ping the peer PC ({c}sudo ip netns exec c1-student ping -c 1 10.77.1.11{/}) and check the neighbour table again. This time a new entry appears. Why is the peer different from the server?"

  section "Security lens: ARP spoofing"
  say "ARP has {b}no authentication{/}. Any host can send a reply saying 'the gateway 10.77.1.1 is at MY MAC', even without being asked. Victims update their caches and start sending all their traffic to the attacker, who can read it, change it, or pass it on (a man-in-the-middle)."
  figure "Normal vs poisoned cache on the student PC" <<'EOF'
  NORMAL:    10.77.1.1  lladdr 02:c1:dc:01:00:01  REACHABLE   (the real router)
  POISONED:  10.77.1.1  lladdr 02:c1:dc:01:00:11  REACHABLE   (the peer PC's MAC!)
             10.77.1.11 lladdr 02:c1:dc:01:00:11  REACHABLE
             └─ red flag: two different IPs now share ONE MAC address
EOF
  terms "Detection :: two IPs with the same MAC; the gateway's MAC suddenly changing; tools such as arpwatch; a burst of unsolicited ARP replies in a capture." \
        "Prevention :: Dynamic ARP Inspection (DAI) on managed switches, static entries for critical hosts, segmentation, and encryption (TLS) so a man-in-the-middle sees nothing useful."
  say "Troubleshooting ticket #6 (menu T) drops you into a poisoned network to investigate yourself."
  reflect "When the student pings 8.8.8.8 on the Internet, whose MAC address does it put in the Ethernet frame, and why?" \
    "The default gateway's MAC (10.77.1.1 = 02:c1:dc:01:00:01). 8.8.8.8 is not on the local network, so the host ARPs for the gateway and hands every remote packet to it. The destination IP stays 8.8.8.8."
  quiz "An ARP request is sent to which destination MAC address?" A "Requests are broadcast because the sender does not yet know who owns the IP. Replies are unicast." "ff:ff:ff:ff:ff:ff (broadcast)" "The gateway's MAC" "00:00:00:00:00:00" "The DNS server's MAC"
  quiz "Which state means 'request sent, no reply yet'?" C "INCOMPLETE. If nobody ever answers, the entry becomes FAILED." "STALE" "REACHABLE" "INCOMPLETE" "PERMANENT"
  takeaways "ARP maps an IPv4 address to a MAC address, but only within one LAN." \
    "Requests are broadcast, replies are unicast; results are cached in the neighbour table." \
    "For remote destinations a host ARPs for its gateway, never for the remote host." \
    "ARP has no authentication: spoofing enables man-in-the-middle attacks. Watch for one MAC claiming several IPs."
  mark_done
}

# ----------------------------------------------------------------- 05 -------
module05(){
  module_open 05 "${MOD_TITLE[5]}" "${MOD_MIN[5]}" "${MOD_TRACK[5]}"
  objectives "Describe the four DHCP messages (DORA) and what a lease contains" \
    "Watch a real DHCP offer arrive in the lab" \
    "Explain how DNS resolves a name, and the common record types" \
    "Read every section of a dig answer" \
    "Explain why 'dig works but ping fails' (and the reverse) can happen"

  section "DHCP: how a device gets its settings"
  say "A new laptop on a network knows nothing: not its IP, not its gateway, not its DNS server. {b}DHCP{/} (Dynamic Host Configuration Protocol) hands all of that out automatically, for a limited time called a {b}lease{/}."
  figure "DORA: four messages over UDP, server port 67, client port 68" <<'EOF'
  CLIENT (no IP yet: 0.0.0.0)                          DHCP SERVER
     │ ① DISCOVER  "Is there a DHCP server?" → 255.255.255.255   │
     │ ─────────────────────────────────────────────────────────►│
     │ ② OFFER     "You can have 10.77.1.141, gateway .1, DNS…"  │
     │ ◄─────────────────────────────────────────────────────────│
     │ ③ REQUEST   "I'll take 10.77.1.141, please" (broadcast)   │
     │ ─────────────────────────────────────────────────────────►│
     │ ④ ACK       "It's yours for 10 minutes"                   │
     │ ◄─────────────────────────────────────────────────────────│
  Renewal at 50% of the lease (T1), fallback to any server at 87.5% (T2).
EOF
  terms "Why broadcast? :: The client has no IP address yet and does not know where the server is, so it shouts to everyone on the LAN." \
        "What is in a lease? :: IP address, subnet mask (option 1), default gateway (option 3), DNS servers (option 6), domain name (option 15), lease time (option 51)." \
        "DHCP relay :: Routers do not forward broadcasts; an 'ip helper' relays DHCP to a central server on another network."
  callout security "A {b}rogue DHCP server{/} (an attacker's laptop answering faster than the real one) can give victims a malicious gateway or DNS server and silently become a man-in-the-middle. {b}DHCP starvation{/} grabs every free address. Managed switches stop both with {b}DHCP snooping{/}: only trusted ports may send OFFERs."
  practical title="Ask for a DHCP offer from inside the lab" \
    goal="The academy starts a DHCP server on the router's LAN A port. From the peer PC you send a real DISCOVER and read the OFFER, without changing any address." \
    cmd="sudo ip netns exec c1-peer nmap --script broadcast-dhcp-discover --script-args broadcast-dhcp-discover.timeout=4 -e eth0" \
    anatomy="nmap --script broadcast-dhcp-discover :: run Nmap's DHCP-discover script (no port scan)
--script-args …timeout=4 :: wait up to 4 seconds for offers
-e eth0 :: send on this interface" \
    predict="Which options do you expect in the offer? Write down at least three." \
    pre="$TOOLS/labctl start dhcp" \
    after="$TOOLS/labctl stop dhcp" \
    read="IP Offered :: the address the server proposes (from its pool 10.77.1.100-150)
Server Identifier :: who made the offer: the router 10.77.1.1
Subnet Mask, Router :: option 1 and option 3: the mask and the default gateway
Domain Name Server :: option 6: the resolver clients should use (10.77.2.20)
IP Address Lease Time :: how long the address may be kept; renewal at 50%" \
    explain="Nmap sent a DISCOVER from a made-up MAC and printed the OFFER, but never sent a REQUEST, so nothing was actually leased. Real clients continue with REQUEST and ACK. If two different Server Identifiers answer on a production LAN, you may have found a rogue DHCP server." \
    lab=1 needs="nmap dnsmasq"
  pageturn

  section "DNS: the Internet's phone book"
  say "People remember names; packets need addresses. The {b}Domain Name System{/} translates names into IP addresses (and much more). It is a distributed, hierarchical database: no single server knows everything."
  figure "Resolving intranet.c1dc.lab, the long way" <<'EOF'
  your PC ── "intranet.c1dc.lab?" ──► RECURSIVE RESOLVER (does the legwork, caches)
                                         │ ① ask a ROOT server (.)    → "try the .lab servers"
                                         │ ② ask the .lab TLD server  → "try c1dc.lab's server"
                                         │ ③ ask the AUTHORITATIVE    → "10.77.2.20"
                                         ▼    server for c1dc.lab
  your PC ◄── "10.77.2.20" ──────── answer cached for TTL seconds
  (In our lab, 10.77.2.20 is both the resolver and the authority for c1dc.lab.)
EOF
  figure "Record types you will meet" <<'EOF'
  A      name → IPv4 address          AAAA   name → IPv6 address
  CNAME  alias → canonical name       MX     mail servers for a domain
  NS     authoritative servers        TXT    free text (SPF, verification)
  PTR    IP → name (reverse lookup)   SOA    zone settings and serial number
EOF
  say "DNS normally uses {b}UDP port 53{/} (one question, one answer, no handshake), switching to {b}TCP 53{/} for large answers and zone transfers. Modern clients may use encrypted DNS: DoT (TLS, port 853) or DoH (HTTPS, port 443)."
  callout security "DNS is in almost every attack story: {b}spoofing and cache poisoning{/} (fake answers), {b}typosquatting{/} (c1dc-lab.com), {b}DNS tunnelling{/} (data hidden in long random subdomains) and {b}hosts-file tampering{/} by malware. DoH also hides lookups from network monitoring, a challenge for defenders."
  pageturn

  section "How Linux looks up a name"
  practical title="Which sources does this machine trust for names?" \
    goal="The 'hosts' line in nsswitch.conf decides the ORDER in which name sources are consulted." \
    cmd="grep hosts: /etc/nsswitch.conf" \
    anatomy="grep hosts: :: print only lines containing 'hosts:'
/etc/nsswitch.conf :: the Name Service Switch configuration" \
    read="files :: /etc/hosts is checked FIRST
dns :: then the DNS servers listed in /etc/resolv.conf
mdns4_minimal :: multicast DNS for .local names (if present)" \
    explain="Because 'files' usually comes first, one line in /etc/hosts overrides the whole DNS system for this machine. Great for testing, dangerous when malware writes to it." \
    needs=grep
  practical title="Which DNS server does this machine ask?" \
    goal="See the resolver configuration of your real Kali machine." \
    cmd="cat /etc/resolv.conf" \
    anatomy="cat :: print a file
/etc/resolv.conf :: resolver settings: nameserver, search domain, options" \
    read="nameserver :: the IP address of a DNS resolver (up to 3, tried in order)
search :: a domain appended to short names (ping server → server.c1dc.lab)
127.0.0.53 :: a local caching stub (systemd-resolved), if present" \
    needs=cat
  practical title="Look up a name through the system resolver" \
    goal="getent asks the system's resolver chain exactly as ping or a browser would." \
    cmd="getent hosts localhost" \
    anatomy="getent hosts :: resolve a name using nsswitch.conf (files, then DNS…)" \
    read="::1 or 127.0.0.1 :: the answer, here coming from /etc/hosts (no DNS packet was sent)" \
    needs=getent
  pageturn

  section "DNS in the lab: query, read, capture"
  practical title="Query the lab's DNS server directly" \
    goal="dig is the analyst's DNS microscope: it shows the entire answer, not just the address." \
    cmd="sudo ip netns exec c1-student dig @10.77.2.20 intranet.c1dc.lab" \
    anatomy="dig :: DNS lookup tool (package dnsutils / bind9-dnsutils)
@10.77.2.20 :: ask THIS server, ignore resolv.conf
intranet.c1dc.lab :: the name to resolve (record type A by default)" \
    predict="Which IP address do you expect, and how long might the answer be cached?" \
    read="status: NOERROR :: the query succeeded (NXDOMAIN = name does not exist; SERVFAIL = server problem)
flags: qr aa rd ra :: qr = a response; aa = authoritative answer; rd/ra = recursion desired/available
QUESTION SECTION :: what we asked: name, class IN (Internet), type A
ANSWER SECTION :: name, TTL in seconds, class, type, value (10.77.2.20)
Query time / SERVER :: how long it took and which server answered (port 53)" \
    lab=1 needs="dig dnsmasq"
  practical title="Ask for a different record type: mail servers" \
    goal="DNS stores more than addresses. MX records tell the world where to deliver a domain's e-mail." \
    cmd="sudo ip netns exec c1-student dig @10.77.2.20 c1dc.lab MX +short" \
    anatomy="c1dc.lab MX :: the domain, and the record type we want
+short :: only print the answer values" \
    read="10 mail.c1dc.lab. :: preference 10 (lower = preferred), then the mail server's name" \
    lab=1 needs="dig dnsmasq"
  callout turn "Now try {c}TXT{/} for c1dc.lab (an SPF policy that says who may send its mail) and {c}www.c1dc.lab{/} without a type (you will see a CNAME alias followed by the A record)."
  practical title="A name that does not exist" \
    goal="Learn to read failure. NXDOMAIN is a definitive 'no such name', not a network error." \
    cmd="sudo ip netns exec c1-student dig @10.77.2.20 ghost.c1dc.lab +noall +comments" \
    anatomy="+noall +comments :: hide everything except the header comments (status and flags)" \
    read="status: NXDOMAIN :: 'non-existent domain': the authoritative server says the name does not exist
ANSWER: 0 :: no records came back" \
    explain="Compare: a timeout ('no servers could be reached') means a network or firewall problem; SERVFAIL means the server could not complete the lookup; NXDOMAIN means everything worked and the name simply does not exist. Many NXDOMAINs for random-looking names can indicate malware using a domain generation algorithm." \
    lab=1 needs="dig dnsmasq"
  practical title="Capture a DNS question and answer" \
    goal="See DNS on the wire: one UDP packet out, one UDP packet back. No handshake." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -c 2 udp port 53" \
    anatomy="udp port 53 :: capture filter for DNS traffic
-c 2 :: one query plus one response" \
    bg="ip netns exec c1-student dig @10.77.2.20 server.c1dc.lab +short" \
    read="10.77.1.10.PORT > 10.77.2.20.53 :: the query, from a random source port to port 53
A? server.c1dc.lab. :: the question: 'A record of server.c1dc.lab?'
10.77.2.20.53 > 10.77.1.10.PORT :: the answer comes back to the same random port
1/0/0 A 10.77.2.20 :: 1 answer, 0 authority, 0 additional records: the A record" \
    explain="Plain DNS is unencrypted: anyone on the path (like this capture) sees every name you look up. That is valuable for defenders and a privacy problem for users, and the reason DoT/DoH exist. The random source port and a 16-bit query ID are the main defences against blind spoofing of answers." \
    lab=1 needs="tcpdump dnsmasq"
  practical title="dig does NOT read /etc/hosts" \
    goal="peer.c1dc.lab exists only in the lab's hosts file (/etc/netns/c1-student/hosts), not in DNS." \
    cmd="sudo ip netns exec c1-student getent hosts peer.c1dc.lab" \
    anatomy="getent hosts :: the system resolver chain: files (hosts file) first, then DNS" \
    read="10.77.1.11 peer.c1dc.lab :: found in the hosts file; no DNS packet was sent" \
    explain="Now ask DNS for the same name: sudo ip netns exec c1-student dig @10.77.2.20 peer.c1dc.lab +short. It prints nothing, because dig talks DNS directly and ignores /etc/hosts. This is why 'dig works but the browser does not' (or the reverse) happens: they are not asking the same sources." \
    lab=1 needs=getent
  reflect "A user can open https://10.77.2.20:8443 but not https://server.c1dc.lab:8443. List two testable hypotheses and the command that tests each." \
    "1) DNS does not resolve the name: test with dig @10.77.2.20 server.c1dc.lab (and check resolv.conf). 2) The system resolves it differently, e.g. a wrong /etc/hosts entry: test with getent hosts server.c1dc.lab and compare with dig. Connectivity to the IP already works, so layers 1-4 are fine."
  quiz "Why is a DHCP DISCOVER sent as a broadcast?" B "The client has no IP address yet and does not know the server's address, so it must reach everyone on the LAN." "To be faster" "The client has no address and does not know where the server is" "Because DHCP uses TCP" "To reach the Internet"
  quiz "dig returns 'status: NXDOMAIN'. What does that mean?" A "NXDOMAIN is a successful, authoritative 'this name does not exist'. A timeout would mean the server was unreachable." "The name does not exist" "The DNS server is unreachable" "The firewall blocked port 53" "The TTL expired"
  takeaways "DHCP (DORA, UDP 67/68) gives a host its IP, mask, gateway and DNS server for a lease period." \
    "DNS resolves names through resolvers and authoritative servers; answers are cached for their TTL." \
    "Linux checks /etc/hosts before DNS; dig ignores the hosts file, getent and ping do not." \
    "Rogue DHCP, DNS spoofing and hosts-file tampering all redirect victims: know what normal answers look like."
  mark_done
}

# ----------------------------------------------------------------- 06 -------
module06(){
  module_open 06 "${MOD_TITLE[6]}" "${MOD_MIN[6]}" "${MOD_TRACK[6]}"
  objectives "Explain ports, sockets and the 5-tuple" \
    "Describe TCP's handshake, sequence numbers, acknowledgements and teardown" \
    "Capture a real handshake and dissect a SYN byte by byte" \
    "Tell 'connection refused' (RST) from 'timed out' (silence)" \
    "Contrast UDP with TCP and recognise ICMP port-unreachable"

  section "Ports and sockets"
  say "An IP address gets a packet to the right {b}machine{/}; a {b}port{/} (0-65535) gets it to the right {b}program{/}. Servers listen on well-known ports; clients pick a random {b}ephemeral{/} port for each new conversation, so replies find the right browser tab."
  figure "Well-known ports worth memorising" <<'EOF'
  20/21 FTP    22 SSH      23 Telnet   25 SMTP     53 DNS        67/68 DHCP
  80 HTTP      110 POP3    123 NTP     143 IMAP    161 SNMP      389 LDAP
  443 HTTPS    445 SMB     3306 MySQL  3389 RDP    5432 Postgres 8080 HTTP-alt
  Ports are conventions, not laws: anything can listen anywhere.
  A listening port is an exposed program, not automatically a vulnerability.
EOF
  practical title="Which range do client ports come from?" \
    goal="The kernel picks source ports for outgoing connections from this range." \
    cmd="cat /proc/sys/net/ipv4/ip_local_port_range" \
    anatomy="/proc/sys/net/ipv4/… :: kernel settings exposed as files (also readable with sysctl)" \
    read="32768 60999 :: (typical) the lowest and highest ephemeral port" \
    explain="When you see 10.77.1.10.51514 in a capture, 51514 comes from this range: that side is the client. 10.77.2.20.8000 is a fixed, well-known server port. Recognising which side is the client is the first step in reading any capture." \
    needs=cat
  practical title="What is listening on the lab server?" \
    goal="List the server's listening sockets: its attack surface." \
    cmd="sudo ip netns exec c1-server ss -tuln" \
    anatomy="ss -tuln :: TCP and UDP, Listening sockets only, numeric" \
    predict="Which ports do you expect, given the lab map (menu M)?" \
    read="tcp LISTEN 10.77.2.20:8000 :: the web server, bound to one address
tcp LISTEN 10.77.2.20:8443 :: the HTTPS server
udp UNCONN 10.77.2.20:53 :: DNS (UDP has no LISTEN state, just unconnected sockets)
udp UNCONN 10.77.2.20:5300 :: our silent UDP listener
0.0.0.0 or * :: would mean 'every address of this host'; 127.0.0.1 = this host only" \
    lab=1 needs=ss
  pageturn

  section "TCP: a reliable conversation"
  say "TCP turns an unreliable network into a reliable, ordered byte stream. It numbers every byte ({b}sequence numbers{/}), confirms receipt ({b}acknowledgements{/}), resends what is lost, and slows down when the network is congested. Before any data flows, both sides agree on starting numbers: the {b}three-way handshake{/}."
  figure "A complete TCP conversation (curl fetching a page)" <<'EOF'
  CLIENT 10.77.1.10:51514                            SERVER 10.77.2.20:8000
   │ ① SYN        seq=1000                                     │ "let's talk; I start at 1000"
   │ ─────────────────────────────────────────────────────────►│
   │ ② SYN,ACK    seq=5000 ack=1001                            │ "OK; I start at 5000;
   │ ◄─────────────────────────────────────────────────────────│  I expect your byte 1001"
   │ ③ ACK        seq=1001 ack=5001                            │ ESTABLISHED
   │ ─────────────────────────────────────────────────────────►│
   │   PSH,ACK    "GET / HTTP/1.1…" (78 bytes)                 │
   │ ─────────────────────────────────────────────────────────►│
   │   ACK ack=1079, then PSH,ACK "HTTP/1.0 200 OK…"           │
   │ ◄─────────────────────────────────────────────────────────│
   │   FIN,ACK … FIN,ACK … ACK                                 │ polite goodbye, both sides
   │ ◄────────────────────────────────────────────────────────►│
EOF
  figure "TCP flags and how tcpdump prints them" <<'EOF'
  FLAG  MEANING                                   TCPDUMP
  SYN   synchronise: open, carries the start seq  [S]
  ACK   the acknowledgement field is valid        [.]     (SYN+ACK = [S.])
  PSH   push: hand data to the application now    [P.]
  FIN   finished sending: graceful close          [F.]
  RST   reset: abort / 'nobody here'              [R] or [R.]
EOF
  pageturn
  practical title="Capture a real three-way handshake" \
    goal="Record the first three packets of a connection while the academy fetches the intranet page from the student PC." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -c 3 tcp port 8000" \
    anatomy="tcp port 8000 :: only TCP traffic to or from port 8000
-c 3 :: exactly the handshake: SYN, SYN-ACK, ACK" \
    predict="Which flags will the three packets have, in order?" \
    bg="ip netns exec c1-student curl -s -o /dev/null http://10.77.2.20:8000/" \
    read="Flags [S] :: ① the client's SYN with its random initial sequence number
Flags [S.] :: ② the server's SYN-ACK: its own seq, and ack = client seq + 1
Flags [.] :: ③ the client's ACK: the connection is ESTABLISHED
win :: receive window (flow control); options: mss, sackOK, TS, wscale" \
    explain="tcpdump shows the real (random) initial sequence numbers in the SYN and SYN-ACK, then switches to RELATIVE numbers (starting at 1) to keep the rest readable; add -S to see absolute numbers. The random start makes it very hard for an attacker to inject forged packets into somebody else's connection." \
    lab=1 needs="tcpdump curl"
  practical title="Record a whole web conversation to a file" \
    goal="Save the full exchange as a PCAP (packet capture) file for later analysis in modules 07 and 14." \
    cmd="sudo ip netns exec c1-student timeout 5 tcpdump -i eth0 -nn -U -w - tcp port 8000 > evidence/web.pcap" \
    anatomy="timeout 5 :: stop tcpdump after 5 seconds (we do not know how many packets will come)
-U :: write each packet immediately, not in big buffered chunks
-w - :: write raw binary PCAP to standard output ('-' means stdout)…
> evidence/web.pcap :: …which YOUR shell redirects into a file you own (no permission problems)" \
    bg="ip netns exec c1-student curl -s -o /dev/null http://10.77.2.20:8000/" \
    read="listening on eth0 :: tcpdump's status messages go to stderr, so you still see them
N packets captured :: how many were written to the file
exit status 124 :: this is timeout saying it stopped tcpdump: normal here" \
    expect=any lab=1 needs="tcpdump curl"
  practical title="Read the conversation back from the file" \
    goal="Analyse offline: no sudo needed to read a capture you own." \
    cmd="tcpdump -nn -r evidence/web.pcap" \
    anatomy="-r FILE :: read packets from a file instead of a live interface" \
    read="[S] [S.] [.] :: the handshake
[P.] … length 78 :: the client's HTTP request (the payload length)
[P.] … HTTP/1.0 200 OK :: the server's response
[F.] … :: the FIN exchange that closes the connection" \
    lab=1 needs=tcpdump
  [[ -s $EVID/web.pcap ]] && decode_packet "$EVID/web.pcap" "tcp[tcpflags] == tcp-syn" "the client's SYN"
  pageturn

  section "Refused vs timed out: reading failure correctly"
  say "When a TCP connection fails, {b}how{/} it fails tells you where to look. A closed port on a live host answers immediately with {b}RST{/} ('nobody here'): you get 'Connection refused'. A firewall that silently drops packets gives no answer at all: the client retries until it gives up with 'timed out'."
  practical title="Connect to a port where nothing listens" \
    goal="See 'Connection refused' and understand what it proves." \
    cmd="sudo ip netns exec c1-student curl -sS --max-time 3 http://10.77.2.20:9999/" \
    anatomy="curl :: a command-line HTTP client
-sS :: silent, but still show errors
--max-time 3 :: give up after 3 seconds" \
    predict="Refused or timed out? What does your answer tell you about the network path?" \
    read="Failed to connect … Connection refused :: a RST came back: the HOST is alive and reachable, the PORT is closed" \
    expect=fail lab=1 needs=curl
  practical title="Capture the RST" \
    goal="Prove it with packets: one SYN, one RST." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -c 2 tcp port 9999" \
    anatomy="tcp port 9999 :: only the failed connection attempt" \
    bg="ip netns exec c1-student curl -s --max-time 2 http://10.77.2.20:9999/" \
    read="Flags [S] :: the client asks to connect
Flags [R.] :: the server's kernel answers RESET (+ACK): no program listens on 9999" \
    explain="This is exactly how an Nmap scan labels a port 'closed'. If the SYN had vanished without any answer (a firewall DROP), Nmap would say 'filtered' and curl would say 'timed out'. In module 10 you build both behaviours yourself." \
    lab=1 needs="tcpdump curl"
  pageturn

  section "UDP: fire and forget"
  say "{b}UDP{/} has no handshake, no sequence numbers, no acknowledgements and no retransmission: an 8-byte header and the data. That makes it fast and simple, perfect for DNS, DHCP, NTP, voice, video, games and QUIC (HTTP/3). Reliability, if needed, is the application's job."
  practical title="Send a UDP datagram with nothing but bash" \
    goal="Bash can write to /dev/udp/HOST/PORT. The lab's UDP listener on the server logs what arrives." \
    cmd="sudo ip netns exec c1-student bash -c 'echo hello-udp > /dev/udp/10.77.2.20/5300'" \
    anatomy="bash -c '…' :: run a small bash command inside the student host
/dev/udp/10.77.2.20/5300 :: a bash feature: writing here sends one UDP datagram" \
    read="(no output) :: of course: UDP never confirms anything" \
    lab=1 needs=bash
  practical title="Did it arrive? Read the server's log" \
    goal="With UDP the sender cannot know. Only the receiver can tell you." \
    cmd="tail -n 3 logs/svc-udp.log" \
    anatomy="tail -n 3 :: the last three lines of a file
logs/svc-udp.log :: the UDP listener's log (in your lab folder)" \
    read="from 10.77.1.10:PORT 10 bytes: b'hello-udp\\n' :: source address, size and content of the datagram" \
    lab=1 needs=tail
  practical title="UDP to a closed port: the ICMP answer" \
    goal="UDP has no RST. A closed UDP port is reported with an ICMP 'port unreachable' message instead." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -c 2 udp port 5301 or icmp" \
    anatomy="udp port 5301 or icmp :: our datagram, and any ICMP that comes back" \
    bg="ip netns exec c1-student bash -c 'echo probe > /dev/udp/10.77.2.20/5301'" \
    read="UDP, length 6 :: the datagram to port 5301
ICMP 10.77.2.20 udp port 5301 unreachable :: the server's kernel: 'nobody listens there'" \
    explain="Silence is ambiguous with UDP: an open port that ignores you looks exactly like a firewall that drops you. Only the ICMP message proves 'closed'. This is why UDP scanning is slow and uncertain (module 13), and why blocking ALL ICMP makes troubleshooting much harder." \
    lab=1 needs=tcpdump

  section "ICMP: the network's error messages"
  figure "The ICMP messages you will meet most" <<'EOF'
  TYPE  NAME                     WHO SENDS IT, AND WHY
  0     Echo Reply               the answer to ping
  8     Echo Request             ping
  3     Destination Unreachable  code 0 net, 1 host, 3 PORT (closed UDP port),
                                 4 frag needed (MTU, module 12), 13 admin-prohibited
  11    Time Exceeded            a router: the TTL reached 0 (traceroute, module 08)
  5     Redirect                 a router: 'use a better gateway' (usually disabled)
EOF
  callout security "ICMP can be abused (ping sweeps for discovery, data tunnelled inside echo payloads), but blocking all of it breaks path-MTU discovery and error reporting. Good policy allows the useful types and rate-limits the rest."
  reflect "Your browser says 'connection timed out' for a server, but a colleague gets 'connection refused'. What does each message tell you about the path between each of you and the server?" \
    "Refused = a RST came back: the server host is reachable and answering, the port is simply closed. Timed out = nothing came back: packets are being dropped somewhere (a firewall, a routing problem, a down host). The colleague reaches the host; you do not."
  quiz "Which flags does the SECOND packet of a TCP handshake carry?" B "SYN, then SYN+ACK, then ACK." "SYN" "SYN and ACK" "ACK" "FIN"
  quiz "A UDP datagram is sent to a closed port. What normally comes back?" C "UDP has no RST; the receiving kernel sends ICMP Destination Unreachable, code 3 (port unreachable)." "A TCP RST" "Nothing, ever" "ICMP port unreachable" "A DNS error"
  quiz "Which 5 values identify one TCP or UDP conversation?" A "Protocol + source IP + source port + destination IP + destination port: the 5-tuple." "Protocol, source IP, source port, destination IP, destination port" "MAC, IP, port, TTL, flags" "Source IP, destination IP, TTL, length, checksum" "Interface, gateway, mask, DNS, port"
  takeaways "Ports select the program; clients use random ephemeral ports, servers well-known ones." \
    "TCP = handshake (S, S., .), sequence and ack numbers, retransmission, and FIN or RST to finish." \
    "Refused (RST) = host reachable, port closed. Timed out = something dropped the packets." \
    "UDP = no handshake, no confirmation; closed UDP ports answer with ICMP port unreachable."
  mark_done
}

# ----------------------------------------------------------------- 07 -------
ensure_web_pcap(){
  [[ -s $EVID/web.pcap ]] && return 0
  lab_ready || return 0
  info "The academy is recording a fresh web conversation into evidence/web.pcap (normally created in module 06)…"
  cap_bg "$NS_STU" eth0 "$EVID/web.pcap" 10 tcp port 8000
  sleep 1.5
  priv "ip netns exec $NS_STU curl -s -o /dev/null http://$SRV_IP:8000/" >/dev/null 2>&1
  sleep 1.5
  priv "pkill -INT -f -- '-w $EVID/web.pcap' || true" >/dev/null 2>&1
  cap_wait "$EVID/web.pcap"
}

module07(){
  module_open 07 "${MOD_TITLE[7]}" "${MOD_MIN[7]}" "${MOD_TRACK[7]}"
  objectives "Capture packets to a file safely and read them back" \
    "Choose between tcpdump, tshark and Wireshark" \
    "Write capture filters (BPF) and display filters, and know the difference" \
    "Read any tcpdump line, and dissect a packet byte by byte"

  section "Why packets are the ground truth"
  say "Logs say what a program {i}thinks{/} happened. Packets show what {b}actually{/} crossed the wire. When two teams argue ('the firewall blocks us' vs 'the server never answers'), a capture at the right point ends the argument in minutes."
  callout warn "Capturing traffic you are not authorised to see is illegal in most countries, and a PCAP may contain passwords, cookies and personal data. Capture only in labs or with written permission, store PCAPs with restricted permissions, and delete them when the job is done."
  terms "tcpdump :: Command-line capture and display. Available on almost every Linux box and network appliance." \
        "tshark :: Wireshark's command-line twin: the same decoders and display filters, scriptable." \
        "Wireshark :: Graphical analyser: colour rules, 'Follow TCP Stream', statistics." \
        "PCAP / PCAPNG :: The file formats all three read and write."

  section "Two kinds of filters (do not mix them up)"
  figure "Capture filters decide what is RECORDED; display filters decide what is SHOWN" <<'EOF'
  GOAL               CAPTURE FILTER (BPF)             DISPLAY FILTER (Wireshark)
                     tcpdump, while capturing         Wireshark / tshark -Y, afterwards
  one host           host 10.77.2.20                  ip.addr == 10.77.2.20
  source only        src host 10.77.1.10              ip.src == 10.77.1.10
  a TCP port         tcp port 8000                    tcp.port == 8000
  pings              icmp                             icmp
  ARP                arp                              arp
  SYN packets        'tcp[tcpflags] & tcp-syn != 0'   tcp.flags.syn == 1
  DNS                udp port 53                      dns
  all except SSH     not port 22                      !(tcp.port == 22)
EOF
  figure "tcpdump options you will use every day" <<'EOF'
  -i IF   interface           -n / -nn  no name / no port lookups   -c N   stop after N
  -e      show MAC addresses  -v / -vv  more header detail           -A     payload as text
  -X/-XX  hex + text dump     -w FILE   write a PCAP                 -r F   read a PCAP
  -U      unbuffered writes   -l        line-buffered output         -D     list interfaces
EOF
  pageturn

  section "Anatomy of a tcpdump line"
  figure "Learn to read this line without thinking" <<'EOF'
 14:02:11.482913 IP 10.77.1.10.51514 > 10.77.2.20.8000: Flags [S], seq 271, win 64240, length 0
 └─ timestamp ─┘ │  └─ src IP.port ─┘   └ dst IP.port ┘  └ flags ┘  └seq┘  └window┘  └payload┘
                 └ layer-3 protocol
EOF
  practical title="Capture four ICMP packets into a file" \
    goal="Make your own evidence file: two pings from the student to its gateway, recorded on the student's interface." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -c 4 -w - icmp > evidence/icmp.pcap" \
    anatomy="-c 4 :: two echo requests + two echo replies
-w - :: binary PCAP to stdout…
> evidence/icmp.pcap :: …redirected by your shell into a file you own
icmp :: capture filter: only ICMP" \
    bg="ip netns exec c1-student ping -c 2 -i 0.3 10.77.1.1" \
    read="listening on eth0, link-type EN10MB (Ethernet) :: EN10MB = standard Ethernet framing
4 packets captured :: the file now holds exactly four packets" \
    lab=1 needs=tcpdump
  practical title="Read the capture back" \
    goal="The default view: one line per packet." \
    cmd="tcpdump -nn -r evidence/icmp.pcap" \
    anatomy="-r evidence/icmp.pcap :: read from the file (no sudo needed: you own it)" \
    read="ICMP echo request, id N, seq 1 :: question number 1 from ping process N
ICMP echo reply, id N, seq 1 :: the matching answer (same id and seq)" \
    lab=1 needs=tcpdump
  practical title="Ask tcpdump for more detail" \
    goal="-v decodes the IP header too: TTL, ID, flags, total length." \
    cmd="tcpdump -nn -v -r evidence/icmp.pcap" \
    anatomy="-v :: verbose: show IP header fields" \
    read="ttl 64 :: Linux sends with TTL 64 (Windows usually 128): a hint for OS fingerprinting
id :: the IP identification field
flags [DF] :: Don't Fragment is set
proto ICMP (1) :: the protocol number inside IP
length 84 :: 20 bytes IP header + 8 bytes ICMP header + 56 bytes of data" \
    lab=1 needs=tcpdump
  practical title="See the raw bytes" \
    goal="-XX prints every byte of the first packet in hex (left) and as text (right)." \
    cmd="tcpdump -nn -XX -c 1 -r evidence/icmp.pcap" \
    anatomy="-XX :: hex and ASCII dump, including the Ethernet header
-c 1 :: only the first packet" \
    read="0x0000: :: the byte offset of the line (16 bytes per line)
02c1 dc01 0001 :: the first six bytes: the destination MAC
0800 :: the EtherType (IPv4) at offset 12" \
    lab=1 needs=tcpdump
  [[ -s $EVID/icmp.pcap ]] && decode_packet "$EVID/icmp.pcap" "icmp" "your first echo request"
  callout tip "Open the same file in Wireshark ({c}wireshark ~/c1dc-network-labs/evidence/icmp.pcap &{/} in a second terminal) and click each header in the middle pane: you will recognise every field from the table above."
  pageturn

  section "tshark: Wireshark's power on the command line"
  practical title="Summarise a capture with tshark" \
    goal="The same one-line-per-packet view, from Wireshark's decoders." \
    cmd="tshark -r evidence/icmp.pcap" \
    anatomy="tshark -r FILE :: read a capture file" \
    read="No. Time Source -> Destination Protocol Length Info :: Wireshark's columns, as text" \
    lab=1 needs=tshark
  practical title="Pull out exactly the fields you need" \
    goal="Analysts extract fields to build timelines and spreadsheets." \
    cmd="tshark -r evidence/icmp.pcap -T fields -e frame.number -e ip.src -e ip.dst -e ip.ttl -e icmp.type" \
    anatomy="-T fields :: output selected fields only, tab-separated
-e NAME :: a Wireshark field name (in Wireshark: right-click a field > Copy > Field Name)" \
    read="icmp.type 8 / 0 :: request / reply
ip.ttl :: 64 from both hosts here (both are Linux)" \
    lab=1 needs=tshark
  ensure_web_pcap
  practical title="A capture filter on a saved file: only SYN packets" \
    goal="BPF can test individual bits. tcp[tcpflags] is the flags byte of the TCP header." \
    cmd="tcpdump -nn -r evidence/web.pcap 'tcp[tcpflags] & tcp-syn != 0'" \
    anatomy="'…' :: quotes stop the shell from interpreting [ ] and &
tcp[tcpflags] :: the TCP flags byte
& tcp-syn != 0 :: keep packets whose SYN bit is set" \
    read="[S] and [S.] :: the client's SYN and the server's SYN-ACK: both have the SYN bit" \
    lab=1 needs=tcpdump
  practical title="A display filter with tshark: only HTTP requests" \
    goal="Display filters understand protocols, here HTTP." \
    cmd="tshark -r evidence/web.pcap -Y http.request" \
    anatomy="-Y FILTER :: a Wireshark display filter, applied when reading" \
    read="GET / HTTP/1.1 :: the request line, decoded by Wireshark's HTTP dissector" \
    lab=1 needs=tshark
  callout turn "In Wireshark, open evidence/web.pcap, right-click any packet and choose {b}Follow > TCP Stream{/}. You will see the whole HTTP conversation as text: request in one colour, response in the other. Then try the display filter {c}tcp.flags.reset == 1{/}."
  reflect "You must find out why a server is slow, but its link carries 900 Mbit/s of backups. Would you use a capture filter or a display filter, and why?" \
    "A capture filter (e.g. host SERVER and tcp port 443): it stops irrelevant traffic from ever being recorded, saving disk and CPU and avoiding dropped packets. Display filters only hide packets that were already captured."
  quiz "Which is a Wireshark DISPLAY filter rather than a BPF capture filter?" C "ip.addr == X is display-filter syntax; 'host X' is BPF." "host 10.77.2.20" "tcp port 80" "ip.addr == 10.77.2.20" "not port 22"
  quiz "Why do we write captures with '-w - > file' in this course?" B "With -w -, tcpdump writes to stdout and YOUR shell creates the file, so you own it. tcpdump itself drops root privileges and may not be allowed to write into your home directory." "It is faster" "Your own shell creates the file, so you own it" "It encrypts the file" "It compresses the file"
  takeaways "Packets are ground truth; capture only with authorisation and protect your PCAPs." \
    "Capture filters (BPF) choose what is recorded; display filters choose what is shown." \
    "Read lines as: time, protocol, src.port > dst.port, flags, seq/ack, length." \
    "tshark -T fields -e … turns captures into data you can sort, count and report."
  mark_done
}

# ----------------------------------------------------------------- 08 -------
journey_cmp(){ # journey_cmp FIELD A B [verdict-if-different]
  if [[ $2 == "$3" ]]; then printf '  %-17s %-21s %-21s %s= unchanged%s\n' "$1" "$2" "$3" "$BGRN" "$RST"
  else printf '  %-17s %-21s %-21s %s%s %s%s\n' "$1" "$2" "$3" "$BYEL" "$ARR" "${4:-rewritten}" "$RST"; fi
}
journey_compare(){
  local a="$EVID/journey-lanA.pcap" b="$EVID/journey-lanB.pcap"
  local HA HB a_sm a_dm a_si a_di a_tt b_sm b_dm b_si b_di b_tt
  HA=$(pcap_hex "$a" "icmp[icmptype] == icmp-echo" 1); HB=$(pcap_hex "$b" "icmp[icmptype] == icmp-echo" 1)
  if ((${#HA} < 68 || ${#HB} < 68)); then warn "The academy's captures did not record the ping. Run this module again."; return 0; fi
  HEX=$HA; a_sm=$(hmac 6); a_dm=$(hmac 0); a_si=$(hip 26); a_di=$(hip 30); a_tt=$(hd 22 1)
  HEX=$HB; b_sm=$(hmac 6); b_dm=$(hmac 0); b_si=$(hip 26); b_di=$(hip 30); b_tt=$(hd 22 1)
  printf '\n  %s THE SAME PACKET, SEEN ON BOTH SIDES OF THE ROUTER %s\n\n' "$BMAG$REV" "$RST"
  printf '  %s%-17s %-21s %-21s %s%s\n' "$BOLD" "FIELD" "LAN A (router eth0)" "LAN B (router eth1)" "VERDICT" "$RST"
  journey_cmp "Source MAC" "$a_sm" "$b_sm"
  journey_cmp "Destination MAC" "$a_dm" "$b_dm"
  journey_cmp "Source IP" "$a_si" "$b_si"
  journey_cmp "Destination IP" "$a_di" "$b_di"
  journey_cmp "TTL" "$a_tt" "$b_tt" "decremented by the router"
  echo
  say "Read it slowly. The router {b}stripped{/} the old Ethernet header (student → router), looked at the destination {b}IP{/}, found a route, {b}decremented the TTL{/} ($a_tt → $b_tt, so it also recomputed the IP checksum) and wrapped the packet in a {b}brand-new{/} Ethernet header (router eth1 → server). The IP addresses never changed. That is routing."
}

lpm_drill(){
  figure "A routing table: the kernel picks the LONGEST matching prefix" <<'EOF'
  ROUTE              NEXT HOP
  default (0/0)      via 192.0.2.1    (A)  the ISP
  10.0.0.0/8         via 10.255.0.1   (B)  the corporate WAN
  10.77.0.0/16       via 10.77.0.1    (C)  the lab core
  10.77.2.0/24       dev eth1         (D)  directly connected
EOF
  say "For each destination choose the route the router uses. Several may match; the most specific (longest prefix) wins."
  quiz "Destination 10.77.2.20?" D "/24 is the longest match: directly connected on eth1." "A" "B" "C" "D"
  quiz "Destination 10.77.9.9?" C "It matches /8 and /16 (not the /24); /16 is longer." "A" "B" "C" "D"
  quiz "Destination 10.1.2.3?" B "Only 10.0.0.0/8 and the default match; /8 wins." "A" "B" "C" "D"
  quiz "Destination 8.8.8.8?" A "Nothing specific matches, so the default route (/0) is used." "A" "B" "C" "D"
}

module08(){
  module_open 08 "${MOD_TITLE[8]}" "${MOD_MIN[8]}" "${MOD_TRACK[8]}"
  objectives "Read a routing table and apply longest-prefix match" \
    "Describe exactly what a router does to every packet" \
    "Prove with captures that MACs change per hop while IPs stay" \
    "Use TTL and traceroute; switch IP forwarding off and on" \
    "Explain return paths, and build source NAT with nftables"

  section "The routing table"
  say "Every host and router keeps a {b}routing table{/}: a list of destination networks and how to reach each one. For every packet the kernel finds all routes that match the destination and picks the {b}most specific{/} one (the longest prefix). The {b}default route{/} (0.0.0.0/0) matches everything, so it is used only when nothing better exists."
  figure "Reading the lines of 'ip route'" <<'EOF'
  default via 10.77.1.1 dev eth0             ← no better match? send to 10.77.1.1
  10.77.1.0/24 dev eth0 proto kernel scope link src 10.77.1.10
  └─ network ─┘ └iface─┘ └─ added by the ─┘ └directly┘ └─my address─┘
                         kernel with the IP  connected   on that net
EOF
  practical title="Your own routing table" \
    goal="Find your default gateway and the networks you reach directly." \
    cmd="ip route show" \
    anatomy="route show :: print the main routing table (IPv4)" \
    read="default via X dev Y :: your default gateway X, reached through interface Y
NET/PREFIX dev Y scope link :: a directly connected network (no gateway needed)
proto dhcp / kernel / static :: who added the route
metric N :: preference when two routes are equally specific (lower wins)" \
    needs=ip
  practical title="The lab router's table" \
    goal="A router with no routing protocol knows only its own connected networks, and that is enough here." \
    cmd="sudo ip -n c1-router route" \
    anatomy="ip -n c1-router route :: the routing table inside the router namespace" \
    read="10.77.1.0/24 dev eth0 :: LAN A, directly connected
10.77.2.0/24 dev eth1 :: LAN B, directly connected
(no default route) :: the lab has no Internet: anything else is unreachable" \
    lab=1 needs=ip
  section "Longest-prefix match drill"
  lpm_drill
  pageturn

  section "What a router does to every packet"
  numbered "Receive a frame addressed to its own MAC; strip the Ethernet header." \
    "Read the destination IP. One of MY addresses? Deliver locally. Otherwise forward (only if forwarding is enabled)." \
    "Look up the longest matching route. No match: drop it and send ICMP 'network unreachable'." \
    "Decrement the TTL. If it reaches 0: drop it and send ICMP 'time exceeded' to the source." \
    "Recompute the IP header checksum (the TTL changed)." \
    "ARP for the next hop's MAC, build a NEW Ethernet header, send it out of the chosen interface."
  practical title="Follow one packet through the router" \
    goal="The academy records on BOTH router interfaces while you ping the server once. Then we compare the two copies." \
    cmd="sudo ip netns exec c1-student ping -c 1 10.77.2.20" \
    anatomy="ping -c 1 :: exactly one echo request (and its reply)" \
    predict="Which fields will be different on the two sides of the router?" \
    pre="rm -f '$EVID/journey-lanA.pcap' '$EVID/journey-lanB.pcap'; setsid -f ip netns exec c1-router timeout 10 tcpdump -i eth0 -nn -U -Z root -c 2 -w '$EVID/journey-lanA.pcap' icmp >/dev/null 2>&1; setsid -f ip netns exec c1-router timeout 10 tcpdump -i eth1 -nn -U -Z root -c 2 -w '$EVID/journey-lanB.pcap' icmp >/dev/null 2>&1; sleep 1.2" \
    lab=1 needs="ping tcpdump"
  if lab_ready && [[ -e $EVID/journey-lanA.pcap ]]; then cap_wait "$EVID/journey-lanA.pcap" "$EVID/journey-lanB.pcap"; journey_compare; fi
  pageturn

  section "TTL and traceroute"
  say "Every IP packet carries a {b}Time To Live{/}: a hop counter that each router decreases by one. It exists to kill packets caught in routing loops. When it hits 0 the router discards the packet and tells the sender with ICMP {b}Time Exceeded{/}. traceroute uses this on purpose: it sends probes with TTL 1, 2, 3… and lists who complains at each step."
  practical title="Make a packet die at the first router" \
    goal="Send a ping with TTL 1. The router must decrement it to 0 and refuse to forward it." \
    cmd="sudo ip netns exec c1-student ping -c 1 -t 1 10.77.2.20" \
    anatomy="-t 1 :: set the TTL of outgoing packets to 1" \
    predict="Who will answer: the server, the router, or nobody?" \
    read="From 10.77.1.1 icmp_seq=1 Time to live exceeded :: the ROUTER answered, not the server
100% packet loss :: no echo reply came back from the target" \
    expect=fail lab=1 needs=ping
  practical title="traceroute: map every hop" \
    goal="List each router on the path." \
    cmd="sudo ip netns exec c1-student traceroute -n 10.77.2.20" \
    anatomy="traceroute :: send probes with increasing TTL (UDP to high ports by default)
-n :: numeric output only" \
    read="1  10.77.1.1  … ms :: hop 1: the router said 'time exceeded' to the TTL=1 probes
2  10.77.2.20  … ms :: hop 2: the destination itself ('port unreachable' ends the trace)
three times per hop :: three probes per TTL; * means no answer (often a firewall)" \
    lab=1 needs=traceroute
  pageturn

  section "A router is just a host with forwarding switched on"
  practical title="Switch the router's forwarding OFF" \
    goal="Linux forwards packets between interfaces only when net.ipv4.ip_forward = 1." \
    cmd="sudo ip netns exec c1-router sysctl -w net.ipv4.ip_forward=0" \
    anatomy="sysctl -w KEY=VALUE :: change a kernel setting (here only inside the router namespace)" \
    read="net.ipv4.ip_forward = 0 :: confirmation of the new value" \
    verify="[ \$(ip netns exec c1-router sysctl -n net.ipv4.ip_forward) = 0 ]" \
    lab=1 needs=sysctl
  practical title="Ping the server again" \
    goal="Same command as before. Nothing else changed." \
    cmd="sudo ip netns exec c1-student ping -c 2 -W 1 10.77.2.20" \
    anatomy="-W 1 :: wait at most 1 second for each reply" \
    predict="What will happen now: an error message, or just silence?" \
    read="100% packet loss :: the router received the packets and silently refused to forward them" \
    expect=fail lab=1 needs=ping
  practical title="Switch forwarding back ON" \
    goal="Restore the router." \
    cmd="sudo ip netns exec c1-router sysctl -w net.ipv4.ip_forward=1" \
    anatomy="=1 :: forwarding enabled" \
    verify="ip netns exec c1-student ping -c 1 -W 1 10.77.2.20" \
    lab=1 needs=sysctl
  callout security "Any machine with two interfaces and forwarding enabled is a router, whether its owner knows it or not. A compromised dual-homed host (one leg in the office LAN, one in a sensitive network) becomes a {b}pivot{/} for attackers. Auditors check net.ipv4.ip_forward on servers that should never route."
  pageturn

  section "Return paths: both directions must work"
  say "A ping needs TWO successful journeys: the request there and the reply back. The server must also know how to reach the student's network. Let us break the way back on purpose."
  practical title="Remove the server's default route" \
    goal="The server will still receive requests but will not know where to send the replies." \
    cmd="sudo ip -n c1-server route del default" \
    anatomy="route del default :: delete the default route (0.0.0.0/0)" \
    lab=1 needs=ip
  practical title="Ping the server from the student" \
    goal="Requests still arrive at the server. What about the replies?" \
    cmd="sudo ip netns exec c1-student ping -c 2 -W 1 10.77.2.20" \
    anatomy="(the same ping as before)" \
    read="100% packet loss :: from the student's point of view, identical to a dead server" \
    explain="A capture on the server would show the echo requests ARRIVING, with no replies leaving: the server has no route back to 10.77.1.0/24. This one-way failure misleads many engineers, which is why ticket #10 (menu T) makes you diagnose it on your own." \
    expect=fail lab=1 needs=ping
  practical title="Fix it with a specific static route" \
    goal="Instead of a default route, tell the server exactly how to reach LAN A." \
    cmd="sudo ip -n c1-server route add 10.77.1.0/24 via 10.77.2.1" \
    anatomy="route add 10.77.1.0/24 :: a route for exactly the student's network
via 10.77.2.1 :: the next hop: the router's LAN B address" \
    verify="ip netns exec c1-student ping -c 1 -W 1 10.77.2.20" \
    after="ip -n c1-server route del 10.77.1.0/24; ip -n c1-server route add default via 10.77.2.1" \
    lab=1 needs=ip
  pageturn

  section "NAT: rewriting addresses on purpose"
  figure "Source NAT (masquerade): many private hosts share one address" <<'EOF'
  BEFORE the router:  10.77.1.10:51514 → 10.77.2.20:8000
  AFTER  the router:  10.77.2.1:51514  → 10.77.2.20:8000     (source rewritten)
  The router remembers the mapping in its connection-tracking table and
  rewrites the replies back:  10.77.2.20:8000 → 10.77.1.10:51514
EOF
  terms "SNAT / masquerade :: Rewrite the SOURCE address: how a home router shares one public IP among all your devices (with ports: PAT)." \
        "DNAT / port forward :: Rewrite the DESTINATION: 'traffic to my public IP on port 443 goes to the internal web server'." \
        "NAT is not a firewall :: NAT hides internal addresses as a side effect; the security comes from the stateful filtering that usually runs next to it."
  practical title="Create a NAT table on the router" \
    goal="nftables keeps rules in tables. Create one for NAT (family ip = IPv4)." \
    cmd="sudo ip netns exec c1-router nft add table ip c1nat" \
    anatomy="nft :: the nftables firewall tool (module 10 explains it fully)
add table ip c1nat :: a new, empty table called c1nat for IPv4" \
    lab=1 needs=nft
  practical title="Hook a chain into post-routing" \
    goal="Source NAT happens AFTER the routing decision, just before the packet leaves." \
    cmd="sudo ip netns exec c1-router nft 'add chain ip c1nat post { type nat hook postrouting priority 100 ; }'" \
    anatomy="add chain ip c1nat post :: a chain named post in the table c1nat
type nat hook postrouting :: a NAT chain attached to the postrouting hook
priority 100 :: the standard priority for source NAT" \
    lab=1 needs=nft
  practical title="Masquerade everything leaving on eth1" \
    goal="Rewrite the source of packets going towards LAN B to the router's own address." \
    cmd="sudo ip netns exec c1-router nft add rule ip c1nat post oifname eth1 masquerade" \
    anatomy="oifname eth1 :: match packets whose OUTPUT interface is eth1
masquerade :: replace the source IP with the outgoing interface's address" \
    lab=1 needs=nft
  practical title="Prove it: what does the SERVER see?" \
    goal="Capture on the server while the student pings it." \
    cmd="sudo ip netns exec c1-server tcpdump -i eth0 -nn -c 2 icmp" \
    anatomy="(capture on the server's only interface)" \
    predict="Which source address will the server see in the echo request?" \
    bg="ip netns exec c1-student ping -c 1 -W 1 10.77.2.20" \
    read="IP 10.77.2.1 > 10.77.2.20: ICMP echo request :: the server sees the ROUTER, not the student
IP 10.77.2.20 > 10.77.2.1: ICMP echo reply :: the reply goes to the router, which translates it back" \
    explain="Connection tracking (conntrack) remembers 'echo id N from 10.77.1.10 was rewritten' and reverses the change on the reply. The forensic consequence: the server's logs now show only the router's IP. To find the real client, investigators need the NAT device's logs." \
    lab=1 needs=tcpdump
  practical title="Remove the NAT table" \
    goal="Return the lab to its normal, un-NATed state." \
    cmd="sudo ip netns exec c1-router nft delete table ip c1nat" \
    anatomy="delete table :: removes the table and every chain and rule inside it" \
    verify="! ip netns exec c1-router nft list table ip c1nat" \
    lab=1 needs=nft
  reflect "The student can ping the server, but a capture on the server shows every connection coming from 10.77.2.1. Explain why, and what an investigator would need to identify the real client." \
    "Source NAT (masquerade) on the router rewrites the source address to its own. The real client is recorded only in the router's connection-tracking state or NAT logs, so the investigator needs logs from the NAT device, with accurate timestamps, to map 10.77.2.1:PORT back to 10.77.1.10."
  quiz "A router receives a packet with TTL=1 that must be forwarded. What happens?" B "The TTL is decremented to 0; the router drops the packet and returns ICMP Time Exceeded." "TTL becomes 2" "It is dropped and ICMP Time Exceeded goes back" "It is forwarded unchanged" "DNS is queried"
  quiz "Which header fields does a normal router rewrite when forwarding?" C "A new Ethernet header (both MACs), TTL minus 1, a new IP checksum. IP addresses stay, unless NAT is configured." "Source and destination IP" "Nothing at all" "The MAC addresses and the TTL" "The TCP ports"
  takeaways "Routing tables are matched by longest prefix; the default route is the last resort." \
    "Routers rewrite MACs and decrement TTL at every hop; IP addresses stay end-to-end." \
    "traceroute uses TTL expiry to reveal hops; forwarding is just a kernel switch." \
    "Every conversation needs a working return path; NAT rewrites addresses and hides the real client."
  mark_done
}

# ----------------------------------------------------------------- 09 -------
module09(){
  module_open 09 "${MOD_TITLE[9]}" "${MOD_MIN[9]}" "${MOD_TRACK[9]}"
  objectives "Explain how a switch learns, forwards, floods and ages MAC addresses" \
    "Watch a real MAC address table fill up" \
    "Explain 802.1Q VLAN tags, access ports and trunks" \
    "Build a VLAN interface and capture a tagged frame" \
    "Explain why traffic between VLANs must pass a router, where policy lives"

  section "How a switch thinks"
  say "A switch keeps a {b}MAC address table{/} (also called the CAM table or forwarding database): 'MAC X lives behind port Y'. It builds the table by watching the {b}source{/} MAC of every frame that arrives. For each frame it then decides what to do based on the {b}destination{/} MAC:"
  terms "Learn :: Frame arrives on port 2 from MAC A → remember 'A is on port 2' (for about 300 seconds)." \
        "Forward :: Destination MAC is in the table → send the frame out of that one port only." \
        "Flood :: Destination unknown, broadcast (ff:ff:…) or multicast → send it out of EVERY port except the one it came in on." \
        "Filter :: Destination is on the same port it came from → drop it." \
        "Age :: Entries not refreshed are deleted, so devices can move."
  terms "Broadcast domain :: All devices that receive each other's broadcasts: one LAN / one VLAN. Routers end broadcast domains." \
        "Collision domain :: Devices that share one half-duplex medium. Every switch port is its own; hubs share one."
  pageturn

  section "Watch the switch learn"
  practical title="Look at the switch's ports" \
    goal="Our switch is a Linux bridge called br0 inside the c1-switch namespace." \
    cmd="sudo ip netns exec c1-switch bridge link" \
    anatomy="bridge :: the iproute2 tool for Linux bridges (software switches)
link :: list the bridge ports" \
    read="sw-student, sw-peer, sw-router :: the three ports (each one end of a virtual cable)
master br0 :: the port belongs to the switch br0
state forwarding :: the port is passing traffic (other states: blocking, listening, learning, used by STP)" \
    lab=1 needs=bridge
  practical title="Read the MAC address table after a flush" \
    goal="The academy empties the table first. You read what is left." \
    cmd="sudo ip netns exec c1-switch bridge fdb show br br0 dynamic" \
    anatomy="fdb :: forwarding database = the MAC address table
br br0 :: only the switch br0
dynamic :: only LEARNED entries (hide the switch's own permanent ones)" \
    pre="ip -n c1-switch link set br0 type bridge fdb_flush" \
    read="(empty or nearly empty) :: the switch has forgotten everyone; the next frames will be flooded" \
    lab=1 needs=bridge
  practical title="Generate traffic: the student pings the peer" \
    goal="Two hosts on the same LAN talk through the switch." \
    cmd="sudo ip netns exec c1-student ping -c 1 10.77.1.11" \
    anatomy="10.77.1.11 :: the peer PC, on the same LAN as the student" \
    lab=1 needs=ping
  practical title="Read the MAC address table again" \
    goal="See what the switch learned from those few frames." \
    cmd="sudo ip netns exec c1-switch bridge fdb show br br0 dynamic" \
    anatomy="(the same command as before)" \
    predict="Which MAC will be listed on port sw-student, and which on sw-peer?" \
    read="02:c1:dc:01:00:10 dev sw-student :: learned from the student's frames (its source MAC)
02:c1:dc:01:00:11 dev sw-peer :: learned from the peer's reply" \
    explain="The very first frame (the ARP broadcast) was flooded to every port; the switch learned the student's MAC from it. The peer's reply taught it the peer's MAC. From then on, frames between them go only to the right port. An attacker who floods a switch with thousands of fake source MACs can fill this table; some switches then flood everything like a hub (MAC flooding), which is why port security limits how many MACs one port may teach." \
    lab=1 needs=bridge
  pageturn

  section "VLANs: several LANs on one switch"
  say "A {b}VLAN{/} (Virtual LAN) splits one physical switch into several separate broadcast domains. Hosts in VLAN 10 and VLAN 20 may share the same switch, yet they cannot exchange a single frame directly. To travel between switches, frames carry a 4-byte {b}802.1Q tag{/} saying which VLAN they belong to."
  figure "An Ethernet frame with an 802.1Q tag" <<'EOF'
  ┌────────┬────────┬───────────────────────────┬──────────┬─────────┬─────┐
  │ dst MAC│ src MAC│ 802.1Q TAG (4 bytes)      │ EtherType│ payload │ FCS │
  │ 6 B    │ 6 B    │ TPID 0x8100 │PCP│DEI│VID  │ 0x0800   │         │     │
  └────────┴────────┴─────────────┴───┴───┴─────┴──────────┴─────────┴─────┘
                     'a tag follows' 3b  1b  12 bits → VLAN 1-4094
EOF
  terms "Access port :: Belongs to ONE VLAN; the switch adds/removes tags, so the PC never sees them." \
        "Trunk port :: Carries MANY VLANs between switches (or to a router or hypervisor), each frame tagged." \
        "Native VLAN :: The one VLAN a trunk sends UNtagged. Mismatches here cause leaks." \
        "Inter-VLAN routing :: Traffic between VLANs must go through a router or layer-3 switch, which is exactly where a firewall policy can be applied."
  callout security "{b}VLAN hopping{/}: an attacker pretends to be a switch (DTP) to get a trunk, or double-tags frames to sneak into the native VLAN. Defences: disable DTP, set access ports to access mode, use an unused native VLAN. Remember: VLANs {b}separate{/} traffic, firewalls {b}control{/} it. A VLAN with routing and no policy is not a security boundary."
  practical title="Create a VLAN 10 interface on the student PC" \
    goal="Make the student PC a member of VLAN 10, as a server on a trunk port would be." \
    cmd="sudo ip -n c1-student link add link eth0 name eth0.10 type vlan id 10" \
    anatomy="link add … name eth0.10 :: create a new virtual interface called eth0.10
link eth0 :: on top of the physical eth0
type vlan id 10 :: frames sent through it get an 802.1Q tag with VLAN ID 10" \
    verify="ip -n c1-student -d link show eth0.10 | grep -q 'vlan protocol 802.1Q id 10'" \
    lab=1 needs=ip
  practical title="Give it an address in the VLAN 10 subnet" \
    goal="Each VLAN normally has its own IP subnet: here 10.77.10.0/24." \
    cmd="sudo ip -n c1-student addr add 10.77.10.10/24 dev eth0.10" \
    anatomy="addr add 10.77.10.10/24 dev eth0.10 :: an address for the VLAN interface" \
    lab=1 needs=ip
  practical title="Bring the VLAN interface up" \
    goal="New interfaces start DOWN." \
    cmd="sudo ip -n c1-student link set eth0.10 up" \
    anatomy="link set … up :: administratively enable the interface" \
    lab=1 needs=ip
  practical title="Capture a tagged frame" \
    goal="The academy gives the router a VLAN 10 interface (10.77.10.1: a 'router on a stick') and pings it from the student. You watch the tags on the wire." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -e -c 4 vlan" \
    anatomy="-e :: show the Ethernet header (needed to see the tag)
vlan :: capture filter: only 802.1Q-tagged frames" \
    predict="Which EtherType will appear first in each line: 0x0800 or 0x8100?" \
    pre="ip -n c1-router link add link eth0 name eth0.10 type vlan id 10 2>/dev/null; ip -n c1-router addr add 10.77.10.1/24 dev eth0.10 2>/dev/null; ip -n c1-router link set eth0.10 up" \
    bg="ip netns exec c1-student ping -c 1 -W 1 10.77.10.1" \
    read="ethertype 802.1Q (0x8100) :: a VLAN tag follows the MAC addresses
vlan 10, p 0 :: VLAN ID 10, priority (PCP) 0
ethertype ARP / IPv4 :: the real payload type, after the tag" \
    lab=1 needs=tcpdump
  practical title="Traffic between VLANs goes through the router" \
    goal="The peer (on untagged LAN A) reaches the student's VLAN 10 address. Which path does it take?" \
    cmd="sudo ip netns exec c1-peer traceroute -n 10.77.10.10" \
    anatomy="traceroute -n :: list the hops to the destination" \
    read="1 10.77.1.1 :: the router: inter-VLAN traffic MUST be routed
2 10.77.10.10 :: the student's VLAN 10 address" \
    explain="Even though both hosts plug into the same switch, traffic from LAN A to VLAN 10 goes up to the router and back down the same cable (a 'router on a stick'). That router hop is where an enterprise puts its firewall rules between, say, the guest VLAN and the finance VLAN." \
    after="ip -n c1-student link del eth0.10; ip -n c1-router link del eth0.10" \
    lab=1 needs=traceroute
  reflect "A manager says: 'The cameras are on their own VLAN, so they are isolated'. What question would you ask before agreeing?" \
    "Is there any routing between the camera VLAN and the others, and if so, what firewall policy controls it? A VLAN only separates layer 2; if a layer-3 interface routes it without filtering, the cameras are reachable from everywhere. Also check trunk and native-VLAN settings for hopping risks."
  quiz "A switch receives a frame for a destination MAC it has never seen. What does it do?" B "Unknown unicast is flooded out of every port in the VLAN except the incoming one." "Drops it" "Floods it to all other ports in that VLAN" "Sends it to the router" "Sends an ARP request"
  quiz "Two hosts in VLAN 10 and VLAN 20 must communicate. What is required?" C "Different VLANs = different broadcast domains; only a layer-3 device can move traffic between them, and that is where policy belongs." "A trunk port only" "A hub" "Inter-VLAN routing (and a policy deciding what is allowed)" "Nothing: same switch"
  takeaways "Switches learn source MACs, forward known destinations, flood unknown/broadcast, and age entries out." \
    "{c}bridge fdb show{/} reveals a Linux switch's MAC table; port security limits MAC flooding." \
    "802.1Q tags (0x8100 + a 12-bit VLAN ID) carry many VLANs over one trunk." \
    "VLANs separate; routers and firewalls control. No policy, no boundary."
  mark_done
}

# ----------------------------------------------------------------- 10 -------
module10(){
  module_open 10 "${MOD_TITLE[10]}" "${MOD_MIN[10]}" "${MOD_TRACK[10]}"
  objectives "Explain stateless vs stateful filtering, default-deny and least privilege" \
    "Name the netfilter hooks and pick the right one for a router" \
    "Build a stateful default-deny firewall with nftables, rule by rule" \
    "Show the difference between DROP and REJECT from the attacker's side" \
    "Read rule counters as evidence"

  section "What a firewall decides"
  say "A firewall compares each packet with an ordered list of rules: source and destination address, protocol, port, interface, and (for a {b}stateful{/} firewall) the {b}connection state{/}. The first matching rule gives the verdict: accept, drop or reject. If nothing matches, the chain's {b}policy{/} decides."
  terms "Stateless ACL :: Judges every packet alone. To allow web browsing you must also allow the replies explicitly, which is clumsy and easy to get wrong." \
        "Stateful firewall :: Tracks connections (conntrack). Allow the first packet; replies of an ESTABLISHED connection are then allowed automatically." \
        "Default deny :: Policy DROP, then allow only what is needed: least privilege for networks." \
        "DROP vs REJECT :: DROP = silence (the client times out; an attacker learns little, slowly). REJECT = an honest refusal (RST or ICMP; fast failure for legitimate users)." \
        "Ingress / egress :: Filtering traffic coming in vs going out. Egress filtering stops malware calling home and data leaving."
  figure "Netfilter hooks: where Linux lets a firewall inspect packets" <<'EOF'
   packet in ──► PREROUTING ──► routing ──┬──► INPUT ──► local program (this host)
                 (DNAT here)   decision   │                     │
                                          │                  OUTPUT
                                          ▼                     │
                                       FORWARD ──────────► POSTROUTING ──► packet out
                                 (a ROUTER filters here)    (SNAT here)
EOF
  say "Our lab router forwards traffic between LAN A and LAN B, so its policy belongs in the {b}FORWARD{/} hook. A server protecting itself would filter in INPUT."
  figure "nftables vocabulary" <<'EOF'
  TABLE  a container with a family:  ip (IPv4)  ip6  inet (both)  arp  bridge
  CHAIN  a list of rules; a 'base chain' is attached to a hook with a priority
         and has a policy (accept/drop) for packets that no rule matched
  RULE   matches + a verdict:  ip saddr 10.77.1.0/24 tcp dport 8000 accept
EOF
  pageturn

  section "Build a stateful firewall on the lab router"
  practical title="Start from an empty ruleset" \
    goal="Check that the router has no firewall yet." \
    cmd="sudo ip netns exec c1-router nft list ruleset" \
    anatomy="nft list ruleset :: print every table, chain and rule" \
    read="(no output) :: no rules at all: everything is allowed" \
    lab=1 needs=nft
  practical title="Create a table for both IPv4 and IPv6" \
    goal="The inet family covers both IP versions with one rule set. Forgetting IPv6 is a classic hole." \
    cmd="sudo ip netns exec c1-router nft add table inet c1fw" \
    anatomy="add table inet c1fw :: a table named c1fw in the inet (IPv4 + IPv6) family" \
    lab=1 needs=nft
  practical title="Attach a default-deny chain to the FORWARD hook" \
    goal="From this moment, nothing passes through the router unless a rule allows it." \
    cmd="sudo ip netns exec c1-router nft 'add chain inet c1fw forward { type filter hook forward priority 0 ; policy drop ; }'" \
    anatomy="'…' :: quotes, because { } and ; mean something to the shell
type filter hook forward :: a filtering chain on the forward hook
priority 0 :: order relative to other chains on the same hook
policy drop :: the verdict for packets that match no rule" \
    lab=1 needs=nft
  practical title="Test: can the student still reach the server?" \
    goal="The same ping as always." \
    cmd="sudo ip netns exec c1-student ping -c 2 -W 1 10.77.2.20" \
    anatomy="(the familiar ping)" \
    predict="Will you see an error message, or silence?" \
    read="100% packet loss, no error :: DROP is silent: the client cannot tell a firewall from a dead host" \
    expect=fail lab=1 needs=ping
  practical title="Rule 1: let replies of existing conversations through" \
    goal="The heart of a stateful firewall." \
    cmd="sudo ip netns exec c1-router nft add rule inet c1fw forward ct state established,related accept" \
    anatomy="ct state :: the conntrack state of the packet's connection
established :: belongs to a connection that was already allowed
related :: an associated packet, e.g. an ICMP error about an allowed connection
accept :: the verdict" \
    lab=1 needs=nft
  practical title="Rule 2: allow exactly one service, from one network" \
    goal="LAN A may use the intranet web server on TCP 8000. Nothing else." \
    cmd="sudo ip netns exec c1-router nft add rule inet c1fw forward ip saddr 10.77.1.0/24 ip daddr 10.77.2.20 tcp dport 8000 counter accept" \
    anatomy="ip saddr 10.77.1.0/24 :: source: anyone on LAN A
ip daddr 10.77.2.20 :: destination: the server only
tcp dport 8000 :: destination port 8000 only
counter :: count matching packets and bytes (evidence!)
accept :: the verdict" \
    lab=1 needs=nft
  practical title="Test the web service" \
    goal="Only the HTTP status code is printed." \
    cmd="sudo ip netns exec c1-student curl -s -o /dev/null -w '%{http_code}\n' http://10.77.2.20:8000/" \
    anatomy="-o /dev/null :: throw the page away
-w '%{http_code}\n' :: print only the HTTP status code" \
    read="200 :: the request passed the firewall: the SYN was allowed by rule 2, the replies by rule 1" \
    lab=1 needs=curl
  practical title="And ping?" \
    goal="We never allowed ICMP." \
    cmd="sudo ip netns exec c1-student ping -c 1 -W 1 10.77.2.20" \
    anatomy="(ping again)" \
    predict="The web works. Will ping work too?" \
    read="100% packet loss :: least privilege: only what was explicitly allowed passes" \
    explain="This is why 'ping works' and 'the service works' are two different questions. A host can answer ping and block 443, or (as here) serve 8000 and ignore ping. Always test the actual service." \
    expect=fail lab=1 needs=ping
  practical title="Rule 3: REJECT port 8443 instead of dropping it" \
    goal="Compare the attacker's view of DROP (the policy) and REJECT (this rule)." \
    cmd="sudo ip netns exec c1-router nft add rule inet c1fw forward tcp dport 8443 reject with tcp reset" \
    anatomy="tcp dport 8443 :: the HTTPS service
reject with tcp reset :: answer with a forged RST, as if no service listened" \
    lab=1 needs=nft
  practical title="Scan three ports through the firewall" \
    goal="8000 is allowed, 8443 is rejected (but the service IS running), 9000 falls to the drop policy." \
    cmd="sudo ip netns exec c1-student nmap -Pn -sT -p 8000,8443,9000 10.77.2.20" \
    anatomy="-Pn :: skip host discovery (our ping is blocked anyway)
-sT :: TCP connect scan
-p 8000,8443,9000 :: only these ports" \
    predict="Predict the state Nmap reports for each port: open, closed or filtered?" \
    read="8000/tcp open :: allowed by rule 2; the server answered SYN-ACK
8443/tcp closed :: the FIREWALL sent a RST: Nmap believes nothing listens (a lie: the TLS service is running)
9000/tcp filtered :: silence: the policy dropped the SYN, so Nmap cannot tell" \
    explain="'closed' does not always mean 'no service': a firewall can impersonate a closed port. And 'filtered' tells an attacker that a firewall exists. Defenders choose DROP or REJECT knowingly: DROP slows scanners down; REJECT gives legitimate users a fast, clear failure." \
    lab=1 needs=nmap
  practical title="Read the ruleset with handles and counters" \
    goal="Counters turn a firewall into an evidence source." \
    cmd="sudo ip netns exec c1-router nft -a list ruleset" \
    anatomy="-a :: show the handle number of every rule (needed to delete a single rule)" \
    read="policy drop :: the default verdict of the chain
ct state established,related accept :: rule 1
counter packets N bytes M :: how many packets matched rule 2 (curl + nmap)
# handle N :: the rule's ID: nft delete rule inet c1fw forward handle N" \
    lab=1 needs=nft
  practical title="Remove the lab firewall" \
    goal="Delete the whole table; reachability returns." \
    cmd="sudo ip netns exec c1-router nft delete table inet c1fw" \
    anatomy="delete table inet c1fw :: removes the table with all its chains and rules" \
    verify="ip netns exec c1-student ping -c 1 -W 1 10.77.2.20" \
    lab=1 needs=nft
  callout turn "Your own Kali host has a firewall too. Read it (read-only!) with {c}sudo nft list ruleset{/}. If Docker is installed you will see its chains: every rule there decides what reaches your containers."
  callout security "A firewall is only as good as its review. Common real-world failures: 'any any accept' rules left over from testing, IPv6 forgotten (use the inet family), egress left wide open, and no logging, so nobody notices the breach. A firewall is not an IDS: it enforces policy; it does not detect attacks hidden inside allowed traffic."
  reflect "Write, in plain English, a three-rule policy for a guest Wi-Fi VLAN that may only browse the Internet. Then say why rule order matters." \
    "1) Allow established/related replies. 2) Allow the guest VLAN to the Internet on TCP 80/443, and DNS (53) to the approved resolver only. 3) Drop the guest VLAN to every internal network (or rely on a default-drop policy). Order matters because the first matching rule wins: a broad accept placed above a deny makes the deny useless."
  quiz "What makes a firewall 'stateful'?" A "It tracks connections, so replies to allowed connections pass automatically (ct state established)." "It tracks connections and their state" "It inspects application payloads" "It has a default-deny policy" "It logs everything"
  quiz "A port is filtered with DROP. What does a TCP client experience?" C "No answer at all: the SYN is retransmitted until the client gives up." "Connection refused" "ICMP time exceeded" "A timeout after retries" "A TLS error"
  takeaways "Rules are matched in order; the chain policy decides the rest. Default-deny + explicit allows = least privilege." \
    "Stateful filtering (ct state established,related) makes replies just work." \
    "DROP is silent (filtered, timeout); REJECT is an honest refusal (closed, refused)." \
    "Counters are evidence; the inet family covers IPv4 and IPv6 together."
  mark_done
}

# ----------------------------------------------------------------- 11 -------
module11(){
  module_open 11 "${MOD_TITLE[11]}" "${MOD_MIN[11]}" "${MOD_TRACK[11]}"
  objectives "Read an HTTP request and response line by line" \
    "Prove that HTTP exposes credentials to anyone on the path" \
    "Explain what TLS protects, and what it does not" \
    "Create a certificate, inspect it, and see trust succeed and fail" \
    "Show that the same capture over HTTPS reveals nothing useful"

  section "HTTP: a plain-text conversation"
  figure "One HTTP exchange" <<'EOF'
  REQUEST (client → server)                RESPONSE (server → client)
  GET /index.html HTTP/1.1   ← method,     HTTP/1.0 200 OK          ← version, status
  Host: intranet.c1dc.lab      path,       Server: C1DC-Lab/1.0     ← banner
  User-Agent: curl/8.x         version     Content-Type: text/html
  Accept: */*                              Content-Length: 312
  (blank line = end of headers)            (blank line)  <html>… body …
EOF
  terms "Methods :: GET (read), POST (send data, e.g. a login form), PUT, DELETE, HEAD, OPTIONS." \
        "Status codes :: 1xx info, 2xx success (200 OK), 3xx redirect (301/302), 4xx client error (401, 403, 404), 5xx server error (500, 502, 503)." \
        "Key headers :: Host (which site; many sites share one IP), User-Agent (the client software), Cookie / Set-Cookie (sessions), Authorization (credentials)."
  practical title="Watch curl talk HTTP" \
    goal="-v shows the connection, every header sent (>) and every header received (<)." \
    cmd="sudo ip netns exec c1-student curl -v http://intranet.c1dc.lab:8000/" \
    anatomy="curl -v :: verbose: show the whole conversation, not just the body
intranet.c1dc.lab:8000 :: a name (resolved by the lab DNS) and a port" \
    read="* Trying 10.77.2.20:8000 :: DNS gave the address; the TCP connect starts
* Connected :: the three-way handshake succeeded
> GET / HTTP/1.1 :: the request line sent by curl
> Host: … :: tells the server which website we want
< HTTP/1.0 200 OK :: the status line returned by the server
< Server: C1DC-Lab/1.0 :: the server's banner (information for attackers too)
<html>… :: the body: the page itself" \
    lab=1 needs=curl
  pageturn

  section "Why plain HTTP is dangerous"
  say "Everything in HTTP is readable text: URLs, cookies, form fields, passwords. Any device on the path (a Wi-Fi access point, a router, a compromised switch) can read it. Let us stand where the router stands and watch a colleague log in."
  practical title="Sniff a login on the router" \
    goal="The academy makes the student submit a login form over HTTP. You capture on the router's LAN B interface: a man-in-the-middle position." \
    cmd="sudo ip netns exec c1-router timeout 5 tcpdump -i eth1 -nn -A -l tcp port 8000 | grep -a password" \
    anatomy="timeout 5 :: capture for 5 seconds
-A :: print each packet's payload as text
-l :: line-buffered, so the output flows straight into grep
| grep -a password :: keep only lines containing 'password' (-a = treat binary as text)" \
    predict="Will you be able to read the password? Write down what you expect to see." \
    bg="ip netns exec c1-student curl -s -o /dev/null -d 'user=alice&password=Winter2026' http://10.77.2.20:8000/login" \
    read="user=alice&password=Winter2026 :: the form body, captured in clear text by a device that was only supposed to route it" \
    explain="Nothing was hacked: the router simply read the bytes it was forwarding. That is why logins must never travel over plain HTTP, and why defenders love captures (and attackers love open Wi-Fi)." \
    lab=1 needs="tcpdump curl grep"
  pageturn

  section "TLS: what it protects, and what it does not"
  terms "Confidentiality :: Content is encrypted; on-path devices see random bytes." \
        "Integrity :: Any modification in transit is detected." \
        "Authentication :: The server proves its identity with a certificate the client trusts." \
        "Still visible :: IP addresses, ports, timing, sizes, and usually the server name (SNI in the ClientHello). Defenders analyse exactly this metadata (JA3/JA4 fingerprints)."
  figure "TLS 1.3 handshake, simplified" <<'EOF'
  CLIENT                                                         SERVER
   │ ClientHello: versions, ciphers, key share, SNI=server.c1dc.lab  │
   │ ───────────────────────────────────────────────────────────────►│
   │ ServerHello + key share; then ENCRYPTED: Certificate,           │
   │ CertificateVerify, Finished                                     │
   │ ◄───────────────────────────────────────────────────────────────│
   │ the client CHECKS the certificate: name, dates, trusted issuer  │
   │ Finished, then encrypted HTTP ("application data")              │
   │ ◄──────────────────────────────────────────────────────────────►│
EOF
  say "A {b}certificate{/} binds a public key to names (the Subject Alternative Names), is valid between two dates, and is signed by an {b}issuer{/}. A client trusts it only if the chain leads to a Certificate Authority in its trust store. A {b}self-signed{/} certificate is signed by itself, so nothing vouches for it unless you explicitly decide to trust it."
  practical title="Create your own certificate and private key" \
    goal="Become your own (tiny) certificate authority for the lab server." \
    cmd="openssl req -x509 -newkey rsa:2048 -nodes -keyout lab/pki/student.key -out lab/pki/student.crt -days 30 -subj /CN=server.c1dc.lab -addext subjectAltName=DNS:server.c1dc.lab,IP:10.77.2.20" \
    anatomy="req -x509 :: create a self-signed certificate (not just a signing request)
-newkey rsa:2048 :: generate a new 2048-bit RSA key pair
-nodes :: do not protect the private key with a passphrase (lab only!)
-keyout / -out :: where to save the private key / the certificate
-days 30 :: the validity period
-subj /CN=… :: the subject's common name
-addext subjectAltName=… :: the names and IPs the certificate is valid for (what clients really check)" \
    read="....+++++ :: progress dots while searching for prime numbers
(no error) :: two files now exist: student.key (SECRET) and student.crt (public)" \
    after="sed -i 's#^TLS_CERT=.*#TLS_CERT=$PKI/student.crt#; s#^TLS_KEY=.*#TLS_KEY=$PKI/student.key#' '$LABDIR/services.conf'; $TOOLS/labctl restart tls" \
    lab=1 needs=openssl
  say "The academy has restarted the lab's HTTPS service (port 8443) with YOUR certificate."
  practical title="Inspect the certificate" \
    goal="Read what a client will check." \
    cmd="openssl x509 -in lab/pki/student.crt -noout -subject -issuer -dates -ext subjectAltName" \
    anatomy="x509 -in FILE :: read a certificate
-noout :: do not print the encoded certificate itself
-subject -issuer -dates -ext … :: print only these fields" \
    read="subject=CN=server.c1dc.lab :: who the certificate is for
issuer=CN=server.c1dc.lab :: who signed it: the same name = self-signed
notBefore / notAfter :: the validity window
X509v3 Subject Alternative Name :: the names and IPs clients will accept" \
    lab=1 needs=openssl
  practical title="Connect over HTTPS without trusting the certificate" \
    goal="Let curl validate the server like a browser would." \
    cmd="sudo ip netns exec c1-student curl -sS https://server.c1dc.lab:8443/" \
    anatomy="https:// :: TLS first, then HTTP inside it
-sS :: show errors" \
    predict="Will curl show the page?" \
    read="SSL certificate problem: self-signed certificate :: curl refused: no trusted authority vouches for this certificate" \
    explain="This failure is TLS doing its job. If an attacker intercepted the connection with their own certificate, this is exactly the error the victim would get. Clicking through such warnings, or using curl -k, throws the protection away." \
    expect=fail lab=1 needs=curl
  practical title="Connect again, trusting YOUR certificate explicitly" \
    goal="Tell curl which certificate to trust." \
    cmd="sudo ip netns exec c1-student curl -sS --cacert lab/pki/student.crt https://server.c1dc.lab:8443/" \
    anatomy="--cacert FILE :: trust this certificate as an authority, for this request only" \
    read="<html>… :: the page, delivered over an authenticated, encrypted channel" \
    lab=1 needs=curl
  practical title="Look at the TLS session itself" \
    goal="openssl s_client is the analyst's TLS microscope." \
    cmd="sudo ip netns exec c1-student openssl s_client -connect 10.77.2.20:8443 -brief" \
    anatomy="s_client :: a generic TLS client
-connect HOST:PORT :: where to connect
-brief :: a short summary of the negotiated session" \
    read="Protocol version: TLSv1.3 :: the TLS version negotiated
Ciphersuite :: e.g. TLS_AES_256_GCM_SHA384: the encryption and integrity algorithm
Peer certificate :: the server certificate's subject
Verification error: self-signed certificate :: s_client reports trust problems but continues
Negotiated group :: the key exchange; X25519MLKEM768 is a post-quantum hybrid" \
    expect=any lab=1 needs=openssl
  practical title="Sniff the same login, this time over HTTPS" \
    goal="Same capture position, same grep, same form. Only the protocol changed." \
    cmd="sudo ip netns exec c1-router timeout 5 tcpdump -i eth1 -nn -A -l tcp port 8443 | grep -a password" \
    anatomy="tcp port 8443 :: the HTTPS service this time" \
    predict="What will grep find this time?" \
    bg="ip netns exec c1-student curl -s -o /dev/null --cacert $PKI/student.crt -d 'user=alice&password=Winter2026' https://10.77.2.20:8443/login" \
    read="(no output, exit status 1) :: grep found no 'password' anywhere: the payload is encrypted" \
    explain="The router forwarded exactly the same login, but saw only ciphertext. It could still see who talked to whom, when, and how much: TLS protects content, not metadata." \
    expect=any lab=1 needs="tcpdump curl grep"
  callout security "HTTPS does not mean 'safe website': phishing sites get valid certificates in minutes. It means 'a private, authentic connection to whoever owns this name'. Defenders inspect certificates (issuer, age, names) and TLS fingerprints to spot malicious servers."
  reflect "A user says 'the padlock is shown, so this login page is safe'. What does the padlock actually prove, and what does it not prove?" \
    "It proves the connection is encrypted and that the server holds a certificate for that exact hostname, issued by a trusted CA. It does not prove the site belongs to the real organisation (it may be a look-alike domain), that the site is not malicious, or that the server stores the password safely."
  quiz "Which information is still visible to an on-path observer of HTTPS traffic?" D "IPs, ports, packet sizes and timing, and usually the SNI hostname, stay visible; URLs, cookies and form data are encrypted." "The URL path and cookies" "The password" "Nothing at all" "IP addresses, ports, timing and usually the server name"
  quiz "curl reports 'self-signed certificate'. What is the professional response?" B "Verify the certificate through another channel and, if legitimate, trust that certificate or CA explicitly (--cacert). Never make -k a habit." "Use -k and continue" "Verify the certificate out of band, then trust it explicitly" "Switch to HTTP" "Ignore it"
  takeaways "HTTP is plain text: anyone on the path reads URLs, cookies and passwords." \
    "TLS gives confidentiality, integrity and server authentication, but metadata stays visible." \
    "Certificates bind names to keys and must chain to a trusted CA; self-signed means 'trust me'." \
    "Verification errors are protection working. Never make -k a habit."
  mark_done
}

# ----------------------------------------------------------------- 12 -------
module12(){
  module_open 12 "${MOD_TITLE[12]}" "${MOD_MIN[12]}" "${MOD_TRACK[12]}"
  objectives "Read, compress and classify IPv6 addresses" \
    "Explain how a link-local address is built from a MAC (EUI-64)" \
    "Capture Neighbor Discovery, IPv6's replacement for ARP" \
    "Explain MTU, fragmentation and path-MTU discovery, and break it on purpose"

  section "IPv6 addresses"
  say "IPv4's 4.3 billion addresses ran out years ago. {b}IPv6{/} uses {b}128-bit{/} addresses, written as eight groups of four hex digits. A normal LAN is always a {b}/64{/}: 64 bits of network, 64 bits of host."
  figure "Two rules make IPv6 addresses shorter" <<'EOF'
  full form      fd77:0001:0000:0000:0000:0000:0000:0010
  rule 1  drop leading zeros in each group         →  fd77:1:0:0:0:0:0:10
  rule 2  replace ONE run of zero groups with ::   →  fd77:1::10
          (only once per address, or it would be ambiguous)
EOF
  figure "Address types" <<'EOF'
  ::1/128          loopback
  fe80::/10        link-local: every IPv6 interface has one; never routed
  fc00::/7 (fd..)  unique local (ULA): private, like 10.0.0.0/8 (our lab uses fd77::)
  2000::/3         global unicast: public Internet addresses
  ff00::/8         multicast (IPv6 has NO broadcast); ff02::1 = all nodes on the link
EOF
  quiz "What is the shortest correct form of 2001:0db8:0000:0000:0000:0000:0000:0001?" B "Drop leading zeros and compress the single run of zero groups: 2001:db8::1." "2001:db8:0:0::1:0" "2001:db8::1" "2001:db8::0001" "2001::db8::1"
  quiz "Which prefix length does a normal IPv6 LAN use?" C "/64: the host half is 64 bits so that SLAAC and privacy addresses work." "/24" "/48" "/64" "/128"
  pageturn

  section "Addresses from a MAC: EUI-64"
  figure "How the kernel built the student's link-local address" <<'EOF'
  MAC                02 : c1 : dc  :  01 : 00 : 10
  split + insert     02 c1 dc [ff fe] 01 00 10
  flip bit 1 (U/L)   02 → 00
  interface ID       00c1:dcff:fe01:0010
  link-local         fe80::c1:dcff:fe01:10
EOF
  callout security "EUI-64 embeds the MAC address in the IP address, so a laptop can be tracked across networks. Modern systems use random 'privacy' or 'stable-privacy' addresses for global traffic instead. Seeing ff:fe in the middle of an address tells you EUI-64 was used."
  practical title="Your Kali host's IPv6 addresses" \
    goal="Most machines have IPv6 even when nobody configured it." \
    cmd="ip -6 -br addr" \
    anatomy="-6 :: IPv6 only" \
    read="::1/128 :: loopback
fe80::…/64 :: link-local on every active interface
2…: or fd…: :: global or unique-local addresses, if the network provides them" \
    needs=ip
  practical title="The student's IPv6 addresses" \
    goal="Check the EUI-64 calculation above against reality." \
    cmd="sudo ip -n c1-student -6 addr show dev eth0" \
    anatomy="-6 addr show dev eth0 :: the IPv6 addresses of eth0 only" \
    read="inet6 fd77:1::10/64 scope global :: the static lab address
inet6 fe80::c1:dcff:fe01:10/64 scope link :: the EUI-64 link-local address, derived from 02:c1:dc:01:00:10" \
    lab=1 needs=ip
  practical title="Ping across the router over IPv6" \
    goal="The router forwards IPv6 too (net.ipv6.conf.all.forwarding=1)." \
    cmd="sudo ip netns exec c1-student ping -6 -c 2 fd77:2::20" \
    anatomy="-6 :: use IPv6" \
    read="64 bytes from fd77:2::20 :: a reply over IPv6
ttl=63 :: in IPv6 the field is called Hop Limit; it works exactly like the TTL" \
    lab=1 needs=ping
  pageturn

  section "Neighbor Discovery: ARP's successor"
  say "IPv6 has no ARP. The {b}Neighbor Discovery Protocol{/} (NDP) does the same job with ICMPv6 messages, sent to a special multicast group instead of a broadcast: the {b}solicited-node{/} address ff02::1:ffXX:XXXX, built from the last 24 bits of the target address."
  terms "NS (type 135) :: Neighbor Solicitation: 'who has fd77:1::1? Tell me your MAC.'" \
        "NA (type 136) :: Neighbor Advertisement: 'fd77:1::1 is at 02:c1:dc:01:00:01.'" \
        "RS / RA (133/134) :: Router Solicitation / Advertisement: routers announce prefixes and themselves as gateways (SLAAC)."
  practical title="Capture Neighbor Discovery" \
    goal="The academy clears the IPv6 neighbour caches and pings the router's IPv6 address from the student." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -c 4 icmp6" \
    anatomy="icmp6 :: capture filter for ICMPv6 (NDP and ping6 both use it)" \
    predict="To which destination address will the first packet go?" \
    pre="ip -n c1-student -6 neigh flush all; ip -n c1-router -6 neigh flush all" \
    bg="ip netns exec c1-student ping -6 -c 1 -W 1 fd77:1::1" \
    read="fd77:1::10 > ff02::1:ff00:1 … neighbor solicitation, who has fd77:1::1 :: the NS, sent to the solicited-node group of …::1
fd77:1::1 > fd77:1::10 … neighbor advertisement, tgt is fd77:1::1 :: the NA: the router answers with its MAC
ICMP6, echo request / echo reply :: the ping, now that the MAC is known" \
    lab=1 needs=tcpdump
  practical title="The IPv6 neighbour cache" \
    goal="Same table as ARP, different protocol." \
    cmd="sudo ip -n c1-student -6 neigh" \
    anatomy="-6 neigh :: the IPv6 part of the neighbour table" \
    read="fd77:1::1 dev eth0 lladdr 02:c1:dc:01:00:01 router REACHABLE :: the 'router' flag came from the NA" \
    lab=1 needs=ip
  callout security "IPv6 is often enabled but unmonitored: an attacker who sends fake Router Advertisements (rogue RA) becomes everybody's IPv6 gateway, even on an 'IPv4-only' network. Defences: RA Guard on switches, monitoring ICMPv6, and firewalling both families. Do not 'fix' IPv6 security by blindly disabling it: control it."
  pageturn

  section "MTU: how big can a packet be?"
  say "Every link has a {b}Maximum Transmission Unit{/}: the largest IP packet it can carry in one frame, usually {b}1500 bytes{/} on Ethernet. Tunnels and VPNs add headers, so their MTU is smaller. If a packet is too big for the next link, an IPv4 router may fragment it, unless the {b}DF{/} (Don't Fragment) bit is set. Then the router drops it and sends ICMP 'fragmentation needed' with the MTU, so the sender can shrink its packets: {b}path-MTU discovery{/} (PMTUD). IPv6 routers never fragment."
  figure "Where the 1500 bytes go" <<'EOF'
  ┌─ Ethernet 14 ─┬─────────────── IP packet = MTU 1500 ──────────────┬ FCS 4 ┐
  │ dst src type  │ IP hdr 20 │ TCP hdr 20 │ data ≤ 1460 (= TCP MSS)  │       │
  └───────────────┴───────────┴────────────┴──────────────────────────┴───────┘
  ping -s 1472 → 1472 data + 8 ICMP + 20 IP = 1500 bytes: exactly one full packet
EOF
  practical title="The largest ping that fits" \
    goal="Send exactly 1500 bytes of IP with 'Don't Fragment' set." \
    cmd="sudo ip netns exec c1-student ping -c 1 -M do -s 1472 10.77.2.20" \
    anatomy="-M do :: set the DF bit (prohibit fragmentation)
-s 1472 :: 1472 bytes of ICMP data (+8 ICMP +20 IP = 1500)" \
    read="1472(1500) bytes of data :: payload (total IP size)
1480 bytes from 10.77.2.20 :: the reply (ICMP header + data)" \
    lab=1 needs=ping
  practical title="Shrink the router's LAN B link to 1400" \
    goal="Simulate a VPN or tunnel with a smaller MTU in the middle of the path." \
    cmd="sudo ip -n c1-router link set eth1 mtu 1400" \
    anatomy="link set eth1 mtu 1400 :: the maximum IP packet size on the router's eth1" \
    lab=1 needs=ip
  practical title="Send the same 1500-byte packet again" \
    goal="It no longer fits on the router's eth1." \
    cmd="sudo ip netns exec c1-student ping -c 2 -M do -s 1472 10.77.2.20" \
    anatomy="(the same as before)" \
    predict="Who will report the problem, and which number will they report?" \
    read="From 10.77.1.1 … Frag needed and DF set (mtu = 1400) :: the ROUTER explains why it dropped the packet
ping: sendmsg: Message too long :: the second time, the student's kernel remembered the path MTU and refused locally" \
    explain="This is path-MTU discovery working: the ICMP message carried the number 1400, the kernel cached it, and TCP would now send smaller segments automatically. If a firewall blocks those ICMP messages, large transfers hang while small ones work (a 'PMTU black hole'): pages half-load, SSH logs in and then freezes. Classic VPN trouble." \
    after="ip -n c1-router link set eth1 mtu 1500; ip -n c1-student route flush cache" \
    expect=fail lab=1 needs=ping
  reflect "Users on a new VPN can open small web pages, but big downloads freeze and SSH hangs after login. What is your hypothesis, and how would you test it?" \
    "A path-MTU black hole: the tunnel has a smaller MTU and the ICMP 'fragmentation needed' messages are blocked, so large packets silently disappear. Test with ping -M do -s <size> to find the largest size that passes, check the ICMP filtering, then lower the MTU or clamp the TCP MSS on the tunnel."
  quiz "Which protocol replaces ARP in IPv6?" A "Neighbor Discovery (ICMPv6 types 135/136) does address resolution in IPv6." "NDP (ICMPv6)" "DHCPv6" "NAT64" "IGMP"
  quiz "An IPv4 packet with DF set is larger than the next link's MTU. What does the router do?" C "It drops the packet and sends ICMP type 3 code 4, 'fragmentation needed', including the next-hop MTU." "Fragments it" "Forwards it anyway" "Drops it and sends 'fragmentation needed' with the MTU" "Resets the TCP connection"
  takeaways "IPv6: 128-bit addresses, /64 LANs, :: compresses one zero run, no broadcast (multicast instead)." \
    "Link-local fe80:: addresses always exist; EUI-64 embeds the MAC (ff:fe inserted, U/L bit flipped)." \
    "NDP (NS/NA, RS/RA over ICMPv6) replaces ARP; rogue RAs are the IPv6 version of rogue DHCP." \
    "The MTU limits packet size; PMTUD needs ICMP. Blocking it creates black holes."
  mark_done
}

# ----------------------------------------------------------------- 13 -------
module13(){
  module_open 13 "${MOD_TITLE[13]}" "${MOD_MIN[13]}" "${MOD_TRACK[13]}"
  objectives "State the legal and professional rules for scanning" \
    "Explain how Nmap decides open, closed and filtered" \
    "Discover hosts, scan TCP and UDP, and identify services in the lab" \
    "See what a SYN scan looks like on the wire, from the defender's side"

  section "Rules of engagement first"
  callout warn "Scanning systems you do not own or have WRITTEN permission to test is illegal in many countries, even if 'nothing happened'. Professionals work from a signed scope: which addresses, which dates and times, which techniques, and who to call if something breaks. In this course you scan only the C1DC cyber-range."
  numbered "Get written authorisation and an exact scope (addresses, times, methods, contacts)." \
    "Start passive: asset inventory, DNS, DHCP leases, network diagrams." \
    "Discover live hosts, then open ports, then services and versions, within scope only." \
    "Verify findings manually: a port or a version string is not yet a vulnerability." \
    "Report clearly, help fix, retest; keep your evidence and logs."

  section "How a scanner reads the network"
  figure "Port states, from the packets that come back" <<'EOF'
  PROBE SENT      ANSWER                      NMAP SAYS       MEANING
  SYN             SYN-ACK                     open            a program accepts connections
  SYN             RST                         closed          host reachable, nothing on the port
  SYN             nothing (after retries)     filtered        something dropped the probe
  SYN             ICMP unreachable (admin)    filtered        a firewall rejected it with ICMP
  UDP datagram    UDP reply                   open
  UDP datagram    ICMP port unreachable       closed
  UDP datagram    nothing                     open|filtered   silence is ambiguous
EOF
  terms "-sn :: Host discovery only (no port scan). On a local LAN Nmap uses ARP, which host firewalls cannot block." \
        "-sT :: TCP connect scan: a full handshake via the operating system. No root needed; easy to see in server logs." \
        "-sS :: SYN ('half-open') scan: sends SYN, reads the answer, then RST instead of completing. Needs root; the classic default." \
        "-sU :: UDP scan: slow and ambiguous (see the table)." \
        "-sV :: Service/version detection: talks to open ports and matches their banners." \
        "-Pn / -p / -oN :: skip discovery / choose ports / save normal output to a file."
  pageturn

  section "Scan the cyber-range"
  practical title="Which hosts are alive on LAN A?" \
    goal="Host discovery on the student's own subnet." \
    cmd="sudo ip netns exec c1-student nmap -sn 10.77.1.0/24" \
    anatomy="-sn :: ping scan: discover hosts, do not scan ports
10.77.1.0/24 :: all 256 addresses of LAN A" \
    predict="How many hosts will Nmap report as up?" \
    read="Nmap scan report for 10.77.1.1 / .11 :: live hosts found
MAC Address: 02:C1:DC:… (Unknown) :: found via ARP; 'Unknown' because 02: is not a registered vendor prefix
10.77.1.10 :: the student itself (no MAC shown for yourself)
3 hosts up :: router, peer and student" \
    lab=1 needs=nmap
  practical title="TCP connect scan of the server" \
    goal="Check five interesting ports on the intranet server." \
    cmd="sudo ip netns exec c1-student nmap -sT -Pn -p 22,53,80,8000,8443 10.77.2.20" \
    anatomy="-sT :: full TCP connect
-Pn :: treat the host as up (skip discovery)
-p … :: exactly these ports" \
    read="22/tcp closed ssh :: RST: no SSH server (the service NAME is only Nmap's guess from the port number)
53/tcp open domain :: DNS also listens on TCP
8000/tcp open http-alt :: the web server
8443/tcp open https-alt :: the TLS server" \
    lab=1 needs=nmap
  practical title="What does a SYN scan look like on the wire?" \
    goal="Capture on the student while the academy runs a SYN scan against port 8000." \
    cmd="sudo ip netns exec c1-student tcpdump -i eth0 -nn -c 3 tcp port 8000" \
    anatomy="-c 3 :: the SYN, the SYN-ACK, and whatever the scanner sends next" \
    predict="A normal client answers a SYN-ACK with an ACK. What will the scanner send?" \
    bg="ip netns exec c1-student nmap -sS -Pn -p 8000 10.77.2.20" \
    read="Flags [S], … win 1024 :: Nmap's SYN (note the tiny window: a known Nmap fingerprint)
Flags [S.] :: the server: 'open, let's talk'
Flags [R] :: the scanner tears it down before the connection completes: 'half-open'" \
    explain="Because the handshake never completes, the web application never sees a connection and logs nothing. Only network monitoring (an IDS such as Suricata or Zeek, or firewall logs) notices. Defenders hunt for many SYNs to many ports, each followed by a RST: exactly what you will do in module 14." \
    lab=1 needs="tcpdump nmap"
  practical title="Identify the service behind each open port" \
    goal="Version detection talks to the service and reads its banner." \
    cmd="sudo ip netns exec c1-student nmap -sV -Pn -p 8000,8443 10.77.2.20" \
    anatomy="-sV :: probe open ports to identify the software and its version" \
    read="SERVICE / VERSION :: e.g. http C1DC-Lab 1.0: taken from the Server: header you saw in module 11
ssl/http :: Nmap noticed TLS on 8443 and looked inside" \
    explain="Banners leak information. Our web server hides its Python version (sys_version is empty in tools/c1dc_web.py) but still shows its name. Attackers map versions to known vulnerabilities, so hardening guides say 'minimise banners', and analysts treat a version string as a lead, not proof." \
    lab=1 needs=nmap
  practical title="UDP: the three possible answers" \
    goal="Port 53 runs DNS, 5300 runs a silent listener, 5301 has nothing." \
    cmd="sudo ip netns exec c1-student nmap -sU -Pn -p 53,5300,5301 10.77.2.20" \
    anatomy="-sU :: UDP scan" \
    predict="Predict the state of each of the three ports." \
    read="53/udp open domain :: DNS answered Nmap's DNS probe
5300/udp open|filtered :: no answer: open but silent, OR filtered; Nmap cannot know
5301/udp closed :: ICMP port unreachable came back" \
    lab=1 needs=nmap
  callout turn "Repeat the TCP scan with {c}-oN evidence/scan.txt{/} added, then read the file. Professionals always keep raw output as evidence of what was tested, when, and from where."
  reflect "A scan shows 'Apache 2.4.49' on a client's server. A junior wants to write 'Critical RCE vulnerability' in the report. What should happen first?" \
    "Verify. Banners can be wrong or deliberately altered, backported patches may fix the bug without changing the version, and the vulnerable module or configuration may not be enabled. Confirm with safe, in-scope checks or vendor evidence before reporting, and describe the evidence honestly."
  quiz "An Nmap SYN probe gets no response at all after retries. Which state is reported?" C "No answer = something dropped the probe = filtered." "open" "closed" "filtered" "open|filtered"
  quiz "Why can a SYN scan be invisible to the web application's logs?" A "The handshake never completes (the scanner sends RST), so the application never accepts a connection." "The connection is never completed, so the application never sees it" "It is encrypted" "It uses UDP" "It spoofs the MAC address"
  takeaways "Scope and written permission come first; scanning is a professional, documented activity." \
    "SYN-ACK = open, RST = closed, silence = filtered; for UDP, silence = open|filtered." \
    "SYN scans are half-open: invisible to applications, visible to network monitoring." \
    "Versions and banners are leads to verify, not findings to copy into a report."
  mark_done
}

# ----------------------------------------------------------------- 14 -------
module14(){
  module_open 14 "${MOD_TITLE[14]}" "${MOD_MIN[14]}" "${MOD_TRACK[14]}"
  objectives "Handle network evidence properly: hash, timestamps, copies" \
    "Summarise a capture with capinfos and tshark statistics" \
    "Hunt for a port scan, a beacon and leaked credentials in a real PCAP" \
    "Write findings that separate evidence from interpretation"

  section "Evidence first"
  terms "Hash first :: Compute the SHA-256 of the original capture before analysis; re-hash later to prove it did not change." \
        "Work on copies :: Analyse a copy; keep the original read-only." \
        "Time matters :: Record timestamps WITH a time zone (UTC is best). Correlating logs from devices with skewed clocks is a classic failure." \
        "Chain of custody :: Who collected what, when and how, and who has handled it since."
  section "How hunters think"
  numbered "Start from a hypothesis ('someone on LAN A is scanning the server')." \
    "Choose the data that can confirm or refute it (a capture at the router)." \
    "Analyse: filter, count, sort, compare with what is normal." \
    "Conclude only what the evidence supports; note the alternative explanations."
  figure "Network indicators and their innocent look-alikes" <<'EOF'
  PATTERN                           COULD BE MALICIOUS       COULD BE INNOCENT
  one source → many ports, SYN+RST  port scan                a vulnerability scanner you own
  same request every N seconds      malware beacon (C2)      update checks, monitoring
  an odd User-Agent string          custom malware           internal script, old device
  long random DNS names             DNS tunnelling, DGA      CDNs, anti-virus lookups
  credentials in clear text         anyone can steal them    (never acceptable)
EOF
  pageturn

  section "The scenario"
  say "{b}Incident 2026-C1DC-014.{/} The server team reports unusual activity on LAN A. A capture sensor on the router's LAN A interface (eth0) recorded about 25 seconds of traffic. Your job: find out what happened, using only the evidence."
  if ! hunt_generate; then warn "The hunt needs the cyber-range and tcpdump. Build the lab (menu L) and come back."; mark_done; return 0; fi
  practical title="Hash the evidence before touching it" \
    goal="SHA-256 fingerprints the file. Copy the hash into your journal." \
    cmd="sha256sum evidence/hunt.pcap" \
    anatomy="sha256sum :: compute the SHA-256 digest of a file" \
    read="64 hex characters :: the fingerprint; changing even one bit of the file changes it completely" \
    lab=1 needs=sha256sum
  practical title="What is in the file? (metadata)" \
    goal="capinfos summarises a capture without showing packets." \
    cmd="capinfos evidence/hunt.pcap" \
    anatomy="capinfos :: capture-file summary tool (Wireshark suite)" \
    read="Number of packets :: how much traffic was recorded
First / Last packet time, Capture duration :: the time window of the evidence
Data size, average packet rate :: the volume" \
    lab=1 needs=capinfos
  practical title="Who talked to whom? (conversation statistics)" \
    goal="Start broad: list every IP conversation with packet and byte counts." \
    cmd="tshark -r evidence/hunt.pcap -q -z conv,ip" \
    anatomy="-q :: do not print packets, only the statistics
-z conv,ip :: a table of IP-to-IP conversations" \
    read="Address A <-> Address B :: one row per pair of hosts
Frames / Bytes :: the volume in each direction and in total
Rel Start / Duration :: when the conversation started and how long it lasted" \
    lab=1 needs=tshark
  hunt_questions
  callout tip "Write each finding as: {b}what{/} was observed, the {b}evidence{/} (filter used, packet counts, timestamps), your {b}interpretation{/}, your {b}confidence{/}, and the {b}recommended action{/}. Example: '10.77.1.11 sent SYNs to 200+ ports on 10.77.2.20 within 2 s, each followed by RST (filter: …). Consistent with an Nmap SYN scan. High confidence. Identify the user and process on 10.77.1.11.'"
  reflect "You found periodic HTTP requests every 3 seconds from 10.77.1.10 with an unusual User-Agent. List two benign and two malicious explanations, and the next evidence you would collect to decide." \
    "Benign: an internal monitoring or health-check script; a software updater. Malicious: malware beaconing to command-and-control; an attacker's implant checking for tasks. Next evidence: which process on 10.77.1.10 opens those connections (EDR, ss -tp), the full URI and response contents, whether other hosts do the same, and the server-side logs and owner of /update."
  quiz "Why compute the SHA-256 hash of a PCAP before analysing it?" B "The hash lets you prove later that the evidence was not modified; it does not prove who created it." "To decrypt it" "To prove later that it has not been altered" "To compress it" "To identify the attacker"
  takeaways "Hash, preserve, timestamp: evidence handling comes before analysis." \
    "Go broad to narrow: capinfos → conversations → targeted filters → individual packets." \
    "Scans, beacons and cleartext credentials each leave clear, countable traces." \
    "Report the observation, the evidence, the interpretation and your confidence separately."
  mark_done
}

# ----------------------------------------------------------------- 15 -------
module15(){
  module_open 15 "${MOD_TITLE[15]}" "${MOD_MIN[15]}" "${MOD_TRACK[15]}"
  objectives "Apply a repeatable, layer-by-layer troubleshooting method" \
    "Translate common error messages into the layer that failed" \
    "Diagnose and fix deliberately broken lab networks on your own"

  section "The method"
  numbered "{b}Define{/} the problem precisely: who, what, since when, what changed? 'The Internet is down' is not a problem statement." \
    "{b}Gather facts{/} before touching anything, and write them down." \
    "{b}Form one hypothesis{/}, and find the test that would prove it WRONG." \
    "{b}Change one thing at a time{/}, then re-test. Two changes at once and you will never know which one helped." \
    "{b}Verify{/} the fix from the user's point of view, then {b}document{/} the root cause."
  figure "Bottom-up checklist (or start at L3 with ping and move up or down)" <<'EOF'
  LAYER  QUESTION                                   COMMAND
  L1/L2  Is the link up? Carrier? Errors?           ip -br link    ip -s link
  L2     Can I resolve the gateway's MAC?           ip neigh       (FAILED = trouble)
  L3     Right address/prefix? Gateway? Route?      ip -br addr    ip route    ip route get X
  L3     Does a packet get there AND back?          ping    traceroute    tcpdump at both ends
  L4     Is the service listening? Firewall?        ss -tuln (server)   nft list ruleset   nmap -p
  L7     Name resolution? HTTP status? TLS?         dig    getent hosts    curl -v    openssl s_client
EOF
  figure "Error messages decoded" <<'EOF'
  MESSAGE                                    LIKELY LAYER / CAUSE
  Network is unreachable                     L3, local: no matching route (missing gateway?)
  No route to host / Destination Host Unr.   L2/L3: ARP for the next hop failed, or host-unreachable
  Connection refused                         L4: host reached, port closed (RST) or firewall REJECT
  Connection timed out                       something DROPS packets: firewall, routing, return path
  Could not resolve host / NXDOMAIN          L7 DNS: resolver config, DNS server, missing record
  Time to live exceeded                      a routing loop, or TTL too small
  SSL certificate problem                    TLS: trust, hostname mismatch, expired certificate
  Frag needed / Message too long             MTU / path-MTU discovery
EOF
  pageturn
  section "Baseline: know what 'healthy' looks like"
  practical title="Baseline the student PC: addresses" \
    goal="Before a fault, record the healthy state. You will compare against it." \
    cmd="sudo ip -n c1-student -br addr" \
    anatomy="(you know this one)" \
    lab=1 needs=ip
  practical title="Baseline the student PC: routes" \
    goal="The default route and the connected network." \
    cmd="sudo ip -n c1-student route" \
    anatomy="(you know this one too)" \
    read="default via 10.77.1.1 dev eth0 :: the gateway
10.77.1.0/24 dev eth0 … src 10.77.1.10 :: the connected LAN" \
    lab=1 needs=ip
  practical title="Baseline the server: listening services" \
    goal="What should be listening when everything is fine." \
    cmd="sudo ip netns exec c1-server ss -tuln" \
    anatomy="(the server's listening sockets)" \
    lab=1 needs=ss
  callout tip "Save baselines in your journal. In real networks 'what changed?' is the most powerful question, and you can only answer it if you know what things looked like before."
  section "Troubleshooting tickets"
  say "Now the real practice. The academy will {b}break the lab on purpose{/} and hand you a user's ticket. Nobody tells you what is wrong. You open shells on the lab hosts (they are real Linux network stacks), investigate with the tools from this course, fix the fault yourself, and press {b}V{/} to have the academy verify your fix. Hints are available, but they cost points."
  tickets_menu
  quiz "A user gets 'Connection refused' to 10.77.2.20:8000. Which is the LEAST likely cause?" D "Refused means a RST came back, so packets reached a host (or a rejecting firewall). A missing route on the client would give 'Network is unreachable' or a timeout instead." "The service stopped" "The service is bound to 127.0.0.1 only" "A firewall REJECT rule" "The client has no route to the server"
  takeaways "Define, gather facts, hypothesise, change one thing, verify, document." \
    "Error messages point to layers: unreachable (L3), refused (L4), NXDOMAIN (DNS), certificate (TLS)." \
    "Always test both directions: the return path breaks as often as the forward path." \
    "Baselines turn 'it feels broken' into 'this changed'."
  mark_done
}

# ----------------------------------------------------------------- 16 -------
module16(){
  module_open 16 "${MOD_TITLE[16]}" "${MOD_MIN[16]}" "${MOD_TRACK[16]}"
  say "No AI and no copying: your notebook, a terminal, the cyber-range and your journal. The practical part is assessed by your instructor; the knowledge part below is scored automatically."
  section "Practical tasks (instructor-assessed, 100 marks)"
  figure "Show each item live and explain it in your own words" <<'EOF'
  A  Draw the 7 OSI layers with one protocol and one attack per layer        (8)
  B  For 192.168.50.142/27: network, mask, broadcast, host range, count,
     one local and one remote example address                                (12)
  C  On your Kali host: interface, MAC, IP/prefix, default gateway, DNS       (8)
  D  Show and explain the neighbour entry created by a lab ping               (8)
  E  Capture a TCP handshake to a PCAP; show the filter; explain each flag    (12)
  F  Explain DHCP DORA, DNS resolution (dig output) and IPv6 NDP              (10)
  G  Prove routed connectivity; show the TTL change across the router         (8)
  H  Build a lab firewall rule; show before/after evidence and counters       (10)
  I  Solve one troubleshooting ticket (menu T) and present the root cause     (12)
  J  Threat-hunt report (module 14): findings + PCAP SHA-256                  (12)
  70+ pass · 85+ distinction · a screenshot without an explanation earns nothing
EOF
  callout turn "Bonus scenarios to discuss with your instructor: (1) the server answers ping but port 443 times out; (2) 10.0.0.25/24 and 10.0.1.25/24 cannot ping each other directly; (3) a name fails but its IP works; (4) why a VLAN is not a substitute for a firewall; (5) why an open port is not automatically a vulnerability."
  pageturn
  section "Knowledge test (10 questions)"
  quiz "Which device forwards based on the destination IP address?" C "Routers forward packets between networks using IP; switches use MAC addresses." "Hub" "Switch" "Router" "Access point"
  quiz "How many usable hosts are in a /27?" B "2^5 = 32 addresses, minus network and broadcast = 30." "32" "30" "62" "14"
  quiz "Which protocol maps an IPv4 address to a MAC address?" A "ARP." "ARP" "DNS" "DHCP" "NDP"
  quiz "A client's SYN is answered by RST. Nmap reports the port as…" B "RST = closed (host reachable, nothing listening)." "open" "closed" "filtered" "open|filtered"
  quiz "Which header field does every router decrement?" D "The TTL (IPv4) / Hop Limit (IPv6)." "Source port" "Sequence number" "Checksum only" "TTL"
  quiz "Which DNS record type points to a domain's mail servers?" C "MX." "A" "CNAME" "MX" "PTR"
  quiz "Which nftables expression lets replies of allowed connections through?" A "ct state established,related accept." "ct state established,related accept" "policy accept" "tcp dport 0-65535 accept" "masquerade"
  quiz "What does TLS NOT hide from an on-path observer?" B "IP addresses, ports, sizes and timing (and usually the SNI) remain visible." "The URL path" "IP addresses and ports" "Form fields" "Cookies"
  quiz "Small pages load but large transfers hang through a new VPN. Most likely cause?" C "A path-MTU black hole: oversized packets are dropped and the ICMP 'frag needed' messages are blocked." "DNS failure" "ARP spoofing" "A PMTU black hole" "An expired certificate"
  quiz "What is the strongest proof that a routed lab path works?" B "Observed traffic plus route evidence beats diagrams or assumptions." "A diagram" "Successful traffic plus the verified route" "The port name" "An assumption"
  section "Your evidence pack"
  say "Hand in: your journal (it already contains every prediction, reflection and quiz answer you gave), your PCAPs and their hashes, your ticket root-cause notes, and your threat-hunt findings."
  printf '  %sJournal:%s %s\n' "$BOLD" "$RST" "${JOURNAL/#$HOME/\~}"
  printf '  %sEvidence folder:%s %s\n' "$BOLD" "$RST" "${EVID/#$HOME/\~}"
  ls -1 "$EVID" 2>/dev/null | sed 's/^/     /'
  journal "" "### Final knowledge test: $Q_OK/$Q_TOTAL" ""
  printf '\n  %sKnowledge test score: %d / %d%s\n' "$BOLD" "$Q_OK" "$Q_TOTAL" "$RST"
  mark_done
}

# =============================================================================
# PART 5 · PRACTICE: SUBNETTING, TICKETS, THREAT HUNT, REFERENCE
# =============================================================================

# ------------------------------------------------------------ subnetting ----
ip2int(){ local IFS=.; local -a o; read -r -a o <<<"$1"; echo $(((o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3])); }
int2ip(){ local n=$1; printf '%d.%d.%d.%d' $(((n >> 24) & 255)) $(((n >> 16) & 255)) $(((n >> 8) & 255)) $((n & 255)); }
mask_of(){ if (($1 == 0)); then echo 0; else echo $(((0xFFFFFFFF << (32 - $1)) & 0xFFFFFFFF)); fi; }
bits_colored(){ # 32 bits, dotted, network bits green / host bits yellow
  local n=$1 p=$2 i s='' pos
  for ((i = 31; i >= 0; i--)); do
    pos=$((31 - i))
    if ((pos < p)); then s+="$GRN$(((n >> i) & 1))"; else s+="$YEL$(((n >> i) & 1))"; fi
    ((i % 8 == 0 && i > 0)) && s+="$RST."
  done
  printf '%s%s' "$s" "$RST"
}

subnet_explain(){ # subnet_explain IP PREFIX
  local ip=$1 p=$2 ipn mask net bc total usable first last
  ipn=$(ip2int "$ip"); mask=$(mask_of "$p"); net=$((ipn & mask)); bc=$((net | (~mask & 0xFFFFFFFF)))
  total=$((1 << (32 - p)))
  if ((p <= 30)); then usable=$((total - 2)); first=$((net + 1)); last=$((bc - 1))
  elif ((p == 31)); then usable=2; first=$net; last=$bc
  else usable=1; first=$net; last=$net; fi
  printf '    %-12s %-16s %s\n' "address" "$ip" "$(bits_colored "$ipn" "$p")"
  printf '    %-12s %-16s %s\n' "mask /$p" "$(int2ip "$mask")" "$(bits_colored "$mask" "$p")"
  printf '    %s%-12s %-16s %s%s\n' "$DIM" "" "AND" "$(rep "$H" 35)" "$RST"
  printf '    %s%-12s%s %-16s %s   %s← host bits all 0%s\n' "$BOLD" "network" "$RST" "$(int2ip "$net")" "$(bits_colored "$net" "$p")" "$DIM" "$RST"
  printf '    %s%-12s%s %-16s %s   %s← host bits all 1%s\n' "$BOLD" "broadcast" "$RST" "$(int2ip "$bc")" "$(bits_colored "$bc" "$p")" "$DIM" "$RST"
  echo
  printf '    %-20s %s\n' "First usable host" "$(int2ip "$first")"
  printf '    %-20s %s\n' "Last usable host" "$(int2ip "$last")"
  printf '    %-20s 2^%d = %d addresses, %d usable\n' "Block size" $((32 - p)) "$total" "$usable"
  if ((p % 8 != 0)); then
    local oct=$((p / 8)) mval blk
    mval=$(((mask >> (24 - 8 * oct)) & 255)); blk=$((256 - mval))
    printf '    %-20s octet %d has mask value %d → block = 256 - %d = %d\n' "Shortcut" $((oct + 1)) "$mval" "$mval" "$blk"
  else
    printf '    %-20s the mask ends exactly on an octet boundary\n' "Shortcut"
  fi
  echo
}

DRILL_OK=0; DRILL_TOTAL=0
drill_field(){ # drill_field LABEL EXPECTED
  local label=$1 want=$2 got
  ((++DRILL_TOTAL))
  if ((NONINTERACTIVE)); then got=$want
  else read -e -r -p "    $(printf '%-20s' "$label") $PROMPT " got || got=''; fi
  got=${got// /}
  if [[ $got == "$want" ]]; then ((++DRILL_OK)); printf '      %s%s correct%s\n' "$BGRN" "$OK" "$RST"
  else printf '      %s%s the answer is %s%s\n' "$BYEL" "$NO" "$want" "$RST"; fi
}

subnet_drill(){ # subnet_drill [COUNT]
  local n=${1:-5} q p a b c d ip ipn mask net bc
  DRILL_OK=0; DRILL_TOTAL=0
  for ((q = 1; q <= n; q++)); do
    if ((RANDOM % 5 == 0)); then p=$((16 + RANDOM % 4)); else p=$((20 + RANDOM % 11)); fi
    case $((RANDOM % 3)) in
      0) a=10; b=$((RANDOM % 256)) ;;
      1) a=172; b=$((16 + RANDOM % 16)) ;;
      *) a=192; b=168 ;;
    esac
    c=$((RANDOM % 256)); d=$((1 + RANDOM % 254))
    ip="$a.$b.$c.$d"; ipn=$(ip2int "$ip"); mask=$(mask_of "$p"); net=$((ipn & mask)); bc=$((net | (~mask & 0xFFFFFFFF)))
    if ((ipn == net || ipn == bc)); then ((q--)); continue; fi
    printf '\n  %s QUESTION %d of %d %s   host %s%s/%d%s\n\n' "$BYEL$REV" "$q" "$n" "$RST" "$BOLD" "$ip" "$p" "$RST"
    drill_field "Network address" "$(int2ip "$net")"
    drill_field "Broadcast address" "$(int2ip "$bc")"
    drill_field "First usable host" "$(int2ip $((net + 1)))"
    drill_field "Last usable host" "$(int2ip $((bc - 1)))"
    drill_field "Usable hosts" "$(((1 << (32 - p)) - 2))"
    printf '\n  %sThe working:%s\n' "$BOLD" "$RST"
    subnet_explain "$ip" "$p"
    ((q < n)) && pageturn
  done
  printf '  %sDrill score: %d / %d fields correct%s\n\n' "$BOLD" "$DRILL_OK" "$DRILL_TOTAL" "$RST"
  journal "- SUBNET DRILL: $DRILL_OK/$DRILL_TOTAL fields correct ($(date '+%F %H:%M'))"
  printf 'drill|%s|%s|%s\n' "$DRILL_OK" "$DRILL_TOTAL" "$(date '+%F %T')" >>"$SCORES"
  return 0
}

drill_page(){
  section_like "SUBNETTING DRILL"
  say "Five random questions. Work each one out on paper first (block-size method), then type your answers. Every question ends with the full binary explanation."
  subnet_drill 5
}

# ------------------------------------------------------ troubleshooting -----
TK_TITLE=("" "Nothing works off my desk" "The router seems dead" "New address, no network"
  "Ping works, the website does not" "Connection refused" "The colleague's PC is acting strange"
  "Server room 'tidy-up'" "The intranet name is broken, only for me" "Only big downloads hang"
  "Requests arrive, replies never leave")
TK_LEVEL=(0 1 1 2 2 2 2 3 3 3 3)
TK_STORY=(""
  "Alex (c1-student, 10.77.1.10): 'I can ping my colleague's PC (10.77.1.11), but nothing on the server network works. http://10.77.2.20:8000 is down for me!'"
  "Helpdesk: 'Everybody on LAN A can ping the router at 10.77.1.1, but nobody reaches the intranet server 10.77.2.20. The server team says the server is fine.'"
  "Alex: 'IT changed my PC's address this morning. Since then nothing works, not even my colleague's PC right next to me.'"
  "Alex: 'The intranet (http://10.77.2.20:8000) times out. The server team says: ping works, so the network is fine; it must be your browser.'"
  "Helpdesk: 'After maintenance, everybody gets Connection refused on http://10.77.2.20:8000. The server admin swears the web service is running.'"
  "Alex: 'I can reach my colleague's PC (10.77.1.11), but nothing beyond it. By the way, that PC has been acting strange lately.'"
  "Facilities: 'A technician tidied the cables in the server room. Now the intranet server 10.77.2.20 is unreachable from everywhere. The router looks fine.'"
  "Alex: 'http://intranet.c1dc.lab:8000 does not work for me, but my colleagues can open it, and http://10.77.2.20:8000 works for me too. IT restarted the DNS server: no change.'"
  "Alex: 'The intranet home page opens, but the download http://10.77.2.20:8000/big.bin just hangs forever. Small pages are fine.'"
  "Server admin: 'The intranet is unreachable, but I ran tcpdump on the server and the requests ARE arriving. The problem must be on your side!'")
TK_H1=("" "The same LAN works, another network fails. What does a host need in order to reach OTHER networks?"
  "Hosts reach the router; does the router reach the server (try it from a router shell)? What does the router do with packets that are not for itself?"
  "Even the neighbour fails. Start at layer 3 on the student: address and prefix."
  "Ping and the web service are different protocols. Could something in the middle treat them differently?"
  "'Refused' means a RST came back: the server host IS reachable. What exactly is listening on the server, and on which address?"
  "Off-LAN traffic goes to the gateway's MAC. Which MAC is the student actually using for 10.77.1.1?"
  "Start at the server itself (shell, host 5). Layers 1 and 2 first."
  "The IP works, the name does not: compare dig with getent on the student PC."
  "Small works, big fails: think about size limits along the path."
  "If the requests arrive, look at how the server sends its REPLIES.")
TK_H2=("" "Read the student's routing table: sudo ip -n c1-student route"
  "Check the router's forwarding switch: sudo ip netns exec c1-router sysctl net.ipv4.ip_forward"
  "Compare the address with the lab map: sudo ip -n c1-student -br addr (and check the routes)."
  "Read the router's firewall: sudo ip netns exec c1-router nft list ruleset"
  "On the server: sudo ip netns exec c1-server ss -tln (look at the local address of port 8000)."
  "sudo ip -n c1-student neigh: compare the MAC for 10.77.1.1 with the lab map (menu M)."
  "sudo ip -n c1-server -br link, then sudo ip -n c1-server route"
  "getent consults /etc/hosts first. For the student namespace that file is /etc/netns/c1-student/hosts."
  "Compare the MTU of every interface on the path and test with ping -M do -s 1472. Also read the router's nft ruleset."
  "sudo ip -n c1-server route, and sudo ip -n c1-server neigh (look for FAILED).")
TK_H3=("" "Fix: sudo ip -n c1-student route add default via 10.77.1.1"
  "Fix: sudo ip netns exec c1-router sysctl -w net.ipv4.ip_forward=1"
  "Remove the wrong address, add 10.77.1.10/24, then re-add the default route via 10.77.1.1."
  "Delete the offending table: sudo ip netns exec c1-router nft delete table inet c1dc_ticket"
  "The bind address in ~/c1dc-network-labs/lab/services.conf is wrong. Fix WEB_BIND, then run: sudo ~/c1dc-network-labs/tools/labctl restart web"
  "Delete the poisoned entry: sudo ip -n c1-student neigh del 10.77.1.1 dev eth0"
  "Bring the interface up (ip -n c1-server link set eth0 up) and re-add the server's default route via 10.77.2.1."
  "Remove the bad line from the hosts file: sudo nano /etc/netns/c1-student/hosts"
  "Restore MTU 1500 on the router's eth0, and delete the nft table c1dc_ticket that drops the ICMP 'frag needed' messages."
  "Fix: sudo ip -n c1-server route replace default via 10.77.2.1")
TK_CAUSE=(""
  "The student's default route was missing. Same-LAN traffic needs no gateway, so the colleague still worked; everything else got 'Network is unreachable'."
  "IP forwarding was disabled on the router (net.ipv4.ip_forward=0). Hosts could talk TO the router, but it refused to pass packets THROUGH it."
  "The student was given 10.77.10.10/24, a different subnet from its LAN. The gateway was no longer on-link, so the kernel removed the default route, and even the neighbour became 'remote'."
  "A firewall rule on the router dropped TCP port 8000 while ICMP passed. 'Ping works' says nothing about other protocols."
  "The web server was bound to 127.0.0.1 (services.conf). It accepted connections only from the server itself; remote SYNs got a RST."
  "ARP poisoning: a permanent neighbour entry mapped the gateway 10.77.1.1 to the PEER's MAC (02:c1:dc:01:00:11). Off-LAN traffic went to the peer, which dropped it. In real life this is a man-in-the-middle indicator: two IPs sharing one MAC."
  "The server's eth0 was administratively down. Bringing it back up restores the connected route, but NOT the default route the kernel removed: two faults to fix."
  "A hosts-file entry on the student PC mapped intranet.c1dc.lab to 10.77.2.99. The hosts file is consulted before DNS, so DNS was healthy but never asked. Malware uses the same trick."
  "A path-MTU black hole: the router's eth0 MTU was 1400 and an nft rule dropped the ICMP 'fragmentation needed' messages, so full-size packets vanished silently while small ones passed."
  "The server's default route pointed to 10.77.2.254, which does not exist. Requests arrived, but replies were sent towards a dead next hop (neighbour FAILED). Always check the return path.")
TK_FIX=(""
  "ip -n c1-student route add default via 10.77.1.1"
  "ip netns exec c1-router sysctl -qw net.ipv4.ip_forward=1"
  "ip -n c1-student addr del 10.77.10.10/24 dev eth0; ip -n c1-student addr add 10.77.1.10/24 dev eth0; ip -n c1-student route add default via 10.77.1.1"
  "ip netns exec c1-router nft delete table inet c1dc_ticket"
  "sed -i 's/^WEB_BIND=.*/WEB_BIND=10.77.2.20/' '$LABDIR/services.conf'; '$TOOLS/labctl' restart web"
  "ip -n c1-student neigh del 10.77.1.1 dev eth0"
  "ip -n c1-server link set eth0 up; ip -n c1-server route add default via 10.77.2.1"
  "sed -i '/10.77.2.99/d' /etc/netns/c1-student/hosts"
  "ip -n c1-router link set eth0 mtu 1500; ip netns exec c1-router nft delete table inet c1dc_ticket"
  "ip -n c1-server route replace default via 10.77.2.1")

tk_apply(){
  case $1 in
    1) priv "ip -n c1-student route del default" ;;
    2) priv "ip netns exec c1-router sysctl -qw net.ipv4.ip_forward=0" ;;
    3) priv "ip -n c1-student addr del 10.77.1.10/24 dev eth0; ip -n c1-student addr add 10.77.10.10/24 dev eth0" ;;
    4) priv "ip netns exec c1-router nft 'add table inet c1dc_ticket'; ip netns exec c1-router nft 'add chain inet c1dc_ticket forward { type filter hook forward priority -10 ; }'; ip netns exec c1-router nft 'add rule inet c1dc_ticket forward tcp dport 8000 drop'" ;;
    5) priv "sed -i 's/^WEB_BIND=.*/WEB_BIND=127.0.0.1/' '$LABDIR/services.conf'; '$TOOLS/labctl' restart web" ;;
    6) priv "ip -n c1-student neigh replace 10.77.1.1 lladdr $PEER_MAC dev eth0 nud permanent" ;;
    7) priv "ip -n c1-server link set eth0 down" ;;
    8) priv "sed -i '1i 10.77.2.99 intranet.c1dc.lab' /etc/netns/c1-student/hosts" ;;
    9) priv "ip -n c1-router link set eth0 mtu 1400; ip netns exec c1-router nft 'add table inet c1dc_ticket'; ip netns exec c1-router nft 'add chain inet c1dc_ticket output { type filter hook output priority 0 ; }'; ip netns exec c1-router nft 'add rule inet c1dc_ticket output icmp type destination-unreachable drop'" ;;
    10) priv "ip -n c1-server route replace default via 10.77.2.254" ;;
  esac
}
# "works" = curl itself succeeds (exit 0, the whole body arrived) AND the status is 200.
# (curl prints 200 as soon as the headers arrive, even if the body then times out.)
tk_web_ok(){ priv "c=\$(ip netns exec c1-student curl -s -o /dev/null -w '%{http_code}' --max-time ${2:-4} ${1:-http://10.77.2.20:8000/}) && [ \"\$c\" = 200 ]"; }
tk_check(){
  case $1 in
    1) priv "ip -n c1-student route show default | grep -q 'via 10.77.1.1'" && tk_web_ok ;;
    3) priv "ip -n c1-student -4 addr show dev eth0 | grep -q '10.77.1.10/24'" && tk_web_ok ;;
    6) ! priv "ip -n c1-student neigh show 10.77.1.1 | grep -qi '$PEER_MAC'" && tk_web_ok ;;
    8) priv "ip netns exec c1-student getent hosts intranet.c1dc.lab | grep -q '^10.77.2.20 '" && tk_web_ok http://intranet.c1dc.lab:8000/ ;;
    9) tk_web_ok http://10.77.2.20:8000/big.bin 8 ;;
    *) tk_web_ok ;;
  esac
}
stars(){ local i s=''; if ((UTF == 0)); then printf 'level %s/3' "$1"; return; fi; for i in 1 2 3; do if ((i <= $1)); then s+="★"; else s+="☆"; fi; done; printf '%s' "$s"; }
tk_solved(){ grep -qx "$1" "$STATE_DIR/tickets_solved" 2>/dev/null; }

ticket_card(){
  local t=$1
  echo
  boxline "$DTL" "$DH" "$DTR"
  boxtext "TICKET #$t  ·  ${TK_TITLE[t]}" "$BYEL"
  boxtext "Difficulty: $(stars "${TK_LEVEL[t]}")" "$DIM"
  boxline "$DBL" "$DH" "$DBR"
  echo
  wrap "  $BOLD REPORT:$RST " '          ' 10 "${TK_STORY[t]}"
  echo
  say "The fault is hidden in the cyber-range. Investigate like an engineer: define the problem, gather facts, form a hypothesis, test one thing at a time. Note your observations as you go."
}

ticket_run(){ # ticket_run NUMBER [resume]
  local t=$1 resume=${2:-} c hints=0 start note
  if [[ -z $resume ]]; then
    info "Resetting the cyber-range to a clean state, then injecting the fault… (which fault stays secret: that is the point)"
    lab_reset || { bad "Could not rebuild the lab."; return 1; }
    tk_apply "$t" >/dev/null 2>&1; printf '%s\n' "$t" >"$TICKET_FILE"
  fi
  start=$(date +%s)
  journal "" "### Ticket #$t — ${TK_TITLE[t]} (started $(date '+%H:%M'))"
  ticket_card "$t"
  while true; do
    printf '\n  %sS%s shell on a lab host  %sH%s hint (%d/3 used)  %sV%s verify my fix  %sM%s map  %sR%s reveal  %sQ%s leave\n' \
      "$BCYN" "$RST" "$BCYN" "$RST" "$hints" "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST"
    read -r -p "  ticket #$t $PROMPT " c || return 0
    case ${c^^} in
      S) lab_shell ;;
      M) lab_map ;;
      H)
        if ((hints >= 3)); then warn "No more hints. Use R to reveal if you are truly stuck."; continue; fi
        ((++hints))
        case $hints in 1) callout tip "${TK_H1[t]}" ;; 2) callout tip "${TK_H2[t]}" ;; 3) callout tip "${TK_H3[t]}" ;; esac
        journal "  - used hint $hints" ;;
      V)
        info "Re-testing from the user's point of view…"
        if tk_check "$t" 2>/dev/null; then
          local mins=$((($(date +%s) - start + 59) / 60)) score=$((100 - 20 * hints))
          echo; good "{b}RESOLVED!{/} The user's problem is gone. Time: about ${mins} min · hints: $hints · score: $score/100"
          callout concept "{b}Root cause:{/} ${TK_CAUSE[t]}"
          ask "Write your root-cause note for the ticket (one or two sentences)"; note=$REPLY_TEXT
          journal "  - RESOLVED in ~${mins} min with $hints hint(s), score $score" "  - my root-cause note: ${note:-<blank>}"
          grep -qx "$t" "$STATE_DIR/tickets_solved" 2>/dev/null || printf '%s\n' "$t" >>"$STATE_DIR/tickets_solved"
          rm -f "$TICKET_FILE"; return 0
        else
          bad "Not fixed yet: the user's problem still happens. What did you change? Re-test it yourself from the user's PC (c1-student)."
        fi ;;
      R)
        callout concept "{b}Root cause:{/} ${TK_CAUSE[t]}" "{b}Fix (as root):{/} ${TK_FIX[t]}"
        journal "  - REVEALED after $hints hint(s)"
        local a; read -r -p "  Apply the fix for you? [y/N] $PROMPT " a || a=n
        if [[ ${a,,} == y* ]]; then priv "${TK_FIX[t]}" >/dev/null 2>&1; tk_check "$t" 2>/dev/null && good "Fixed and verified."; rm -f "$TICKET_FILE"; fi
        return 0 ;;
      Q) warn "Leaving the ticket. The lab stays broken until you come back (menu T) or rebuild it (menu L)."; return 0 ;;
    esac
  done
}

tickets_selftest(){
  local t
  for t in 1 2 3 4 5 6 7 8 9 10; do
    lab_reset >/dev/null 2>&1 || { st_record "T$t" fail "lab reset failed"; continue; }
    tk_apply "$t" >/dev/null 2>&1
    if tk_check "$t" >/dev/null 2>&1; then st_record "T$t" fail "ticket $t: the fault had no effect"; bad "ticket #$t: the fault did not break anything"; continue; fi
    priv "${TK_FIX[t]}" >/dev/null 2>&1
    if tk_check "$t" >/dev/null 2>&1; then st_record "T$t" pass; good "ticket #$t (${TK_TITLE[t]}): fault reproduced, documented fix verified"
    else st_record "T$t" fail "ticket $t: the fix did not verify"; bad "ticket #$t: the documented fix did not verify"; fi
  done
  lab_reset >/dev/null 2>&1
  return 0
}

tickets_menu(){
  if ((NONINTERACTIVE)); then tickets_selftest; return 0; fi
  lab_ensure || return 0
  local t c
  while true; do
    section_like "TROUBLESHOOTING TICKETS"
    [[ -f $TICKET_FILE ]] && warn "Ticket #$(cat "$TICKET_FILE") is still active. Enter C to continue it."
    for t in 1 2 3 4 5 6 7 8 9 10; do
      if tk_solved "$t"; then c="$BGRN$OK$RST"; else c="$GRY$BUL$RST"; fi
      printf '    %s %2d  %-44s %s\n' "$c" "$t" "${TK_TITLE[t]}" "$(stars "${TK_LEVEL[t]}")"
    done
    echo
    read -r -p "  Ticket number (1-10), C = continue the active one, Q = back $PROMPT " c || return 0
    case ${c^^} in
      Q | '') return 0 ;;
      C) [[ -f $TICKET_FILE ]] && ticket_run "$(cat "$TICKET_FILE")" resume ;;
      *) [[ $c =~ ^([1-9]|10)$ ]] && ticket_run "$c" ;;
    esac
  done
}

# ------------------------------------------------------------ threat hunt ---
hunt_generate(){
  lab_ensure || return 1
  command -v tcpdump >/dev/null 2>&1 || return 1
  local f="$EVID/hunt.pcap" a i
  if [[ -s $f ]] && ((NONINTERACTIVE == 0)); then
    read -r -p "  A hunt capture already exists. Record a fresh one? [y/N] $PROMPT " a || a=n
    [[ ${a,,} == y* ]] || return 0
  fi
  cat >"$LABDIR/hunt-scenario.sh" <<EOF
#!/usr/bin/env bash
# The incident the academy plays for module 14. SPOILERS: do not read before the hunt!
rm -f '$f' '$RUNDIR/hunt.done'
ip netns exec c1-router timeout 26 tcpdump -i eth0 -nn -U -Z root -w '$f' not arp >/dev/null 2>&1 &
sleep 1.5
( for i in 1 2 3 4; do ip netns exec c1-student curl -s -o /dev/null -A 'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Firefox/128.0' http://intranet.c1dc.lab:8000/; sleep 5; done ) &
( sleep 2; for i in 1 2 3 4 5 6 7; do ip netns exec c1-student curl -s -o /dev/null -A 'c1-updater/2.1' 'http://10.77.2.20:8000/update?host=ws-010&id=7f3a91'; sleep 3; done ) &
( sleep 6; ip netns exec c1-peer nmap -sS -Pn -T4 -p 1-200,8000,8443 10.77.2.20 >/dev/null 2>&1 ) &
( sleep 12; ip netns exec c1-peer curl -s -o /dev/null -d 'user=jsmith&password=Summer-Trout-42' http://10.77.2.20:8000/login ) &
( sleep 9; for s in 6b3f2a9c0d1e4f aa91c3e07b5d22 0c7e9d1f33a8b6; do ip netns exec c1-student dig @10.77.2.20 +short TXT \$s.exfil.c1dc.lab >/dev/null 2>&1; sleep 1; done ) &
wait
chown '$RUN_AS:' '$f'; chmod 600 '$f'
touch '$RUNDIR/hunt.done'
EOF
  rm -f "$RUNDIR/hunt.done"
  printf '\n  %sRecording the incident%s (sensor: tcpdump on c1-router eth0, about 26 seconds)\n  ' "$BOLD" "$RST"
  priv_bg "bash '$LABDIR/hunt-scenario.sh'"
  for i in $(seq 1 70); do
    [[ -f $RUNDIR/hunt.done ]] && break
    ((i % 2 == 0)) && printf '%s' "$BGRN$FULL$RST"
    sleep 0.5
  done
  printf '\n'
  [[ -s $f ]] || { bad "No capture was recorded."; return 1; }
  good "Evidence saved: ${f/#$HOME/\~} ($(stat -c %s "$f") bytes)"
  return 0
}

HUNT_SCANNER=''; HUNT_PORTS=''; HUNT_OPEN=''
hunt_answers(){
  local f="$EVID/hunt.pcap" top
  top=$(tcpdump -nn -r "$f" 'tcp[tcpflags] == tcp-syn' 2>/dev/null |
    awk '{split($3,a,"."); split($5,b,"."); p=b[5]; sub(":","",p); print a[1]"."a[2]"."a[3]"."a[4], p}' |
    sort -u | awk '{c[$1]++} END {for (s in c) print c[s], s}' | sort -rn | head -1)
  HUNT_PORTS=${top%% *}; HUNT_SCANNER=${top#* }
  HUNT_OPEN=$(tcpdump -nn -r "$f" "src host 10.77.2.20 and dst host $HUNT_SCANNER and tcp[tcpflags] == (tcp-syn|tcp-ack)" 2>/dev/null |
    awk '{split($3,a,"."); sub(":","",a[5]); print a[5]}' | sort -un | paste -sd, -)
}
norm_set(){ grep -oE '[0-9]+' <<<"$1" | sort -un | paste -sd, -; }

hunt_ask(){ # hunt_ask "question" "expected" MODE "hint"
  local q=$1 want=$2 mode=$3 hint=$4 ans tries=0 ok x
  ((++Q_TOTAL))
  printf '\n  %s HUNT QUESTION %s\n' "$BMAG$REV" "$RST"; wrap '  ' '  ' 2 "{b}$q{/}"
  while true; do
    if ((NONINTERACTIVE)); then ans=$want
    else read -e -r -p "  Answer (a = analysis shell, h = hint, s = show answer) $PROMPT " ans || ans=s; fi
    case ${ans,,} in
      a) analysis_shell; continue ;;
      h) callout tip "$hint"; continue ;;
      s) warn "Answer: $want"; journal "- HUNT: $q -> revealed ($want)"; return 0 ;;
    esac
    ok=0
    case $mode in
      exact) [[ ${ans// /} == "$want" ]] && ok=1 ;;
      number) [[ $(grep -oE '[0-9]+' <<<"$ans" | head -1) == "$want" ]] && ok=1 ;;
      interval) x=$(grep -oE '[0-9]+([.][0-9]+)?' <<<"$ans" | head -1)
                [[ -n $x ]] && awk -v x="$x" -v w="$want" 'BEGIN{exit !(x>=w-0.6 && x<=w+0.6)}' && ok=1 ;;
      contains) if ((${#ans} >= 4)) && [[ ${want,,} == *"${ans,,}"* || ${ans,,} == *"${want,,}"* ]]; then ok=1; fi ;;
      set) [[ -n $(norm_set "$ans") && $(norm_set "$ans") == "$(norm_set "$want")" ]] && ok=1 ;;
    esac
    if ((ok)); then ((++Q_OK)); good "Correct."; journal "- HUNT: $q -> $ans (correct)"; return 0; fi
    ((++tries)); bad "Not quite. Check your filter and count again (or h for a hint)."
    if ((tries >= 3)); then warn "Answer: $want"; journal "- HUNT: $q -> missed ($want)"; return 0; fi
  done
}

hunt_questions(){
  hunt_answers
  say "Investigate with any tools you like: open an analysis shell with {b}a{/} at any question, or work in a second terminal inside ~/c1dc-network-labs/evidence. Good starting points:"
  figure "Useful hunting commands (run them inside evidence/)" <<'EOF'
  tcpdump -nn -r hunt.pcap 'tcp[tcpflags] == tcp-syn' | head -20
  tshark  -r hunt.pcap -q -z endpoints,ip
  tshark  -r hunt.pcap -Y http.request -T fields -e frame.time_relative \
          -e ip.src -e http.user_agent -e http.request.uri
  tcpdump -nn -A -r hunt.pcap 'tcp port 8000' | grep -a -i pass
  tshark  -r hunt.pcap -Y 'dns.flags.response == 0' -T fields -e ip.src -e dns.qry.name
EOF
  hunt_ask "Which IP address performed a port scan?" "$HUNT_SCANNER" exact \
    "Look for one source sending SYNs to many different destination ports: tcpdump -nn -r hunt.pcap 'tcp[tcpflags] == tcp-syn'"
  hunt_ask "How many DIFFERENT destination ports did the scanner send SYNs to?" "$HUNT_PORTS" number \
    "tcpdump -nn -r hunt.pcap 'src host SCANNER and tcp[tcpflags] == tcp-syn' | awk '{print \$5}' | sort -u | wc -l"
  hunt_ask "Which TCP ports on 10.77.2.20 answered the scanner as OPEN? (comma-separated)" "$HUNT_OPEN" set \
    "Open ports answer with SYN-ACK: tcpdump -nn -r hunt.pcap 'src host 10.77.2.20 and tcp[tcpflags] == (tcp-syn|tcp-ack)'"
  hunt_ask "One host repeats the same HTTP request regularly (a beacon). Every how many seconds?" "3" interval \
    "List the HTTP requests with their relative time and URI (tshark … -Y http.request …), then subtract the times of the repeating /update requests."
  hunt_ask "What User-Agent does the beacon use?" "c1-updater/2.1" contains \
    "tshark -r hunt.pcap -Y 'http.request.uri contains \"update\"' -T fields -e http.user_agent"
  hunt_ask "A password crossed the network in clear text. What is it?" "Summer-Trout-42" contains \
    "Plain HTTP POST bodies are readable: tcpdump -nn -A -r hunt.pcap 'tcp port 8000' | grep -a password"
  if command -v dnsmasq >/dev/null 2>&1; then
    hunt_ask "Which domain receives the suspicious, random-looking DNS queries?" "exfil.c1dc.lab" contains \
      "tshark -r hunt.pcap -Y 'dns.flags.response == 0' -T fields -e dns.qry.name"
  fi
  printf '\n  %sHunt score: %d / %d%s\n' "$BOLD" "$Q_OK" "$Q_TOTAL" "$RST"
}

# -------------------------------------------------------- reference sheets ---
reference(){
  section_like "COMMAND REFERENCE"
  figure "Look at your own machine" <<'EOF'
  ip -br link             interfaces, state, MAC        ip -s link         counters, errors
  ip -br addr             addresses and prefixes        ip route           routing table
  ip route get <IP>       which way would it go?        ip neigh           ARP / NDP cache
  ss -tuln                listening sockets             ss -tunap          sockets + process
  cat /etc/resolv.conf    DNS servers                   getent hosts NAME  resolve like apps do
EOF
  figure "Test connectivity" <<'EOF'
  ping -c 3 <IP>          L3 reachability               ping -M do -s 1472 <IP>  MTU test
  traceroute -n <IP>      every hop                     dig @SERVER NAME TYPE    raw DNS answer
  curl -v http://H:P/     HTTP conversation             curl --cacert C https:// trusted TLS
  openssl s_client -connect H:P -brief                  TLS version, cipher, certificate
  nmap -sn NET/24 · nmap -sT -Pn -p PORTS IP · nmap -sU -p PORTS IP   (authorised targets only)
EOF
  figure "Capture and analyse" <<'EOF'
  tcpdump -i IF -nn -c N FILTER      live capture        tcpdump -nn -r F.pcap     read a file
  tcpdump … -w - FILTER > F.pcap     save (you own it)   tcpdump -nn -XX -r F      raw bytes
  tshark -r F -Y 'DISPLAY FILTER'    decoded view        tshark -r F -q -z conv,ip statistics
  capinfos F · sha256sum F           evidence summary and fingerprint
  BPF: host X · net 10.77.1.0/24 · tcp port 80 · icmp · arp · 'tcp[tcpflags] & tcp-syn != 0'
EOF
  figure "Inside the cyber-range" <<'EOF'
  sudo ip netns exec c1-student CMD               run any command on a lab host
  sudo ip -n c1-router route                      shortcut for ip commands
  sudo ~/c1dc-network-labs/tools/labctl status    lab services (restart web|tls|dns|udp)
  menu S = root shell on a lab host · M = map · L = rebuild · T = tickets
EOF
  say "Further study: RFC 791 (IPv4), RFC 8200 (IPv6), RFC 9293 (TCP), RFC 768 (UDP), RFC 826 (ARP), RFC 1034/1035 (DNS), RFC 2131 (DHCP), RFC 8446 (TLS 1.3), the Wireshark User's Guide and the Nmap Reference Guide. Then practise with GNS3 or containerlab, Zeek and Suricata."
}

glossary(){
  section_like "GLOSSARY"
  terms "ARP :: Address Resolution Protocol: finds the MAC for an IPv4 address on the LAN." \
    "Bridge :: A software switch (Linux br0)." \
    "Broadcast :: A frame or packet for every host on the LAN (ff:ff:ff:ff:ff:ff, x.x.x.255)." \
    "CIDR / prefix :: The /24 notation: the number of network bits." \
    "Conntrack :: The kernel's table of connections, used by stateful firewalls and NAT." \
    "Default gateway :: The router a host uses for every non-local destination." \
    "DHCP :: Hands out IP configuration (DORA, UDP 67/68)." \
    "DNS :: Translates names to addresses and more (UDP/TCP 53)." \
    "Encapsulation :: Wrapping data in successive headers (segment → packet → frame)." \
    "Ephemeral port :: A random client-side port for one connection." \
    "Frame / packet / segment :: The unit of data at L2 / L3 / L4." \
    "ICMP :: IP's control and error messages (ping, unreachable, time exceeded)." \
    "Link-local :: An address valid on one link only (169.254/16, fe80::/10)." \
    "MAC address :: The 48-bit hardware address of an interface; hop-local." \
    "MTU / MSS :: Max IP packet size on a link / max TCP payload per segment." \
    "NAT / PAT :: Rewriting addresses (and ports) as packets cross a device." \
    "NDP :: IPv6 Neighbor Discovery: ARP's replacement (ICMPv6)." \
    "Namespace (netns) :: An isolated copy of the Linux network stack: how our lab works." \
    "PCAP :: The packet capture file format." \
    "Port :: A 16-bit number selecting the program at L4." \
    "RST :: TCP reset: 'abort' or 'nobody listens here'." \
    "Socket :: One endpoint of a conversation: IP + port + protocol." \
    "Stateful firewall :: A firewall that tracks connections and allows replies automatically." \
    "Subnet mask :: The prefix written as 1s and 0s (255.255.255.0)." \
    "TLS :: Encryption + integrity + server authentication for TCP (HTTPS)." \
    "TTL / Hop Limit :: A hop counter decremented by every router; 0 = discard." \
    "VLAN / 802.1Q :: A virtual LAN; the 4-byte tag that carries its ID on trunks."
}

# =============================================================================
# PART 6 · INTRO, MENU AND ENTRY POINT
# =============================================================================
banner(){
  echo
  if ((UTF)); then
    printf '%s' "$BCYN"
    cat <<'EOF'
     ██████╗ ██╗██████╗  ██████╗
    ██╔════╝███║██╔══██╗██╔════╝     NETWORK ACADEMY
    ██║     ╚██║██║  ██║██║          for cybersecurity professionals
    ██║      ██║██║  ██║██║
    ╚██████╗ ██║██████╔╝╚██████╗     read · predict · type · prove · explain
     ╚═════╝ ╚═╝╚═════╝  ╚═════╝
EOF
    printf '%s' "$RST"
  else
    printf '%s    C1DC NETWORK ACADEMY  -  for cybersecurity professionals%s\n' "$BCYN" "$RST"
  fi
  printf '    %sv%s · single-file course for Kali Linux · labs isolated in network namespaces%s\n\n' "$DIM" "$VERSION" "$RST"
}

intro(){
  clear_screen; term_width; banner
  section_like "HOW THIS ACADEMY WORKS"
  say "This is not a script that runs commands for you. It is a course you {b}work through{/}: you read a concept, predict what will happen, type the real command yourself, read the live output with a field guide, and explain it. Everything you predict and write is saved in your journal as evidence of your own learning."
  figure "Every practical follows the same rhythm" <<'EOF'
   1  READ       the concept, the diagram and the analogy
   2  PREDICT    write down what you expect BEFORE running anything
   3  TYPE       the command yourself (arrow keys work, h = hint)
   4  READ       the live output with the 'how to read it' field guide
   5  EXPLAIN    answer the reflection, then compare with an expert answer
EOF
  say "Look out for these boxes:"
  callout concept "The core idea, in plain words."
  callout analogy "A comparison with everyday life, to make the idea stick."
  callout deep "What the kernel and the protocol are really doing."
  callout security "How attackers abuse it, and how defenders see it."
  callout turn "Do it again on your own, without the academy holding your hand."
  pageturn
  section_like "THE COURSE"
  figure "16 modules in five tracks, plus free practice" <<'EOF'
  FOUNDATIONS         01 hardware · 02 OSI/TCP-IP · 03 addressing · 04 ARP
  CORE PROTOCOLS      05 DHCP & DNS · 06 TCP/UDP/ICMP · 07 packet analysis
  INFRASTRUCTURE      08 routing & NAT · 09 switching & VLANs · 10 firewalls
  APPLIED & ADVANCED  11 HTTP & TLS · 12 IPv6 & MTU · 13 recon · 14 hunting
  OPERATIONS          15 troubleshooting (10 break-and-fix tickets) · 16 exam
  PRACTICE            subnetting drill · tickets · root shells on every lab host
EOF
  say "Plan about {b}11 hours{/} in total: for example three 4-hour workshops (01-07, 08-12, 13-16), or self-paced. Modules 01-03 need nothing but your Kali machine. From module 04 on you use the {b}cyber-range{/}: five virtual hosts inside your machine, built with Linux network namespaces and fully isolated from your real network."
  say "{b}Rules:{/} authorised systems only (this lab, or written permission); no scanning of public networks; no changes to production networks; protect your captures, they can contain secrets." \
      "{b}Instructors:{/} students should explain every output in their own words. The journal (~/c1dc-network-labs/journal.md) records every prediction and answer. Run {c}bash $(basename "$0") --self-test{/} on a fresh VM before class."
  pause
}

check_dependencies(){
  section_like "READINESS CHECK"
  local d grp ok=1
  for grp in "REQUIRED|bash ip ss ping sudo python3 grep awk setsid" \
             "LAB TOOLS|tcpdump nmap curl dig nft dnsmasq traceroute bridge openssl" \
             "ANALYSIS|tshark capinfos wireshark sha256sum"; do
    printf '  %s%s%s\n' "$BOLD" "${grp%%|*}" "$RST"
    for d in ${grp#*|}; do
      if command -v "$d" >/dev/null 2>&1; then printf '    %s%s%s %s\n' "$BGRN" "$OK" "$RST" "$d"
      else
        printf '    %s%s%s %s %s(missing)%s\n' "$BYEL" "$NO" "$RST" "$d" "$DIM" "$RST"
        [[ ${grp%%|*} == REQUIRED ]] && ok=0
      fi
    done
  done
  echo
  info "Install everything on Kali with:"
  printf '    %ssudo apt update && sudo apt install -y iproute2 iputils-ping tcpdump tshark wireshark nmap dnsutils curl python3 nftables dnsmasq-base traceroute openssl%s\n\n' "$BCYN" "$RST"
  if ip netns list >/dev/null 2>&1; then good "Network namespaces are supported by this kernel."
  else warn "'ip netns' does not work here; the cyber-range needs network-namespace support (some containers block it)."; fi
  ((EUID == 0)) && warn "You are running as root. Run the academy as your normal user; it asks for sudo only when the lab needs it."
  if ((ok)); then good "Required tools are present."; else bad "Install the missing required tools first."; fi
  return 0
}

progress_view(){
  section_like "YOUR PROGRESS"
  local i n line qok qt pd dt solved=0 a b c
  for i in $(seq 1 16); do
    n=$(printf '%02d' "$i")
    if grep -Fxq "$n" "$PROGRESS" 2>/dev/null; then
      line=$(grep "^$n|" "$SCORES" 2>/dev/null | tail -1)
      IFS='|' read -r _ qok qt pd dt <<<"$line"
      printf '  %s%s%s %s  %-44s %squiz %s/%s · %s practicals · %s%s\n' "$BGRN" "$OK" "$RST" "$n" "${MOD_TITLE[i]}" "$DIM" "${qok:-?}" "${qt:-?}" "${pd:-?}" "${dt%% *}" "$RST"
    else
      printf '  %s%s %s  %s%s\n' "$GRY" "$BUL" "$n" "${MOD_TITLE[i]}" "$RST"
    fi
  done
  echo
  [[ -f $STATE_DIR/tickets_solved ]] && solved=$(sort -u "$STATE_DIR/tickets_solved" | grep -c .)
  info "Tickets solved: $solved / 10"
  line=$(grep '^drill|' "$SCORES" 2>/dev/null | tail -1)
  if [[ -n $line ]]; then IFS='|' read -r _ a b c <<<"$line"; info "Last subnetting drill: $a/$b fields correct (${c%% *})"; fi
  info "Journal: ${JOURNAL/#$HOME/\~}   ·   Evidence: ${EVID/#$HOME/\~}"
}

journal_view(){
  [[ -f $JOURNAL ]] || { info "No journal yet: it starts with your first module."; return 0; }
  if command -v less >/dev/null 2>&1; then less -R "$JOURNAL"; else cat "$JOURNAL"; fi
}

menu(){
  term_width
  local done_n=0 i n mark labtag prev='' st
  [[ -f $PROGRESS ]] && done_n=$(sort -u "$PROGRESS" | grep -c .)
  echo
  boxline "$DTL" "$DH" "$DTR"
  boxtext "C1DC NETWORK ACADEMY   ·   v$VERSION   ·   main menu" "$BCYN"
  boxline "$DBL" "$DH" "$DBR"
  if lab_ready; then st="$BGRN$DOT running$RST"; else st="$GRY$ODOT not built$RST"; fi
  printf '  Cyber-range: %s      Progress: %s %d/16\n' "$st" "$(progress_bar "$done_n" 16 20)" "$done_n"
  [[ -f $TICKET_FILE ]] && printf '  %sTicket #%s is active: the lab is deliberately broken (T to continue)%s\n' "$BYEL" "$(cat "$TICKET_FILE")" "$RST"
  for i in $(seq 1 16); do
    if [[ ${MOD_TRACK[i]} != "$prev" ]]; then
      printf '\n  %s%s%s\n' "$BOLD$CYN" "${MOD_TRACK[i]}" "$RST"; prev=${MOD_TRACK[i]}
    fi
    n=$(printf '%02d' "$i")
    if grep -Fxq "$n" "$PROGRESS" 2>/dev/null; then mark="$BGRN$OK$RST"; else mark="$GRY$BUL$RST"; fi
    if ((MOD_LAB[i])); then labtag="${MAG}lab$RST"; else labtag='   '; fi
    printf '    %s %s%s%s  %-44s %s %s%3sm%s\n' "$mark" "$BOLD" "$n" "$RST" "${MOD_TITLE[i]}" "$labtag" "$DIM" "${MOD_MIN[i]}" "$RST"
  done
  printf '\n  %sPRACTICE & TOOLS%s\n' "$BOLD$CYN" "$RST"
  printf '    %sL%s build/rebuild range   %sM%s lab map    %sS%s shell on a lab host   %sX%s remove range\n' "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST"
  printf '    %sD%s subnetting drill      %sT%s tickets    %sR%s command reference     %sG%s glossary\n' "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST"
  printf '    %sP%s progress   %sJ%s journal   %sC%s check tools   %sI%s introduction   %sQ%s quit\n\n' "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST" "$BCYN" "$RST"
}

run_module(){ local m; printf -v m 'module%02d' "$((10#$1))"; journal_init; "$m"; }

self_test(){
  NONINTERACTIVE=1; SELFTEST=1
  JOURNAL="$LABDIR/selftest-journal.md"; PROGRESS="$LABDIR/selftest-progress.txt"; SCORES="$LABDIR/selftest-scores.txt"
  : >"$JOURNAL"; : >"$PROGRESS"; : >"$SCORES"
  banner; check_dependencies
  sudo_ready || { bad "Self-test needs non-interactive sudo. Run 'sudo -v' first, then retry within a few minutes."; return 1; }
  section_like "SELF-TEST: BUILDING THE LAB"
  lab_build || return 1
  local i
  for i in $(seq 1 16); do run_module "$i"; done
  section_like "SELF-TEST RESULT"
  printf '  checks passed: %s%d%s   failed: %s%d%s\n' "$BGRN" "$ST_PASS" "$RST" "$BRED" "$ST_FAIL" "$RST"
  for i in "${ST_FAILS[@]}"; do bad "$i"; done
  if [[ ${C1DC_KEEP_LAB:-0} != 1 ]]; then lab_destroy quiet; info "Lab removed (set C1DC_KEEP_LAB=1 to keep it)."; fi
  ((ST_FAIL == 0))
}

usage(){
  cat <<EOF
Usage: bash $(basename "$0") [option]
  (no option)     interactive academy
  --module N      run module N (1-16)
  --lab           build the isolated cyber-range     --cleanup    remove it
  --map           lab map and service status         --shell NS   root shell in a lab host
  --drill [N]     subnetting drill (N questions)     --tickets    troubleshooting tickets
  --check         check installed tools              --self-test  run every lab unattended
  --ascii         plain ASCII output                 --no-color   no colours
EOF
}

main(){
  local -a args=()
  local a
  for a in "$@"; do [[ $a == --ascii || $a == --no-color ]] || args+=("$a"); done
  set -- "${args[@]+"${args[@]}"}"
  write_tools 2>/dev/null
  [[ -s $WWW/big.bin ]] || head -c 300000 /dev/urandom >"$WWW/big.bin" 2>/dev/null
  case "${1:-}" in
    --check) check_dependencies; return ;;
    --lab) lab_build; return ;;
    --cleanup) cleanup_lab; return ;;
    --map) lab_map; return ;;
    --shell) lab_shell "${2:-}"; return ;;
    --drill) journal_init; section_like "SUBNETTING DRILL"; subnet_drill "${2:-5}"; return ;;
    --tickets) journal_init; tickets_menu; return ;;
    --self-test) self_test; return ;;
    --version) echo "$VERSION"; return ;;
    --help | -h) usage; return ;;
    --module)
      [[ ${2:-} =~ ^(0?[1-9]|1[0-6])$ ]] || { echo "Use --module 1 through 16" >&2; return 2; }
      run_module "$2"; return ;;
    '') ;;
    *) usage >&2; return 2 ;;
  esac
  [[ -t 0 ]] || { echo "The interactive academy needs a terminal. Try --help." >&2; return 2; }
  set -o history 2>/dev/null; HISTFILE=''
  journal_init
  intro
  local option
  while true; do
    menu
    INTERRUPTED=0
    read -r -p "  Choose a module (01-16) or a letter $PROMPT " option || break
    case "${option^^}" in
      Q) printf '\n  See you in the next lab. Keep your journal and your evidence safe.\n\n'; break ;;
      I) intro ;;
      L) lab_build; pause ;;
      X) cleanup_lab; pause ;;
      M) lab_map; pause ;;
      S) lab_shell ;;
      C) check_dependencies; pause ;;
      P) progress_view; pause ;;
      R) reference; pause ;;
      G) glossary; pause ;;
      J) journal_view ;;
      D) drill_page; pause ;;
      T) tickets_menu ;;
      '') ;;
      *)
        if [[ $option =~ ^(0?[1-9]|1[0-6])$ ]]; then run_module "$option"; pause
        else warn "Unknown choice. Type a module number (01-16) or one of the letters shown."; fi ;;
    esac
  done
}

main "$@"
