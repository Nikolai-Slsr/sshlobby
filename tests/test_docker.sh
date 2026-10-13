# shellcheck shell=bash
# Modus docker (Container direkt auf dem Host, Fixture host-docker aus Beispieldaten).
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer
# Hauptmenü: 1 authproxy, 2 gitea, 3 jellyfin, 4 nextcloud, 5 Einzelcontainer, 6 Werkzeuge
# nextcloud: 1 admin-panel 2 api 3 firecrawl-mcp 4 meilisearch 5 mongodb, 6 Logs, 7 ps,
#            8 Restart, 9 Stop, 10 Start, 11 Compose-Ordner
# Einzelcontainer: 1 agent-dev 2 eager_turing 3 hermes 4 homepage 5 old-demo 6 quirky_hopper

dmode() { conf "MODE=docker" "SSH_HOSTS=Docker-Host"; }

t_docker_main_groups() {
  dmode; menu 'q\n'; rc_is 20; no_err
  has "$OUT" "COMPOSE-PROJEKTE"
  has_re "$OUT" " 1\) ● authproxy +1/1"; has_re "$OUT" " 4\) ● nextcloud +5/5"
  has_re "$OUT" " 5\) ● Einzelcontainer +4/6  ohne Compose-Projekt"; has "$OUT" " 6) Werkzeuge"
  has "$OUT" "12/14 Container laufen"
  hasnt "$OUT" "Nextcloud"; hasnt "$OUT" "eager_turing"   # Container erst eine Ebene tiefer
  ! grep -q '== incus' "$STUB_LOG" || die "docker-Modus ruft incus auf"
}
t_docker_project_screen() {
  dmode; menu '4\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ nextcloud · 5/5 laufen"; has "$OUT" "Ordner $PD_FIX/fs/host/opt/nextcloud"
  has_re "$OUT" " 1\) ● admin-panel +nextcloud-admin-panel  Up 5 days \(healthy\)"
  has_re "$OUT" " 2\) ● api +Nextcloud  Up 4 days \(healthy\)"
  has_re "$OUT" " 5\) ● mongodb +chat-mongodb  Up 4 weeks"
  has "$OUT" " 6) Logs aller Services folgen"; has "$OUT" "11) Compose-Ordner öffnen"
}
t_docker_standalone_group() {
  dmode; menu '5\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ Einzelcontainer · 4/6 laufen"
  has_re "$OUT" " 2\) ● eager_turing +busybox:1.36  Up About an hour"
  has_re "$OUT" " 5\) ● old-demo +alpine  Exited \(0\) 4 weeks ago"
  hasnt "$OUT" "Logs aller Services"                 # keine Projekt-Aktionen
}
t_docker_project_actions_confirm() {
  dmode; norecent; menu '4\n8\nn\n9\n\n10\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Projekt nextcloud neu starten (alle Services)? [j/N]"
  has "$OUT" "Projekt nextcloud stoppen (alle Services)? [j/N]"
  has "$OUT" "STUB-COMPOSE nextcloud start"
  if logged restart || logged stop; then die "ohne Bestätigung ausgeführt"; fi
  menu '4\n8\nj\n9\ny\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "STUB-COMPOSE nextcloud restart"; has "$OUT" "STUB-COMPOSE nextcloud stop"
  grep -qx '== docker@host' "$STUB_LOG" && logged "-p" && logged nextcloud || die "compose -p fehlt"
  ! grep -qE '^  (up|pull|down)$' "$STUB_LOG" || die "up/pull/down in Phase 1 verboten"
}
t_docker_project_logs_ps() {
  dmode; menu '4\n6\n7\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "STUB-COMPOSE nextcloud logs"; has "$OUT" "Logfolge beendet"
  has "$OUT" "STUB-COMPOSE nextcloud ps"; has "$OUT" "Nextcloud running Up 4 days (healthy)"
  logged "--tail" && logged "100" && logged "-f" || die "logs -f --tail 100 fehlt"
}
t_docker_project_dir_shell() {
  dmode; norecent; menu '4\n11\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "STUB-HOSTSHELL $PD_FIX/fs/host/opt/nextcloud"
  rm -r "$PD_FIX/fs/host/opt/nextcloud"
  menu '4\n11\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Ordner $PD_FIX/fs/host/opt/nextcloud gibt es nicht"; hasnt "$OUT" "STUB-HOSTSHELL"
}
t_docker_container_screen() {
  dmode; norecent; menu '4\n2\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ Nextcloud · nextcloud"
  has "$OUT" "Image    registry.example.org/nextcloud/nextcloud:v0.8.8"
  has "$OUT" "Status   ● Up 4 days (healthy)"; has "$OUT" "Health   healthy"
  has "$OUT" "Ports    127.0.0.1:3080->3080/tcp"; has "$OUT" "Projekt  nextcloud / api"
  has "$OUT" "Compose  $PD_FIX/fs/host/opt/nextcloud"; has "$OUT" "Neustart always"
  has "$OUT" "Fastpath ssh -t testhost sshlobby --go nextcloud/Nextcloud"
  menu '5\n3\nb\nb\nq\n'; rc_is 20; no_err       # hermes: kein Healthcheck, kein Projekt
  has "$OUT" "Health   kein Healthcheck"; hasnt "$OUT" "Projekt  "; hasnt "$OUT" "Compose-Ordner öffnen"
  has "$OUT" "Fastpath ssh -t testhost sshlobby --go hermes"
}
t_docker_container_actions() {
  dmode; menu '4\n2\n4\n\n3\nj\n5\n1\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Nextcloud stoppen? [j/N]"; ! logged stop || die "Stop ohne Bestätigung"
  logged restart && logged start || die "restart/start fehlen"
  has "$OUT" "STUB-DOCKER-EXEC host/Nextcloud"
  eq "$(cut -d'|' -f2- "$CONF/recents")" "nextcloud|-|project"$'\n'"nextcloud|Nextcloud|shell"
}
t_docker_preflight() {
  dmode; menu '5\n5\n1\n\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" 'Container „old-demo“ läuft nicht (exited)'; no_docker_exec
  [ ! -s "$CONF/recents" ] || die "Fehlversuch im Verlauf"
  rm -f "$PD_FIX/.pscount"; export STUB_GONE=hermes STUB_GONE_AFTER=2   # weg zwischen Liste und Screen
  menu '5\n3\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" 'Container „hermes“ gibt es nicht (mehr)'
}
t_docker_recents_favorites() {
  local now; now=$(date +%s)
  dmode
  printf '%s\n' "$((now-10))|nextcloud|Nextcloud|shell" "$((now-20))|-|hermes|logs" "$((now-30))|alpha|app|shell" \
    "$((now-40))|alpha|-|ctshell" "$((now-50))|gitea|weg|shell" > "$CONF/recents"
  printf '%s\n' "alpha|app" "nextcloud|Nextcloud" "-|weg" "alpha|-" > "$CONF/favorites"
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" " 1) nextcloud / Nextcloud"; has "$OUT" " 2) hermes"
  hasnt "$OUT" "alpha"; hasnt "$OUT" "gitea / weg"   # andere Modi und fehlende Container ausgeblendet
  has "$OUT" " 3) ★ nextcloud/Nextcloud"; has_re "$OUT" " 4\) ☆ weg +Container fehlt"
  menu '1\n2\nq\n'; rc_is 20; no_err
  has "$OUT" "STUB-DOCKER-EXEC host/Nextcloud"; has "$OUT" "log line from hermes"
  menu '4\nj\nq\n'; rc_is 20
  has "$OUT" 'Container „weg“ gibt es nicht mehr. Favorit weg entfernen? [j/N]'
  eq "$(cat "$CONF/favorites")" $'alpha|app\nnextcloud|Nextcloud\nalpha|-'
  menu '8\n3\nf\nb\nb\nq\n'; rc_is 20              # 1-2 Verlauf, 3 Favorit, 8 Einzelcontainer → hermes
  grep -qx -- '-|hermes' "$CONF/favorites" || die "Favorit -|hermes fehlt"
}
t_docker_unreachable() {
  dmode; export STUB_HOST_DOCKER=down
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" "(Docker nicht erreichbar)"; has "$OUT" " 1) Werkzeuge"
}
t_docker_health_scan() {
  dmode; sed -i 's/^chat-mongodb|\([^|]*\)|running|Up 4 weeks|/chat-mongodb|\1|running|Up 4 weeks (unhealthy)|/' "$PD_FIX/host-docker"
  menu '6\n3\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "$(row16 nextcloud '✗ unhealthy: chat-mongodb')"
  has "$OUT" "$(row16 gitea '✓ ok (1 laufend)')"
  has "$OUT" "$(row16 Einzelcontainer '! 4/6 laufen, gestoppt: agent-dev old-demo')"
}
t_docker_tools_filtered() {
  dmode; menu '6\nb\nq\n'; rc_is 20; no_err
  has "$OUT" " 1) RAM / Disk / Top-Prozesse"; has "$OUT" " 3) Docker-Health-Scan"
  has "$OUT" " 4) Anderer Server (SSH)"; setup_is_last
  hasnt "$OUT" "Incus-Übersicht"; hasnt "$OUT" "CVE-Monitor"; hasnt "$OUT" "Neues Projekt"
  conf "MODE=docker"                                # ohne SSH_HOSTS kein SSH-Werkzeug
  menu '6\nb\nq\n'; hasnt "$OUT" "Anderer Server"
}
