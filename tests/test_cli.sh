# shellcheck shell=bash
# CLI: Hilfe, Argumente, --list und --go pro Modus (Standard-Config: layered).
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

t_b13_help_version() {
  cli --help; rc_is 0; has "$OUT" "Usage: sshlobby"; no_err
  cli -h; rc_is 0; has "$OUT" "--go <ziel>"; has "$OUT" "--setup"; has "$OUT" "--mode <m>"
  cli --version; rc_is 0; eq "$OUT" "sshlobby 3.1.1"
}
t_b13_unknown_args() {
  local a
  for a in --bogus foo "--list extra" "--go" "--go a b" "--help x" "--list --list" "--list --go a" "--mode"; do
    # shellcheck disable=SC2086 # Wortzerlegung gewollt: mehrere Argumente
    cli $a; rc_is 2; eq "$OUT" "" "stdout bei »$a«"; has "$ERR" "Usage: sshlobby"
  done
  cli --go ""; rc_is 2
  cli --go /app; rc_is 2
}
t_b13_go_validation() {
  cli --go oldsite; rc_is 1; has "$ERR" "gibt es nicht"
  cli --go beta; rc_is 1; has "$ERR" "läuft nicht"
  cli --go alpha/ghost; rc_is 1; has "$ERR" "ghost"
  cli --go alpha/pp; rc_is 1                      # kein Teilstring-Treffer auf "app"
  cli --go gamma/x; rc_is 1; has "$ERR" "gamma: kein Docker installiert"
  cli --go delta/x; rc_is 1; has "$ERR" "delta: Docker im CT nicht erreichbar"
  cli --go alpha/db; rc_is 1; has "$ERR" 'Container „db“ läuft nicht (exited)'
  no_docker_exec
  [ ! -s "$CONF/recents" ] || die "Verlauf trotz Fehler geschrieben: $(cat "$CONF/recents")"
}
t_go_ok() {
  cli --go alpha; rc_is 0; has "$OUT" "STUB-BASH alpha"
  cli --go alpha/app; rc_is 0; has "$OUT" "STUB-DOCKER-EXEC alpha/app"
  logged "-i" || die "ohne TTY muss docker exec -i (nicht -it) laufen"
  eq "$(cut -d'|' -f2- "$CONF/recents" | sort | tr '\n' ' ')" "alpha|-|ctshell alpha|app|shell "
}
t_list() {
  cli --list; rc_is 0; no_err
  has "$OUT" "$(listrow alpha Running 10.0.0.11 2)"
  has "$OUT" "$(listrow beta Stopped - -)"
  has "$OUT" "$(listrow delta Running - '?')"
  has "$OUT" "$(listrow gamma Running 10.0.0.13 kein)"
  has "$OUT" "$(listrow ntfy Running 10.0.0.14 kein)"
  hasnt "$OUT" $'\e['                              # ohne TTY keine Farben
}
t_list_empty() {
  : > "$PD_FIX/cts"
  cli --list; rc_is 0; no_err; eq "$(wc -l <<< "$OUT")" 1
}

# ─── incus ─────────────────────────────────────────────────────────────────
t_cli_incus() {
  conf "MODE=incus"
  cli --list; rc_is 0; no_err
  has "$OUT" "$(printf '%-18s %-10s %s' alpha Running 10.0.0.11)"; hasnt "$OUT" "DOCKER"
  ! grep -q '== docker@' "$STUB_LOG" || die "--list im incus-Modus fragt Docker ab"
  cli --go alpha; rc_is 0; has "$OUT" "STUB-BASH alpha"
  cli --go alpha/app; rc_is 2; has "$ERR" "nur --go <ct>"
  cli --go beta; rc_is 1; has "$ERR" "läuft nicht"
}

# ─── docker ────────────────────────────────────────────────────────────────
t_cli_docker_list() {
  conf "MODE=docker"
  cli --list; rc_is 0; no_err
  has "$OUT" "$(printf '%-18s %-28s %s' nextcloud Nextcloud 'Up 4 days (healthy)')"
  has "$OUT" "$(printf '%-18s %-28s %s' - old-demo 'Exited (0) 4 weeks ago')"
  eq "$(tail -n1 <<< "$OUT" | cut -c1)" "-" "Einzelcontainer zuletzt"
  eq "$(wc -l <<< "$OUT")" 15 "Kopf + 14 Container"
  export STUB_HOST_DOCKER=down
  cli --list; rc_is 1; has "$ERR" "Docker nicht erreichbar"
}
t_cli_docker_go() {
  conf "MODE=docker"
  cli --go Nextcloud; rc_is 0; has "$OUT" "STUB-DOCKER-EXEC host/Nextcloud"
  cli --go nextcloud/Nextcloud; rc_is 0
  cli --go hermes; rc_is 0; has "$OUT" "STUB-DOCKER-EXEC host/hermes"
  cli --go -/hermes; rc_is 0
  eq "$(cut -d'|' -f2- "$CONF/recents" | sort | tr '\n' ' ')" "-|hermes|shell nextcloud|Nextcloud|shell "
  cli --go gitea/Nextcloud; rc_is 1; has "$ERR" 'gehört zu Projekt „nextcloud“'
  cli --go old-demo; rc_is 1; has "$ERR" 'Container „old-demo“ läuft nicht (exited)'
  cli --go ghost; rc_is 1; has "$ERR" 'Container „ghost“ gibt es nicht'
  cli --go nextcloud; rc_is 1                       # Projektname ist kein Container
  cli --go a/b/c; rc_is 2
  cli --go nextcloud/; rc_is 2
  no_docker_exec_for old-demo
}
no_docker_exec_for() { ! grep -A3 -x '  exec' "$STUB_LOG" | grep -qx "  $1" || die "docker exec auf $1"; }
