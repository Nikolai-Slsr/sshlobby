# shellcheck shell=bash
# Favoriten per Taste f auf der markierten Zeile (Zeilenmodus: „f <Nummer>“), Projekte und Werkzeuge als Favoriten.
# docker (RECENT_MAX=0): Hauptmenü 1 authproxy 2 gitea 3 jellyfin 4 nextcloud 5 Einzelcontainer 6 Werkzeuge,
#   Favoriten stehen davor und verschieben die Nummern. Werkzeuge: 3 Docker-Health. nextcloud: 1 admin-panel
#   2 api … 5 mongodb, 6 Logs. Einzelcontainer: 1 agent-dev 2 eager_turing 3 hermes.
# layered: 1 alpha … 6 security, 7 Werkzeuge. alpha: 1 myapp 2 app 3 db, dann CT-Aktionen.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

fv_dmode() { conf "MODE=docker" "SSH_HOSTS=Docker-Host" "RECENT_MAX=0"; }
fv_has() { grep -qxF -- "$1" "$CONF/favorites" 2>/dev/null || die "Favorit »$1« fehlt:\n$(cat "$CONF/favorites" 2>/dev/null)"; }
fv_hasnt() { ! grep -qxF -- "$1" "$CONF/favorites" 2>/dev/null || die "Favorit »$1« unerwartet"; }

t_fav_main_project() {                             # f auf Projektzeile: Projekt-Favorit, öffnet das Projekt, f entfernt
  fv_dmode; menu 'f 4\nq\n'; rc_is 20; no_err
  has "$OUT" "f) Favorit ★"; has "$OUT" "nextcloud zu den Favoriten hinzugefügt"; fv_has "nextcloud|-"
  menu '1\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" " 1\) ★ nextcloud +Compose-Projekt"; has "$OUT" "┌─ nextcloud · 5/5 laufen"
  menu 'f 1\nq\n'; rc_is 20; has "$OUT" "nextcloud aus den Favoriten entfernt"; fv_hasnt "nextcloud|-"
  menu 'q\n'; hasnt "$OUT" "FAVORITEN"
}
t_fav_main_hints() {                               # f ohne Nummer erklärt, Einzelcontainer-Gruppe und Werkzeuge gehen nicht
  fv_dmode; menu 'f\nf 5\nf 6\nq\n'; rc_is 20; no_err
  has "$OUT" "Welche Zeile? Im Zeilenmodus: f und die Nummer, z. B. f 3."
  eq "$(count "$OUT" "Für diese Zeile gibt es keinen Favoriten.")" 2 "Einzelcontainer und Werkzeuge"
  [ ! -s "$CONF/favorites" ] || die "Favorit angelegt:\n$(cat "$CONF/favorites")"
}
t_fav_project_screen() {                           # Projekt-Screen: Container-Zeile = Container, Aktionszeile = Projekt
  fv_dmode; menu '4\nf 2\nf 6\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Nextcloud zu den Favoriten hinzugefügt"; fv_has "nextcloud|Nextcloud"; fv_has "nextcloud|-"
  menu '7\nf 3\nb\nq\n'; rc_is 20; no_err                     # 2 Favoriten oben: Einzelcontainer = 7, Gruppe „-“
  fv_has "-|hermes"
  menu 'q\n'; has_re "$OUT" "★ nextcloud/Nextcloud"; has_re "$OUT" "★ hermes"
}
t_fav_recent_row() {                               # f auf Verlaufszeile: Ziel des Eintrags
  fv_dmode; conf "MODE=docker" "SSH_HOSTS=Docker-Host"
  printf '%s|nextcloud|-|project\n%s|nextcloud|chat-mongodb|logs\n' "$(( $(date +%s) - 5 ))" "$(date +%s)" > "$CONF/recents"
  menu 'f 1\nf 2\nq\n'; rc_is 20; no_err
  fv_has "nextcloud|chat-mongodb"; fv_has "nextcloud|-"
}
t_fav_tool() {                                     # Werkzeug-Favorit: ★ im Werkzeug-Menü, Eintrag im Hauptmenü öffnet es
  fv_dmode; menu '6\nf 3\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Docker-Health zu den Favoriten hinzugefügt"; fv_has "@tool|health"
  has_re "$OUT" " 3\) ★ Docker-Health"
  menu '1\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" " 1\) ★ Docker-Health +Werkzeug"; has "$OUT" "┌─ Docker-Health · alle"
  menu '7\nf 17\nb\nq\n'; rc_is 20                          # Einstellungen (letzter Eintrag) geht nicht
  has "$OUT" "Für diese Zeile gibt es keinen Favoriten."
  printf '@tool|incus_overview\n' >> "$CONF/favorites"        # Werkzeug anderer Modi: unsichtbar
  menu 'q\n'; hasnt "$OUT" "Incus-Übersicht"
}
t_fav_layered() {                                  # CT-Zeile im Hauptmenü, CT-Screen: f allein = CT, f auf Container
  menu 'f 1\nq\n'; rc_is 20; no_err; fv_has "alpha|-"
  menu '2\nf 2\nb\nq\n'; rc_is 20; no_err                   # Favorit alpha steht oben: alpha = 2, app = Zeile 2
  fv_has "alpha|app"
  menu '3\nf\nb\nq\n'; rc_is 20; no_err; fv_hasnt "alpha|-"   # 2 Favoriten oben: alpha = 3; f ohne Nummer = der CT (wie bisher)
  menu 'q\n'; has "$OUT" "★ alpha/app"; hasnt "$OUT" "★ alpha (CT-Shell)"
}
t_fav_health() {                                   # Docker-Health: Projekt, Einzelcontainer; layered: CT, Projekt im CT nicht
  hl_dmode; menu '6\n3\nf 1\nf 5\nb\nb\nq\n'; rc_is 20; no_err   # 1 nextcloud (unhealthy), 5 hermes
  fv_has "nextcloud|-"; fv_has "-|hermes"
  rm -f "$CONF/favorites"; conf "MODE=layered" "SSH_HOSTS=Docker-Host" "CVE_CT=security" "RECENT_MAX=0"
  menu '7\n4\nf 1\nb\nb\nq\n'; rc_is 20; no_err; fv_has "alpha|-"
  rm -f "$CONF/favorites"; hl_web
  menu '7\n4\n1\nf 1\nf 2\nb\nb\nb\nq\n'; rc_is 20; no_err     # alpha: 1 Projekt web (geht nicht), 2 myapp
  has "$OUT" "Für diese Zeile gibt es keinen Favoriten."; fv_has "alpha|myapp"
}
t_fav_tui() {                                      # f wirkt auf die Cursorzeile, Cursor bleibt auf ihr
  fv_dmode
  tui_start; tui_title "sshlobby"; tui_wait "f Favorit ★"
  tui_keys 4; tui_sel_is "nextcloud"; tui_keys f
  tui_wait "nextcloud zu den Favoriten hinzugefügt"; tui_wait "FAVORITEN"; tui_sel_is "● nextcloud"
  fv_has "nextcloud|-"
  tui_keys / g i t; tui_wait "1 Treffer"; tui_keys Enter f; tui_wait "gitea zu den Favoriten hinzugefügt"; fv_has "gitea|-"
  tui_keys Escape q; tui_rc 20
}
