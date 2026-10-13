# shellcheck shell=bash
# Verlauf („Zuletzt“): was aufgezeichnet wird, was im Hauptmenü erscheint, Öffnen von Einträgen.
# Hauptmenü docker: Zuletzt (falls vorhanden), dann 1 authproxy … 4 nextcloud, 5 Einzelcontainer, Werkzeuge.
# Hauptmenü layered: Zuletzt (falls vorhanden), dann alpha beta delta gamma ntfy security, Werkzeuge.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

rec_dmode() { conf "MODE=docker" "SSH_HOSTS=Docker-Host"; }
rec_file() { cat "$CONF/recents" 2>/dev/null; }
rec_section() { awk '/▌ ZULETZT/ { f = 1; next } f && /▌ / { exit } f' <<< "$1"; } # Zeilen unter Zuletzt

t_rec_project_recorded() {                         # Projekt öffnen = Eintrag, erscheint oben und öffnet das Projekt
  rec_dmode; menu '4\nb\nq\n'; rc_is 20; no_err
  grep -qE '^[0-9]+\|nextcloud\|-\|project$' "$CONF/recents" || die "kein Projekt-Eintrag:\n$(rec_file)"
  menu 'q\n'; rc_is 20
  has_re "$OUT" " 1\) nextcloud +Compose-Projekt · gerade eben"
  menu '1\nb\nq\n'; rc_is 20; no_err; has "$OUT" "┌─ nextcloud · 5/5 laufen"
}
t_rec_project_actions_kept() {                     # Projekt-Logs, ps und Compose-Ordner: Projekt bleibt der Eintrag
  rec_dmode; menu '4\n6\n7\n\n11\nb\nq\n'; rc_is 20; no_err
  eq "$(grep -c . "$CONF/recents")" 1 "Einträge"; grep -q '|nextcloud|-|project$' "$CONF/recents" || die "$(rec_file)"
}
t_rec_standalone_group_not_recorded() {            # die Gruppe „Einzelcontainer“ ist kein Verlaufseintrag
  rec_dmode; menu '5\nb\nq\n'; rc_is 20; no_err
  [ ! -s "$CONF/recents" ] || die "unerwarteter Eintrag:\n$(rec_file)"
}
t_rec_project_gone_hidden() {                      # Projekt ohne Container und CT-Einträge anderer Modi: unsichtbar
  rec_dmode
  printf '%s|weg|-|project\n%s|alpha|-|ctshell\n%s|-|-|project\n' "$(date +%s)" "$(date +%s)" "$(date +%s)" > "$CONF/recents"
  menu 'q\n'; rc_is 20; no_err; hasnt "$OUT" "ZULETZT"
}
t_rec_tools_not_in_main() {                        # Werkzeuge verdrängen keine Container mehr (RECENT_MAX=3)
  conf "MODE=docker" "RECENT_MAX=3"
  local now; now=$(date +%s)
  printf '%s|nextcloud|chat-mongodb|logs\n%s|@tool|sysinfo|tool\n%s|@tool|ports|tool\n%s|@tool|check|tool\n' \
    $((now - 300)) $((now - 30)) $((now - 20)) $((now - 10)) > "$CONF/recents"
  menu 'q\n'; rc_is 20; no_err
  local s; s=$(rec_section "$OUT")
  has "$s" "nextcloud / chat-mongodb"; hasnt "$s" "Server-Check"; hasnt "$s" "Ports"; hasnt "$s" "RAM"
}
t_rec_action_shown() {                             # Beschreibung nennt die Aktion
  rec_dmode
  local now; now=$(date +%s)
  printf '%s|nextcloud|chat-mongodb|logs\n%s|-|agent-dev|shell\n%s|gitea|gitea|compose\n' \
    $((now - 30)) $((now - 20)) $((now - 10)) > "$CONF/recents"
  menu 'q\n'; rc_is 20; no_err
  has_re "$OUT" " 1\) gitea / gitea +Compose-Ordner · gerade eben"
  has_re "$OUT" " 2\) agent-dev +Shell · gerade eben"
  has_re "$OUT" " 3\) nextcloud / chat-mongodb +Logs · gerade eben"
}
t_rec_same_second_order() {                        # Einträge derselben Sekunde: der später geschriebene zuerst
  rec_dmode
  local now; now=$(date +%s)
  printf '%s|-|agent-dev|shell\n%s|nextcloud|chat-mongodb|logs\n' "$now" "$now" > "$CONF/recents"
  menu 'q\n'; rc_is 20; has_re "$OUT" " 1\) nextcloud / chat-mongodb "; has_re "$OUT" " 2\) agent-dev "
  printf '%s|nextcloud|chat-mongodb|logs\n%s|-|agent-dev|shell\n' "$now" "$now" > "$CONF/recents"
  menu 'q\n'; rc_is 20; has_re "$OUT" " 1\) agent-dev "; has_re "$OUT" " 2\) nextcloud / chat-mongodb "
}
t_rec_gone_container_docker() {                    # docker: fehlender Container bleibt unsichtbar
  rec_dmode; printf '%s|-|gibtsnicht|logs\n' "$(date +%s)" > "$CONF/recents"
  menu 'q\n'; rc_is 20; hasnt "$OUT" "gibtsnicht"
}
t_rec_gone_container_layered() {                   # layered: Container fehlt im CT → Meldung, Eintrag weg, kein exec
  printf '%s|alpha|gibtsnicht|shell\n%s|alpha|app|logs\n' "$(( $(date +%s) - 5 ))" "$(( $(date +%s) - 9 ))" > "$CONF/recents"
  menu '1\n\nq\n'; rc_is 20; no_err
  has "$OUT" "alpha / gibtsnicht"
  has "$OUT" "Container „gibtsnicht“ gibt es in alpha nicht mehr, aus „Zuletzt“ entfernt."
  no_docker_exec; ! grep -q 'gibtsnicht' "$CONF/recents" || die "Eintrag noch da:\n$(rec_file)"
  grep -q '|alpha|app|logs$' "$CONF/recents" || die "anderer Eintrag verloren:\n$(rec_file)"
  menu 'q\n'; rc_is 20; hasnt "$OUT" "gibtsnicht"; has_re "$OUT" " 1\) alpha / app +Logs · "
}
t_rec_ct_down_kept() {                             # CT gestoppt: normale Fehlermeldung, Eintrag bleibt
  printf '%s|beta|app|shell\n' "$(date +%s)" > "$CONF/recents"
  menu '1\n\nq\n'; rc_is 20
  hasnt "$OUT" "aus „Zuletzt“ entfernt"; grep -q '|beta|app|shell$' "$CONF/recents" || die "Eintrag verloren:\n$(rec_file)"
}
t_rec_layered_ignores_projects_and_tools() {       # layered: Projekt- und Werkzeug-Einträge nicht im Hauptmenü
  printf '%s|alpha|-|project\n%s|@tool|check|tool\n' "$(date +%s)" "$(date +%s)" > "$CONF/recents"
  menu 'q\n'; rc_is 20; no_err; hasnt "$OUT" "ZULETZT"
}
