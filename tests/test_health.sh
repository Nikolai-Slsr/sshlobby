# shellcheck shell=bash
# Werkzeug Docker-Health (lib/tools_health.sh) und die Seite „Zustand und Healthcheck“ im Container-Screen.
# docker (chat-mongodb unhealthy gemacht): Werkzeuge = 6, Docker-Health = 3. Danach Compose-Projekte
#   1 nextcloud (Fehler), 2 authproxy 3 gitea 4 jellyfin, Einzelcontainer 5 hermes (OOM-Kill), 6 agent-dev
#   (Exit 137), 7 homepage (7 Neustarts), 8 old-demo (gestoppt), 9 eager_turing 10 quirky_hopper.
# layered: Werkzeuge = 7, Docker-Health = 4. CTs: 1 alpha 2 delta 3 beta 4 gamma 5 ntfy 6 security.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

hl_dmode() {
  conf "MODE=docker" "SSH_HOSTS=Docker-Host" "RECENT_MAX=0"
  sed -i 's/^chat-mongodb|\([^|]*\)|running|Up 4 weeks|/chat-mongodb|\1|running|Up 4 weeks (unhealthy)|/' "$PD_FIX/host-docker"
}
hl_after() { awk -v m="$2" 'index($0, m) { f = 1 } f' <<< "$1"; } # ausgabe marke → ab der Marke
hl_web() { # layered: app und db in alpha als Compose-Projekt „web“
  awk -F'|' -v OFS='|' '$1 == "app" || $1 == "db" { $0 = $0 "|web|" $1 } 1' "$PD_FIX/docker/alpha" > "$W/alpha"
  mv "$W/alpha" "$PD_FIX/docker/alpha"
}

# ─── docker ────────────────────────────────────────────────────────────────
t_health_docker_sections() {                       # Projekte und Einzelcontainer getrennt, Probleme zuerst
  hl_dmode; menu '6\n3\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ Docker-Health · alle"; has "$OUT" "Status ● 12/14 laufen · 2 Fehler · 2 Warnungen · 1 gestoppt"
  has "$OUT" "▌ COMPOSE-PROJEKTE"; has "$OUT" "▌ EINZELCONTAINER"
  has_re "$OUT" " 1\) ● nextcloud +5/5  unhealthy  mongodb \(unhealthy\)"
  has_re "$OUT" " 2\) ● authproxy +1/1  ok"; has_re "$OUT" " 4\) ● jellyfin +1/1  ok"
  has_re "$OUT" " 5\) ● hermes +3fc21559a8b7  OOM-Kill  Up 2 months"
  has_re "$OUT" " 6\) ● agent-dev .*  Exit 137"; has_re "$OUT" " 7\) ● homepage .*  7× neu gestartet"
  has_re "$OUT" " 8\) ● old-demo .*  gestoppt"; has_re "$OUT" "10\) ● quirky_hopper .*  ok"
  hasnt "$(hl_after "$OUT" "┌─ Docker-Health" | awk '{ print } /p\) nur Probleme/ { exit }')" "4/6"   # keine Sammelzeile
  has "$OUT" "p) nur Probleme"; has "$OUT" "r) neu prüfen"
  logged '{{.Name}}|{{.RestartCount}}|{{.State.OOMKilled}}|{{.State.ExitCode}}' || die "kein docker inspect"
  eq "$(grep -c '^  inspect$' "$STUB_LOG")" 1 "ein inspect für alle Container"
}
t_health_docker_problems_only() {                  # p blendet ok aus, noch einmal p zeigt alles
  hl_dmode; menu '6\n3\np\np\nb\nb\nq\n'; rc_is 20; no_err
  local s; s=$(hl_after "$OUT" "┌─ Docker-Health · nur Probleme" | awk '/p\) alle zeigen/ { print; exit } { print }')
  has_re "$s" " 1\) ● nextcloud "; has_re "$s" " 2\) ● hermes "; has_re "$s" " 5\) ● old-demo "
  hasnt "$s" "authproxy"; hasnt "$s" "eager_turing"; has "$s" "p) alle zeigen"
  eq "$(count "$OUT" "┌─ Docker-Health · alle")" 2 "zweites p zeigt wieder alles"
  printf '%s\n' "$(grep -E '^(gitea|authproxy)\|' "$PD_FIX/host-docker")" > "$PD_FIX/host-docker"
  menu 'q\n'; local tw; tw=$(tt_nr "$OUT" ") Werkzeuge")                  # nur 2 Projekte: Werkzeuge = 3
  menu "$tw\n3\np\nb\nb\nq\n"; rc_is 20; no_err; has "$OUT" "Keine Probleme. Taste p zeigt alles."
}
t_health_docker_open() {                           # Enter: Projekt-Screen bzw. Container-Screen
  hl_dmode; menu '6\n3\n1\nb\n5\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ nextcloud · 5/5 laufen"; has "$OUT" "┌─ hermes · Docker"; has "$OUT" "Fastpath ssh -t testhost sshlobby --go hermes"
}
t_health_docker_down() {                           # Docker aus: Meldung, zurück ins Werkzeug-Menü
  hl_dmode; export STUB_HOST_DOCKER=down
  menu '1\nb\nq\n'; local n; n=$(tt_nr "$OUT" ") Docker-Health"); [ -n "$n" ] || die "Werkzeug fehlt:\n$OUT"
  menu "1\n$n\n\nb\nq\n"; rc_is 20; no_err; has "$OUT" "Docker nicht erreichbar."; hasnt "$OUT" "┌─ Docker-Health"
}

# ─── Zustand und Healthcheck ───────────────────────────────────────────────
t_health_state_page() {                            # Healthcheck-Log neueste zuerst, ohne Healthcheck ein Hinweis
  hl_dmode; menu '6\n3\n1\n5\n7\n\nb\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" " 7) Zustand und Healthcheck"; has "$OUT" "── Zustand: chat-mongodb ──"
  has_re "$OUT" "Health +unhealthy · 3 Fehlschläge in Folge"; has_re "$OUT" "Healthcheck +curl -f http://localhost/ \|\| exit 1"
  has_re "$OUT" "Neustart-Regel always"; has "$OUT" "Letzte Prüfungen (neueste zuerst)"
  local s; s=$(hl_after "$OUT" "Letzte Prüfungen")
  has_re "$s" "2026-10-13 09:10:00 UTC  Exit 1  curl: \(7\) Failed to connect to localhost port 80"
  [ "$(grep -n '09:10:00' <<< "$s" | cut -d: -f1)" -lt "$(grep -n '09:09:30' <<< "$s" | cut -d: -f1)" ] || die "Reihenfolge:\n$s"
  menu '6\n3\n6\n6\n\nb\nb\nb\nq\n'; rc_is 20; no_err   # agent-dev: Container-Screen ohne Compose-Ordner, Eintrag 6
  has "$OUT" "── Zustand: agent-dev ──"; has_re "$OUT" "Exit-Code +137"; has_re "$OUT" "Beendet +2026-09-15 08:00:00 UTC"
  has "$OUT" "Kein Healthcheck definiert."; hasnt "$OUT" "Letzte Prüfungen"
  menu '6\n3\n5\n6\n\nb\nb\nb\nq\n'; rc_is 20                       # hermes: OOM-Kill
  has_re "$OUT" "OOM-Kill +ja"
  export STUB_INSPECT_RC=1; menu '6\n3\n5\n6\n\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "docker inspect hermes hat nichts geliefert."
}

# ─── layered ───────────────────────────────────────────────────────────────
t_health_layered_cts() {                           # eine Zeile pro CT, Probleme zuerst, ohne docker inspect
  norecent; menu '7\n4\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Status ● 6 CTs · 1 mit Fehlern · 1 mit Warnungen"; has "$OUT" "▌ INCUS-CONTAINER"
  has_re "$OUT" " 1\) ● alpha +2/3  unhealthy  myapp \(unhealthy\), db \(gestoppt\)"
  has_re "$OUT" " 2\) ● delta +Docker nicht erreichbar"; has_re "$OUT" " 3\) ● beta +CT gestoppt"
  has_re "$OUT" " 4\) ● gamma +kein Docker"; has_re "$OUT" " 6\) ● security +1/1  ok"
  ! grep -qx '  inspect' "$STUB_LOG" || die "docker inspect in der CT-Übersicht"
}
t_health_layered_ct_view() {                       # Enter auf CT: Projekte und Einzelcontainer im CT
  norecent; hl_web; menu '7\n4\n1\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ alpha · alle"; has "$OUT" "Status ● 2/3 laufen · 1 Fehler · 0 Warnungen · 1 gestoppt"
  has_re "$OUT" " 1\) ● web +1/2  gestoppt  db \(gestoppt\)"; has_re "$OUT" " 2\) ● myapp .*  unhealthy"
  grep -qx '== docker@alpha' "$STUB_LOG" && logged inspect || die "kein inspect im CT"
}
t_health_layered_project() {                       # Projekt im CT: Projekt-Screen mit CT-Kontext, Aktionen im CT
  norecent; hl_web; menu '7\n4\n1\n1\n3\nb\nb\nb\nb\nq\n'; rc_is 20; no_err   # 1 web, 3 = Logs (2 Container)
  has "$OUT" "┌─ web · 1/2 laufen"; has "$OUT" "Shell im CT alpha in /opt/it's app"
  has "$OUT" "STUB-COMPOSE web logs"
  awk '/^== /{s=($0 == "== docker@alpha"); next} s' "$STUB_LOG" | grep -qx '  compose' || die "compose nicht im CT:\n$(cat "$STUB_LOG")"
  [ ! -s "$CONF/recents" ] || ! grep -q '|web|-|project' "$CONF/recents" || die "Projekt im CT im Verlauf"
}
t_health_layered_stopped_ct() {                    # Enter auf gestoppten CT: CT-Screen (dort starten)
  norecent; menu '7\n4\n3\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ beta"; has "$OUT" ") CT starten"
}
t_health_layered_problems_only() {
  norecent; menu '7\n4\np\nb\nb\nq\n'; rc_is 20; no_err
  local s; s=$(hl_after "$OUT" "┌─ Docker-Health · nur Probleme" | awk '{ print } /p\) alle zeigen/ { exit }')
  has_re "$s" " 1\) ● alpha "; has_re "$s" " 3\) ● beta "; hasnt "$s" "gamma"; hasnt "$s" "security"
}

# ─── Englisch und TUI ──────────────────────────────────────────────────────
t_health_en() {
  export SSHLOBBY_LANG=en; hl_dmode
  menu '6\n3\n1\n5\n7\n\nb\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ Docker health · all"; has "$OUT" "Status ● 12/14 running · 2 errors · 2 warnings · 1 stopped"
  has "$OUT" "▌ STANDALONE CONTAINERS"; has "$OUT" "restarted 7×"; has "$OUT" "OOM killed"; has "$OUT" "exit 137"
  has "$OUT" "p) problems only"; has "$OUT" "r) check again"; has "$OUT" " 7) State and health check"
  has "$OUT" "── State: chat-mongodb ──"; has_re "$OUT" "Health +unhealthy · 3 failures in a row"
  has "$OUT" "Recent checks (newest first)"
  local w; for w in Einzelcontainer gestoppt "neu prüfen" Zustand Fehlschläge Prüfungen; do hasnt "$OUT" "$w"; done
}
t_health_tui() {
  hl_dmode
  tui_start; tui_title "sshlobby"; tui_keys 6 Enter; tui_title "Server-Werkzeuge"
  tui_keys 3 Enter; tui_title "Docker-Health"; tui_wait "EINZELCONTAINER"; tui_wait "OOM-Kill"; tui_wait "eager_turing"
  tui_sel_is "nextcloud"; tui_keys p; tui_wait "nur Probleme"; tui_gone "eager_turing"
  tui_keys Enter; tui_title "nextcloud"; tui_keys q; tui_title "Docker-Health"; tui_sel_is "nextcloud"
  tui_keys q q; tui_title "sshlobby"; tui_keys q; tui_rc 20
}
