# shellcheck shell=bash
# Modus layered (Incus-CTs mit Docker darin), Zeilenmodus. Enthält die v1.1-Tests.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer
# Standard-Config aus setup(): MODE=layered, SSH_HOSTS=Docker-Host, CVE_CT=security
# Hauptmenü der Fixture: alpha beta delta gamma ntfy security (1–6), Werkzeuge 7.

# ─── Menü / Navigation ─────────────────────────────────────────────────────
t_b6_exit_codes() {
  menu 'q\n'; rc_is 20; no_err
  menu 's\n'; rc_is 10
  menu '';    rc_is 0                              # EOF (Ctrl-D) loggt nie aus
  menu 'x\n99\n0\nb\n\n'; rc_is 0                  # Unsinn, dann EOF
}
t_nav_numbers() {
  menu '01\nb\nq\n'; rc_is 20; no_err; has "$OUT" "┌─ alpha"          # führende Null
  menu ' 1 \nb\nq\n'; rc_is 20; has "$OUT" "┌─ alpha"                # Leerzeichen
  menu '08\nb\nq\n'; rc_is 20; no_err                                 # 08 kein Oktal-Fehler
  menu 'abc\n-1\n99999999999999999999\nq\n'; rc_is 20; no_err
  hasnt "$OUT" "┌─"
}
t_nav_empty_ct_list() {
  : > "$PD_FIX/cts"
  menu '1\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "keine Incus-Container gefunden"; has "$OUT" " 1) Werkzeuge"
}
t_b1_printf_headers() {
  menu '1\n2\nb\nb\nq\n'; rc_is 20; no_err
  eq "$(count "$OUT" "┌─")" 3 "Screen-Header (CT, Container, CT)"
  eq "$(count "$OUT" "3) Restart")" 1
  menu '7\n9\nb\nb\nq\n'; rc_is 20; no_err
  eq "$(count "$OUT" "┌─")" 3 "Header (Werkzeuge, Neues Projekt, Werkzeuge)"
  eq "$(count "$OUT" "┌─ Neues Projekt")" 1
}
t_b3_exact_container() {
  menu '1\n2\nb\nb\nq\n'                            # Fixture: myapp steht vor app
  has "$OUT" "Image    nginx:1.27"; hasnt "$OUT" "Image    ghcr.io/x/myapp"
}
t_b3_container_vanished() {
  export STUB_GONE=app STUB_GONE_AFTER=1           # app verschwindet nach der CT-Ansicht
  menu '1\n2\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" 'Container „app“ gibt es in alpha nicht (mehr)'
  hasnt "$OUT" "Image    "
}
t_ct_screen_states() {
  menu '2\nb\n3\nb\n4\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "(CT läuft nicht)"                    # beta gestoppt
  eq "$(count "$OUT" "(Docker im CT nicht erreichbar)")" 1   # delta: Daemon aus
  eq "$(count "$OUT" "(kein Docker installiert)")" 1           # gamma: Normalzustand
  hasnt "$OUT" "(keine Docker-Container)"
}
t_b10_reload() {
  sed 's/10.0.0.11/10.0.0.99/' "$PD_FIX/cts" > "$PD_FIX/cts.later"
  menu '1\nr\nb\nq\n'; rc_is 20
  has "$OUT" "alpha · 10.0.0.99"
}
t_ct_vanished() {
  grep -v '^alpha|' "$PD_FIX/cts" > "$PD_FIX/cts.later"
  menu '1\nr\n\nq\n'; rc_is 20; no_err
  has "$OUT" 'CT „alpha“ gibt es nicht (mehr)'
}

# ─── Container-Aktionen ────────────────────────────────────────────────────
t_r3_preflight_container() {
  menu '1\n3\n1\n\nb\nb\nq\n'; rc_is 20; no_err   # db ist exited
  has "$OUT" 'Container „db“ läuft nicht (exited)'; has "$OUT" "[Enter] weiter"; no_docker_exec
  : > "$CONF/recents"; printf '%s\n' "alpha|ghost" "alpha|db" "beta|app" "delta|x" "gamma|x" > "$CONF/favorites"
  menu '1\n\n2\n\n3\n\n4\n\n5\n\nq\n'; rc_is 20; no_err   # Favoriten 1-5 der Reihe nach
  has "$OUT" 'Container „ghost“ gibt es in alpha nicht (mehr)'
  eq "$(count "$OUT" 'Container „db“ läuft nicht (exited)')" 1 "Favorit auf gestoppten Container"
  has "$OUT" "beta: CT läuft nicht"; has "$OUT" "delta: Docker im CT nicht erreichbar"
  has "$OUT" "gamma: kein Docker installiert"
  eq "$(count "$OUT" "[Enter] weiter")" 5; no_docker_exec
  [ ! -s "$CONF/recents" ] || die "fehlgeschlagener Versuch im Verlauf: $(cat "$CONF/recents")"
}
t_r3_preflight_ct_and_compose() {
  local now; now=$(date +%s)
  printf '%s\n' "$now|beta|-|ctshell" > "$CONF/recents"   # Verlauf: CT-Shell auf gestoppten CT
  menu '1\n\nq\n'; rc_is 20; no_err
  has "$OUT" 'CT „beta“ läuft nicht (Stopped)'; hasnt "$OUT" "STUB-BASH"
  rm -r "$PD_FIX/fs/alpha/opt/it's app"
  menu '2\n2\n6\n\nb\nb\nq\n'; rc_is 20; no_err   # Compose-Ordner fehlt im CT
  has "$OUT" "Ordner /opt/it's app gibt es in alpha nicht"; hasnt "$OUT" "STUB-SH"
}
t_r3_shell_exit_code_no_pause() {
  export STUB_EXEC_RC=2 STUB_SHELL_RC=2            # letzter Befehl in der Shell schlug fehl
  menu '1\n2\n1\n6\nb\n4\nb\nq\n'; rc_is 20; no_err   # Docker-, Compose-, CT-Shell
  has "$OUT" "STUB-DOCKER-EXEC alpha/app"; has "$OUT" "STUB-SH alpha"; has "$OUT" "STUB-BASH alpha"
  hasnt "$OUT" "[Enter] weiter"; ! grep -qE 'Exit-Code [0-9]' <<< "$OUT" || die "Exit-Code gemeldet"
  cli --go alpha/app; rc_is 2                       # --go reicht den Shell-Exit-Code durch
}
t_b9_confirm() {
  menu '1\n2\n4\n\n3\nn\nb\nb\nq\n'; rc_is 20       # Stop: Enter = nein, Restart: n
  has "$OUT" "app stoppen? [j/N]"; has "$OUT" "app neu starten? [j/N]"
  if logged stop || logged restart; then die "ohne Bestätigung ausgeführt"; fi
  menu '1\n2\n4\nj\n3\ny\n5\nb\nb\nq\n'; rc_is 20; no_err
  for a in stop restart start; do logged "$a" || die "$a fehlt im Log"; done
  eq "$(count "$OUT" "starte…")" 2 "restarte… + starte…"
}
t_action_error_shown() {                           # Fehler bei Restart: Meldung mit Exit-Code + Pause
  export STUB_ACTION_RC=3
  menu '1\n2\n5\n\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "app: starte: Exit-Code 3"; has "$OUT" "[Enter] weiter"
}
t_b11_compose_path_arg() {
  menu '1\n2\n6\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "STUB-SH alpha"
  logged "/opt/it's app" || die "Pfad nicht als eigenes Argument übergeben"
  ! grep -q "cd '/opt" "$STUB_LOG" || die "Pfad steckt im Befehlsstring"
  # shellcheck disable=SC2016 # literales $1 im geloggten Skript
  grep -qF 'cd "$1"' "$STUB_LOG" || die "Skript erwartet cd \"\$1\""
}
t_container_info_layered() {
  menu '1\n2\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Health   healthy"; has "$OUT" "Ports    0.0.0.0:80->80/tcp"
  has "$OUT" "Compose  /opt/it's app  (Ordner liegt im CT)"; has "$OUT" "Neustart no"
  has "$OUT" "Fastpath ssh -t testhost sshlobby --go alpha/app"
}

# ─── CT-Aktionen im layered-CT-Screen (nach den Docker-Containern) ─────────
t_layered_ct_actions() {
  # alpha: 1-3 Container, 4 CT-Shell, 5 starten, 6 stoppen, 7 neu starten, 8 info, 9 Log, 10 Ressourcen
  menu '1\n5\n6\nn\n7\nj\n8\n\n9\n\n10\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "STUB-CT-start alpha"; hasnt "$OUT" "STUB-CT-stop"; has "$OUT" "STUB-CT-restart alpha"
  has "$OUT" "Name: alpha"; has "$OUT" "STUB-LOG alpha"; has "$OUT" "STUB-LIST list ^alpha\$ -c"
  has "$OUT" "CT alpha stoppen? [j/N]"
  eq "$(count "$OUT" "[Enter] weiter")" 3 "info, Log, Ressourcen"
}

# ─── Favoriten / Verlauf ───────────────────────────────────────────────────
t_b2_fav_toggle_last() {
  menu '1\n2\nf\nb\nb\nq\n'; rc_is 20
  eq "$(cat "$CONF/favorites")" "alpha|app"
  menu '2\nb\nq\n'; has "$OUT" "★ alpha/app"
  menu '1\nq\n'; rc_is 20; has "$OUT" "STUB-DOCKER-EXEC alpha/app"   # Favorit öffnet Shell
  menu '3\n2\nf\nb\nb\nq\n'; rc_is 20              # 1 Verlauf, 2 Favorit, 3 alpha: Favorit entfernen
  [ ! -s "$CONF/favorites" ] || die "letzter Favorit nicht entfernt: $(cat "$CONF/favorites")"
  [ -z "$(find "$CONF" -name '*.tmp' -o -name '*.??????')" ] || die "tmp-Datei liegen geblieben"
}
t_b2_fav_keeps_others() {
  printf '%s\n' "alpha|myapp" "alpha|app" "xalpha|app" > "$CONF/favorites"
  menu '4\n2\nf\nb\nb\nq\n'; rc_is 20              # 1-3 Favoriten (xalpha fehlt), 4 = alpha
  eq "$(cat "$CONF/favorites")" $'alpha|myapp\nxalpha|app'
}
t_b2_recent_dedupe() {
  printf '%s\n' "100|xalpha|app|shell" "200|alpha|app|shell" "300|alpha|appx|shell" > "$CONF/recents"
  cli --go alpha/app; rc_is 0
  eq "$(grep -c '|alpha|app|' "$CONF/recents")" 1 "alpha|app genau einmal"
  grep -q '^100|xalpha|app|' "$CONF/recents" || die "fremder Eintrag xalpha|app gelöscht"
  grep -q '^300|alpha|appx|' "$CONF/recents" || die "fremder Eintrag appx gelöscht"
  printf '%s\n' "200|alpha|app|shell" > "$CONF/recents"   # einziger Eintrag
  cli --go alpha/app; rc_is 0
  eq "$(wc -l < "$CONF/recents")" 1; hasnt "$(cat "$CONF/recents")" "200|"
  [ -z "$(find "$CONF" -name 'recents.*')" ] || die "tmp-Datei liegen geblieben"
}
t_recent_cap_200() {
  local i; for i in $(seq 1000 1250); do echo "$i|alpha|c$i|shell"; done > "$CONF/recents"
  cli --go alpha/app; eq "$(wc -l < "$CONF/recents")" 200; tail -1 "$CONF/recents" | grep -q '|alpha|app|shell$' || die
}
t_recents_menu() {
  local now; now=$(date +%s)
  printf '%s\n' "$((now-120))|alpha|app|logs" "$((now-60))|alpha|-|ctshell" "$((now-30))|alpha|app|shell" > "$CONF/recents"
  menu '1\n2\nq\n'; rc_is 20; no_err
  has "$OUT" " 1) alpha / app"; has "$OUT" " 2) alpha (CT-Shell)"; hasnt "$OUT" " 3) alpha / app"
  has "$OUT" "STUB-DOCKER-EXEC alpha/app"; has "$OUT" "STUB-BASH alpha"
}
t_recent_logs_and_compose() {
  local now; now=$(date +%s)
  printf '%s\n' "$((now-60))|alpha|app|compose" "$((now-30))|alpha|app|logs" > "$CONF/recents"
  menu '1\nq\n'; rc_is 20; no_err                  # dedupe: nur der neueste (logs)
  has "$OUT" "log line from app"; has "$OUT" "Logfolge beendet"
  printf '%s\n' "$now|alpha|app|compose" > "$CONF/recents"
  menu '1\nq\n'; rc_is 20; no_err; has "$OUT" "STUB-SH alpha"
}
t_b12_missing_ct_entries() {
  local now; now=$(date +%s)
  printf '%s\n' "$((now-10))|oldsite|web|shell" "$((now-20))|alpha|app|shell" > "$CONF/recents"
  printf '%s\n' "oldsite|web" "alpha|app" > "$CONF/favorites"
  menu 'q\n'; rc_is 20; no_err
  hasnt "$OUT" "oldsite / web"                       # Verlauf: ausgeblendet
  has "$OUT" " 1) alpha / app"; has "$OUT" "oldsite/web"; has "$OUT" "CT fehlt"
  menu '2\nn\nq\n'; rc_is 20                       # gelöschter Favorit: nicht entfernen
  has "$OUT" 'CT „oldsite“ gibt es nicht mehr'; grep -q oldsite "$CONF/favorites" || die
  menu '2\nj\nq\n'; rc_is 20
  eq "$(cat "$CONF/favorites")" "alpha|app"
  ! grep -q '== docker@oldsite' "$STUB_LOG" || die "gelöschter CT angesprochen"
}
t_broken_state_lines() {
  printf '%s\n' "garbage" "abc|alpha|app|shell" "|||" "089|alpha|db|shell" "123|alpha|app" "" "$(date +%s)|alpha|app|shell" > "$CONF/recents"
  printf '%s\n' "kaputt" "|x" "alpha|" "" "alpha|app" > "$CONF/favorites"
  menu 'q\n'; rc_is 20; no_err
  eq "$(count "$OUT" "alpha / ")" 1 "nur ein gültiger Verlaufseintrag"
  eq "$(count "$OUT" ") ★ ")" 1 "nur ein gültiger Favorit"   # Menüzeilen, nicht der Tastenhinweis „f) Favorit ★“
}
t_ct_favorite() {                                  # CT selbst als Favorit (ziel "-")
  menu '1\nf\nb\nq\n'; rc_is 20; no_err
  eq "$(cat "$CONF/favorites")" "alpha|-"
  menu '1\nq\n'; rc_is 20; has "$OUT" "★ alpha (CT-Shell)"; has "$OUT" "STUB-BASH alpha"
}

# ─── Werkzeuge ─────────────────────────────────────────────────────────────
t_b5_cve_alerts() {
  menu '7\n7\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "2 neu"; has "$OUT" "CVE-2026-0001.json"; has "$OUT" "CVE-2026-0002.json"
  hasnt "$OUT" "archive"; hasnt "$OUT" "CVE-2025-9999"
  logged "/opt/cve-monitor/alerts" || die "nicht per incus exec gelesen"
  rm "$PD_FIX"/fs/security/opt/cve-monitor/alerts/*.json; rm -f "$CONF/recents"   # Werkzeug unter Zuletzt verschiebt Nummern
  menu '7\n7\n\nb\nq\n'; rc_is 20; has "$OUT" "keine neuen Alerts"
  rm -r "$PD_FIX/fs/security/opt/cve-monitor"; rm -f "$CONF/recents"
  menu '7\n7\n\nb\nq\n'; rc_is 20; has "$OUT" "Alert-Ordner nicht lesbar"
  sed -i 's/^security|Running/security|Stopped/' "$PD_FIX/cts"; rm -f "$CONF/recents"
  menu '7\n7\n\nb\nq\n'; rc_is 20; has "$OUT" 'CT „security“ läuft nicht (Stopped)'
  sed -i '/^security|/d' "$PD_FIX/cts"; rm -f "$CONF/recents"
  menu '6\n7\n\nb\nq\n'; rc_is 20; has "$OUT" 'CT „security“ nicht gefunden'
}
t_r1_stdin_not_swallowed() {
  # Mehrstufige Eingabe über Docker-Health (incus exec in jedem CT, Enter auf alpha, zurück), CVE-Alerts
  # und Incus-Übersicht: frisst ein incus exec stdin, fehlen die späteren Schritte und das Menü endet
  # per EOF mit 0 statt 20.
  norecent; menu '7\n4\n1\nb\nb\n7\n\n1\n\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" " 6\) ● security +1/1  ok"; has "$OUT" "┌─ alpha · alle"
  has "$OUT" "2 neu"; has "$OUT" "STUB-LIST list -c nsm4"
  eq "$(count "$OUT" "[Enter] weiter")" 2
}
t_r1_stdin_container_screen() {                    # Container-Screen + restart/start + Verlauf
  menu '1\n2\n3\nj\n5\nb\nb\nq\n'; rc_is 20; no_err
  for a in restart start; do logged "$a" || die "$a fehlt im Log"; done
}
t_b17_pause_without_tty() {
  norecent; menu '7\n1\n\n3\n\n5\nb\nq\n'; rc_is 20; no_err   # ui_pause liest Enter von stdin
  eq "$(count "$OUT" "[Enter] weiter")" 2
  has "$OUT" "STUB-LIST list -c nsm4"; has "$OUT" "STUB-JOURNALCTL"; has "$OUT" "STUB-SSH Docker-Host"
}
t_new_ct() {
  menu '7\n9\n01\n1bad\nalpha\nneu1\nj\nn\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "debian/12"; has "$OUT" "0123456789ab"
  has "$OUT" "Ungültig"; has "$OUT" '„alpha“ existiert schon'; has "$OUT" "✓ neu1 läuft"
  for a in launch debian/12 neu1; do logged "$a" || die "$a fehlt im Log"; done
  echo '[]' > "$PD_FIX/images.json"; rm -f "$CONF/recents"  # neu1 existiert jetzt → Werkzeuge = 8
  menu '8\n9\n\nb\nq\n'; rc_is 20; has "$OUT" "Keine lokalen Images"
}

# ─── B7: SIGINT ────────────────────────────────────────────────────────────
start_bg() { # eingabe-datei → PID (eigene Session, SIGINT auf Default)
  env --default-signal=INT setsid bash "$@" < "$W/in" > "$W/out" 2> "$W/err" &
  BG=$!
}
wait_file() { local i; for i in $(seq 50); do [ -e "$1" ] && return 0; sleep 0.1; done; return 1; }
t_sigint_harness_sanity() {                        # ohne Trap stirbt ein Skript an SIGINT
  printf 'sleep 30; echo ueberlebt\n' > "$W/plain.sh"; : > "$W/in"
  start_bg "$W/plain.sh"; sleep 0.3
  kill -INT -- "-$BG"; wait "$BG"
  hasnt "$(<"$W/out")" "ueberlebt"
}
t_b7_sigint_logs() {
  export STUB_LOGS_SLEEP=30
  printf '1\n2\n2\nb\nb\nq\n' > "$W/in"            # alpha → app → Logs folgen
  start_bg "$PD"
  wait_file "$PD_FIX/.logs-running" || { kill -9 -- "-$BG"; die "logs -f nicht gestartet"; }
  sleep 0.2
  kill -INT -- "-$BG"
  wait "$BG"; RC=$?
  rc_is 20                                          # Skript lebt weiter und liest b, b, q
  has "$(<"$W/out")" "Logfolge beendet"
  ! grep -qE 'Exit-Code [0-9]' "$W/out" || die "Fehlermeldung nach Ctrl-C"   # keine Meldung/Pause (Text der Meldung: „…: Exit-Code n“)
}
t_sigint_menu_exits_clean() {                      # Ctrl-C im Menü selbst beendet sshlobby (130)
  mkfifo "$W/fifo"
  env --default-signal=INT setsid bash "$PD" < "$W/fifo" > "$W/out" 2> "$W/err" &
  BG=$!; exec 3> "$W/fifo"; sleep 0.5
  kill -INT -- "-$BG"; wait "$BG"; RC=$?; exec 3>&-
  rc_is 130
}

# ─── Beschreibungen ────────────────────────────────────────────────────────
t_b14_descriptions() {
  ! grep -rq 'oldsite' "$ROOT/lib" "$ROOT/examples" "$PD" || die "oldsite noch im Code"
  ! grep -rq 'Pocket-ID' "$ROOT/lib" "$PD" || die "Beschreibungen fest im Code"
  grep -qxF 'ntfy|Self-hosted ntfy push alerts :2586' "$ROOT/examples/descriptions.incus-host" || die "ntfy fehlt"
  grep -qxF 'shop|Price monitoring' "$ROOT/examples/descriptions.incus-host" || die "shop falsch"
  menu 'q\n'; hasnt "$OUT" "Self-hosted ntfy"      # ohne descriptions-Datei keine Texte
  cp "$ROOT/examples/descriptions.incus-host" "$CONF/descriptions"
  menu 'q\n'; has_re "$OUT" "ntfy +Self-hosted ntfy push alerts :2586"
  menu '6\nb\nq\n'; has "$OUT" "Info SecObserve CVE management"   # auch im CT-Screen
}
