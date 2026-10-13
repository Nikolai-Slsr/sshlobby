# shellcheck shell=bash
# UI-Tests in tmux: Layout bei verschiedenen Größen, Auswahlbalken, Scrollen, Filter, Größen-
# wechsel, Betrachter (ui_run_page), Dialoge, Tastatur-Robustheit, NO_COLOR, ASCII-Fallback.
# Nutzt die Helfer aus test_tui.sh (tui_start mit TUI_W/TUI_H, tui_wait, tui_title …).
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

ui_stop() { TM kill-session -t "$TS" 2>/dev/null; } # Session beenden (mehrere Starts pro Test)
ui_cap() { TM capture-pane -p -e -t "$TS"; }       # Bildschirm mit Farben/Attributen

# Nichts läuft über die Breite (umbrochene Zeilen würde -J zusammenfügen, dann fehlen Zeilen),
# Höhe stimmt, Fußzeile steht in der letzten Zeile
ui_fits() { # [fußzeilentext]
  local cols rows l n=0 last=""
  cols=$(TM display -p -t "$TS" '#{pane_width}'); rows=$(TM display -p -t "$TS" '#{pane_height}')
  while IFS= read -r l; do
    n=$((n + 1)); last=$l
    [ ${#l} -le "$cols" ] || die "Zeile $n breiter als $cols: »$l«"
  done < <(TM capture-pane -p -J -t "$TS")
  eq "$n" "$rows" "Zeilen bei ${cols}x$rows (Umbruch?)"
  [ -z "${1:-}" ] || [[ $last == *"$1"* ]] || die "Fußzeile ohne »$1«: »$last«\n$(tui_screen)"
}
ui_sel_bar() { # Auswahlzeile hat Balken-Hintergrund (256 Farben: 48;5;24)
  ui_cap | grep -F -- "$TUI_SEL" | head -n1 | grep -qF '48;5;24' || die "kein Auswahlbalken:\n$(ui_cap | grep -F -- "$TUI_SEL" | cat -v)"
}

# Werkzeug-Erweiterung für Betrachter-Tests: breite und lange Ausgabe, langsame zweite Seite
ui_demo_lib() {
  mkdir -p "$W/alt"; cp -r "$ROOT/lib" "$W/alt/lib"
  cat > "$W/alt/lib/tools_uidemo.sh" <<'EOF'
_uid_wide() { local i; printf 'BREIT-%0300d-ENDE\n' 0; for ((i=1; i<=120; i++)); do printf 'zeile %d\tspalte\n' "$i"; done; }
_uid_slow() { sleep 2; echo "LANGSAM-FERTIG"; }
_uid_page1() { ui_run_page "Breite Ausgabe" _uid_wide; }
_uid_page2() { ui_run_page "Langsame Ausgabe" _uid_slow; }
tool_register uid1 "UI-Demo breit" "Test" "all" - _uid_page1 1
tool_register uid2 "UI-Demo langsam" "Test" "all" - _uid_page2 2
EOF
}

t_ui_layout_sizes() {
  conf "MODE=docker" "RECENT_MAX=0"
  local s
  for s in 60x20 80x24 120x40; do
    TUI_W=${s%x*} TUI_H=${s#*x} tui_start; tui_title "sshlobby"; tui_wait "COMPOSE-PROJEKTE"
    tui_sel_is "authproxy"; ui_fits "q Logout"; ui_sel_bar
    tui_keys 4 Enter; tui_title "nextcloud"; tui_sel_is "admin-panel"; ui_fits "q zurück"; ui_sel_bar
    tui_wait "Start › nextcloud"
    tui_keys 2 Enter; tui_title "Nextcloud"; tui_wait "Start › nextcloud › Nextcloud"; ui_fits "q zurück"
    tui_wait "Image"; tui_sel_is "Shell rein"
    tui_keys q q; tui_title "sshlobby"; tui_keys q; tui_rc 20; ui_stop
    rm -f "$W/tui.rc"
  done
}
t_ui_header_values() {
  conf "MODE=docker"
  tui_start; tui_title "sshlobby"
  local top; top=$(tui_screen | head -n1)
  [[ $top == *TESTHOST*docker*"v3.1.1"* ]] || die "Kopf: $top"
  [[ $top == *"12/14 Container"* ]] || die "Zähler fehlt: $top"
  [[ $top =~ RAM\ [0-9]+%.*Disk\ [0-9]+%.*Load\ [0-9.]+.*up\ [0-9]+ ]] || die "Systemwerte: $top"
  [[ $top =~ up\ [0-9]+\ (T|h|min) ]] || die "Uptime nicht kompakt: $top"
  tui_keys q; tui_rc 20
}
t_ui_unhealthy_red() {
  conf "MODE=docker"
  sed -i 's/^chat-mongodb|mongo:8.0.20|running|Up 4 weeks|/chat-mongodb|mongo:8.0.20|running|Up 4 weeks (unhealthy)|/' "$PD_FIX/host-docker"
  tui_start; tui_title "sshlobby"; tui_wait "✗ 1 unhealthy"; tui_wait "1 unhealthy"
  ui_cap | head -n1 | grep -qF '38;5;203' || die "unhealthy im Kopf nicht rot"
  tui_keys 4 Enter; tui_title "nextcloud"; tui_wait "unhealthy"
  tui_keys q q; tui_rc 20
}
t_ui_scroll_and_position() {
  many_cts 60
  TUI_W=80 TUI_H=24 tui_start; tui_wait "ct01"; ui_fits "q Logout"
  tui_screen | tail -n1 | grep -qE '1–[0-9]+/6[0-9]' || die "Position fehlt: $(tui_screen | tail -n1)"
  tui_keys End; tui_sel_is "Werkzeuge"; tui_wait "ct60"; ui_fits
  tui_keys PageUp; tui_sel_is "● ct"; ui_sel_bar
  tui_keys Home; tui_sel_is "ct01"; tui_wait "PROJEKTE"
  tui_keys q; tui_rc 20
}
t_ui_filter() {
  local now; now=$(date +%s)
  printf '%s\n' "$now|alpha|app|shell" > "$CONF/recents"; printf '%s\n' "alpha|db" > "$CONF/favorites"
  tui_start; tui_wait "ZULETZT"; tui_wait "/ filtern"
  tui_keys / g a m; tui_wait "/ gam"; tui_wait "1 Treffer"
  tui_sel_is "gamma"; tui_gone "ZULETZT"; tui_gone "FAVORITEN"; tui_wait "PROJEKTE / CONTAINER"
  tui_gone "alpha"
  tui_keys Enter; tui_wait "Filter gam"; tui_wait "esc Filter aufheben"
  tui_keys Escape; tui_wait "alpha"; tui_wait "ZULETZT"; tui_title "sshlobby"   # Esc hebt Filter auf
  tui_keys / a p p; tui_wait "1 Treffer"; tui_wait "ZULETZT"; tui_gone "FAVORITEN"         # leere Abschnitte weg
  tui_keys Escape; tui_wait "FAVORITEN"
  tui_keys / x y z; tui_wait "keine Treffer für „xyz“"; tui_keys BSpace BSpace BSpace; tui_wait "FAVORITEN"
  tui_keys Escape
  tui_keys / d e l t a Enter Enter; tui_title "delta"                                    # übernehmen, öffnen
  tui_keys Escape; tui_title "sshlobby"; tui_wait "FAVORITEN"                    # Filter weg
  tui_keys 9 Enter; tui_title "Server-Werkzeuge"; tui_keys / a n d e r                    # auch in Werkzeugen
  tui_wait "1 Treffer"; tui_sel_is "Anderer Server"; tui_gone "Fehler-Log"
  tui_keys Escape Escape; tui_title "sshlobby"
  tui_keys q; tui_rc 20
}
t_ui_resize() {
  many_cts 60
  TUI_W=120 TUI_H=40 tui_start; tui_wait "ct01"; tui_keys End; tui_sel_is "Werkzeuge"; ui_fits "q Logout"
  local s i
  for s in 60x20 80x24 100x30 120x40; do
    TM resize-window -t "$TS" -x "${s%x*}" -y "${s#*x}"
    for ((i=0; i<30; i++)); do
      [ "$(tui_screen | wc -l)" -eq "${s#*x}" ] && tui_screen | tail -n1 | grep -qF "q Logout" && break; sleep 0.1
    done
    sleep 0.4; ui_fits "q Logout"; tui_sel_is "Werkzeuge"
  done
  tui_keys q; tui_rc 20
}
t_ui_pager() {
  ui_demo_lib; norecent
  TUI_W=80 TUI_H=24 tui_start SSHLOBBY_LIB="$W/alt/lib"; tui_title "sshlobby"
  tui_keys 7 Enter; tui_title "Server-Werkzeuge"; tui_keys 1 Enter
  tui_title "Breite Ausgabe"; tui_wait "BREIT-000"; tui_wait "Zeile 1–19 von 121"
  ui_fits "q schließen"
  tui_screen | grep -qF "ENDE" && die "breite Zeile umgebrochen statt abgeschnitten"
  tui_wait "zeile 10        spalte"                       # Tab ausgerollt (8er-Raster)
  tui_keys End; tui_wait "zeile 120"; tui_keys Home; tui_wait "BREIT-000"
  tui_keys PageDown; tui_wait "Zeile 19–"; tui_keys Up; tui_wait "Zeile 18–"
  tui_keys Home; tui_wait "Zeile 1–"
  local i; for i in 1 2 3 4 5 6 7 8; do tui_keys Right; done
  tui_wait "-ENDE"; tui_wait "Spalte"; ui_fits
  tui_keys Left Left Left Left Left Left Left Left; tui_gone "Spalte"
  tui_keys /; tui_wait "Suchen:"; tui_keys -l "zeile 77"; tui_keys Enter
  tui_wait "Suche „zeile 77“"; tui_wait "zeile 77"
  tui_keys q; tui_title "Server-Werkzeuge"
  # zweite Seite: sofort neuer Titel und Lade-Hinweis, nie die alte Ausgabe
  tui_keys 2 Enter; tui_title "Langsame Ausgabe"; tui_wait "lädt"
  tui_screen | grep -qF "BREIT-" && die "alte Ausgabe sichtbar:\n$(tui_screen)"
  tui_wait "LANGSAM-FERTIG" 6; tui_keys Escape; tui_title "Server-Werkzeuge"
  tui_keys q q; tui_rc 20
}
t_ui_confirm_dialog() {
  conf "MODE=docker"
  tui_start; tui_title "sshlobby"; tui_keys 4 Enter; tui_title "nextcloud"
  tui_keys 2 Enter; tui_title "Nextcloud"
  tui_keys 4 Enter; tui_wait "Achtung"; tui_wait "Nextcloud stoppen? [j/N]"; tui_wait "N Nein"
  ui_cap | grep -F "Achtung" | grep -qF '38;5;203' || die "gefährliche Aktion nicht rot"
  tui_keys n; tui_gone "Achtung"; tui_title "Nextcloud"; ! logged stop || die "Stop trotz n"
  tui_keys 5 Enter; tui_wait "starte"; tui_gone "Achtung"                     # Start fragt nicht
  tui_keys 3 Enter; tui_wait "Nextcloud neu starten? [j/N]"; tui_keys j; wait_logged restart
  tui_gone "Achtung"; tui_keys q q; tui_title "sshlobby"; tui_keys q; tui_rc 20
}
t_ui_message_box() {
  tui_start STUB_ACTION_RC=3; tui_title "sshlobby"
  tui_keys Enter; tui_title "alpha"; tui_keys 2 Enter; tui_title "app"
  tui_keys 5 Enter; tui_wait "Fehler"; tui_wait "app: starte: Exit-Code 3"; tui_wait "[Enter] weiter"
  ui_fits; tui_keys Enter; tui_gone "Exit-Code 3"; tui_title "app"
  tui_keys q q; tui_title "sshlobby"; tui_keys q; tui_rc 20
}
t_ui_keys_not_lost() {                                   # Esc Esc in einem Rutsch, Tippen im Voraus
  conf "MODE=docker" "RECENT_MAX=0"
  tui_start; tui_title "sshlobby"
  local i
  for i in 1 2 3; do
    tui_keys 4 Enter 5 Enter; tui_title "chat-mongodb"; tui_wait "Start › nextcloud › chat-mongodb"
    TM send-keys -t "$TS" -l $'\e\e'; tui_title "sshlobby"
  done
  tui_keys 4 Enter 2 Enter; tui_title "Nextcloud"
  TM send-keys -t "$TS" -l $'\e\e6'; tui_title "sshlobby"; tui_sel_is "Werkzeuge"
  tui_keys Enter; tui_title "Server-Werkzeuge"
  tui_keys q q; tui_rc 20
}
t_ui_input_box() {                                       # ui_input im TUI: vorbelegt, editierbar
  tui_start; tui_title "sshlobby"
  tui_keys 7 Enter; tui_title "Server-Werkzeuge"; tui_keys 9 Enter; tui_title "Neues Projekt"
  tui_keys Enter; tui_wait "Name:"; tui_wait "esc abbrechen"
  tui_keys -l "Neu"; tui_wait "Name: Neu"; tui_keys BSpace BSpace BSpace; tui_keys -l "neu1"; tui_wait "Name: neu1"
  tui_keys Escape; tui_title "Server-Werkzeuge"; ! logged launch || die "Launch trotz Esc"
  tui_keys q q; tui_rc 20
}
t_ui_no_color() {
  conf "MODE=docker"
  tui_start NO_COLOR=1; tui_title "sshlobby"; tui_keys Down
  local cap i
  for ((i=0; i<50; i++)); do tui_screen | grep -F "›" | grep -qF gitea && break; sleep 0.1; done
  cap=$(ui_cap)
  grep -qE $'\e\\[[0-9;]*(3[0-7]|9[0-7]|4[0-7]|38;5|48;5)[;m]' <<< "$cap" && die "Farben trotz NO_COLOR:\n$(cat -v <<< "$cap" | head -5)"
  grep -F "›" <<< "$cap" | grep -F "gitea" | grep -qF $'\e[7m' || die "Auswahl nicht reverse mit ›:\n$(cat -v <<< "$cap" | grep gitea)"
  ui_fits "q Logout"
  tui_keys 4 Enter; tui_title "nextcloud"; tui_wait "[healthy]"          # Pills als [text]
  tui_keys q q; tui_rc 20
}
t_ui_ascii_fallback() {
  conf "MODE=docker"
  TUI_W=80 TUI_H=24 tui_start LC_ALL=C; tui_wait "COMPOSE-PROJEKTE"
  local scr; scr=$(tui_screen)
  grep -qE '─|❯|●|▌|›|╭|★' <<< "$scr" && die "Unicode-Rahmen/Symbole trotz LC_ALL=C:\n$scr"
  grep -F "authproxy" <<< "$scr" | grep -qF " > " || die "ASCII-Marker > fehlt:\n$scr"
  grep -qF "# COMPOSE-PROJEKTE ---" <<< "$scr" || die "ASCII-Überschrift fehlt"
  ui_fits "q Logout"
  tui_keys 4 Enter; tui_wait "Start > nextcloud"; tui_keys 8 Enter; tui_wait "+-"; tui_wait "[j/N]"
  tui_keys n; tui_gone "[j/N]"; tui_keys q q; tui_rc 20
}
t_ui_terminal_clean_after_pager() {
  ui_demo_lib
  tui_start SSHLOBBY_LIB="$W/alt/lib"; tui_title "sshlobby"
  tui_keys 7 Enter 1 Enter; tui_title "Breite Ausgabe"; TM resize-window -t "$TS" -x 70 -y 20
  sleep 0.5; ui_fits; tui_keys q; tui_title "Server-Werkzeuge"; tui_keys q q; tui_rc 20
  eq "$(TM display -p -t "$TS" '#{alternate_on} #{cursor_flag}')" "0 1" "Alternate Screen aus, Cursor an"
  grep -qE '(^| )echo( |$)' "$W/tui.stty" || die "echo aus nach Ende"
  grep -qE '(^| )icanon( |$)' "$W/tui.stty" || die "icanon aus nach Ende"
}
t_ui_line_mode_plain() {                                 # Zeilenmodus ohne TTY: keine Escapes, keine Balken
  menu '1\n2\nb\nb\nq\n'; rc_is 20; no_err
  grep -q $'\e' <<< "$OUT" && die "Escape-Sequenzen im Zeilenmodus"
  hasnt "$OUT" "sshlobby ›"; hasnt "$OUT" "▲"; has "$OUT" " 3) Restart"
}
