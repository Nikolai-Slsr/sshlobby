# shellcheck shell=bash
# ui.sh: Menü-Engine, Tastatur, Rendering, Dialoge und Vordergrundbefehle.
#
# ═══ API (von screens.sh und tools*.sh genutzt, Details in docs/ARCHITECTURE.md) ═══════════
# Zwei Darstellungen, gleiche API und gleiche Nummern:
#   UI_MODE=tui   Pfeiltasten, Alternate Screen (stdin und stdout sind ein Terminal)
#   UI_MODE=line  nummerierte Zeilen, Eingabe zeilenweise von stdin (Pipe, Tests, Skripte)
#   SSHLOBBY_UI=line|tui erzwingt eine Darstellung (tui nur mit Terminal).
#
# ui_init                       Darstellung wählen, Traps setzen, Terminal vorbereiten
# ui_cleanup                    Terminal zurücksetzen (läuft automatisch bei EXIT, INT, TERM, HUP)
#
# Menü:
#   UI_ITEMS=("typ|wert|label|rechts|status[|spalten]" …)  typ: item (wählbar), header (Abschnitt),
#                                 disabled (Hinweiszeile), sep (Leerzeile)
#                                 status: run stop warn err fav gone danger (Markierung) oder leer
#                                 spalten: Tabellenzellen fürs TUI, durch Tab getrennt (optional)
#   ui_item typ wert label [rechts] [status] [spalten]   hängt an UI_ITEMS an, ersetzt | in Texten
#   ui_cell stil text             Zelle mit Stil (ok warn err info dim acc, Pills p-ok p-warn
#                                 p-err p-info) für spalten, rechts und ui_info-Werte
#   UI_INFO=("label|wert[|status]" …)            Infozeilen unter dem Titel
#   ui_info label wert [status]                  hängt an UI_INFO an
#   UI_KEYS=("taste|beschreibung" …)             Hotkeys des Screens (nicht b h j k l q /, keine Ziffern)
#   UI_ROOT=1                     Hauptmenü: q = quit, zurück-Tasten tun nichts
#   UI_STYLE=main                 Dashboard-Kopf (HOST_LABEL, VERSION, MODE, SYS_* aus sys_stats)
#   UI_PRESEL=wert                Cursor startet auf diesem Eintrag (sonst: zuletzt gewählter
#                                 Eintrag unter demselben Titel, sonst der erste)
#   UI_STAT="laufend|gesamt|unhealthy|einheit"   Zähler in der Kopfzeile (bleibt stehen)
#   ui_menu titel [untertitel]
#     → UI_ACT=select (UI_SEL=wert) | key (UI_SEL=taste) | back | quit | eof, Rückgabe immer 0.
#     Bei key steht in UI_KEYROW der Wert der markierten Zeile (TUI: Cursor; Zeilenmodus: „taste nr“,
#     z. B. „f 3“), sonst leer. So wirken Tasten wie f auf die markierte Zeile einer Liste.
#     Danach sind UI_ITEMS, UI_INFO, UI_KEYS, UI_ROOT, UI_STYLE, UI_PRESEL wieder leer.
#     TUI: / filtert die Liste live (Enter übernimmt, Esc hebt auf).
#
# Dialoge:
#   ui_confirm frage              → 0 nur bei j/J/y/Y
#   ui_msg stufe text             Meldung (stufe: info ok warn err), wartet auf Enter/Taste
#   ui_note stufe text            Meldung ohne Warten (Zeile bzw. Statuszeile bis zur nächsten Taste)
#   ui_pause                      „[Enter] weiter“
#   ui_input prompt [vorgabe]     → UI_INPUT (leer = vorgabe), Rückgabe 1 bei EOF/Abbruch
#   ui_loading [text]             TUI: Lade-Hinweis in der Statuszeile (Zeilenmodus: nichts)
#
# Vordergrundbefehle (Ctrl-C beendet nur den Befehl, sshlobby läuft weiter, danach PD_INT=1):
#   ui_run_fg cmd…                TUI verlassen, cmd ausführen, zurück; Rückgabe = Exit-Code von cmd
#   ui_run_page titel cmd…        Ausgabe von cmd (stdin </dev/null) im Betrachter (TUI: scrollbar,
#                                 kein Umbruch; Zeilenmodus: einfache Ausgabe, danach ui_pause)
#   ui_run_task text cmd…         nicht-interaktiv, Ausgabe gesammelt, „text…“ als Fortschritt,
#                                 bei Fehler ui_msg mit Exit-Code und Ausgabe
#   ui_check_rc rc was [ausgabe]  Fehlermeldung bei rc≠0 (nicht nach Ctrl-C)
#
# Rendering: nur ui_theme, die Funktionen _ui_render_* (Zeilenmodus) und _ui_tui_* (TUI) erzeugen
# Text und Farben. Die Logik (_ui_menu_*, _ui_move, _ui_scroll, Tasten) ruft sie nur auf.
# ═══════════════════════════════════════════════════════════════════════════════════════════
# shellcheck disable=SC2034,SC1111 # UI_* setzen die Screens (SC1111: „…“ sind gewollte Anführungszeichen)

UI_MODE=line UI_ACTIVE=0 UI_STTY="" UI_ROWS=24 UI_COLS=80
UI_ITEMS=() UI_INFO=() UI_KEYS=() UI_ROOT=0 UI_STYLE="" UI_PRESEL="" UI_STAT=""
UI_ACT="" UI_SEL="" UI_KEY="" UI_INPUT="" UI_KEYROW=""
declare -gA _UI_LAST=() _UK=()
declare -ga _UPOS=() _UVIS=() _UCR_D=() _UCR_T=() _UI_CRUMB=() _UI_FRAME=()
_UI_WINCH=0 _UI_SIG="" _UI_IN_READ=0 _UI_STATUS="" _UI_STATUS_LVL=info _UI_VIEW_H=10
_UI_PEND="" _UI_CLR=1 _UFILT="" _UFTYPE=0 _UPG_LOAD=0
_UI_SMCUP="" _UI_RMCUP="" _UI_CIVIS="" _UI_CNORM=""

# ─── Theme ─────────────────────────────────────────────────────────────────
# Fähigkeiten: _UI_UTF8 (Locale), _UI_NCOL 256 | 8 | 0 (NO_COLOR, kein Terminal). Ohne Farben
# bleiben fett/dim/reverse, die Auswahl ist dann ein reverse-Balken mit Marker ›.
ui_theme() {
  local loc=${LC_ALL:-${LC_CTYPE:-${LANG:-}}} n
  _UI_UTF8=0; case "${loc^^}" in *UTF-8*|*UTF8*) _UI_UTF8=1;; esac
  [ "${SYMBOLS_PREF:-auto}" = ascii ] && _UI_UTF8=0   # Einstellung „Symbole: nur ASCII“
  _UI_NCOL=0
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    n=$(tput colors 2>/dev/null); [[ $n =~ ^[0-9]+$ ]] || n=8
    if [ "$n" -ge 256 ]; then _UI_NCOL=256; elif [ "$n" -ge 8 ]; then _UI_NCOL=8; fi
  fi
  if [ -t 1 ]; then C_R=$'\e[0m' C_B=$'\e[1m' C_D=$'\e[2m' C_REV=$'\e[7m'; else C_R="" C_B="" C_D="" C_REV=""; fi
  case "$_UI_NCOL" in
    256)
      C_CYA=$'\e[38;5;75m' C_GRN=$'\e[38;5;114m' C_YLW=$'\e[38;5;221m' C_RED=$'\e[38;5;203m'
      C_GRY=$'\e[38;5;245m' C_WHT=$'\e[38;5;253m' C_MAG=$'\e[38;5;176m' C_SEL=$'\e[1;38;5;117m'
      C_RULE=$'\e[38;5;239m' C_BAR=$'\e[48;5;236m' C_DLG=$'\e[48;5;235m' C_SELBG=$'\e[48;5;24m\e[38;5;255m'
      C_POK=$'\e[48;5;22m\e[38;5;157m' C_PWRN=$'\e[48;5;94m\e[38;5;230m' C_PERR=$'\e[48;5;88m\e[38;5;224m'
      C_PINF=$'\e[48;5;239m\e[38;5;254m' C_BADGE=$'\e[1;48;5;61m\e[38;5;255m';;
    8)
      C_CYA=$'\e[36m' C_GRN=$'\e[32m' C_YLW=$'\e[33m' C_RED=$'\e[31m'
      C_GRY=$'\e[90m' C_WHT=$'\e[37m' C_MAG=$'\e[35m' C_SEL=$'\e[1;36m'
      C_RULE=$'\e[90m' C_BAR="" C_DLG="" C_SELBG=$'\e[1;37;44m'
      C_POK=$'\e[30;42m' C_PWRN=$'\e[30;43m' C_PERR=$'\e[1;37;41m' C_PINF=$'\e[30;47m' C_BADGE=$'\e[1;30;46m';;
    *)
      C_CYA="" C_GRN="" C_YLW="" C_RED="" C_GRY="" C_WHT="" C_MAG="" C_SEL=$C_B
      C_RULE="" C_BAR="" C_DLG="" C_SELBG=$C_REV C_POK="" C_PWRN="" C_PERR="" C_PINF="" C_BADGE=$C_B;;
  esac
  if [ "$_UI_UTF8" = 1 ]; then
    UI_SYM_SEL='❯' UI_SYM_DOT='●' UI_SYM_FAV='★' UI_SYM_GONE='☆' UI_SYM_HDR='▌' UI_SYM_DANGER='▲'
    UI_SYM_CRUMB='›' UI_SYM_ELL='…' UI_SYM_ARR='→' UI_SYM_OK='✓' UI_SYM_ERR='✗' UI_SYM_MORE='›'
    _UI_H='─' _UI_V='│' _UI_TL='╭' _UI_TR='╮' _UI_BL='╰' _UI_BR='╯' _UI_KNAV='↑↓' _UI_KENT='⏎' _UI_KLR='←→' _UI_CUR='▏'
    [ -n "${NO_COLOR:-}" ] && UI_SYM_SEL='›'
  else
    UI_SYM_SEL='>' UI_SYM_DOT='o' UI_SYM_FAV='*' UI_SYM_GONE='-' UI_SYM_HDR='#' UI_SYM_DANGER='!'
    UI_SYM_CRUMB='>' UI_SYM_ELL='~' UI_SYM_ARR='->' UI_SYM_OK='+' UI_SYM_ERR='x' UI_SYM_MORE='>'
    _UI_H='-' _UI_V='|' _UI_TL='+' _UI_TR='+' _UI_BL='+' _UI_BR='+' _UI_KNAV=${TX[ui.key.arrows]} _UI_KENT='Enter' _UI_KLR='<>' _UI_CUR='_'
  fi
}
ui_theme

_ui_lvl_col() { # stufe → _UI_COL
  case "$1" in ok) _UI_COL=$C_GRN;; warn) _UI_COL=$C_YLW;; err) _UI_COL=$C_RED;; *) _UI_COL=$C_WHT;; esac
}
_ui_lvl_sym() { # stufe → _UI_SYM
  case "$1" in ok) _UI_SYM=$UI_SYM_OK;; err) _UI_SYM=$UI_SYM_ERR;; warn) _UI_SYM='!';; *) _UI_SYM='·';; esac
  [ "$_UI_UTF8" = 1 ] || [ "$1" != info ] || _UI_SYM='-'
}

# ─── Init / Terminal ───────────────────────────────────────────────────────
ui_init() {
  local want=${SSHLOBBY_UI:-auto}
  UI_MODE=line
  if [ "$want" != line ] && [ -t 0 ] && [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]; then UI_MODE=tui; fi
  trap '_ui_on_signal 130' INT
  trap '_ui_on_signal 143' TERM
  trap '_ui_on_signal 129' HUP
  trap 'ui_cleanup' EXIT
  [ "$UI_MODE" = tui ] || return 0
  UI_STTY=$(stty -g 2>/dev/null)
  _UI_SMCUP=$(tput smcup 2>/dev/null); [ -n "$_UI_SMCUP" ] || _UI_SMCUP=$'\e[?1049h'
  _UI_RMCUP=$(tput rmcup 2>/dev/null); [ -n "$_UI_RMCUP" ] || _UI_RMCUP=$'\e[?1049l'
  _UI_CIVIS=$(tput civis 2>/dev/null); [ -n "$_UI_CIVIS" ] || _UI_CIVIS=$'\e[?25l'
  _UI_CNORM=$(tput cnorm 2>/dev/null); [ -n "$_UI_CNORM" ] || _UI_CNORM=$'\e[?25h'
  trap '_UI_WINCH=1' WINCH
  _ui_size
  _ui_enter
}

_ui_enter() {
  printf '%s%s' "$_UI_SMCUP" "$_UI_CIVIS"
  stty -echo -icanon 2>/dev/null
  UI_ACTIVE=1 _UI_CLR=1
}
_ui_leave() {
  printf '%s%s' "$_UI_CNORM" "$_UI_RMCUP"
  [ -n "$UI_STTY" ] && stty "$UI_STTY" 2>/dev/null
  UI_ACTIVE=0
}
_ui_tui_on() { [ "$UI_MODE" = tui ] && [ "$UI_ACTIVE" = 1 ]; }

ui_suspend() { if _ui_tui_on; then _ui_leave; fi; }
ui_resume()  { if [ "$UI_MODE" = tui ] && [ "$UI_ACTIVE" = 0 ]; then _ui_enter; fi; }

ui_cleanup() {
  [ "$UI_MODE" = tui ] || return 0
  [ "$UI_ACTIVE" = 1 ] && printf '%s' "$_UI_RMCUP"
  printf '%s' "$_UI_CNORM"
  [ -n "$UI_STTY" ] && stty "$UI_STTY" 2>/dev/null
  UI_ACTIVE=0
}
# Signal während read -s: read stellt beim Abwickeln seinen Terminalzustand (ohne Echo) wieder
# her, ein exit direkt im Trap hinterließe ein Terminal ohne Echo. Deshalb dort nur merken,
# _ui_readkey beendet nach dem read.
_ui_on_signal() {
  if [ "$_UI_IN_READ" = 1 ]; then _UI_SIG=$1; return; fi
  ui_cleanup; trap - EXIT; exit "$1"
}

_ui_size() {
  local s
  s=$(stty size 2>/dev/null)
  if [[ $s =~ ^([0-9]+)\ ([0-9]+)$ ]] && [ "${BASH_REMATCH[1]}" -gt 0 ]; then
    UI_ROWS=${BASH_REMATCH[1]} UI_COLS=${BASH_REMATCH[2]}
  elif [[ ${LINES:-} =~ ^[1-9][0-9]*$ ]] && [[ ${COLUMNS:-} =~ ^[1-9][0-9]*$ ]]; then
    UI_ROWS=$LINES UI_COLS=$COLUMNS
  else
    UI_ROWS=$(tput lines 2>/dev/null || echo 24) UI_COLS=$(tput cols 2>/dev/null || echo 80)
  fi
  [ "$UI_COLS" -ge 20 ] || UI_COLS=20
  [ "$UI_ROWS" -ge 6 ] || UI_ROWS=6
}

# ─── Tastatur ──────────────────────────────────────────────────────────────
# Eine Taste → UI_KEY: up down left right home end pgup pgdn enter esc backspace tab
# timeout unknown oder das Zeichen selbst. Rückgabe 1 bei EOF. Escape-Sequenzen in beiden
# Cursor-Modi (\e[A und \eOA). Ein Zeichen, das nach Esc kommt, aber keine Sequenz beginnt
# (z. B. zweites Esc), geht nicht verloren: es landet in _UI_PEND und ist die nächste Taste.
_ui_getc() { # timeout → _UI_C (Zeilenende als $'\n'), Rückgabe 0 ok, 1 EOF, 2 timeout
  local c rc
  if [ -n "$_UI_PEND" ]; then _UI_C=${_UI_PEND:0:1}; _UI_PEND=${_UI_PEND:1}; return 0; fi
  _UI_IN_READ=1
  if [ -n "$1" ]; then IFS= read -rsn1 -t "$1" c; rc=$?; else IFS= read -rsn1 c; rc=$?; fi
  _UI_IN_READ=0
  [ -n "$_UI_SIG" ] && _ui_on_signal "$_UI_SIG"
  [ "$rc" -gt 128 ] && return 2
  [ "$rc" -eq 0 ] || return 1
  _UI_C=${c:-$'\n'}
}
_ui_readkey() { # [timeout]
  local k s="" rc
  UI_KEY=""
  _ui_getc "${1:-}"; rc=$?
  if [ "$rc" -eq 2 ]; then UI_KEY=timeout; return 0; fi
  [ "$rc" -eq 0 ] || return 1
  k=$_UI_C
  case "$k" in
    $'\n'|$'\r') UI_KEY=enter;;
    $'\e')
      if _ui_getc 0.1; then
        if [ "$_UI_C" = "[" ] || [ "$_UI_C" = O ]; then
          while _ui_getc 0.05; do s+=$_UI_C; case "$_UI_C" in [A-Za-z~]) break;; esac; done
          case "$s" in
            *A) UI_KEY=up;; *B) UI_KEY=down;; *C) UI_KEY=right;; *D) UI_KEY=left;;
            *H|1~|7~) UI_KEY=home;; *F|4~|8~) UI_KEY=end;;
            5~) UI_KEY=pgup;; 6~) UI_KEY=pgdn;; *) UI_KEY=unknown;;
          esac
        else
          UI_KEY=esc _UI_PEND=$_UI_C$_UI_PEND
        fi
      else
        UI_KEY=esc
      fi;;
    $'\x7f'|$'\b') UI_KEY=backspace;;
    $'\t') UI_KEY=tab;;
    *) UI_KEY=$k;;
  esac
}
_ui_wait_key() { # irgendeine Taste (Timeouts ignorieren), 1 bei EOF
  while _ui_readkey 1; do [ "$UI_KEY" = timeout ] || return 0; done
  return 1
}

# ─── Menü-Engine ───────────────────────────────────────────────────────────
ui_item() { # typ wert label [rechts] [status] [spalten]
  local l=${3:-} r=${4:-} c=${6:-}
  l=${l//|/¦}; l=${l//$'\n'/ }; r=${r//|/¦}; r=${r//$'\n'/ }; c=${c//|/¦}; c=${c//$'\n'/ }
  UI_ITEMS+=("$1|${2:-}|$l|$r|${5:-}|$c")
}
ui_info() { # label wert [status]
  local v=${2:-}; v=${v//|/¦}; v=${v//$'\n'/ }
  UI_INFO+=("$1|$v|${3:-}")
}
ui_cell() { printf '\001%s\002%s' "$1" "$2"; } # stil text → Zelle mit Stil

ui_menu() { # titel [untertitel]
  local title=$1 sub=${2:-}
  _ui_prepare
  UI_ACT="" UI_SEL="" UI_KEYROW=""
  if [ "$UI_MODE" = tui ]; then
    _ui_crumb_enter "$title" "${#FUNCNAME[@]}"
    _ui_menu_tui "$title" "$sub"
    case "$UI_ACT" in select|key|back) ui_loading;; esac
  else
    _ui_menu_line "$title" "$sub"
  fi
  [ "$UI_ACT" = select ] && _UI_LAST[$title]=$UI_SEL
  [ "$UI_ACT" = key ] && [ -n "$UI_KEYROW" ] && _UI_LAST[$title]=$UI_KEYROW   # nach f & Co. bleibt der Cursor stehen
  UI_ITEMS=() UI_INFO=() UI_KEYS=() UI_ROOT=0 UI_STYLE="" UI_PRESEL=""
  return 0
}

# Breadcrumb über die Aufruftiefe: ein Menü auf gleicher oder geringerer Tiefe ersetzt alles
# ab dieser Tiefe (zurück oder neu geladen), ein tieferes hängt sich an.
_ui_crumb_enter() { # titel tiefe
  local -a nd=() nt=(); local k
  for k in "${!_UCR_D[@]}"; do
    [ "${_UCR_D[k]}" -lt "$2" ] && { nd+=("${_UCR_D[k]}"); nt+=("${_UCR_T[k]}"); }
  done
  if [ "$UI_ROOT" = 1 ]; then nd=("$2") nt=("${TX[ui.crumb.start]}"); else nd+=("$2") nt+=("$1"); fi
  _UCR_D=("${nd[@]}") _UCR_T=("${nt[@]}")
  if [ "$UI_ROOT" = 1 ]; then _UI_CRUMB=("${TX[ui.crumb.main]}"); else _UI_CRUMB=("${nt[@]}"); fi
}

# UI_ITEMS → parallele Arrays _UT (typ) _UV (wert) _UL (label) _UR (rechts) _URP (rechts als
# Klartext) _US (status) _UC (spalten) _USR (Suchtext) _UN (Nummer, 0 = nicht wählbar),
# _UIDX[nummer] = index, _UCWN[k] natürliche Spaltenbreiten. Vor Überschriften eine Leerzeile.
_ui_prepare() {
  local e t v l r s c n=0 i=0 prev="" k
  _UT=() _UV=() _UL=() _UR=() _URP=() _US=() _UC=() _USR=() _UN=() _UIDX=() _UCWN=()
  _ULW=0 _UMW=0 _URWN=0
  for e in "${UI_ITEMS[@]}"; do
    IFS='|' read -r t v l r s c <<< "$e"
    if [ "$t" = header ] && [ $i -gt 0 ] && [ "$prev" != sep ]; then
      _UT[i]=sep _UV[i]="" _UL[i]="" _UR[i]="" _URP[i]="" _US[i]="" _UC[i]="" _USR[i]="" _UN[i]=0; i=$((i+1))
    fi
    _ui_plain "$r"
    _UT[i]=$t _UV[i]=$v _UL[i]=$l _UR[i]=$r _URP[i]=$_UI_P _US[i]=$s _UC[i]=$c _UN[i]=0 _USR[i]=""
    if [ "$t" = item ]; then
      n=$((n+1)); _UN[i]=$n; _UIDX[n]=$i
      _ui_w "$l"; [ "$_UI_W" -gt "$_ULW" ] && _ULW=$_UI_W
      if [ -n "$s" ] && { [ "$s" != danger ] || [ "$UI_MODE" = tui ]; }; then _UMW=2; fi
      if [ -n "$c" ]; then
        _ui_split "$c"
        for k in "${!_UI_CELLS[@]}"; do
          _ui_cellw "${_UI_CELLS[k]}"; [ "$_UI_W" -gt "${_UCWN[k]:-0}" ] && _UCWN[k]=$_UI_W; _UCWN[k]=${_UCWN[k]:-0}
        done
      elif [ -n "$r" ]; then
        _ui_w "$_UI_P"; [ "$_UI_W" -gt "$_URWN" ] && _URWN=$_UI_W
      fi
      _ui_plain "$l $_UI_P $c"; _USR[i]=${_UI_P,,}
    fi
    prev=$t; i=$((i+1))
  done
  _UCNT=$n _UTOTAL=$i _UNW=${#n}; [ "$_UNW" -lt 2 ] && _UNW=2
  _UK=()
  for e in "${UI_KEYS[@]}"; do _UK[${e%%|*}]=${e#*|}; done
}

# ─── Zeilenmodus ───────────────────────────────────────────────────────────
_ui_menu_line() { # titel untertitel
  local in n
  while true; do
    _ui_draw_line "$1" "$2"
    if ! read -r in; then UI_ACT=eof; printf '\n'; return; fi
    case "$in" in
      ""|b) [ "$UI_ROOT" = 1 ] && continue; UI_ACT=back; return;;
      q)    if [ "$UI_ROOT" = 1 ]; then UI_ACT=quit; else UI_ACT=back; fi; return;;
    esac
    if [[ $in =~ ^[0-9]{1,4}$ ]] && (( 10#$in >= 1 && 10#$in <= _UCNT )); then
      n=$((10#$in)); UI_ACT=select UI_SEL=${_UV[_UIDX[n]]}; return
    fi
    if [ -n "$in" ] && [ -n "${_UK[$in]+x}" ]; then UI_ACT=key UI_SEL=$in UI_KEYROW=""; return; fi
    # „taste nr“ (auch ohne Leerzeichen): Taste für den Eintrag mit dieser Nummer
    if [[ $in =~ ^([^0-9[:space:]]+)\ ?([0-9]{1,4})$ ]] && [ -n "${_UK[${BASH_REMATCH[1]}]+x}" ]; then
      n=$((10#${BASH_REMATCH[2]}))
      if (( n >= 1 && n <= _UCNT )); then UI_ACT=key UI_SEL=${BASH_REMATCH[1]} UI_KEYROW=${_UV[_UIDX[n]]}; return; fi
    fi
  done
}

_ui_draw_line() { # titel untertitel
  local i
  [ -t 1 ] && tput clear 2>/dev/null
  _UI_LINES=()
  _ui_render_header "$1" "$2"
  _ui_render_info
  _UI_LINES+=("")
  for ((i=0; i<_UTOTAL; i++)); do _ui_render_entry "$i"; _UI_LINES+=("$_UI_OUT"); done
  _UI_LINES+=("")
  _ui_render_keys_line
  printf '%s\n' "${_UI_LINES[@]}"
  _ui_render_prompt
}

# ─── TUI ───────────────────────────────────────────────────────────────────
# Sichtbare Liste: _UVIS = Indizes in _UT… (-1 = Leerzeile), _UPOS[index] = Position darin.
# _UCUR ist ein Index, _UTOP die erste sichtbare Position.
_ui_menu_tui() { # titel untertitel
  local title=$1 sub=$2 digits="" n dirty=1 t
  _UFILT="" _UFTYPE=0
  _ui_cursor_init "$title"
  _ui_visible
  _UTOP=0
  while true; do
    if [ "$_UI_WINCH" = 1 ]; then _UI_WINCH=0; _ui_size; _UI_CLR=1 dirty=1; fi
    [ "$dirty" = 1 ] && _ui_draw_tui "$title" "$sub"
    dirty=0
    # kurzes Polling, damit SIGWINCH (unterbricht read nicht) zügig neu zeichnet
    if [ -n "$digits" ]; then t=0.8; else t=0.25; fi
    _ui_readkey "$t" || { UI_ACT=eof; return; }
    if [ "$UI_KEY" = timeout ]; then [ -n "$digits" ] && digits=""; continue; fi
    dirty=1 _UI_STATUS=""
    if [ "$_UFTYPE" = 1 ]; then _ui_filter_key; continue; fi
    # Ziffern: Sprung zum Eintrag, mehrstellig solange eine längere Nummer möglich ist
    if [[ $UI_KEY == [0-9] ]]; then
      digits+=$UI_KEY; n=$((10#$digits))
      (( n >= 1 && n <= _UCNT )) && [ -n "${_UPOS[_UIDX[n]]+x}" ] && _UCUR=${_UIDX[n]}
      (( n * 10 > _UCNT )) && digits=""
      continue
    fi
    digits=""
    case "$UI_KEY" in
      up|k)   _ui_move -1;;
      down|j) _ui_move 1;;
      pgup)   _ui_move -1 $((_UI_VIEW_H - 1));;
      pgdn)   _ui_move 1 $((_UI_VIEW_H - 1));;
      home)   _ui_move -1 "$_UTOTAL";;
      end)    _ui_move 1 "$_UTOTAL";;
      /)      _UFTYPE=1;;
      enter|right|l)
        if [ "$_UCUR" -ge 0 ] && [ -n "${_UPOS[_UCUR]+x}" ]; then UI_ACT=select UI_SEL=${_UV[_UCUR]}; return; fi;;
      esc)
        if [ -n "$_UFILT" ]; then _UFILT=""; _ui_refilter
        elif [ "$UI_ROOT" != 1 ]; then UI_ACT=back; return; fi;;
      left|h|backspace|b)
        [ "$UI_ROOT" = 1 ] || { UI_ACT=back; return; };;
      q) if [ "$UI_ROOT" = 1 ]; then UI_ACT=quit; else UI_ACT=back; fi; return;;
      *) if [ -n "$UI_KEY" ] && [ -n "${_UK[$UI_KEY]+x}" ]; then
           UI_ACT=key UI_SEL=$UI_KEY UI_KEYROW=""
           [ "$_UCUR" -ge 0 ] && [ -n "${_UPOS[_UCUR]+x}" ] && UI_KEYROW=${_UV[_UCUR]}   # nur sichtbare Zeile (Filter)
           return
         fi
         dirty=0;;
    esac
  done
}

_ui_filter_key() { # Taste im Filter-Eingabemodus
  case "$UI_KEY" in
    enter)     _UFTYPE=0;;
    esc)       _UFTYPE=0 _UFILT="";;
    backspace) if [ -n "$_UFILT" ]; then _UFILT=${_UFILT:0:${#_UFILT}-1}; else _UFTYPE=0; fi;;
    up)        _ui_move -1;;
    down)      _ui_move 1;;
    pgup)      _ui_move -1 $((_UI_VIEW_H - 1));;
    pgdn)      _ui_move 1 $((_UI_VIEW_H - 1));;
    *)         [ ${#UI_KEY} -eq 1 ] && [[ $UI_KEY == [[:print:]] ]] && _UFILT+=$UI_KEY;;
  esac
  _ui_refilter
}

_ui_visible() { # _UFILT → _UVIS, _UPOS (Abschnitte ohne Treffer und Hinweise ausgeblendet)
  local i f=${_UFILT,,} hdr=-1
  _UVIS=() _UPOS=()
  if [ -z "$f" ]; then
    for ((i=0; i<_UTOTAL; i++)); do _UVIS+=("$i"); done
  else
    for ((i=0; i<_UTOTAL; i++)); do
      case "${_UT[i]}" in
        header) hdr=$i;;
        item)
          [[ ${_USR[i]} == *"$f"* ]] || continue
          if [ "$hdr" -ge 0 ]; then
            [ ${#_UVIS[@]} -gt 0 ] && _UVIS+=(-1)
            _UVIS+=("$hdr"); hdr=-1
          fi
          _UVIS+=("$i");;
      esac
    done
  fi
  for i in "${!_UVIS[@]}"; do [ "${_UVIS[i]}" -ge 0 ] && _UPOS[_UVIS[i]]=$i; done
  return 0
}
_ui_refilter() { # nach Filteränderung: Cursor auf einen sichtbaren Eintrag
  local i
  _ui_visible
  [ "$_UCUR" -ge 0 ] && [ -n "${_UPOS[_UCUR]+x}" ] && return 0
  _UCUR=-1 _UTOP=0
  for i in "${_UVIS[@]}"; do
    if [ "$i" -ge 0 ] && [ "${_UT[i]}" = item ]; then _UCUR=$i; return 0; fi
  done
  [ -n "$_UFILT" ] || _ui_cursor_init ""
}

_ui_cursor_init() { # titel → _UCUR (index des Startpunkts, -1 ohne wählbare Einträge)
  local want=${UI_PRESEL:-${_UI_LAST[$1]:-}} i
  _UCUR=-1
  [ "$_UCNT" -gt 0 ] || return 0
  _UCUR=${_UIDX[1]}
  [ -n "$want" ] || return 0
  for ((i=0; i<_UTOTAL; i++)); do
    if [ "${_UT[i]}" = item ] && [ "${_UV[i]}" = "$want" ]; then _UCUR=$i; return 0; fi
  done
}

_ui_move() { # richtung(-1|1) [schritte]
  local d=$1 steps=${2:-1} p q k n=${#_UVIS[@]} x
  [ "$_UCUR" -ge 0 ] && [ -n "${_UPOS[_UCUR]+x}" ] || return 0
  p=${_UPOS[_UCUR]}
  for ((k=0; k<steps; k++)); do
    q=$((p + d))
    while [ $q -ge 0 ] && [ $q -lt "$n" ]; do
      x=${_UVIS[q]}; [ "$x" -ge 0 ] && [ "${_UT[x]}" = item ] && break
      q=$((q + d))
    done
    if [ $q -lt 0 ] || [ $q -ge "$n" ]; then break; fi
    p=$q
  done
  _UCUR=${_UVIS[p]}
}

_ui_scroll() { # sichtbare höhe → _UTOP
  local h=$1 n=${#_UVIS[@]} c lead x
  if [ "$n" -le "$h" ]; then _UTOP=0; return; fi
  if [ "$_UCUR" -ge 0 ] && [ -n "${_UPOS[_UCUR]+x}" ]; then
    c=${_UPOS[_UCUR]}
    # Überschrift samt Leerzeile direkt über dem Cursor mitzeigen
    lead=$c
    while [ "$lead" -gt 0 ] && [ $((c - lead)) -lt 2 ]; do
      x=${_UVIS[lead-1]}; [ "$x" -ge 0 ] && [ "${_UT[x]}" = item ] && break
      lead=$((lead-1))
    done
    [ "$lead" -lt "$_UTOP" ] && _UTOP=$lead
    [ "$c" -ge $((_UTOP + h)) ] && _UTOP=$((c - h + 1))
  fi
  [ "$_UTOP" -gt $((n - h)) ] && _UTOP=$((n - h))
  [ "$_UTOP" -lt 0 ] && _UTOP=0
}

# Frame: Kopfzeile, Breadcrumb, Leerzeile, Info (+ Leerzeile), Liste, Statuszeile, Fußzeile
_ui_draw_tui() { # titel untertitel
  local w=$UI_COLS h p i end n
  _UI_LINES=()
  _ui_tui_top "$w"
  _ui_tui_crumb "$w" "$2"
  _UI_LINES+=("")
  if [ ${#UI_INFO[@]} -gt 0 ]; then _ui_tui_info "$w"; _UI_LINES+=(""); fi
  h=$((UI_ROWS - ${#_UI_LINES[@]} - 2)); [ $h -lt 1 ] && h=1
  _UI_VIEW_H=$h
  _ui_scroll "$h"
  _ui_tui_layout "$w"
  n=${#_UVIS[@]}
  end=$((_UTOP + h)); [ $end -gt "$n" ] && end=$n
  if [ "$n" -eq 0 ]; then
    if [ -n "$_UFILT" ]; then tf _UI_OUT ui.filter.no_match "$_UFILT"; else _UI_OUT=${TX[ui.list.empty]}; fi
    _ui_fit _UI_OUT $((w - 7)); _UI_LINES+=("      $C_GRY$_UI_OUT$C_R"); end=1
  fi
  for ((p=_UTOP; p<end && n>0; p++)); do
    i=${_UVIS[p]}
    _ui_tui_entry "$i" $(( i == _UCUR ? 1 : 0 )) "$w"; _UI_LINES+=("$_UI_OUT")
  done
  for ((p=end-_UTOP; p<h; p++)); do _UI_LINES+=(""); done
  _ui_tui_status "$w"
  _ui_tui_footer "$w" "$end"
  _ui_flush
}

# _UI_LINES auf einmal ausgeben: Cursor nach Home, jede Zeile bis Zeilenende löschen (mit der
# Hintergrundfarbe, die die Zeile am Ende gesetzt hat), Rest löschen. Komplett leeren nur nach
# einem Größenwechsel oder beim Betreten des Alternate Screens.
_ui_flush() {
  local out=$'\e[H' l
  [ "$_UI_CLR" = 1 ] && { out=$'\e[H\e[2J'; _UI_CLR=0; }
  for l in "${_UI_LINES[@]:0:UI_ROWS}"; do out+="$l"$'\e[K'"$C_R"$'\n'; done
  printf '%s\e[J' "${out%$'\n'}"
  _UI_FRAME=("${_UI_LINES[@]}")
}
_ui_reflush() { _UI_LINES=("${_UI_FRAME[@]}"); _ui_flush; } # letzten Frame erneut (nach Dialogen)

_ui_draw_at() { # zeile text (TUI, Zeile 1-basiert)
  printf '\e[%d;1H\e[K%s%s' "$1" "$2" "$C_R"
}

# ─── Text: Breite, Kürzen, Zellen ──────────────────────────────────────────
# Anzeigebreite: Zeichen (nicht Bytes), ostasiatische und Emoji-Zeichen zählen doppelt.
_ui_w() { # text → _UI_W
  local s=$1 t c cp i
  _UI_W=${#s}
  [ "$_UI_UTF8" = 1 ] && [[ $s == *[![:ascii:]]* ]] || return 0
  t=${s//[[:ascii:]]/}
  for ((i=0; i<${#t}; i++)); do
    c=${t:i:1}; printf -v cp '%d' "'$c"
    if (( (cp>=0x1100 && cp<=0x115f) || (cp>=0x2e80 && cp<=0xa4cf) || (cp>=0xac00 && cp<=0xd7a3) ||
          (cp>=0xf900 && cp<=0xfaff) || (cp>=0xfe30 && cp<=0xfe4f) || (cp>=0xff00 && cp<=0xff60) ||
          (cp>=0xffe0 && cp<=0xffe6) || (cp>=0x1f300 && cp<=0x1faff) )); then _UI_W=$((_UI_W + 1)); fi
  done
}
_ui_fit() { # varname breite: auf Anzeigebreite kürzen, … am Ende
  local -n _ui_ref=$1
  local w=$2 out="" i c acc=0
  [ "$w" -lt 1 ] && { _ui_ref=""; return; }
  _ui_w "$_ui_ref"; [ "$_UI_W" -le "$w" ] && return
  if [ "$_UI_W" -eq ${#_ui_ref} ]; then _ui_ref="${_ui_ref:0:w-1}$UI_SYM_ELL"; return; fi
  for ((i=0; i<${#_ui_ref}; i++)); do
    c=${_ui_ref:i:1}; _ui_w "$c"
    [ $((acc + _UI_W)) -gt $((w - 1)) ] && break
    out+=$c; acc=$((acc + _UI_W))
  done
  _ui_ref=$out$UI_SYM_ELL
}
_ui_pad() { # varname breite: mit Leerzeichen auf Anzeigebreite auffüllen
  local -n _ui_ref=$1
  local n
  _ui_w "$_ui_ref"; n=$(( $2 - _UI_W ))
  [ $n -gt 0 ] && printf -v _ui_ref '%s%*s' "$_ui_ref" "$n" ''
}
_ui_rep() { # zeichen anzahl → _UI_REP
  [ "$2" -gt 0 ] || { _UI_REP=""; return; }
  printf -v _UI_REP '%*s' "$2" ''; _UI_REP=${_UI_REP// /$1}
}
_ui_plain() { # text → _UI_P: Stil-Markup entfernt, Tabs (Spalten) als zwei Leerzeichen
  local s=$1 out=""
  while [[ $s == *$'\001'* ]]; do out+=${s%%$'\001'*}; s=${s#*$'\001'}; s=${s#*$'\002'}; done
  out+=$s; _UI_P=${out//$'\t'/  }
}
_ui_split() { # text → _UI_CELLS (an Tabs getrennt, leere Zellen bleiben)
  local s=$1
  _UI_CELLS=()
  while [[ $s == *$'\t'* ]]; do _UI_CELLS+=("${s%%$'\t'*}"); s=${s#*$'\t'}; done
  _UI_CELLS+=("$s")
}
_ui_cellparse() { # zelle → _UI_CST (stil), _UI_CTX (text)
  _UI_CST="" _UI_CTX=$1
  if [[ $1 == $'\001'* ]]; then _UI_CST=${1%%$'\002'*}; _UI_CST=${_UI_CST#$'\001'}; _UI_CTX=${1#*$'\002'}; fi
}
_ui_cellw() { # zelle → _UI_W (Pills mit Rand)
  _ui_cellparse "$1"; _ui_w "$_UI_CTX"
  [[ $_UI_CST == p-* ]] && [ -n "$_UI_CTX" ] && _UI_W=$((_UI_W + 2))
  return 0
}
_ui_cellr() { # zelle breite standardfarbe → _UI_C (gestylt, endet mit C_R), _UI_CW (Breite)
  local w=$2 col=$3 t
  _ui_cellparse "$1"; t=$_UI_CTX
  if [[ $_UI_CST == p-* ]] && [ -n "$t" ]; then
    _ui_fit t $((w - 2)); _ui_w "$t"; _UI_CW=$((_UI_W + 2))
    [ "$w" -lt 3 ] && { _UI_C="" _UI_CW=0; return; }
    case "$_UI_CST" in p-ok) col=$C_POK;; p-warn) col=$C_PWRN;; p-err) col=$C_PERR;; *) col=$C_PINF;; esac
    if [ "$_UI_NCOL" = 0 ]; then _UI_C="[$t]"; else _UI_C="$col $t $C_R"; fi
    return
  fi
  _ui_fit t "$w"; _ui_w "$t"; _UI_CW=$_UI_W
  case "$_UI_CST" in
    ok) col=$C_GRN;; warn) col=$C_YLW;; err) col=$C_RED;; acc) col=$C_CYA;; info) col=$C_WHT;; dim) col=$C_GRY;; bold) col=$C_B$C_WHT;;
  esac
  _UI_C="$col$t$C_R"
}
_ui_wrap() { # text breite → _UI_WRAP (Zeilen, an Wörtern umbrochen)
  local w=$2 line="" word
  _UI_WRAP=()
  for word in $1; do
    if [ -z "$line" ]; then line=$word
    else _ui_w "$line $word"; if [ "$_UI_W" -le "$w" ]; then line+=" $word"; else _UI_WRAP+=("$line"); line=$word; fi; fi
  done
  [ -n "$line" ] && _UI_WRAP+=("$line")
  local i; for i in "${!_UI_WRAP[@]}"; do _ui_fit "_UI_WRAP[$i]" "$w"; done
}

# ─── Rendering Zeilenmodus (schlicht, maschinenfreundlich, Format seit 2.0 stabil) ─────────
_ui_mark() { # status → _UI_M (farbig, inkl. Leerzeichen), _UI_MW (sichtbare Breite)
  _UI_MW=2
  case "$1" in
    run)    _UI_M="$C_GRN$UI_SYM_DOT$C_R ";;
    stop)   _UI_M="$C_GRY$UI_SYM_DOT$C_R ";;
    warn)   _UI_M="$C_YLW$UI_SYM_DOT$C_R ";;
    err)    _UI_M="$C_RED$UI_SYM_DOT$C_R ";;
    fav)    _UI_M="$C_YLW$UI_SYM_FAV$C_R ";;
    gone)   _UI_M="$C_GRY$UI_SYM_GONE$C_R ";;
    danger) if [ "$UI_MODE" = tui ]; then _UI_M="$C_RED$UI_SYM_DANGER$C_R "; else _UI_M="" _UI_MW=0; fi;;
    *)      _UI_M="" _UI_MW=0;;
  esac
}

_ui_render_header() { # titel untertitel → _UI_LINES (Zeilenmodus)
  local t=$1 s=$2 plain
  if [ "$UI_STYLE" = main ]; then _ui_render_dash "$t" "$s"; return; fi
  plain="┌─ $t${s:+ · $s} "
  _ui_rep ─ $((64 - ${#plain} - 1)); [ ${#_UI_REP} -lt 2 ] && _UI_REP=──
  _UI_LINES+=("$C_CYA┌─$C_R $C_B$C_WHT$t$C_R${s:+ $C_D· $s$C_R} $C_CYA$_UI_REP┐$C_R")
}

_ui_render_dash() { # titel untertitel (Hauptmenü, Zeilenmodus)
  local warn="" sub
  [ "${SYS_DISK_PCT:-0}" -gt 95 ] && warn="  $C_B$C_RED${TX[ui.dash.disk_full]}$C_R"
  tf sub ui.dash.subtitle "$VERSION" "$MODE"
  _UI_LINES+=("  $C_B$C_WHT$1$C_R $C_D$sub$C_R")
  _UI_LINES+=("  ${C_GRY}up$C_R ${SYS_UP:-?} · ${C_GRY}load$C_R ${SYS_LOAD:-?} · ${C_GRY}RAM$C_R ${SYS_RAM:-?} · ${C_GRY}DISK$C_R ${SYS_DISK:-?} · $C_GRY$2$C_R$warn")
}

_ui_render_info() { # → _UI_LINES (Zeilenmodus)
  local e l v s lw=0
  for e in "${UI_INFO[@]}"; do l=${e%%|*}; [ ${#l} -gt "$lw" ] && lw=${#l}; done
  for e in "${UI_INFO[@]}"; do
    IFS='|' read -r l v s <<< "$e"
    _ui_pad l "$lw"; _ui_mark "$s"; _ui_plain "$v"
    _UI_LINES+=("  $C_GRY$l$C_R $_UI_M$_UI_P")
  done
}

_ui_hdr_col() { # status einer Überschrift → _UI_COL
  case "$1" in recent) _UI_COL=$C_MAG;; fav) _UI_COL=$C_YLW;; *) _UI_COL=$C_GRN;; esac
}

_ui_render_entry() { # index → _UI_OUT (Zeilenmodus)
  local i=$1 l=${_UL[$1]} r=${_URP[$1]} num lw
  case "${_UT[i]}" in
    sep) _UI_OUT=""; return;;
    header) _ui_hdr_col "${_US[i]}"; _UI_OUT="  $_UI_COL$UI_SYM_HDR ${l^^}$C_R"; return;;
    disabled) _UI_OUT="      $C_D$l$C_R"; return;;
  esac
  _ui_mark "${_US[i]}"
  printf -v num '%*d)' "$_UNW" "${_UN[i]}"
  # Label-Spalte so breit, dass die rechte Spalte fluchtet (Markierung zählt mit)
  lw=$((_ULW + _UMW - _UI_MW)); [ $lw -gt 42 ] && lw=42
  [ -n "$r" ] && _ui_pad l "$lw"
  _UI_OUT="  $C_B$num$C_R $_UI_M$C_WHT$l$C_R${r:+  $C_GRY$r$C_R}"
}

_ui_render_keys_line() { # Zeilenmodus: Hotkeys und Navigation
  local out="" k
  for k in "${UI_KEYS[@]}"; do out+="$C_B${k%%|*})$C_R ${k#*|}   "; done
  if [ "$UI_ROOT" = 1 ]; then out+="${C_B}q)$C_R ${UI_QUIT_LABEL:-${TX[ui.hint.logout]}}"; else out+="${C_B}b)$C_R ${TX[ui.hint.back]}"; fi
  _UI_LINES+=("  $out")
}

_ui_render_prompt() { printf '%s  %s: %s' "$C_CYA" "${TX[ui.prompt.choice]}" "$C_R"; }

# ─── Rendering TUI ─────────────────────────────────────────────────────────
# Alle Zeilen sind höchstens breite-1 Zeichen breit (letzte Spalte bleibt frei, kein
# automatischer Umbruch). Balken (Kopf, Fuß, Auswahl) enden mit ihrer Hintergrundfarbe,
# \e[K in _ui_flush füllt den Rest der Zeile damit.

_ui_load_col() { # load cpus → _UI_COL (Last pro CPU: ab 0,7 gelb, ab 1,0 rot)
  local l=${1%% *} i f c
  i=${l%%.*}; f=${l#*.}; [ "$f" = "$l" ] && f=0; f="${f}00"; f=${f:0:2}
  if ! [[ $i =~ ^[0-9]+$ && $f =~ ^[0-9]+$ ]]; then _UI_COL=$C_WHT; return; fi
  c=$(( (10#$i * 100 + 10#$f) / ${2:-1} ))
  if [ $c -ge 100 ]; then _UI_COL=$C_RED; elif [ $c -ge 70 ]; then _UI_COL=$C_YLW; else _UI_COL=$C_WHT; fi
}

_ui_tui_top() { # breite → Kopfzeile: Host, Modus, Version | Zähler, RAM, Disk, Load, Uptime
  local w=$(($1 - 1)) b=$C_BAR host=${HOST_LABEL:-${PD_HOST:-}} left lw k avail used
  local -a seg=() sw=() pr=() keep=()
  local run tot bad unit col p
  host=${host^^}; _ui_fit host $((w / 3))
  left=" $C_B$C_WHT$host$C_R$b"; lw=$((1 + ${#host}))
  if [ -n "${MODE:-}" ]; then left+="  $C_BADGE $MODE $C_R$b"; lw=$((lw + 4 + ${#MODE})); fi
  if [ $((lw + 3 + ${#VERSION})) -le $((w / 2)) ]; then left+="  ${C_GRY}v$VERSION$C_R$b"; lw=$((lw + 3 + ${#VERSION})); fi
  if [ -n "$UI_STAT" ]; then
    IFS='|' read -r run tot bad unit <<< "$UI_STAT"
    if [ "${run:-0}" -eq "${tot:-0}" ]; then col=$C_GRN; else col=$C_YLW; fi
    seg+=("$col$UI_SYM_DOT$C_R$b $C_WHT$run/$tot$C_R$b${unit:+ $C_GRY$unit$C_R$b}"); sw+=($((3 + ${#run} + ${#tot} + ${unit:+1} + ${#unit}))); pr+=(1)
    if [ "${bad:-0}" -gt 0 ]; then seg+=("$C_B$C_RED$UI_SYM_ERR $bad unhealthy$C_R$b"); sw+=($((12 + ${#bad}))); pr+=(1); fi
  fi
  if [ -n "${SYS_RAM:-}" ]; then
    col=$C_GRN; [ "${SYS_RAM_PCT:-0}" -gt 80 ] && col=$C_YLW; [ "${SYS_RAM_PCT:-0}" -gt 92 ] && col=$C_RED
    seg+=("${C_GRY}RAM$C_R$b $col${SYS_RAM_PCT}%$C_R$b"); sw+=($((5 + ${#SYS_RAM_PCT}))); pr+=(2)
  fi
  if [ -n "${SYS_DISK:-}" ]; then
    col=$C_GRN; [ "${SYS_DISK_PCT:-0}" -gt 85 ] && col=$C_YLW; [ "${SYS_DISK_PCT:-0}" -gt 95 ] && col=$C_B$C_RED
    seg+=("${C_GRY}Disk$C_R$b $col${SYS_DISK_PCT}%$C_R$b"); sw+=($((6 + ${#SYS_DISK_PCT}))); pr+=(2)
  fi
  if [ -n "${SYS_LOAD:-}" ]; then
    _ui_load_col "$SYS_LOAD" "${SYS_NCPU:-1}"
    seg+=("${C_GRY}Load$C_R$b $_UI_COL${SYS_LOAD%% *}$C_R$b"); k=${SYS_LOAD%% *}; sw+=($((5 + ${#k}))); pr+=(3)
  fi
  if [ -n "${SYS_UP:-}" ]; then seg+=("${C_GRY}up$C_R$b $C_WHT$SYS_UP$C_R$b"); sw+=($((3 + ${#SYS_UP}))); pr+=(4); fi
  # nach Priorität auswählen, Reihenfolge bleibt
  avail=$((w - lw - 2)) used=0
  for p in 1 2 3 4 5 6; do
    for k in "${!seg[@]}"; do
      [ "${pr[k]}" = "$p" ] || continue
      if [ $((used + sw[k] + 2)) -le "$avail" ]; then keep[k]=1; used=$((used + sw[k] + 2)); fi
    done
  done
  local right="" rw=0
  for k in "${!seg[@]}"; do
    [ -n "${keep[k]:-}" ] || continue
    right+="  ${seg[k]}"; rw=$((rw + sw[k] + 2))
  done
  _ui_rep ' ' $((w - lw - rw - 1))
  _UI_LINES+=("$b$left$_UI_REP$right $b")
}

_ui_tui_crumb() { # breite untertitel → Breadcrumb links, Untertitel gedimmt rechts
  local w=$(($1 - 1)) sub=$2 out="" k n start=0 cw=0 t sep=" $UI_SYM_CRUMB "
  local -a cwid=()
  [ ${#_UI_CRUMB[@]} -gt 0 ] || _UI_CRUMB=("")
  n=${#_UI_CRUMB[@]}
  for k in "${!_UI_CRUMB[@]}"; do _ui_w "${_UI_CRUMB[k]}"; cwid[k]=$_UI_W; cw=$((cw + _UI_W)); done
  cw=$((cw + 3 * (n - 1)))
  # zu lang: vorne Elemente durch … ersetzen
  while [ "$cw" -gt $((w - 2)) ] && [ "$start" -lt $((n - 1)) ]; do cw=$((cw - cwid[start] - 3)); start=$((start + 1)); done
  [ "$start" -gt 0 ] && { out="$C_GRY$UI_SYM_ELL$C_R$C_RULE$sep$C_R"; cw=$((cw + 4)); }
  for ((k=start; k<n; k++)); do
    t=${_UI_CRUMB[k]}
    if [ $k -eq $((n - 1)) ]; then
      if [ "$cw" -gt $((w - 2)) ]; then _ui_fit t $((cwid[k] - (cw - w + 2))); cw=$((w - 2)); fi
      out+="$C_B$C_WHT$t$C_R"
    else
      out+="$C_GRY$t$C_R$C_RULE$sep$C_R"
    fi
  done
  k=$((w - 1 - cw - 3))
  if [ -n "$sub" ] && [ "$k" -ge 6 ]; then
    _ui_fit sub "$k"; _ui_w "$sub"
    _ui_rep ' ' $((w - 1 - cw - _UI_W))
    out+="$_UI_REP$C_GRY$sub$C_R"
  fi
  _UI_LINES+=(" $out")
}

_ui_tui_info() { # breite → Infozeilen (Label gedimmt und bündig, Wert mit Zellen-Stilen)
  local w=$(($1 - 1)) e l v s lw=0 room out k
  for e in "${UI_INFO[@]}"; do l=${e%%|*}; _ui_w "$l"; [ "$_UI_W" -gt "$lw" ] && lw=$_UI_W; done
  for e in "${UI_INFO[@]}"; do
    IFS='|' read -r l v s <<< "$e"
    _ui_pad l "$lw"; _ui_mark "$s"
    room=$((w - 3 - lw - 2 - _UI_MW)); out=""
    _ui_split "$v"
    for k in "${!_UI_CELLS[@]}"; do
      [ "$room" -gt 0 ] || break
      [ "$k" -gt 0 ] && { out+="  "; room=$((room - 2)); }
      _ui_cellr "${_UI_CELLS[k]}" "$room" "$C_WHT"; out+=$_UI_C; room=$((room - _UI_CW))
    done
    _UI_LINES+=("   $C_GRY$l$C_R  $_UI_M$out")
  done
}

# Spaltenaufteilung für die aktuelle Breite → _UTL (Breite Markierung+Label), _UTCW[k]
# (gezeigte Spaltenbreiten), _UTNC (Anzahl Spalten), _UTRW (Breite für rechts ohne Spalten)
_ui_tui_layout() { # breite
  local avail need cols=0 k nc=${#_UCWN[@]} rest cw
  _UTLEAD=$((3 + _UNW + 2))
  avail=$(($1 - 1 - _UTLEAD))
  need=$((_UMW + _ULW))
  for k in "${!_UCWN[@]}"; do [ "${_UCWN[k]}" -gt 0 ] && cols=$((cols + _UCWN[k] + 2)); done
  [ "$_URWN" -gt 0 ] && [ $((_URWN + 2)) -gt "$cols" ] && cols=$((_URWN + 2))
  _UTCW=() _UTNC=0
  if [ $((need + cols)) -le "$avail" ]; then
    _UTL=$need
  else
    _UTL=$((avail * 45 / 100)); [ "$_UTL" -lt 12 ] && _UTL=12; [ "$_UTL" -gt "$need" ] && _UTL=$need
  fi
  rest=$((avail - _UTL))
  for ((k=0; k<nc; k++)); do
    cw=${_UCWN[k]:-0}
    if [ "$cw" -eq 0 ]; then _UTCW[k]=0
    elif [ $((rest - 2)) -ge "$cw" ]; then _UTCW[k]=$cw; rest=$((rest - cw - 2))
    elif [ $((rest - 2)) -ge 6 ]; then _UTCW[k]=$((rest - 2)); rest=0; k=$((k + 1)); break
    else break; fi
  done
  _UTNC=${#_UTCW[@]}
  # Platz übrig: Label wieder verbreitern
  if [ "$rest" -gt 0 ] && [ "$_UTL" -lt "$need" ]; then
    k=$((need - _UTL)); [ "$k" -gt "$rest" ] && k=$rest; _UTL=$((_UTL + k)); rest=$((rest - k))
  fi
  _UTRW=$((avail - _UTL - 2))
}

_ui_tui_entry() { # index markiert(0|1) breite → _UI_OUT
  local i=$1 sel=$2 w=$(($3 - 1)) l num out col base="" used k last cell
  if [ "$i" -lt 0 ]; then _UI_OUT=""; return; fi
  l=${_UL[i]}
  case "${_UT[i]}" in
    sep) _UI_OUT=""; return;;
    header)
      _ui_hdr_col "${_US[i]}"; l=${l^^}; _ui_fit l $((w - 8)); _ui_w "$l"
      _ui_rep "$_UI_H" $((w - 6 - _UI_W))
      _UI_OUT="  $_UI_COL$C_B$UI_SYM_HDR $l$C_R $C_RULE$_UI_REP$C_R"; return;;
    disabled) _ui_fit l $((w - 7)); _UI_OUT="      $C_GRY$l$C_R"; return;;
  esac
  [ "$sel" = 1 ] && base=$C_SELBG
  _ui_mark "${_US[i]}"
  printf -v num '%*d' "$_UNW" "${_UN[i]}"
  if [ "$sel" = 1 ]; then out=" $C_SEL$UI_SYM_SEL$C_R "; col=$C_B$C_WHT
  else out="   "; col=$C_WHT; fi
  [ "${_US[i]}" = danger ] && col+=$C_RED
  [ "${_US[i]}" = gone ] && col=$C_GRY
  out+="$C_GRY$num$C_R  $_UI_M"
  _ui_fit l $((_UTL - _UI_MW)); _ui_pad l $((_UTL - _UI_MW))
  out+="$col$l$C_R"; used=$((_UTLEAD + _UTL))
  if [ -n "${_UC[i]}" ]; then
    _ui_split "${_UC[i]}"
    for ((k=0; k<_UTNC; k++)); do
      [ "${_UTCW[k]}" -gt 0 ] || continue
      cell=${_UI_CELLS[k]:-}
      _ui_cellr "$cell" "${_UTCW[k]}" "$C_GRY"
      out+="  $_UI_C"; used=$((used + 2 + _UI_CW))
      last=$(( _UTCW[k] - _UI_CW ))
      if [ $k -lt $((_UTNC - 1)) ] && [ $last -gt 0 ]; then _ui_rep ' ' "$last"; out+=$_UI_REP; used=$((used + last)); fi
    done
  elif [ -n "${_UR[i]}" ] && [ "$_UTRW" -gt 2 ]; then
    cell=${_UR[i]}
    [[ $cell == *$'\t'* ]] && { _ui_plain "$cell"; cell=$_UI_P; }
    _ui_cellr "$cell" "$_UTRW" "$C_GRY"
    out+="  $_UI_C"; used=$((used + 2 + _UI_CW))
  fi
  if [ "$sel" = 1 ]; then
    _ui_rep ' ' $((w - used)); out+=$_UI_REP
    [ -n "$C_R" ] && out=${out//"$C_R"/"$C_R$base"}
    out="$base$out$base"
  fi
  _UI_OUT=$out
}

_ui_tui_status() { # breite → Statuszeile (Filter, Meldung oder leer)
  local w=$(($1 - 1)) t n=0 i
  if [ "$_UFTYPE" = 1 ] || [ -n "$_UFILT" ]; then
    for i in "${_UVIS[@]}"; do [ "$i" -ge 0 ] && [ "${_UT[i]}" = item ] && n=$((n + 1)); done
    t=$_UFILT; _ui_fit t $((w - 24))
    if [ "$_UFTYPE" = 1 ]; then
      _UI_LINES+=(" $C_CYA$C_B/$C_R $C_WHT$t$C_R$C_CYA$_UI_CUR$C_R  $C_GRY$n ${TX[ui.filter.hits]}$C_R")
    else
      _UI_LINES+=(" $C_GRY${TX[ui.filter.label]}$C_R $C_CYA$t$C_R  $C_GRY$n ${TX[ui.filter.hits]}$C_R")
    fi
    return
  fi
  if [ -n "$_UI_STATUS" ]; then
    t=$_UI_STATUS; _ui_lvl_col "$_UI_STATUS_LVL"; _ui_lvl_sym "$_UI_STATUS_LVL"; _ui_fit t $((w - 3))
    _UI_LINES+=(" $_UI_COL$_UI_SYM $t$C_R"); return
  fi
  _UI_LINES+=("")
}

_ui_hints() { # breite "taste|text|prio" … → _UI_OUT (Fußzeile, niedrige prio zuerst behalten)
  local w=$1 e k p used=0 out="" b=$C_BAR; shift
  local -a key=() txt=() pr=() keep=()
  for e in "$@"; do key+=("${e%%|*}"); p=${e#*|}; txt+=("${p%|*}"); pr+=("${e##*|}"); done
  for p in 0 1 2 3 4 5 6 7 8 9; do
    for k in "${!key[@]}"; do
      [ "${pr[k]}" = "$p" ] || continue
      _ui_w "${key[k]} ${txt[k]}"
      if [ $((used + _UI_W + 2)) -le "$w" ]; then keep[k]=1; used=$((used + _UI_W + 2)); fi
    done
  done
  for k in "${!key[@]}"; do
    [ -n "${keep[k]:-}" ] || continue
    out+="  $C_B$C_CYA${key[k]}$C_R$b $C_GRY${txt[k]}$C_R$b"
  done
  _UI_OUT=$out _UI_W=$used
}

_ui_tui_footer() { # breite letzte-sichtbare-position → Fußzeile mit Tastenhinweisen
  local w=$(($1 - 1)) b=$C_BAR pos="" k n=${#_UVIS[@]}
  local -a h=()
  [ "$n" -gt "$_UI_VIEW_H" ] && pos="$((_UTOP + 1))–$2/$n"
  [ "$_UI_UTF8" = 1 ] || pos=${pos//–/-}
  if [ "$_UFTYPE" = 1 ]; then
    h=("$_UI_KENT|${TX[ui.hint.apply]}|1" "esc|${TX[ui.hint.discard]}|1" "$_UI_KNAV|${TX[ui.hint.select]}|2" "⌫|${TX[ui.hint.delete]}|3")
    [ "$_UI_UTF8" = 1 ] || h[3]="${TX[ui.key.backspace]}|${TX[ui.hint.delete]}|3"
  else
    h=("$_UI_KNAV|${TX[ui.hint.select]}|7" "$_UI_KENT|${TX[ui.hint.open]}|3")   # ↑↓ fällt bei Platzmangel zuerst weg
    if [ -n "$_UFILT" ]; then h+=("esc|${TX[ui.hint.filter_off]}|1"); elif [ "$UI_ROOT" != 1 ]; then h+=("esc|${TX[ui.hint.back]}|4"); fi
    h+=("/|${TX[ui.hint.filter]}|6")
    for k in "${UI_KEYS[@]}"; do h+=("${k%%|*}|${k#*|}|2"); done
    if [ "$UI_ROOT" = 1 ]; then h+=("q|${UI_QUIT_LABEL:-${TX[ui.hint.logout]}}|1"); else h+=("q|${TX[ui.hint.back]}|1"); fi
  fi
  _ui_hints $((w - ${#pos} - 2)) "${h[@]}"
  _ui_rep ' ' $((w - _UI_W - ${#pos} - 1))
  _UI_LINES+=("$b$_UI_OUT$_UI_REP$C_GRY$pos$C_R$b $b")
}

# ─── Dialoge ───────────────────────────────────────────────────────────────
ui_loading() { # [text]: Lade-Hinweis in der Statuszeile, bis der nächste Frame steht
  _ui_tui_on || return 0
  _ui_draw_at $((UI_ROWS - 1)) " $C_GRY${1:-${TX[ui.loading]}}$UI_SYM_ELL$C_R"
}

ui_note() { # stufe text
  _ui_lvl_col "$1"
  if _ui_tui_on; then
    _UI_STATUS=$2 _UI_STATUS_LVL=$1
    local t=$2; _ui_lvl_sym "$1"; _ui_fit t $((UI_COLS - 4))
    _ui_draw_at $((UI_ROWS - 1)) " $_UI_COL$_UI_SYM $t$C_R"
  else
    printf '  %s%s%s\n' "$_UI_COL" "$2" "$C_R"
  fi
}

# Kasten mittig im Inhaltsbereich: stufe titel fuß zeilen… (Zeilen werden umbrochen/gekürzt)
_ui_box() {
  local lvl=$1 title=$2 foot=$3 bc l iw=0 bw row c0 i n d=$C_DLG maxw
  shift 3
  local -a lines=()
  maxw=$((UI_COLS - 10)); [ "$maxw" -gt 72 ] && maxw=72; [ "$maxw" -lt 10 ] && maxw=10
  for l in "$@"; do
    _ui_wrap "$l" "$maxw"; [ ${#_UI_WRAP[@]} -eq 0 ] && _UI_WRAP=("")
    lines+=("${_UI_WRAP[@]}")
  done
  n=$((UI_ROWS - 8)); [ "$n" -lt 1 ] && n=1
  [ ${#lines[@]} -gt "$n" ] && lines=("${lines[@]: -$n}")
  for l in "${lines[@]}"; do _ui_w "$l"; [ "$_UI_W" -gt "$iw" ] && iw=$_UI_W; done
  [ "$_UI_BOXFW" -gt "$iw" ] && iw=$_UI_BOXFW
  _ui_w "$title"; [ $((_UI_W + 4)) -gt "$iw" ] && iw=$((_UI_W + 4))
  [ "$iw" -lt 30 ] && iw=30; [ "$iw" -gt "$maxw" ] && iw=$maxw
  bw=$((iw + 6))
  case "$lvl" in err|danger) bc=$C_RED;; warn) bc=$C_YLW;; ok) bc=$C_GRN;; *) bc=$C_CYA;; esac
  row=$(( (UI_ROWS - ${#lines[@]} - 4) / 2 + 1 )); [ "$row" -lt 3 ] && row=3
  _ui_draw_at $((UI_ROWS - 1)) ""
  c0=$(( (UI_COLS - bw) / 2 + 1 ))
  _ui_fit title $((iw - 2)); _ui_w "$title"
  _ui_rep "$_UI_H" $((bw - 5 - _UI_W))
  printf '\e[%d;%dH%s' "$row" "$c0" "$bc$d$_UI_TL$_UI_H $C_B$title$C_R$d$bc $_UI_REP$_UI_TR$C_R"
  for ((i=0; i<${#lines[@]}; i++)); do
    l=${lines[i]}; _ui_pad l "$iw"
    printf '\e[%d;%dH%s' $((row + 1 + i)) "$c0" "$bc$d$_UI_V$C_R$d  $C_WHT$l$C_R$d  $bc$_UI_V$C_R"
  done
  i=${#lines[@]}
  _ui_rep ' ' "$iw"
  printf '\e[%d;%dH%s' $((row + 1 + i)) "$c0" "$bc$d$_UI_V$C_R$d  $_UI_REP  $bc$_UI_V$C_R"
  _ui_rep ' ' $((iw - _UI_BOXFW))
  printf '\e[%d;%dH%s' $((row + 2 + i)) "$c0" "$bc$d$_UI_V$C_R$d  $_UI_REP${foot//"$C_R"/"$C_R$d"}$C_R$d  $bc$_UI_V$C_R"
  _ui_rep "$_UI_H" $((bw - 2))
  printf '\e[%d;%dH%s' $((row + 3 + i)) "$c0" "$bc$d$_UI_BL$_UI_REP$_UI_BR$C_R"
}

ui_msg() { # stufe text (mehrzeilig erlaubt)
  local -a lines; local title
  _ui_lvl_col "$1"
  if _ui_tui_on; then
    mapfile -t lines <<< "$2"
    case "$1" in err) title=${TX[ui.msg.error]};; warn) title=${TX[ui.msg.warning]};; ok) title=${TX[ui.msg.done]};; *) title=${TX[ui.msg.info]};; esac
    _ui_w "${TX[ui.pause]}"; _UI_BOXFW=$_UI_W
    _ui_box "$1" "$title" "$C_GRY${TX[ui.pause]}$C_R" "${lines[@]}"
    _ui_wait_key
    _UI_STATUS=""
    _ui_reflush
    return 0
  fi
  printf '\n  %s%s%s\n' "$_UI_COL" "${2//$'\n'/$'\n'  }" "$C_R"
  ui_pause
}

ui_pause() {
  if _ui_tui_on; then
    _ui_draw_at $((UI_ROWS - 1)) " $C_GRY${TX[ui.pause]}$C_R"; _ui_wait_key; return 0
  fi
  if [ "$UI_MODE" = tui ]; then # suspendiert: normaler Bildschirm, Taste vom Terminal
    printf '\n%s%s%s' "$C_GRY" "${TX[ui.pause]}" "$C_R"; _ui_wait_key; printf '\n'; return 0
  fi
  # Zeilenmodus: am Terminal über /dev/tty, ohne TTY (Pipe, Tests) über stdin
  if { : </dev/tty; } 2>/dev/null; then
    printf '\n%s%s%s' "$C_GRY" "${TX[ui.pause]}" "$C_R" >/dev/tty; read -r _ </dev/tty
  else
    printf '\n%s%s%s' "$C_GRY" "${TX[ui.pause]}" "$C_R"; read -r _ || true
  fi
}

# Gefährlich (roter Rahmen, „Achtung“): Stop, Neustart, Entfernen, Löschen (deutsch und englisch)
_ui_danger() { [[ ${1,,} =~ (stopp|neu\ starten|restart|entfern|lösch|kill|(^|[^a-z])stop|remov|delet) ]]; }

ui_confirm() { # frage → 0 nur bei j/J/y/Y
  local a rc lvl=info title=${TX[ui.confirm.title]} foot y=${TX[ui.confirm.yes_key]} yes=${TX[ui.confirm.yes]} no=${TX[ui.confirm.no]}
  if [ "$UI_MODE" = tui ]; then
    if _ui_tui_on; then
      _ui_danger "$1" && { lvl=danger title=${TX[ui.msg.warning]}; }
      foot="$C_GRY $y$C_R $yes   $C_SELBG$C_B N $no $C_R"
      [ "$_UI_NCOL" = 0 ] && foot=" $y $yes   ${C_REV}[N $no]$C_R"
      _ui_w " $y $yes   N $no "; _UI_BOXFW=$_UI_W
      _ui_box "$lvl" "$title" "$foot" "$1 ${TX[ui.confirm.choices]}"
    else
      printf '  %s %s ' "$1" "${TX[ui.confirm.choices]}"
    fi
    _ui_wait_key || return 1
    [[ $UI_KEY == [jJyY] ]]; rc=$?
    _UI_STATUS=""
    if _ui_tui_on; then _ui_reflush; else printf '\n'; fi
    return $rc
  fi
  printf '  %s %s ' "$1" "${TX[ui.confirm.choices]}"; read -r a || return 1; [[ "$a" =~ ^[jJyY]$ ]]
}

# Zeileneditor in der Statuszeile (TUI): Tippen, ⌫, Ctrl-U leert, Enter übernimmt, Esc bricht ab
_ui_edit() { # prompt vorgabe → UI_INPUT, Rückgabe 1 bei Abbruch/EOF
  local p=$1 t
  UI_INPUT=$2
  while true; do
    t=$UI_INPUT; _ui_fit t $((UI_COLS - ${#p} - 8))
    _ui_draw_at $((UI_ROWS - 1)) " $C_CYA$C_B$p:$C_R $C_WHT$t$C_R$C_CYA$_UI_CUR$C_R"
    _ui_hints $((UI_COLS - 2)) "$_UI_KENT|${TX[ui.hint.apply]}|1" "esc|${TX[ui.hint.cancel]}|1" "^U|${TX[ui.hint.clear]}|2"
    _ui_rep ' ' $((UI_COLS - 2 - _UI_W))
    _ui_draw_at "$UI_ROWS" "$C_BAR$_UI_OUT$_UI_REP$C_BAR"
    _ui_readkey 1 || { UI_INPUT=""; return 1; }
    case "$UI_KEY" in
      timeout) ;;
      enter) return 0;;
      esc) UI_INPUT=""; return 1;;
      backspace) UI_INPUT=${UI_INPUT:0:${#UI_INPUT}-1};;
      $'\x15') UI_INPUT="";;
      *) [ ${#UI_KEY} -eq 1 ] && [[ $UI_KEY == [[:print:]] ]] && UI_INPUT+=$UI_KEY;;
    esac
  done
}

ui_input() { # prompt [vorgabe] → UI_INPUT (leer = vorgabe)
  local rc def=${2:-}
  UI_INPUT=""
  if _ui_tui_on; then
    _ui_edit "$1" "$def"; rc=$?
    _UI_STATUS=""
    _ui_reflush
    return $rc
  fi
  printf '%s  %s%s: %s' "$C_CYA" "$1" "${def:+ [$def]}" "$C_R"; read -r UI_INPUT; rc=$?
  [ -z "$UI_INPUT" ] && [ $rc -eq 0 ] && UI_INPUT=$def
  return $rc
}

# ─── Betrachter für ui_run_page ────────────────────────────────────────────
# Ausgabe → _UPG (Zeilen, Tabs ausgerollt, \r entfernt, SGR-Farben bleiben), _UPGP (Klartext,
# klein, für die Suche), _UPGW (längste Zeile)
_ui_pager_load() { # datei
  local -a raw; local l p i s col piece
  mapfile -t raw < "$1"
  _UPG=() _UPGP=() _UPGW=0
  for l in "${raw[@]}"; do
    l=${l%$'\r'}; l=${l##*$'\r'}
    if [[ $l == *$'\t'* ]]; then # Tabs auf 8er-Raster
      s="" col=0
      while [[ $l == *$'\t'* ]]; do
        piece=${l%%$'\t'*}; l=${l#*$'\t'}; _ui_strip "$piece"
        col=$((col + ${#_UI_P})); s+=$piece; i=$((8 - col % 8)); printf -v piece '%*s' "$i" ''; s+=$piece; col=$((col + i))
      done
      l=$s$l
    fi
    _ui_strip "$l"; p=$_UI_P
    _UPG+=("$l") _UPGP+=("${p,,}")
    _ui_w "$p"; [ "$_UI_W" -gt "$_UPGW" ] && _UPGW=$_UI_W
  done
}
_ui_strip() { # text → _UI_P ohne Escape-Sequenzen
  local s=$1 out=""
  while [[ $s == *$'\e'* ]]; do
    out+=${s%%$'\e'*}; s=${s#*$'\e'}
    if [[ $s == \[* ]]; then s=${s#\[}; s=${s#*[A-Za-z@~]}; fi
  done
  _UI_P=$out$s
}
_ui_slice() { # zeile ab breite → _UI_OUT: sichtbarer Ausschnitt, SGR-Farben bleiben erhalten
  local s=$1 off=$2 w=$3 out="" col=0 txt n a e seq
  while [ -n "$s" ]; do
    if [[ $s == $'\e'* ]]; then
      s=${s:1}
      if [[ $s == \[* ]]; then
        seq=${s%%[A-Za-z@~]*}; s=${s:${#seq}}; e=${s:0:1}; s=${s:1}
        [ "$e" = m ] && out+=$'\e'$seq$e
      fi
      continue
    fi
    txt=${s%%$'\e'*}; s=${s:${#txt}}; n=${#txt}
    if [ $((col + n)) -gt "$off" ] && [ "$col" -lt $((off + w)) ]; then
      a=$((off - col)); [ $a -lt 0 ] && a=0
      e=$((off + w - col)); [ $e -gt "$n" ] && e=$n
      out+=${txt:a:e-a}
    fi
    col=$((col + n))
  done
  _UI_OUT=$out$C_R
}

_ui_pager_draw() { # titel top links treffer suche
  local w=$UI_COLS ph=$((UI_ROWS - 5)) top=$2 left=$3 hit=$4 q=$5 i l n=${#_UPG[@]} cw end pos g x
  local -a hh=()
  _UI_LINES=()
  _ui_tui_top "$w"
  _UI_CRUMB=("${_UCR_T[@]}" "$1"); [ ${#_UCR_T[@]} -gt 0 ] || _UI_CRUMB=("$1")
  tf x ui.pager.lines "$n"
  _ui_tui_crumb "$w" "$x"
  _UI_LINES+=("")
  cw=$((w - 3))
  end=$((top + ph)); [ $end -gt "$n" ] && end=$n
  if [ "$n" -eq 0 ]; then
    if [ "$_UPG_LOAD" = 1 ]; then _UI_LINES+=("   $C_GRY${1}: ${TX[ui.loading]}$UI_SYM_ELL$C_R"); else _UI_LINES+=("   $C_GRY${TX[ui.pager.no_output]}$C_R"); fi
    end=1 top=0
  fi
  for ((i=top; i<end && n>0; i++)); do
    l=${_UPG[i]}
    g=" "; [ "$i" = "$hit" ] && g="$C_YLW$C_B$UI_SYM_HDR$C_R"
    _ui_strip "$l"
    if [ ${#_UI_P} -gt $((left + cw)) ]; then
      _ui_slice "$l" "$left" $((cw - 1)); _UI_OUT+="$C_GRY$UI_SYM_MORE$C_R"
    else
      _ui_slice "$l" "$left" "$cw"
    fi
    _UI_LINES+=("$g $_UI_OUT")
  done
  for ((i=end-top; i<ph; i++)); do _UI_LINES+=(""); done
  tf pos ui.pager.pos $((top + 1)) "$end" "$n"; [ "$n" -eq 0 ] && pos=""
  [ "$left" -gt 0 ] && { tf x ui.pager.column $((left + 1)); pos+=" · $x"; }
  [ "$_UI_UTF8" = 1 ] || pos=${pos//–/-}
  if [ -n "$q" ]; then
    if [ "$hit" -ge 0 ]; then tf x ui.pager.search "$q"; pos+="  $C_YLW$x$C_R"; else tf x ui.pager.not_found "$q"; pos+="  $C_RED$x$C_R"; fi
  fi
  _UI_LINES+=(" $C_GRY$pos$C_R")
  hh=("$_UI_KNAV|${TX[ui.hint.scroll]}|2" "q|${TX[ui.hint.close]}|1" "/|${TX[ui.hint.search]}|3")
  [ -n "$q" ] && hh+=("n|${TX[ui.hint.next]}|4")
  [ "$_UPGW" -gt "$cw" ] && hh+=("$_UI_KLR|${TX[ui.hint.sideways]}|3")
  hh+=("${TX[ui.key.page]}|${TX[ui.hint.page]}|5" "${TX[ui.key.home_end]}|${TX[ui.hint.top_bottom]}|6")
  [ "$_UI_UTF8" = 1 ] || hh[${#hh[@]}-2]="PgUp/PgDn|${TX[ui.hint.page]}|5"
  _ui_hints $((w - 2)) "${hh[@]}"
  _ui_rep ' ' $((w - 2 - _UI_W))
  _UI_LINES+=("$C_BAR$_UI_OUT$_UI_REP $C_BAR")
  _ui_flush
}

_ui_pager_find() { # suchbegriff start richtung → _UI_HIT (-1 = nichts)
  local f=${1,,} i=$2 d=$3 n=${#_UPGP[@]} k
  _UI_HIT=-1
  [ -n "$f" ] && [ "$n" -gt 0 ] || return 0
  for ((k=0; k<n; k++)); do
    (( i < 0 )) && i=$((n - 1)); (( i >= n )) && i=0
    if [[ ${_UPGP[i]} == *"$f"* ]]; then _UI_HIT=$i; return 0; fi
    i=$((i + d))
  done
}

_ui_pager() { # titel
  local title=$1 top=0 left=0 hit=-1 q="" dirty=1 h n=${#_UPG[@]} step mx
  while true; do
    if [ "$_UI_WINCH" = 1 ]; then _UI_WINCH=0; _ui_size; _UI_CLR=1 dirty=1; fi
    h=$((UI_ROWS - 5)); [ $h -lt 1 ] && h=1
    mx=$((n - h)); [ $mx -lt 0 ] && mx=0
    [ $top -gt $mx ] && top=$mx; [ $top -lt 0 ] && top=0
    step=$(( (UI_COLS - 3) / 2 )); [ $step -lt 4 ] && step=4
    [ "$dirty" = 1 ] && _ui_pager_draw "$title" "$top" "$left" "$hit" "$q"
    dirty=1
    _ui_readkey 0.25 || return 0
    case "$UI_KEY" in
      timeout) dirty=0;;
      q|esc|enter|backspace) return 0;;
      up|k) top=$((top - 1));;
      down|j) top=$((top + 1));;
      pgup|b) top=$((top - h + 1));;
      pgdn|" "|f) top=$((top + h - 1));;
      home|g) top=0 left=0;;
      end|G) top=$mx;;
      left|h) left=$((left - step)); [ $left -lt 0 ] && left=0;;
      right|l) [ $((left + UI_COLS - 3)) -lt "$_UPGW" ] && left=$((left + step));;
      /) if _ui_edit "${TX[ui.pager.search_prompt]}" ""; then
           q=$UI_INPUT; _ui_pager_find "$q" "$top" 1; hit=$_UI_HIT
           [ "$hit" -ge 0 ] && { top=$((hit - h / 3)); left=0; }
         fi;;
      n|N) if [ -n "$q" ]; then
             if [ "$UI_KEY" = n ]; then _ui_pager_find "$q" $((hit + 1)) 1; else _ui_pager_find "$q" $((hit - 1)) -1; fi
             hit=$_UI_HIT; [ "$hit" -ge 0 ] && top=$((hit - h / 3))
           fi;;
      *) dirty=0;;
    esac
  done
}

# ─── Vordergrundbefehle ────────────────────────────────────────────────────
# Trap mit Befehl statt trap '' INT, sonst erben Kinder das Ignorieren und Ctrl-C wirkt nicht.
ui_run_fg() { # cmd…
  local rc
  ui_suspend
  PD_INT=0
  trap 'PD_INT=1' INT
  "$@"; rc=$?
  trap '_ui_on_signal 130' INT
  ui_resume
  return "$rc"
}

ui_run_page() { # titel cmd…
  local title=$1 rc tmp text; shift
  if ! _ui_tui_on; then # Zeilenmodus (oder TUI suspendiert): einfache Ausgabe
    ui_suspend
    printf '\n%s── %s ──%s\n' "$C_CYA" "$title" "$C_R"
    PD_INT=0
    trap 'PD_INT=1' INT
    "$@" </dev/null; rc=$?
    trap '_ui_on_signal 130' INT
    ui_pause
    ui_resume
    return "$rc"
  fi
  # TUI: sofort frischer Frame mit Titel und Lade-Hinweis (nie die alte Ausgabe stehen lassen)
  _UPG=() _UPGP=() _UPGW=0 _UI_CLR=1 _UPG_LOAD=1
  _ui_pager_draw "$title" 0 0 -1 ""
  tf text ui.loading_title "$title"; ui_loading "$text"
  tmp=$(mktemp "${TMPDIR:-/tmp}/sshlobby.XXXXXX") || return 1
  PD_INT=0
  trap 'PD_INT=1' INT
  "$@" </dev/null >"$tmp" 2>&1; rc=$?
  trap '_ui_on_signal 130' INT
  _ui_pager_load "$tmp"; rm -f "$tmp"; _UPG_LOAD=0
  if [ "$PD_INT" = 1 ]; then _UPG+=("" "$C_YLW${TX[ui.pager.interrupted]}$C_R"); _UPGP+=("" "")
  elif [ "$rc" -ne 0 ]; then tf text ui.pager.exit_code "$rc"; _UPG+=("" "$C_GRY$text$C_R"); _UPGP+=("" ""); fi
  _ui_pager "$title"
  _UI_STATUS=""
  return "$rc"
}

ui_run_task() { # text cmd…
  local text=$1 rc tmp out; shift
  ui_note info "$text…"
  tmp=$(mktemp "${TMPDIR:-/tmp}/sshlobby.XXXXXX") || return 1
  PD_INT=0
  trap 'PD_INT=1' INT
  "$@" </dev/null >"$tmp" 2>&1; rc=$?
  trap '_ui_on_signal 130' INT
  out=$(tail -n 8 "$tmp"); rm -f "$tmp"
  if [ "$UI_MODE" = line ]; then
    [ -n "$out" ] && printf '    %s\n' "${out//$'\n'/$'\n'    }"
    ui_check_rc "$rc" "$text"
  else
    ui_check_rc "$rc" "$text" "$out"
  fi
  return "$rc"
}

ui_check_rc() { # rc was [ausgabe]
  if [ "$1" -eq 0 ] || [ "$1" -eq 130 ] || [ "$PD_INT" = 1 ]; then return 0; fi
  local m; tf m ui.exit_code "$2" "$1"
  ui_msg err "$m${3:+$'\n'$3}"
}
