# shellcheck shell=bash
# Werkzeug „systemd-Dienste“ (lib/tools_systemd.sh) mit Beispieldaten aus fixtures/tools/systemd.
# Nummern im Werkzeug-Menü hängen von Modus und verfügbaren Werkzeugen ab, deshalb sucht tt_open
# sie über den Titel. Dienst-Screen: 1 Logs, 2 Warnungen, 3 status, 4 Unit-Datei, dann je nach
# Zustand Restart/Stop bzw. Start(/Restart), zuletzt Autostart an/aus.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

# Nummer des ersten Menüeintrags, dessen Zeile den Text enthält
tt_nr() { awk -v l="$2" 'index($0, l) && match($0, /^ *[0-9]+\)/) { s = substr($0, RSTART, RLENGTH); gsub(/[ )]/, "", s); print s; exit }' <<< "$1"; }
# Werkzeug öffnen: tt_open titel eingabe-danach [sshlobby-args] → $OUT usw. (TW, TN bleiben gesetzt)
tt_open() {
  local t=$1 rest=$2; shift 2
  export PD_TOOLS_ROOT="$PD_FIX/tools/root"
  menu 'q\n' "$@"; TW=$(tt_nr "$OUT" ") Werkzeuge"); [ -n "$TW" ] || die "kein Werkzeuge-Eintrag:\n$OUT"
  menu "$TW\nb\nq\n" "$@"; TN=$(tt_nr "$OUT" ") $t"); [ -n "$TN" ] || die "Werkzeug »$t« fehlt:\n$OUT"
  menu "$TW\n$TN\n$rest" "$@"
  # Das Werkzeug steht jetzt unter „Zuletzt“ im Werkzeug-Menü, dadurch verschieben sich die Nummern dort:
  # TN neu bestimmen (erster Treffer = Eintrag unter Zuletzt, öffnet dasselbe Werkzeug), damit
  # Folgeaufrufe mit "$TW\n$TN…" stimmen. OUT/RC/ERR bleiben die des Werkzeug-Laufs.
  local o=$OUT r=$RC e=$ERR
  menu "$TW\nb\nq\n" "$@"; TN=$(tt_nr "$OUT" ") $t")
  OUT=$o RC=$r ERR=$e
}
tt_tools() { export PD_TOOLS_ROOT="$PD_FIX/tools/root"; menu 'q\n'; TW=$(tt_nr "$OUT" ") Werkzeuge"); menu "$TW\nb\nq\n"; } # Werkzeug-Menü → $OUT
tt_svc() { # unit-label eingabe-im-dienst-screen → öffnet die Liste, dann den Dienst
  tt_open "systemd-Dienste" 'b\nb\nq\n'
  TS_N=$(tt_nr "$OUT" "● $1 "); [ -n "$TS_N" ] || die "Dienst $1 fehlt:\n$OUT"
  menu "$TW\n$TN\n$TS_N\n$2"
}
svc_logged() { awk '/^== /{s=($0 == "== systemctl"); next} s' "$STUB_LOG" | grep -qxF -- "  $1"; } # Argument im systemctl-Log

t_tools_services_grouped() {
  tt_open "systemd-Dienste" 'b\nb\nq\n'; rc_is 20; no_err
  local f e l r
  f=$(grep -n "▌ FEHLGESCHLAGEN" <<< "$OUT" | cut -d: -f1); e=$(grep -n "▌ EIGENE / WICHTIGE" <<< "$OUT" | cut -d: -f1)
  l=$(grep -n "▌ LAUFEND" <<< "$OUT" | cut -d: -f1); r=$(grep -n "▌ REST" <<< "$OUT" | cut -d: -f1)
  [ -n "$f" ] && [ "$f" -lt "$e" ] && [ "$e" -lt "$l" ] && [ "$l" -lt "$r" ] || die "Gruppenreihenfolge falsch:\n$OUT"
  has_re "$OUT" " 1\) ● backup-nightly +failed/failed +Nightly Restic Backup"     # Fehlgeschlagen zuerst
  local own; own=$(sed -n "${e},${l}p" <<< "$OUT")
  for u in hermes-gateway hermes-webui cloudflared mutagen docker-oom-shields; do has "$own" "● $u "; done
  hasnt "$own" "● caddy "                                     # Paket-Unit gehört nicht zu den eigenen
  has_re "$(sed -n "${l},${r}p" <<< "$OUT")" "● caddy +active/running +Caddy"
  has_re "$OUT" "● x11-common +inactive/dead"                  # nur in list-unit-files (Rest)
  hasnt "$OUT" "● auditd "                                     # not-found und inaktiv: kein Dienst
  hasnt "$OUT" "● user@ "; has "$OUT" "● user@0 "              # Vorlage weg, Instanz da
  ! grep -qE "● sshd +" <<< "$OUT" || die "Alias sshd.service gelistet"
  has "$OUT" "Fehlgeschlagen ● 1"
  ! grep -qE "systemd-fsck@dev-disk-by[^ ]{40}" <<< "$OUT" || die "überlanger Name nicht gekürzt"
}
t_tools_services_unavailable() {
  path_without systemctl; tt_tools; rc_is 20; no_err
  hasnt "$OUT" "systemd-Dienste"
}
t_tools_services_screen_info() {
  tt_svc hermes-gateway 'b\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ hermes-gateway"
  has_re "$OUT" "Status +● active \(running\) seit Mon 2026-10-12 08:11:44 CEST"
  has_re "$OUT" "Haupt-PID +1080691"; has_re "$OUT" "Speicher +683\.[78]M"
  has_re "$OUT" "Autostart +enabled"; has "$OUT" "/etc/systemd/system/hermes-gateway.service  (eigene)"
  has "$OUT" " 5) Restart"; has "$OUT" " 6) Stop"; has "$OUT" " 7) Autostart deaktivieren"
  hasnt "$OUT" "Achtung"
  tt_svc hermes-webui 'b\nb\nb\nq\n'; has_re "$OUT" "Neustarts +● 4"   # NRestarts > 0 markiert
}
t_tools_services_restart_confirm() {
  tt_svc hermes-gateway '5\nn\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "hermes-gateway neu starten? [j/N]"
  ! svc_logged restart || die "Restart trotz Ablehnung"
  tt_svc hermes-gateway '6\n\nb\nb\nb\nq\n'; ! svc_logged stop || die "Stop ohne j"
  tt_svc hermes-gateway '5\nj\nb\nb\nb\nq\n'; rc_is 20; no_err
  svc_logged restart && svc_logged hermes-gateway.service || die "Restart fehlt im Log"
}
t_tools_services_enable_disable() {
  tt_svc backup-nightly 'b\nb\nb\nq\n'
  has "$OUT" " 5) Start"; has "$OUT" " 6) Restart"; has "$OUT" " 7) Autostart deaktivieren"; has_re "$OUT" "Ergebnis +● exit-code"
  tt_svc backup-nightly '7\nn\nb\nb\nb\nq\n'; has "$OUT" "Autostart für backup-nightly deaktivieren? [j/N]"
  ! svc_logged disable || die "disable trotz Ablehnung"
  tt_svc backup-nightly '5\nb\nb\nb\nq\n'; rc_is 20                # Start ohne Rückfrage
  svc_logged start || die "Start fehlt"; hasnt "$OUT" "[j/N]"
  tt_svc backup-nightly '7\nj\nb\nb\nb\nq\n'; svc_logged disable || die "disable fehlt"
}
t_tools_services_action_error() {
  export STUB_SVC_RC=5
  tt_svc hermes-gateway '5\nj\n\nb\nb\nb\nq\n'; rc_is 20
  has "$OUT" "hermes-gateway: starte neu: Exit-Code 5"
}
t_tools_services_critical_double_confirm() {
  tt_svc ssh '6\nn\nb\nb\nb\nq\n'; rc_is 20; no_err               # ssh: 6 = Stop
  has_re "$OUT" "Achtung +● trägt die SSH-Sitzung"
  has "$OUT" "ACHTUNG: ssh trägt die SSH-Sitzung"; has "$OUT" "Trotzdem: ssh stoppen? [j/N]"
  hasnt "$OUT" "eintippen"; ! svc_logged stop || die "Stop nach n"
  tt_svc ssh '6\nj\nsshd\nb\nb\nb\nq\n'; rc_is 20                  # falscher Name → nichts
  has "$OUT" "Zur Bestätigung „ssh“ eintippen"; has "$OUT" "Abgebrochen, nichts geändert."
  ! svc_logged stop || die "Stop trotz falschem Namen"
  tt_svc ssh '6\nj\nssh\nb\nb\nb\nq\n'; rc_is 20; no_err
  svc_logged stop && svc_logged ssh.service || die "Stop nach doppelter Bestätigung fehlt"
  tt_svc systemd-logind '5\nj\n\nb\nb\nb\nq\n'                    # Restart, leere Eingabe
  ! svc_logged restart || die "logind-Restart ohne Namen"
  tt_svc user@0 'b\nb\nb\nq\n'; has "$OUT" "trägt die SSH-Sitzung"
}
t_tools_services_views() {
  tt_svc caddy '2\n\n3\n\n4\n\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "── Warnungen und Fehler: caddy ──"; has "$OUT" "STUB-JOURNALCTL -u caddy.service -p warning -n 50 --no-pager"
  has "$OUT" "STUB-SYSTEMCTL status caddy.service"; has "$OUT" "STUB-SYSTEMCTL cat caddy.service"
}
t_tools_services_favorite() {
  tt_svc tailscaled 'f\nb\nb\nb\nq\n'; rc_is 20; no_err
  eq "$(cat "$CONF/service-favorites")" "tailscaled.service"
  tt_open "systemd-Dienste" 'b\nb\nq\n'
  has "$OUT" "▌ FAVORITEN"; has_re "$OUT" " 1\) ● tailscaled +active/running"
  [ ! -e "$CONF/favorites" ] || die "fremde Favoriten-Datei angefasst"
  tt_svc tailscaled 'f\nb\nb\nb\nq\n'; [ ! -s "$CONF/service-favorites" ] || die "Favorit nicht entfernt"
}
tt_bg() { env --default-signal=INT setsid bash "$PD" < "$W/in" > "$W/out" 2> "$W/err" & TT_BG=$!; }
tt_wait_file() { local i; for i in $(seq 50); do [ -e "$1" ] && return 0; sleep 0.1; done; return 1; }
t_tools_services_follow_sigint() {
  tt_svc hermes-gateway 'b\nb\nb\nq\n'                              # Nummern ermitteln
  export STUB_JOURNAL_SLEEP=30
  printf '%s\n' "$TW" "$TN" "$TS_N" 1 b b b q > "$W/in"
  tt_bg
  tt_wait_file "$PD_FIX/.journal-following" || { kill -9 -- "-$TT_BG"; die "journalctl -f nicht gestartet"; }
  sleep 0.2; kill -INT -- "-$TT_BG"; wait "$TT_BG"; RC=$?
  rc_is 20                                                          # zurück im Menü, b b b q gelesen
  has "$(<"$W/out")" "Logfolge beendet"; hasnt "$(<"$W/out")" "Exit-Code"
  grep -qxF -- "  -f" "$STUB_LOG" && grep -qxF -- "  hermes-gateway.service" "$STUB_LOG" || die "journalctl -u … -f fehlt"
}
t_tools_services_tui() {
  conf "MODE=docker"; export PD_TOOLS_ROOT="$PD_FIX/tools/root"
  tt_tools; local n; n=$(tt_nr "$OUT" ") systemd-Dienste")
  tui_start PD_TOOLS_ROOT="$PD_TOOLS_ROOT"; tui_wait "COMPOSE-PROJEKTE"
  tui_keys 6 Enter; tui_title "Server-Werkzeuge"
  tui_keys "$n" Enter; tui_wait "FEHLGESCHLAGEN"
  tui_sel_is "backup-nightly"                                       # Überschrift übersprungen
  tui_keys Down; tui_sel_is "cloudflared-update"                    # erste eigene Unit
  tui_keys Enter; tui_title "cloudflared-update"; tui_wait "(eigene)"
  tui_keys Escape; tui_wait "EIGENE / WICHTIGE"; tui_sel_is "cloudflared-update"
  tui_keys q q; tui_wait "COMPOSE-PROJEKTE"; tui_keys q; tui_rc 20
}
