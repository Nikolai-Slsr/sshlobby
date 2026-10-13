# shellcheck shell=bash
# Englische Texte von Hauptmenü, Projekt-, Container-, CT- und Setup-Screen (Zeilenmodus).
# shellcheck disable=SC2015,SC2034 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

t_i18n_screens_docker_en() {                       # Hauptmenü, Compose-Projekt, Container auf Englisch
  export SSHLOBBY_LANG=en
  conf "MODE=docker" "SSH_HOSTS=Docker-Host" "RECENT_MAX=0"
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" "COMPOSE PROJECTS"; has "$OUT" "Standalone containers"; has "$OUT" "no Compose project"
  has "$OUT" "12/14 containers running"; has "$OUT" " 6) Tools"
  hasnt "$OUT" "Container laufen"; hasnt "$OUT" "Werkzeuge"; hasnt "$OUT" "ohne Compose-Projekt"
  menu '4\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "nextcloud · 5/5 running"; has "$OUT" "Follow logs of all services"; has "$OUT" "Open Compose folder"
  has "$OUT" "all services"; hasnt "$OUT" "alle Services"; hasnt "$OUT" "Ordner"
  menu '4\n2\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Open shell"; has "$OUT" "Follow logs"; has "$OUT" "add favorite"
  hasnt "$OUT" "Shell rein"; hasnt "$OUT" "Favorit"; hasnt "$OUT" "Neustart"
}

t_i18n_screens_ct_en() {                           # layered: CT-Screen auf Englisch
  export SSHLOBBY_LANG=en
  menu '1\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "DOCKER CONTAINERS"; has "$OUT" "CT shell"; has "$OUT" "Stop CT"; has "$OUT" "Resources"
  has "$OUT" "CPU, RAM, disk, processes"
  hasnt "$OUT" "CT stoppen"; hasnt "$OUT" "Ressourcen"; hasnt "$OUT" "neu laden"; hasnt "$OUT" "Zuletzt"
}

t_i18n_screens_setup_en() {                        # Setup-Screen auf Englisch
  export SSHLOBBY_LANG=en
  noconf
  printf '1\n' | pd --setup > "$W/out" 2> "$W/err"; RC=$?; OUT=$(<"$W/out"); ERR=$(<"$W/err")
  rc_is 0; no_err
  has "$OUT" "┌─ Setup"; has "$OUT" "Choose mode"; has "$OUT" "reachable, 6 CTs"; has "$OUT" "← detected"
  has "$OUT" "Docker containers directly on the host"; has "$OUT" "Saved: MODE=docker"
  hasnt "$OUT" "Einrichtung"; hasnt "$OUT" "erreichbar"; hasnt "$OUT" "erkannt"; hasnt "$OUT" "Gespeichert"
}
