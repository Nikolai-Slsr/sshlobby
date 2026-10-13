# shellcheck shell=bash
# Testhelfer, geladen von tests/run.sh (dort sind T, ROOT, PD, BASE, SYSBIN gesetzt).
# shellcheck disable=SC2034 # OUT/ERR/RC/W/CONF lesen die Tests

setup() { # frische Fixture + HOME pro Test, Standard-Config layered wie incus-host
  W=$(mktemp -d "$BASE/t.XXXXXX")
  export HOME="$W/home" PD_FIX="$W/fix" STUB_LOG="$W/stub.log" SHELL="$T/stubs/hostshell"
  export PATH="$T/stubs:$SYSBIN"
  export SSHLOBBY_APT_SESSION="sshlobby-apt-test-$$-${W##*.}"   # nie die echte Update-Sitzung des Hosts sehen
  mkdir -p "$HOME"; cp -r "$T/fixtures" "$PD_FIX"
  sed -i "s|@FS@|$PD_FIX/fs/host|g" "$PD_FIX/host-docker"
  CONF="$HOME/.config/sshlobby"; mkdir -p "$CONF"
  conf "MODE=layered" "SSH_HOSTS=Docker-Host" "CVE_CT=security"
}
conf() { printf '%s\n' "$@" > "$CONF/config"; } # Config-Zeilen schreiben
# Verlauf ausblenden: Nummern bleiben stabil, wenn ein Test mehrere Projekte oder Werkzeuge nacheinander öffnet
norecent() { printf 'RECENT_MAX=0\n' >> "$CONF/config"; }
noconf() { rm -f "$CONF/config"; }
# PATH ohne einzelne Stubs (z. B. kein incus installiert): path_without incus docker
path_without() {
  local s b="$W/bin"; mkdir -p "$b"
  for s in "$T"/stubs/*; do
    [[ " $* " == *" ${s##*/} "* ]] || ln -sf "$s" "$b/${s##*/}"
  done
  export PATH="$b:$SYSBIN"
}

# sshlobby ohne Controlling-TTY, SIGINT auf Default (Hintergrund-Jobs erben sonst "ignoriert")
pd() { env --default-signal=INT setsid -w bash "$PD" "$@"; }
# Menü mit gepipter Eingabe: menu "<eingabe>" [args…] → $OUT, $ERR, $RC
menu() {
  local in=$1; shift
  printf '%b' "$in" | pd "$@" > "$W/out" 2> "$W/err"; RC=$?
  OUT=$(<"$W/out"); ERR=$(<"$W/err")
}
cli() { pd "$@" > "$W/out" 2> "$W/err" < /dev/null; RC=$?; OUT=$(<"$W/out"); ERR=$(<"$W/err"); }

die()       { printf '%b\n' "$*"; exit 1; }
skip()      { echo "$*"; exit 77; }
has()       { grep -qF -- "$2" <<< "$1" || die "erwartet: »$2«"; }
hasnt()     { ! grep -qF -- "$2" <<< "$1" || die "unerwartet: »$2«"; }
has_re()    { grep -qE -- "$2" <<< "$1" || die "erwartet (Regex): »$2«"; }
count()     { grep -cF -- "$2" <<< "$1"; }
eq()        { [ "$1" = "$2" ] || die "erwartet »$2«, ist »$1«${3:+ ($3)}"; }
rc_is()     { eq "$RC" "$1" "Exit-Code"; }
no_err()    { [ -z "$ERR" ] || die "stderr nicht leer: $ERR"; }
row16()     { printf '%-16s %s' "$1" "$2"; }
listrow()   { printf '%-18s %-10s %-15s %s' "$@"; }
logged()    { grep -qxF -- "  $1" "$STUB_LOG" 2>/dev/null; }
no_docker_exec() { # kein "docker exec" im Stub-Log (erstes Argument nach "== docker@…")
  ! awk '/^== /{d=($0 ~ /^== docker@/); first=1; next} first{if (d && $0=="  exec") f=1; first=0} END{exit !f}' \
    "$STUB_LOG" 2>/dev/null || die "docker exec trotz Preflight"
}

# Werkzeug-Menü im Zeilenmodus: Nummer von „Einstellungen“ und Prüfung, dass es das letzte ist
setup_nr() { printf '%s\n' "$OUT" | sed -n 's/^ *\([0-9][0-9]*\)) Einstellungen .*/\1/p' | tail -n1; }
setup_is_last() {
  local n m
  n=$(setup_nr); [ -n "$n" ] || die "Werkzeug Einstellungen fehlt"
  m=$(printf '%s\n' "$OUT" | awk '/Server-Werkzeuge/ {f=1; max=0; next} f && /Auswahl/ {f=0; last=max}
        f && match($0, /^ *[0-9]+\)/) {v=substr($0, RSTART, RLENGTH); gsub(/[ )]/, "", v); if (v+0 > max) max=v+0}
        END {print (last ? last : max)}')
  [ "$n" = "$m" ] || die "Einstellungen ist Nr. $n, letztes Werkzeug ist Nr. $m"
}
