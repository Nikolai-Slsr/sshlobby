# shellcheck shell=bash
# Werkzeug Hermes-Instanzen, Update-Aktionen und Werkzeuge unter „Zuletzt“.
# Fixtures entstehen pro Test in der Kopie $PD_FIX (hm_host, hm_ct), damit andere Tests unverändert zählen.
# Echte hermes-, apt-get-, systemctl- und docker-Aufrufe gibt es nie, nur die Stubs.

# Host: systemd-Instanz (Gateway + WebUI auf /srv/hermes/main), Docker-Instanzen hermes (läuft, steht schon
# in host-docker), agent-dev und old-agent (beendet), dazu ein Browser-Hilfscontainer, der nicht zählen darf.
hm_host() {
  local D=$PD_FIX/tools/systemd R=$PD_FIX/tools/root/srv/hermes/main
  cat >> "$D/show" <<'EOF'
hermes-gateway.service|ExecStart={ path=/opt/hermes-agent/venv/bin/python ; argv[]=/opt/hermes-agent/venv/bin/python -m hermes_cli.main gateway run ; ignore_errors=no }
hermes-gateway.service|Environment=HOME=/root HERMES_HOME=/srv/hermes/main
hermes-gateway.service|User=
hermes-webui.service|ExecStart={ path=/opt/hermes-agent/venv/bin/python ; argv[]=/opt/hermes-agent/venv/bin/python /opt/hermes-webui/server.py ; ignore_errors=no }
hermes-webui.service|Environment=HERMES_HOME=/srv/hermes/main
EOF
  cat >> "$PD_FIX/host-docker" <<'EOF'
old-agent|nousresearch/hermes-agent:latest|exited|Exited (0) 3 days ago|||||unless-stopped
hermes-browser|lscr.io/linuxserver/chromium:latest|running|Up 2 days|||||no
EOF
  cat > "$PD_FIX/tools/docker/hermes.host" <<'EOF'
/hermes|running|nousresearch/hermes-agent|/opt/hermes/docker/entrypoint-dispatch.sh gateway run|/srv/agents/agent-main>/opt/data;|HERMES_HOME=/opt/data|
/old-agent|exited|nousresearch/hermes-agent:latest|/opt/hermes/docker/entrypoint-dispatch.sh gateway run|/srv/agents/Old>/opt/data;|HERMES_HOME=/opt/data|
/hermes-browser|running|lscr.io/linuxserver/chromium:latest| /init|/srv/agents/browser>/config;||hermes-browser
/agent-dev|exited|nousresearch/hermes-agent:latest|/opt/hermes/docker/entrypoint-dispatch.sh gateway run|/srv/agents/Dev>/opt/data;|HERMES_HOME=/opt/data|
EOF
  mkdir -p "$R/logs"
  printf '%s\n' "2026-10-12 ERROR gateway: Testfehler 42" > "$R/logs/errors.log"
  printf '%s\n' "model:" "  default: test-model" "  api_key: sk-test-geheim-123" "telegram:" "  bot_token: 123:abc" \
    "password: hunter2" "max_turns: 90" "show_token_analytics: true" > "$R/config.yaml"
}
# Layered: im CT alpha Docker-Gateway agent-dev + WebUI auf denselben Daten, im CT security ein systemd-Gateway
hm_ct() {
  cat >> "$PD_FIX/docker/alpha" <<'EOF'
agent-dev|hermes-agent:patched|running|Up 1 day|||||unless-stopped
agent-dev-webui|ghcr.io/nesquena/hermes-webui:latest|running|Up 1 day|||||unless-stopped
EOF
  cat > "$PD_FIX/tools/docker/hermes.alpha" <<'EOF'
/agent-dev|running|hermes-agent:patched|/opt/hermes/docker/entrypoint-dispatch.sh gateway run|/root/agents/Agent-Dev>/opt/data;|HERMES_HOME=/opt/data|
/agent-dev-webui|running|ghcr.io/nesquena/hermes-webui:latest| /hermeswebui_init.bash|/root/agents/Agent-Dev>/home/hermeswebui/.hermes;/var/lib/docker/volumes/src/_data>/home/hermeswebui/.hermes/hermes-agent;||
EOF
  local G=$PD_FIX/tools/systemd.security
  mkdir -p "$G"
  echo '[{"unit":"hermes-gateway.service","load":"loaded","active":"failed","sub":"failed","description":"Hermes"}]' > "$G/list-units.json"
  echo "hermes-gateway.service enabled enabled" > "$G/unit-files.txt"
  printf '%s\n' 'hermes-gateway.service|ExecStart={ path=/usr/local/lib/hermes-agent/venv/bin/python ; argv[]=python -m hermes_cli.main gateway run }' \
    'hermes-gateway.service|User=hermes' > "$G/show"
}
hm_open() { # instanz-label eingabe-im-instanz-screen [args]
  local i=$1 rest=$2; shift 2
  tt_open "Hermes-Instanzen" 'b\nb\nq\n' "$@"
  HI=$(hm_nr "$OUT" "$i"); [ -n "$HI" ] || die "Instanz $i fehlt:\n$OUT"
  menu "$TW\n$TN\n$HI\n$rest" "$@"
}
hm_item() { # label → Nummer des Eintrags mit genau dieser Bezeichnung (nicht nur Teilstring, „Status“ ≠ „Status prüfen“)
  # nur im letzten Instanz-Screen suchen (Titel „… · Hermes · …“ bis „Auswahl:“), nicht im Werkzeug-Menü davor und danach
  awk -v l="$1" '/· Hermes · / { f = 1; n = ""; next } f && /Auswahl:/ { f = 0; if (n != "") hit = n; next }
    f && n == "" && match($0, /^ *[0-9]+\) /) { r = substr($0, RLENGTH + 1); m = substr($0, 1, RLENGTH)
      if (r == l || index(r, l "  ") == 1) { gsub(/[ )]/, "", m); n = m } }
    END { print hit }' <<< "$OUT"
}
hm_nr() { # ausgabe name → Nummer der Instanz (Zeile „ n) <Status> name  …“)
  awk -v l="$2" 'match($0, /^ *[0-9]+\) /) { r = substr($0, RLENGTH + 1); n = substr($0, 1, RLENGTH)
    sub(/^[^ ]+ /, "", r); if (index(r, l " ") == 1) { gsub(/[ )]/, "", n); print n; exit } }' <<< "$1"
}
logged_in() { awk -v s="== $1" '/^== /{f=($0 == s); next} f' "$STUB_LOG" | grep -qF -- "$2"; } # befehl text

t_hermes_scan_docker_mode() {                      # System + Docker, WebUI gehört zur selben Instanz
  conf "MODE=docker"; hm_host
  tt_open "Hermes-Instanzen" 'b\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "4 gefunden"; has_re "$OUT" "agent-dev +Gateway exited  /srv/agents/Dev"
  has "$OUT" "▌ SYSTEM"; has "$OUT" "▌ DOCKER"; has_re "$OUT" "hermes-gateway +Gateway active · WebUI active  /srv/hermes/main"
  has_re "$OUT" "hermes +Gateway running  /srv/agents/agent-main"; has_re "$OUT" "old-agent +Gateway exited  /srv/agents/Old"
  hasnt "$OUT" "hermes-browser"; hasnt "$OUT" "sk-test"
}

t_hermes_scan_layered() {                          # System → Incus → Docker → Hermes
  hm_ct
  tt_open "Hermes-Instanzen" 'b\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "CT ALPHA › DOCKER"; has_re "$OUT" "agent-dev +Gateway running · WebUI running  /root/agents/Agent-Dev"
  has "$OUT" "CT SECURITY › SYSTEM"; has_re "$OUT" "hermes-gateway +Gateway failed  /home/hermes/.hermes"
  hasnt "$OUT" "agent-dev-webui "; hasnt "$OUT" "STUB-SYSTEMCTL"
  has_re "$OUT" "CTs durchsucht: .*alpha"
}

t_hermes_none_found() {                            # Fixture-Container mit Hermes-Image entfernen
  conf "MODE=docker"; sed -i "/hermes-agent/d" "$PD_FIX/host-docker"
  tt_open "Hermes-Instanzen" 'b\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "(keine Hermes-Instanz gefunden"
}

t_hermes_status_system() {                         # hermes der Installation mit HERMES_HOME der Instanz
  conf "MODE=docker"; hm_host
  hm_open "hermes-gateway" 'b\nb\nb\nq\n'; local s; s=$(hm_item "Status")
  hm_open "hermes-gateway" "$s\n\nb\nb\nb\nq\n"; rc_is 20; no_err
  has "$OUT" "STUB-HERMES home=/srv/hermes/main status"
  has "$OUT" "Gateway"; has "$OUT" "hermes-gateway.service: active"
}

t_hermes_status_docker() {                         # Docker-Instanz: hermes im Container
  conf "MODE=docker"; hm_host
  hm_open "hermes" 'b\nb\nb\nq\n'; local s; s=$(hm_item "Status")
  hm_open "hermes" "$s\n\nb\nb\nb\nq\n"; rc_is 20; no_err
  has "$OUT" "STUB-DOCKER-EXEC host/hermes"; logged_in "docker@host" "hermes"
}

t_hermes_status_in_ct() {                          # Docker im CT: incus exec … docker exec
  hm_ct; sed -i "/hermes-agent/d" "$PD_FIX/host-docker"   # gleichnamige Host-Instanz aus der Fixture weg
  hm_open "agent-dev" 'b\nb\nb\nq\n'; local s; s=$(hm_item "Status")
  hm_open "agent-dev" "$s\n\nb\nb\nb\nq\n"; rc_is 20; no_err
  has "$OUT" "STUB-DOCKER-EXEC alpha/agent-dev"
}

t_hermes_stopped_container() {                     # gestoppt: keine CLI-Aktionen, aber Start und Dateien
  conf "MODE=docker"; hm_host
  hm_open "old-agent" 'b\nb\nb\nq\n'; rc_is 20; no_err
  hasnt "$OUT" ") Status"; has "$OUT" ") Gateway starten"; has "$OUT" ") errors.log anzeigen"
  has "$OUT" ") Neues Image ziehen"
}

t_hermes_config_masked() {                         # Schlüssel, Tokens, Passwörter nie im Klartext
  conf "MODE=docker"; hm_host
  hm_open "hermes-gateway" 'b\nb\nb\nq\n'; local c; c=$(hm_item "config.yaml anzeigen")
  hm_open "hermes-gateway" "$c\n\nb\nb\nb\nq\n"; rc_is 20; no_err
  has "$OUT" "default: test-model"; has "$OUT" "max_turns: 90"; has "$OUT" "show_token_analytics: true"
  has "$OUT" "api_key: *** (maskiert)"; has "$OUT" "bot_token: *** (maskiert)"; has "$OUT" "password: *** (maskiert)"
  hasnt "$OUT" "sk-test"; hasnt "$OUT" "123:abc"; hasnt "$OUT" "hunter2"
}

t_hermes_error_log() {
  conf "MODE=docker"; hm_host
  hm_open "hermes-gateway" 'b\nb\nb\nq\n'; local e; e=$(hm_item "errors.log anzeigen")
  [ -z "$(hm_item "Fehler-Log")" ] || die "Instanz-Screen hat noch den Eintrag Fehler-Log (Name gehört dem Werkzeug)"
  hm_open "hermes-gateway" "$e\n\nb\nb\nb\nq\n"; rc_is 20; no_err
  has "$OUT" "Testfehler 42"
}

t_hermes_restart_needs_confirm() {                 # Nein → nichts, Ja → systemctl restart der Unit
  conf "MODE=docker"; hm_host
  hm_open "hermes-gateway" 'b\nb\nb\nq\n'; local r; r=$(hm_item "Gateway neu starten")
  hm_open "hermes-gateway" "$r\nn\nb\nb\nb\nq\n"; rc_is 20; no_err
  ! svc_logged restart || die "restart trotz Nein"
  hm_open "hermes-gateway" "$r\nj\nb\nb\nb\nq\n"; rc_is 20; no_err
  svc_logged restart || die "kein systemctl restart"; svc_logged hermes-gateway.service || die "falsche Unit"
}

t_hermes_docker_restart() {                        # Docker-Gateway: docker restart, nicht systemctl
  conf "MODE=docker"; hm_host
  hm_open "hermes" 'b\nb\nb\nq\n'; local r; r=$(hm_item "Gateway neu starten")
  hm_open "hermes" "$r\nj\nb\nb\nb\nq\n"; rc_is 20; no_err
  logged_in "docker@host" "restart" || die "kein docker restart"; ! svc_logged restart || die "systemctl statt docker"
}

t_hermes_update_system() {                         # hermes update nur nach Ja, im Vordergrund
  conf "MODE=docker"; hm_host
  hm_open "hermes-gateway" 'b\nb\nb\nq\n'; local u; u=$(hm_item "Hermes aktualisieren")
  hm_open "hermes-gateway" "$u\nn\nb\nb\nb\nq\n"; rc_is 20
  ! grep -q "^  update$" "$STUB_LOG" || die "update trotz Nein"
  hm_open "hermes-gateway" "$u\nj\n\nb\nb\nb\nq\n"; rc_is 20
  has "$OUT" "STUB-HERMES home=/srv/hermes/main update"; has "$OUT" "hermes update beendet (Exit-Code 0)"
}

# ─── Updates: Aktionen ──────────────────────────────────────────────────────
t_updates_actions_listed() {
  conf "MODE=docker"
  tt_open "Updates" 'b\nb\nq\n'; rc_is 20; no_err
  has "$OUT" ") Paketlisten aktualisieren"; has "$OUT" ") Security-Updates installieren"
  has "$OUT" ") Alle Updates installieren"; hasnt "$OUT" ") Server neu starten"
  ! grep -q "== apt-get" "$STUB_LOG" 2>/dev/null || die "apt-get ohne Auswahl"
}

t_updates_security_install() {                     # Nein → kein apt-get, Ja → update + nur Security-Pakete
  conf "MODE=docker"
  tt_open "Updates" 'b\nb\nq\n'; local s; s=$(tt_nr "$OUT" ") Security-Updates installieren")
  tt_open "Updates" "$s\nn\nb\nb\nq\n"; rc_is 20
  ! grep -q "== apt-get" "$STUB_LOG" 2>/dev/null || die "apt-get trotz Nein"
  tt_open "Updates" "$s\nj\n\nb\nb\nq\n"; rc_is 20
  logged_in apt-get "update"; logged_in apt-get "--only-upgrade"; logged_in apt-get "Dpkg::Options::=--force-confold"
  ! logged_in apt-get "--with-new-pkgs" || die "Voll-Upgrade statt Security"
  has "$OUT" "Fertig."
}

t_updates_all_install() {
  conf "MODE=docker"
  tt_open "Updates" 'b\nb\nq\n'; local a; a=$(tt_nr "$OUT" ") Alle Updates installieren")
  tt_open "Updates" "$a\nj\n\nb\nb\nq\n"; rc_is 20
  logged_in apt-get "--with-new-pkgs"; logged_in apt-get "upgrade"
}

t_updates_apt_failure_shown() {
  conf "MODE=docker"; export STUB_APT_RC=100
  tt_open "Updates" 'b\nb\nq\n'; local a; a=$(tt_nr "$OUT" ") Alle Updates installieren")
  tt_open "Updates" "$a\nj\n\nb\nb\nq\n"; rc_is 20
  has "$OUT" "apt-get meldet Exit-Code 100"; ! logged_in apt-get "upgrade" || die "upgrade trotz Fehler bei update"
}

t_updates_reboot_needs_hostname() {               # nur bei Bedarf, Hostname muss stimmen
  conf "MODE=docker"
  mkdir -p "$PD_FIX/tools/root/var/run"; touch "$PD_FIX/tools/root/var/run/reboot-required"
  tt_open "Updates" 'b\nb\nq\n'; local r; r=$(tt_nr "$OUT" ") Server neu starten"); [ -n "$r" ] || die "kein Neustart-Eintrag:\n$OUT"
  tt_open "Updates" "$r\nj\nfalsch\nb\nb\nq\n"; rc_is 20
  ! svc_logged reboot || die "reboot trotz falschem Hostnamen"
  local h; h=$(hostname)
  tt_open "Updates" "$r\nj\n$h\nb\nb\nq\n"; rc_is 20
  svc_logged reboot || die "kein systemctl reboot"
}

t_updates_session_running_vs_done() {             # laufende Sitzung blockiert, fertige wird nur angeboten
  conf "MODE=docker"
  SHELL=$(type -P sh) tmux new-session -d -s "$SSHLOBBY_APT_SESSION" "sleep 60" || skip "tmux-Sitzung nicht startbar"
  tmux has-session -t "$SSHLOBBY_APT_SESSION" 2>/dev/null || skip "tmux-Sitzung endet sofort"
  tt_open "Updates" 'b\nb\nq\n'; has "$OUT" ") Laufendes Update öffnen"
  local a; a=$(tt_nr "$OUT" ") Alle Updates installieren")
  tt_open "Updates" "$a\n\nb\nb\nq\n"; has "$OUT" "Es läuft schon ein Update"
  ! grep -q "== apt-get" "$STUB_LOG" 2>/dev/null || die "apt-get trotz laufender Sitzung"
  echo "0 $(date +%s)" > "$CONF/apt-last"
  tt_open "Updates" 'b\nb\nq\n'; tmux kill-session -t "$SSHLOBBY_APT_SESSION" 2>/dev/null
  has "$OUT" ") Ergebnis des letzten Updates"; has "$OUT" "fertig, Exit-Code 0"; hasnt "$OUT" "Laufendes Update"
}

# ─── Werkzeuge unter „Zuletzt“ (Werkzeug-Menü) ─────────────────────────────
t_recent_tool_listed() {                           # benutztes Werkzeug steht oben im Werkzeug-Menü, nicht im Hauptmenü
  conf "MODE=docker"
  tt_open "Updates" 'b\nb\nq\n'; rc_is 20
  menu 'q\n'; rc_is 20; hasnt "$OUT" "ZULETZT"; hasnt "$OUT" "Updates"
  tt_tools; has "$OUT" "▌ ZULETZT"; has "$OUT" "▌ ALLE WERKZEUGE"
  eq "$(tt_nr "$OUT" ") Updates")" 1 "Updates oben unter Zuletzt"; eq "$(count "$OUT" ") Updates")" 2 "Updates zweimal"
  has_re "$OUT" " 1\) Updates +gerade eben"
  menu "$TW\n1\nb\nb\nq\n"; rc_is 20; no_err; has "$OUT" "Paketlisten aktualisieren"
}

t_recent_tool_hidden_if_unavailable() {            # Werkzeug anderer Modi (incus) erscheint im docker-Modus nicht
  conf "MODE=docker"
  printf '%s|@tool|incus|tool\n' "$(date +%s)" > "$CONF/recents"
  tt_tools; rc_is 20; no_err; hasnt "$OUT" "ZULETZT"; hasnt "$OUT" "ALLE WERKZEUGE"; hasnt "$OUT" "Incus-Übersicht"
}

t_recent_setup_not_recorded() {                    # Einstellungen landen nicht im Verlauf
  conf "MODE=docker"
  tt_open "Einstellungen" 'b\nb\nq\n'
  ! grep -q "@tool|setup|" "$CONF/recents" 2>/dev/null || die "Setup im Verlauf"
}
