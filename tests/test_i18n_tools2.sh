# shellcheck shell=bash
# Englische Oberfläche der Werkzeuge Hermes-Instanzen, Updates und Timer & Cron (SSHLOBBY_LANG=en).

tools2_tw() { # Nummer des Eintrags „Werkzeuge“ im Hauptmenü (englisch „Tools“) → TW
  menu 'q\n'; TW=$(tt_nr "$OUT" ") Tools"); [ -n "$TW" ] || TW=$(tt_nr "$OUT" ") Werkzeuge")
  [ -n "$TW" ] || die "kein Werkzeuge-Eintrag:\n$OUT"
}
tools2_open() { # titel eingabe-danach → $OUT, TW und TN wie bei tt_open
  local t=$1 rest=$2 o r e
  export PD_TOOLS_ROOT="$PD_FIX/tools/root"
  tools2_tw
  menu "$TW\nb\nq\n"; TN=$(tt_nr "$OUT" ") $t"); [ -n "$TN" ] || die "Werkzeug »$t« fehlt:\n$OUT"
  menu "$TW\n$TN\n$rest"; o=$OUT r=$RC e=$ERR
  menu "$TW\nb\nq\n"; TN=$(tt_nr "$OUT" ") $t")         # Werkzeug steht jetzt oben unter „Recent“
  OUT=$o RC=$r ERR=$e
}

t_i18n_tools2_hermes_en() {                       # Instanzliste, Instanz-Screen, maskierte config.yaml
  export SSHLOBBY_LANG=en; conf "MODE=docker"; hm_host
  tools2_open "Hermes instances" 'b\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "4 found"; has_re "$OUT" "hermes-gateway +Gateway active · WebUI active  /srv/hermes/main"
  hasnt "$OUT" "gefunden"; hasnt "$OUT" "Hermes-Instanzen"
  local i c; i=$(hm_nr "$OUT" "hermes-gateway"); [ -n "$i" ] || die "Instanz fehlt:\n$OUT"
  menu "$TW\n$TN\n$i\nb\nb\nb\nq\n"; rc_is 20; no_err
  has "$OUT" ") Open Hermes CLI"; has "$OUT" ") Restart gateway"; has "$OUT" "asks first"
  has "$OUT" "LOGS AND FILES"; has "$OUT" "last 150 lines of logs/errors.log"; has "$OUT" ") Show errors.log"; has "$OUT" ") Update Hermes"
  hasnt "$OUT" "Rückfrage"; hasnt "$OUT" "neu starten"; hasnt "$OUT" "Datenordner"; hasnt "$OUT" "Zeilen"
  c=$(tt_nr "$OUT" ") Show config.yaml"); [ -n "$c" ] || die "kein config.yaml-Eintrag:\n$OUT"
  menu "$TW\n$TN\n$i\n$c\n\nb\nb\nb\nq\n"; rc_is 20; no_err
  has "$OUT" "api_key: *** (masked)"; hasnt "$OUT" "maskiert"; hasnt "$OUT" "sk-test"
}

t_i18n_tools2_updates_en() {                      # Updates-Menü, Übersicht, apt-Lauf im eigenen bash
  export SSHLOBBY_LANG=en; conf "MODE=docker"
  tools2_open "Updates" 'b\nb\nq\n'; rc_is 20; no_err
  has "$OUT" ") Refresh package lists"; has "$OUT" ") Install security updates"; has "$OUT" "packages, asks first"
  has "$OUT" "Package lists"; hasnt "$OUT" "Paketlisten"; hasnt "$OUT" "Rückfrage"; hasnt "$OUT" "Übersicht"
  local o s; o=$(tt_nr "$OUT" ") Overview"); s=$(tt_nr "$OUT" ") Install security updates")
  menu "$TW\n$TN\n$o\n\nb\nb\nq\n"; rc_is 20; no_err
  has_re "$OUT" "Pending updates +124"; has "$OUT" "Installed kernel"; hasnt "$OUT" "Kernel installiert"
  menu "$TW\n$TN\n$s\ny\n\nb\nb\nq\n"; rc_is 20
  has "$OUT" "== Security updates:"; has "$OUT" "Done."; hasnt "$OUT" "Fertig."
}

t_i18n_tools2_timers_en() {
  export SSHLOBBY_LANG=en
  tools2_open "Timers & cron" '\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "systemd timers (next run first)"; has_re "$OUT" "–  +docker-oom-shields +last"
  has "$OUT" "run-parts folders"; hasnt "$OUT" "zuletzt"; hasnt "$OUT" "nächster Lauf"
}
