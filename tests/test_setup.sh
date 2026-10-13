# shellcheck shell=bash
# Moduserkennung, Moduswahl und Setup (Zeilenmodus; Setup am Terminal siehe test_tui.sh).
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

t_detect_layered_silent() {                         # ohne Config und ohne TTY: still erkennen
  noconf
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" "Modus layered"; has "$OUT" "1) ● alpha"
  [ ! -e "$CONF/config" ] || die "Config ohne TTY geschrieben"
  logged "ps" || die "keine Erkennung im CT"
}
t_detect_docker_without_incus() {
  noconf; path_without incus
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" "Modus docker"; has "$OUT" "COMPOSE-PROJEKTE"; has "$OUT" "nextcloud"
}
t_detect_incus_only() {
  noconf; export STUB_HOST_DOCKER=down
  sed -i 's/|yes$/|no/; s/|down$/|no/' "$PD_FIX/cts"
  menu 'q\n'; rc_is 20; no_err; has "$OUT" "Modus incus"
  menu '1\nb\nq\n'; hasnt "$OUT" "DOCKER-CONTAINER"
}
t_detect_nothing() {
  noconf; path_without incus docker
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" "Modus docker"; has "$OUT" "(kein Docker installiert)"
  cli --list; rc_is 1; has "$ERR" "kein Docker installiert"
}
t_detect_prefers_layered_over_host_docker() {
  noconf                                            # Host-Docker hat Container, alpha hat Docker
  cli --list; rc_is 0; has "$OUT" "DOCKER"; has "$OUT" "alpha"
}
t_setup_cli_writes_config() {
  noconf
  printf '1\n' | pd --setup > "$W/out" 2> "$W/err"; RC=$?; OUT=$(<"$W/out"); ERR=$(<"$W/err")
  rc_is 0; no_err
  has "$OUT" "┌─ Einrichtung"; has "$OUT" "Vorschlag     layered"; has "$OUT" "← erkannt"
  has "$OUT" "Incus         erreichbar, 6 CTs"; has "$OUT" "Docker in CTs ja (z. B. alpha)"
  has "$OUT" "Gespeichert: MODE=docker"
  grep -qx 'MODE=docker' "$CONF/config" || die "MODE fehlt: $(cat "$CONF/config")"
  menu 'q\n'; has "$OUT" "Modus docker"
}
t_setup_keeps_other_lines() {
  conf "# meine Notiz" "HOST_LABEL=box" "MODE=incus" "UNBEKANNT=1" "SSH_HOSTS=\"a b\""
  printf '3\n' | pd --setup > /dev/null 2>&1; RC=$?; rc_is 0
  eq "$(cat "$CONF/config")" $'# meine Notiz\nHOST_LABEL=box\nMODE=layered\nUNBEKANNT=1\nSSH_HOSTS="a b"'
  [ -z "$(find "$CONF" -name 'config.*')" ] || die "tmp-Datei liegen geblieben"
}
t_setup_abort() {
  conf "MODE=incus"; cp "$CONF/config" "$W/before"
  printf 'b\n' | pd --setup > /dev/null 2>&1; RC=$?; rc_is 1
  printf '' | pd --setup > /dev/null 2>&1; RC=$?; rc_is 1
  cmp -s "$CONF/config" "$W/before" || die "Abbruch hat die Config geändert"
}
t_setup_examples_offer() {                         # alle Beispiele zur Wahl, passendes vorausgewählt
  noconf; export STUB_HOSTNAME=docker-host
  printf '1\n\n1\n' | pd --setup > "$W/out" 2>&1; RC=$?; OUT=$(<"$W/out"); rc_is 0
  has "$OUT" "┌─ Beschreibungen"; has "$OUT" "2) examples/descriptions.incus-host"
  has_re "$OUT" "1\) examples/descriptions.docker-host +6 Einträge  ← passt zu docker-host"; has "$OUT" "3) keine"
  cmp -s "$CONF/descriptions" "$ROOT/examples/descriptions.docker-host" || die "nicht übernommen"
  menu 'q\n'; has_re "$OUT" "nextcloud +5/5  Nextcloud at cloud.example.org"
  has "$OUT" "DOCKER-HOST sshlobby"
  printf '1\n' | pd --setup > "$W/out" 2>&1; hasnt "$(<"$W/out")" "BEISPIEL-BESCHREIBUNGEN"   # schon gleich
  echo "x|eigener Text" > "$CONF/descriptions"
  printf '1\n\n3\n' | pd --setup > "$W/out" 2>&1                     # „keine“: eigene Datei bleibt
  has "$(<"$W/out")" "descriptions.bak"; eq "$(cat "$CONF/descriptions")" "x|eigener Text"
  printf '1\n\n2\n' | pd --setup > "$W/out" 2>&1                     # anderes Beispiel wählbar
  eq "$(cat "$CONF/descriptions.bak")" "x|eigener Text"
  cmp -s "$CONF/descriptions" "$ROOT/examples/descriptions.incus-host" || die "incus-host nicht übernommen"
  noconf; export STUB_HOSTNAME=unbekannt; rm "$CONF/descriptions" "$CONF/descriptions.bak"
  printf '1\n' | pd --setup > "$W/out" 2>&1; hasnt "$(<"$W/out")" "passt zu"
  [ ! -e "$CONF/descriptions" ] || die
}
t_setup_host_label() {                             # Anzeigename: vorbelegt, nur Änderungen schreiben
  noconf; export STUB_HOSTNAME=vps-0001
  printf '1\nDocker-Host\n\n' | pd --setup > "$W/out" 2>&1; RC=$?; OUT=$(<"$W/out"); rc_is 0
  has "$OUT" "Anzeigename [vps-0001]:"
  grep -qx 'HOST_LABEL=Docker-Host' "$CONF/config" || die "HOST_LABEL fehlt: $(cat "$CONF/config")"
  menu 'q\n'; has "$OUT" "DOCKER-HOST sshlobby"
  menu '4\n2\nb\nb\nq\n'; has "$OUT" "Fastpath ssh -t Docker-Host sshlobby --go nextcloud/Nextcloud"
  printf '1\n\n\n' | pd --setup > /dev/null 2>&1                     # leer = behalten
  eq "$(grep -c '^HOST_LABEL=' "$CONF/config")" 1; grep -qx 'HOST_LABEL=Docker-Host' "$CONF/config" || die
  conf "MODE=docker" "HOST_LABEL=Mein Server"                        # kein SSH-Alias → Hostname
  rm -f "$CONF/recents"                                              # nextcloud unter Zuletzt verschiebt Nummern
  menu '4\n2\nb\nb\nq\n'; has "$OUT" "Fastpath ssh -t vps-0001 sshlobby --go"
  noconf; export STUB_HOSTNAME=docker-host
  printf '1\n\n' | pd --setup > /dev/null 2>&1                       # Default nicht ausgeschrieben
  ! grep -q '^HOST_LABEL=' "$CONF/config" || die "Default-Label geschrieben"
}
t_setup_tool_switches_mode() {                     # Werkzeug „Einstellungen“ → Modus → zurück ins Hauptmenü
  local n
  menu '7\nb\nq\n'; setup_is_last; n=$(setup_nr)          # Einstellungen stehen immer am Ende der Werkzeuge
  menu "7\n$n\n1\n1\nb\nq\n"; rc_is 20; no_err               # Einstellungen → Modus → docker → zurück
  has "$OUT" "$n) Einstellungen"; has "$OUT" "Modus docker"; has "$OUT" "COMPOSE-PROJEKTE"
  grep -qx 'MODE=docker' "$CONF/config" || die
}
t_mode_override() {
  cli --mode docker --list; rc_is 0; has "$OUT" "PROJEKT"; has "$OUT" "Nextcloud"
  cli --list --mode=incus; rc_is 0; has "$OUT" "CT "; hasnt "$OUT" "DOCKER"
  SSHLOBBY_MODE=docker cli --list; rc_is 0; has "$OUT" "PROJEKT"
  SSHLOBBY_MODE=docker cli --mode incus --list; rc_is 0; has "$OUT" "CT "   # --mode vor Env
  cli --mode bogus --list; rc_is 2; has "$ERR" "unbekannter Modus"
  SSHLOBBY_MODE=bogus cli --list; rc_is 2; has "$ERR" "SSHLOBBY_MODE"
  SSHLOBBY_MODE=incus menu 'q\n'; has "$OUT" "Modus incus"
  grep -qx 'MODE=layered' "$CONF/config" || die "Override hat die Config geändert"
}
