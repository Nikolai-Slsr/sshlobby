# shellcheck shell=bash
# Einstellungen: Screen (Taste e, letztes Werkzeug, --settings), neue Config-Keys und ihre Wirkung,
# Zurücksetzen mit Sicherung, Wiederherstellen, --reset.

st_nr() { # label → Nummer im zuletzt gezeigten Einstellungen-Screen (Titel „Einstellungen · …“)
  awk -v l="$1" '/Einstellungen · / { f = 1; n = ""; next } f && /Auswahl:/ { f = 0; if (n != "") hit = n; next }
    f && n == "" && match($0, /^ *[0-9]+\) /) { r = substr($0, RLENGTH + 1); m = substr($0, 1, RLENGTH)
      if (r == l || index(r, l "  ") == 1) { gsub(/[ )]/, "", m); n = m } }
    END { print hit }' <<< "$OUT"
}
st_item() { # label → Nummer (öffnet dafür einmal die Einstellungen), bricht ab, wenn es den Eintrag nicht gibt
  menu 'e\nb\nq\n'; ST=$(st_nr "$1"); [ -n "$ST" ] || die "Eintrag »$1« fehlt:\n$OUT"
}
cfg_has() { grep -qxF -- "$1" "$CONF/config" || die "Config ohne »$1«:\n$(cat "$CONF/config")"; }

t_settings_from_main_key() {
  conf "MODE=docker"
  menu 'e\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "e) Einstellungen"; has "$OUT" "Einstellungen · ~/.config/sshlobby"
  has_re "$OUT" "Modus +docker"; has_re "$OUT" "Beim SSH-Login starten +an"; has_re "$OUT" "Taste q im Hauptmenü +Logout"
  has_re "$OUT" "Einträge unter Zuletzt +5"; has "$OUT" ") Einstellungen zurücksetzen"; has "$OUT" ") Alles zurücksetzen"
  hasnt "$OUT" "CVE-Monitor-CT"; hasnt "$OUT" "Sicherung wiederherstellen"
}

t_settings_cli_and_layered_items() {                # --settings, im layered-Modus auch CVE-CT und Hermes-CT-Suche
  menu 'b\n' --settings; rc_is 0; no_err
  has_re "$OUT" "CVE-Monitor-CT +security"; has_re "$OUT" "Hermes-Suche in Incus-CTs +an"; has_re "$OUT" "Modus +layered"
}

t_settings_toggle_autostart() {
  conf "MODE=docker"; st_item "Beim SSH-Login starten"
  menu "e\n$ST\nb\nq\n"; rc_is 20; no_err; cfg_has "AUTOSTART=no"; has "$OUT" "Gespeichert: AUTOSTART=no"
  has_re "$OUT" "Beim SSH-Login starten +aus"
  menu "e\n$ST\nb\nq\n"; cfg_has "AUTOSTART=yes"
  grep -qx "MODE=docker" "$CONF/config" || die "andere Keys verloren"
}

t_autostart_off_skips_login_only() {               # nur der Login-Start (SSHLOBBY_LOGIN=1) wird übersprungen
  conf "MODE=docker" "AUTOSTART=no"
  export SSHLOBBY_LOGIN=1
  menu 'q\n'; rc_is 0; hasnt "$OUT" "COMPOSE-PROJEKTE"
  cli --list; rc_is 0; has "$OUT" "Nextcloud"                            # Schnellzugriffe laufen weiter
  unset SSHLOBBY_LOGIN
  menu 'q\n'; rc_is 20; has "$OUT" "COMPOSE-PROJEKTE"                     # von Hand startet es immer
  conf "MODE=docker" "AUTOSTART=yes"; export SSHLOBBY_LOGIN=1
  menu 'q\n'; rc_is 20; has "$OUT" "COMPOSE-PROJEKTE"; unset SSHLOBBY_LOGIN
}

t_login_marker_not_inherited() {                   # Kinder (Editor, Shells) dürfen SSHLOBBY_LOGIN nicht sehen
  conf "MODE=docker"
  # shellcheck disable=SC2016 # ${SSHLOBBY_LOGIN} soll erst im Editor-Skript expandieren
  printf '#!/bin/sh\necho "${SSHLOBBY_LOGIN:-unset}" > "%s/edenv"\n' "$W" > "$W/ed"; chmod +x "$W/ed"
  st_item "Beschreibungen"; local d=$ST
  export SSHLOBBY_LOGIN=1 EDITOR="$W/ed"
  menu "e\n$d\n2\nb\nb\nq\n"; unset SSHLOBBY_LOGIN EDITOR; rc_is 20
  [ "$(cat "$W/edenv")" = unset ] || die "SSHLOBBY_LOGIN an den Editor vererbt"
}

t_q_action_shell() {
  conf "MODE=docker" "Q_ACTION=shell"
  menu 'q\n'; rc_is 10; has "$OUT" "q) Shell"
  conf "MODE=docker"; st_item "Taste q im Hauptmenü"
  menu "e\n$ST\nb\nq\n"; rc_is 10; cfg_has "Q_ACTION=shell"
}

t_recent_max() {                                   # 0 blendet Zuletzt aus, 1 zeigt nur den neuesten Eintrag
  conf "MODE=docker" "RECENT_MAX=1"
  printf '%s|nextcloud|chat-mongodb|logs\n%s|-|agent-dev|shell\n' "$(date +%s)" "$(( $(date +%s) - 60 ))" > "$CONF/recents"
  menu 'q\n'; rc_is 20; has "$OUT" "nextcloud / chat-mongodb"; hasnt "$OUT" "agent-dev"
  printf '%s|@tool|updates|tool\n%s|@tool|ports|tool\n' "$(date +%s)" "$(( $(date +%s) - 60 ))" > "$CONF/recents"
  tt_tools; eq "$(count "$OUT" ") Updates ")" 2 "Updates unter Zuletzt"; eq "$(count "$OUT" ") Ports")" 1 "Ports nur in der Liste"
  conf "MODE=docker" "RECENT_MAX=0"
  menu 'q\n'; rc_is 20; hasnt "$OUT" "ZULETZT"
  tt_tools; hasnt "$OUT" "ZULETZT"; hasnt "$OUT" "ALLE WERKZEUGE"
  conf "MODE=docker"; st_item "Einträge unter Zuletzt"
  menu "e\n$ST\n1\nb\nq\n"; rc_is 20; cfg_has "RECENT_MAX=0"
}

t_symbols_ascii() {
  conf "MODE=docker" "SYMBOLS=ascii"
  menu 'q\n'; rc_is 20; no_err; hasnt "$OUT" "●"; has_re "$OUT" "o authproxy"
  conf "MODE=docker"; st_item "Symbole"
  menu "e\n$ST\nb\nq\n"; rc_is 20; cfg_has "SYMBOLS=ascii"; has_re "$OUT" "Symbole +nur ASCII"
}

t_settings_invalid_values_ignored() {
  conf "MODE=docker" "RECENT_MAX=99" "AUTOSTART=vielleicht" "Q_ACTION=reboot" "COLOR=bunt" "UI=gui"
  menu 'e\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" "Einträge unter Zuletzt +5"; has_re "$OUT" "Beim SSH-Login starten +an"; has_re "$OUT" "Farben +automatisch"
  has_re "$OUT" "Oberfläche +Pfeiltasten"
}

t_settings_mode_change() {
  conf "MODE=docker"; st_item "Modus"
  menu "e\n$ST\n3\nb\nq\n"; rc_is 20; no_err; cfg_has "MODE=layered"
  has "$OUT" "alpha"; has "$OUT" "PROJEKTE / CONTAINER"
}

t_settings_ssh_hosts() {
  conf "MODE=docker"; st_item "SSH-Ziele (Anderer Server)"
  menu "e\n$ST\nnas-1 backup@box\nb\nq\n"; rc_is 20; cfg_has 'SSH_HOSTS="nas-1 backup@box"'
  menu "e\n$ST\n-oProxyCommand=x\n\nb\nq\n"; rc_is 20; has "$OUT" "Ungültiges Ziel"; cfg_has 'SSH_HOSTS="nas-1 backup@box"'
  menu "e\n$ST\n-\nb\nq\n"; rc_is 20; cfg_has 'SSH_HOSTS='
}

t_settings_clear_recents_and_favorites() {
  conf "MODE=docker"
  printf '%s|@tool|updates|tool\n' "$(date +%s)" > "$CONF/recents"; echo "nextcloud|Nextcloud" > "$CONF/favorites"
  echo "ssh.service" > "$CONF/service-favorites"
  st_item "Verlauf leeren"; local r=$ST
  menu "e\n$r\nn\nb\nq\n"; [ -s "$CONF/recents" ] || die "Verlauf trotz Nein gelöscht"
  menu "e\n$r\nj\nb\nq\n"; [ ! -e "$CONF/recents" ] || die "Verlauf nicht gelöscht"
  st_item "Favoriten leeren"
  menu "e\n$ST\nj\nb\nq\n"; rc_is 20
  if [ -e "$CONF/favorites" ] || [ -e "$CONF/service-favorites" ]; then die "Favoriten nicht gelöscht"; fi
}

t_settings_reset_cfg() {                           # Sicherung, Config + Beschreibungen weg, Einrichtung, Verlauf bleibt
  conf "MODE=docker" "HOST_LABEL=Altname" "Q_ACTION=shell"
  echo "nextcloud|Alte Beschreibung" > "$CONF/descriptions"
  printf '%s|@tool|updates|tool\n' "$(date +%s)" > "$CONF/recents"
  st_item "Einstellungen zurücksetzen"; local r=$ST
  menu "e\n$r\nn\nb\nq\n"; rc_is 10; cfg_has "HOST_LABEL=Altname"                    # Nein: nichts passiert
  menu "e\n$r\nj\n1\n\nb\nb\nq\n"; rc_is 20; no_err                                  # Ja → Einrichtung: docker, Name, keine Vorlage
  has "$OUT" "Gesichert nach"; cfg_has "MODE=docker"
  ! grep -q "Altname\|Q_ACTION" "$CONF/config" || die "alte Werte noch da"
  [ ! -e "$CONF/descriptions" ] || die "Beschreibungen nicht zurückgesetzt"; [ -s "$CONF/recents" ] || die "Verlauf gelöscht"
  local b; b=$(find "$CONF/backups" -mindepth 1 -maxdepth 1 -type d | head -n1)
  grep -qx "HOST_LABEL=Altname" "$b/config" || die "Sicherung ohne Config"
  grep -q "Alte Beschreibung" "$b/descriptions" || die "Sicherung ohne Beschreibungen"
  [ ! -e "$b/recents" ] || die "Verlauf gehört nicht in diese Sicherung"
  [ "$(stat -c %a "$CONF/backups")" = 700 ] || die "Sicherungsordner nicht 700"
}

t_settings_reset_all_and_restore() {
  conf "MODE=docker" "HOST_LABEL=Altname"
  printf '%s|@tool|updates|tool\n' "$(date +%s)" > "$CONF/recents"; echo "nextcloud|Nextcloud" > "$CONF/favorites"
  st_item "Alles zurücksetzen"
  menu "e\n$ST\nj\n1\n\nb\nb\nq\n"; rc_is 20; no_err
  if [ -e "$CONF/recents" ] || [ -e "$CONF/favorites" ]; then die "Verlauf/Favoriten nicht zurückgesetzt"; fi
  st_item "Sicherung wiederherstellen"; local s=$ST
  menu "e\n$s\n1\nj\nb\nq\n"; rc_is 20; no_err; has "$OUT" "Wiederhergestellt"
  cfg_has "HOST_LABEL=Altname"
  { [ -s "$CONF/recents" ] && [ -s "$CONF/favorites" ]; } || die "Verlauf/Favoriten nicht zurück"
  eq "$(find "$CONF/backups" -mindepth 1 -maxdepth 1 -type d | grep -c .)" 2 "Sicherungen (Reset + vor dem Wiederherstellen)"
}

t_cli_reset() {
  conf "MODE=docker" "HOST_LABEL=Altname"
  menu 'n\n' --reset; rc_is 0; cfg_has "HOST_LABEL=Altname"
  menu 'j\n1\n\nb\nb\n' --reset; rc_is 0; no_err; cfg_has "MODE=docker"; ! grep -q Altname "$CONF/config" || die "nicht zurückgesetzt"
}

t_settings_backups_pruned() {                      # höchstens 10 Sicherungen, die ältesten gehen
  conf "MODE=docker"; local i
  for i in 01 02 03 04 05 06 07 08 09 10 11 12; do mkdir -p "$CONF/backups/202001$i-000000"; done
  st_item "Einstellungen zurücksetzen"
  menu "e\n$ST\nj\n1\n\nb\nb\nq\n"; rc_is 20
  eq "$(find "$CONF/backups" -mindepth 1 -maxdepth 1 -type d | grep -c .)" 10 "Sicherungen"
  [ ! -e "$CONF/backups/20200101-000000" ] || die "älteste Sicherung noch da"
}

t_settings_hook_note() {                           # fehlender, alter und von install.sh geschriebener Hook
  conf "MODE=docker"
  menu 'e\nb\nq\n'; has "$OUT" "Login-Hook nicht installiert"
  [ "$(id -u)" = 0 ] || skip "install.sh braucht root"
  inst_env; inst || die "install: $(cat "$W/iout")"     # echter Hook aus install.sh (Pfade im Testordner)
  cp "$W/bashrc" "$HOME/.bashrc"
  menu 'e\nb\nq\n'; hasnt "$OUT" "Hook veraltet"; hasnt "$OUT" "nicht installiert"
  sed -i 's/ SSHLOBBY_LOGIN=1 / /' "$HOME/.bashrc"      # Hook von vor 2.2.0: ohne Login-Marker
  menu 'e\nb\nq\n'; has "$OUT" "Hook veraltet"
}

t_hermes_scan_cts_off() {                          # HERMES_SCAN_CTS=no: nur Host-Ebenen
  hm_ct; conf "MODE=layered" "HERMES_SCAN_CTS=no"
  tt_open "Hermes-Instanzen" 'b\nb\nq\n'; rc_is 20; no_err
  hasnt "$OUT" "CT ALPHA"; hasnt "$OUT" "CTs durchsucht"
}
