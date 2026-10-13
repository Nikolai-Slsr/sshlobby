# shellcheck shell=bash
# TUI-Tests in tmux (eigener Socket -L sshlobby-test, 100x30 oder TUI_W x TUI_H, eigene Session pro Test).
# Ohne tmux: SKIP. Der Auswahlcursor ist UI_SYM_SEL aus lib/ui.sh (Default ❯); ändert der
# UI-Agent das Symbol, hier TUI_SEL anpassen. Der Screen-Titel steht am Ende der Breadcrumb-
# Zeile (Zeile 2, „Start › nextcloud › chat-mongodb“), tui_title wartet darauf.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

TUI_SEL='❯'
TM() { tmux -L "${PD_TMUX_SOCK:-sshlobby-test}" -f /dev/null "$@"; }

# sshlobby in einer frischen tmux-Session starten: tui_start [VAR=wert …] [-- sshlobby-args]
tui_start() {
  command -v tmux >/dev/null || skip "tmux fehlt"
  local -a envs=() args=(); local a
  while [ $# -gt 0 ]; do [ "$1" = "--" ] && { shift; args=("$@"); break; }; envs+=("$1"); shift; done
  TS="pd$$x${RANDOM}"
  {
    printf 'export PATH=%q HOME=%q PD_FIX=%q STUB_LOG=%q SHELL=%q LC_ALL=C.UTF-8 SSHLOBBY_LANG=%q STUB_TTY_INTERACTIVE=1 SSHLOBBY_UPDATE_CHECK=%q\n' \
      "$PATH" "$HOME" "$PD_FIX" "$STUB_LOG" "$SHELL" "${SSHLOBBY_LANG:-de}" "${SSHLOBBY_UPDATE_CHECK:-no}"
    for a in "${envs[@]}"; do printf 'export %q\n' "$a"; done
    printf 'stty sane\nbash %q' "$PD"; [ ${#args[@]} -eq 0 ] || printf ' %q' "${args[@]}"; printf '\n'
    printf 'echo "RC=$?" > %q\n' "$W/tui.rc"
    printf 'stty -a > %q\n' "$W/tui.stty"
    printf 'exec sleep 60\n'
  } > "$W/tui.sh"
  trap 'TM kill-session -t "$TS" 2>/dev/null' EXIT
  # tmux startet Kommandos über $SHELL -c; im Test ist SHELL der Host-Shell-Stub
  SHELL=$(type -P bash) TERM=${TERM:-xterm-256color} TM new-session -d -x "${TUI_W:-100}" -y "${TUI_H:-30}" -s "$TS" "bash $W/tui.sh" || die "tmux startet nicht"
}
tui_screen() { TM capture-pane -p -t "$TS"; }
tui_keys() { TM send-keys -t "$TS" "$@"; }
tui_wait() { # text [sekunden] → wartet, bis der Text auf dem Bildschirm steht
  local i n=$(( ${2:-5} * 10 ))
  for ((i=0; i<n; i++)); do tui_screen | grep -qF -- "$1" && return 0; sleep 0.1; done
  die "Bildschirm ohne »$1«:\n$(tui_screen)"
}
tui_title() { # titel → wartet, bis die Breadcrumb-Zeile mit diesem Titel endet
  local i l
  for ((i=0; i<50; i++)); do
    l="$(tui_screen | sed -n 2p)  "
    [[ $l == *"› $1  "* || $l == " $1  "* ]] && return 0
    sleep 0.1
  done
  die "Titel »$1« fehlt:\n$(tui_screen)"
}
tui_gone() { # text → wartet, bis der Text vom Bildschirm verschwunden ist
  local i
  for ((i=0; i<50; i++)); do tui_screen | grep -qF -- "$1" || return 0; sleep 0.1; done
  die "Bildschirm zeigt noch »$1«:\n$(tui_screen)"
}
wait_logged() { # zeile → wartet, bis der Stub den Aufruf protokolliert hat
  local i
  for ((i=0; i<50; i++)); do logged "$1" && return 0; sleep 0.1; done
  die "nicht im Stub-Log: $1"
}
tui_sel() { tui_screen | grep -F -- "$TUI_SEL" | head -n1; } # Zeile mit dem Auswahlcursor
tui_sel_is() { # text → wartet, bis die markierte Zeile den Text enthält
  local i
  for ((i=0; i<50; i++)); do tui_sel | grep -qF -- "$1" && return 0; sleep 0.1; done
  die "markiert ist »$(tui_sel)«, erwartet »$1«\n$(tui_screen)"
}
tui_rc() { # erwarteter Exit-Code → wartet auf Ende von sshlobby
  local i
  for ((i=0; i<50; i++)); do [ -s "$W/tui.rc" ] && break; sleep 0.1; done
  eq "$(cat "$W/tui.rc" 2>/dev/null)" "RC=$1" "Exit-Code im TUI"
}
many_cts() { # n → Fixture mit n laufenden CTs ct01…, ohne Docker
  local i; : > "$PD_FIX/cts"
  for ((i=1; i<=$1; i++)); do printf 'ct%02d|Running|10.0.1.%d|no\n' "$i" "$i" >> "$PD_FIX/cts"; done
}

t_tui_arrows_and_vi_keys() {
  tui_start; tui_title "sshlobby"
  tui_sel_is "alpha"
  tui_keys Down; tui_sel_is "beta"
  tui_keys j j; tui_sel_is "gamma"
  tui_keys Up; tui_sel_is "delta"
  tui_keys k; tui_sel_is "beta"
  TM send-keys -t "$TS" -l $'\eOB'; tui_sel_is "delta"     # Application-Cursor-Modus (\eOB)
  TM send-keys -t "$TS" -l $'\e[A'; tui_sel_is "beta"      # Normalmodus (\e[A)
  tui_keys End; tui_sel_is "Werkzeuge"
  tui_keys Home; tui_sel_is "alpha"
  tui_keys q; tui_rc 20
}
t_tui_headers_skipped() {
  local now; now=$(date +%s)
  printf '%s\n' "$now|alpha|app|shell" > "$CONF/recents"; printf '%s\n' "alpha|db" > "$CONF/favorites"
  tui_start; tui_wait "ZULETZT"
  tui_sel_is "alpha / app"
  tui_keys Down; tui_sel_is "★ alpha/db"                   # Überschrift FAVORITEN übersprungen
  tui_keys Down; tui_sel_is "● alpha"                      # PROJEKTE / CONTAINER übersprungen
  tui_keys Up Up; tui_sel_is "alpha / app"
  tui_keys Up; tui_sel_is "alpha / app"                    # oben bleibt oben
  tui_sel | grep -qF "▌" && die "Überschrift markiert"
  tui_keys q; tui_rc 20
}
t_tui_scroll_long_list() {
  many_cts 60
  tui_start; tui_wait "ct01"
  tui_screen | grep -qF "ct40" && die "ct40 dürfte noch nicht sichtbar sein"
  tui_keys End; tui_sel_is "Werkzeuge"
  tui_wait "ct60"; tui_screen | grep -qF " ct01" && die "ct01 nach End noch sichtbar"
  tui_keys PageUp; tui_sel_is "● ct"
  tui_keys Home; tui_sel_is "ct01"; tui_wait "PROJEKTE"
  eq "$(tui_screen | wc -l)" 30 "Bildschirmhöhe"
  tui_keys q; tui_rc 20
}
t_tui_digit_jump() {
  many_cts 60
  tui_start; tui_wait "ct01"
  tui_keys 1 2; tui_sel_is "ct12"                          # mehrstellig
  sleep 1; tui_keys 5; sleep 1.2; tui_sel_is "ct05"        # Timeout schließt die Zahl ab
  tui_keys 3 7 Enter; tui_title "ct37"                   # Zahl + Enter öffnet
  tui_keys Escape; tui_title "sshlobby"; tui_sel_is "ct37"   # Cursor bleibt stehen
  tui_keys q; tui_rc 20
}
t_tui_open_and_back() {
  tui_start; tui_title "sshlobby"
  tui_keys Enter; tui_title "alpha"
  tui_keys Escape; tui_title "sshlobby"
  tui_keys Right; tui_title "alpha"; tui_keys Left; tui_title "sshlobby"
  tui_keys l; tui_title "alpha"; tui_keys h; tui_title "sshlobby"
  tui_keys l; tui_title "alpha"; tui_keys BSpace; tui_title "sshlobby"
  tui_keys l; tui_title "alpha"; tui_keys b; tui_title "sshlobby"
  tui_keys l; tui_title "alpha"; tui_keys q; tui_title "sshlobby"   # q im Untermenü = zurück
  tui_keys Escape b h Left; sleep 0.5; tui_title "sshlobby"       # im Hauptmenü wirkungslos
  tui_keys q; tui_rc 20
}
t_tui_exit_terminal_clean() {
  tui_start; tui_title "sshlobby"
  eq "$(TM display -p -t "$TS" '#{alternate_on}')" 1 "Alternate Screen während des Menüs"
  tui_keys q; tui_rc 20
  eq "$(TM display -p -t "$TS" '#{alternate_on} #{cursor_flag}')" "0 1" "Alternate Screen aus, Cursor an"
  grep -qE '(^| )echo( |$)' "$W/tui.stty" || die "echo aus nach Ende: $(cat "$W/tui.stty")"
  grep -qE '(^| )icanon( |$)' "$W/tui.stty" || die "icanon aus nach Ende"
}
t_tui_ctrl_c_in_logs() {
  tui_start STUB_LOGS_SLEEP=30; tui_title "sshlobby"
  tui_keys Enter; tui_title "alpha"
  tui_keys Down; tui_sel_is " app"; tui_keys Enter; tui_title "app"
  tui_keys Down; tui_sel_is "Logs folgen"; tui_keys Enter
  for _ in $(seq 50); do [ -e "$PD_FIX/.logs-running" ] && break; sleep 0.1; done
  tui_wait "log line from app"
  eq "$(TM display -p -t "$TS" '#{alternate_on}')" 0 "Logs laufen auf dem normalen Bildschirm"
  tui_keys C-c; tui_title "app"; tui_sel_is "Logs folgen"
  tui_screen | grep -qF "Exit-Code" && die "Fehlermeldung nach Ctrl-C"
  tui_keys q; tui_title "alpha"; tui_keys q; tui_title "sshlobby"; tui_keys q; tui_rc 20
}
t_tui_ctrl_c_in_menu() {
  tui_start; tui_title "sshlobby"
  tui_keys C-c; tui_rc 130
  eq "$(TM display -p -t "$TS" '#{alternate_on} #{cursor_flag}')" "0 1" "Terminal nach Ctrl-C"
  grep -qE '(^| )echo( |$)' "$W/tui.stty" || die "echo aus nach Ctrl-C"
}
t_tui_hotkeys_and_dialogs() {
  tui_start; tui_title "sshlobby"
  tui_keys Enter; tui_title "alpha"; tui_keys Down; tui_keys Enter; tui_title "app"
  tui_keys f; tui_wait "Favorit ★ entfernen"; eq "$(cat "$CONF/favorites")" "alpha|app"
  tui_keys 4; tui_sel_is "Stop"; tui_keys Enter; tui_wait "app stoppen? [j/N]"
  tui_keys n; tui_title "app"; ! logged stop || die "Stop trotz n"
  tui_keys 1; tui_keys Enter; tui_title "app"             # Shell (Stub) und direkt zurück
  for _ in $(seq 30); do logged exec && break; sleep 0.1; done; logged exec || die "keine Shell gestartet"
  tui_keys q q; tui_title "sshlobby"; tui_wait "★ alpha/app"
  tui_keys s; tui_rc 10
}
t_tui_message_and_pause() {
  tui_start; tui_title "sshlobby"
  tui_keys 2 Enter; tui_title "beta"; tui_keys Enter      # CT-Shell auf gestopptem CT
  tui_wait "CT „beta“ läuft nicht (Stopped)"; tui_wait "[Enter] weiter"
  tui_keys Enter; tui_gone "[Enter] weiter"; tui_title "beta"
  tui_keys q 7 Enter; tui_title "Server-Werkzeuge"; tui_keys 3 Enter   # Seite mit Ausgabe
  tui_title "Fehler-Log (journalctl -p err)"; tui_wait "STUB-JOURNALCTL"; tui_wait "q schließen"
  eq "$(TM display -p -t "$TS" '#{alternate_on}')" 1 "Ausgabe im Betrachter innerhalb der TUI"
  tui_keys Enter; tui_title "Server-Werkzeuge"
  tui_keys q q; tui_rc 20
}
t_tui_first_start_setup() {
  noconf
  tui_start STUB_HOSTNAME=docker-host; tui_title "Einrichtung"
  tui_wait "Vorschlag      layered"; tui_sel_is "layered"        # erkannter Modus vorausgewählt
  tui_keys Up; tui_sel_is "incus"; tui_keys Up; tui_sel_is "docker"; tui_keys Enter
  tui_wait "Anzeigename: docker-host"; tui_keys Enter
  tui_title "Beschreibungen"; tui_sel_is "examples/descriptions.docker-host"; tui_keys Enter
  tui_title "sshlobby"; tui_wait " docker "; tui_wait "COMPOSE-PROJEKTE"
  grep -qx 'MODE=docker' "$CONF/config" || die "Config nicht geschrieben"
  cmp -s "$CONF/descriptions" "$ROOT/examples/descriptions.docker-host" || die "Beschreibungen fehlen"
  tui_keys q; tui_rc 20
}
t_tui_first_start_setup_cancel() {
  noconf
  tui_start; tui_title "Einrichtung"; tui_keys Escape
  tui_title "sshlobby"; tui_wait " layered "; [ ! -e "$CONF/config" ] || die "Abbruch schreibt Config"
  tui_keys q; tui_rc 20
}
t_tui_resize_redraws() {
  many_cts 60
  tui_start; tui_wait "ct01"; tui_keys End; tui_sel_is "Werkzeuge"
  TM resize-window -t "$TS" -x 80 -y 15
  local i; for ((i=0; i<30; i++)); do [ "$(tui_screen | wc -l)" -eq 15 ] && tui_screen | grep -qF "q Logout" && break; sleep 0.1; done
  tui_screen | tail -n 3 | grep -qF "q Logout" || die "Fußzeile nach Resize nicht unten:\n$(tui_screen)"
  tui_sel_is "Werkzeuge"
  tui_keys q; tui_rc 20
}
t_tui_docker_mode() {
  conf "MODE=docker"
  tui_start; tui_wait "COMPOSE-PROJEKTE"
  tui_keys 4 Enter; tui_title "nextcloud"
  tui_keys 8 Enter; tui_wait "Projekt nextcloud neu starten (alle Services)? [j/N]"; tui_keys j
  wait_logged restart; tui_title "nextcloud"
  tui_keys 2 Enter; tui_title "Nextcloud"; tui_wait "Neustart  always"
  tui_keys q q; tui_wait "COMPOSE-PROJEKTE"; tui_keys q; tui_rc 20
}
