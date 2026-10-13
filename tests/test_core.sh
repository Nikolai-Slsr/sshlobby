# shellcheck shell=bash
# Statik (bash -n, shellcheck), Config-Parser, Doku/Version.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

t_syntax_bash_n() {
  local f
  for f in "$ROOT"/sshlobby.sh "$ROOT"/install.sh "$ROOT"/uninstall.sh "$ROOT"/lib/*.sh "$T"/*.sh "$T"/stubs/*; do
    bash -n "$f" || die "bash -n: $f"
  done
}
t_shellcheck() {
  command -v shellcheck >/dev/null || skip "shellcheck fehlt"
  shellcheck -S style -x "$ROOT"/sshlobby.sh "$ROOT"/install.sh "$ROOT"/uninstall.sh "$ROOT"/lib/*.sh \
    "$T"/*.sh "$T"/stubs/*
}

# ─── Config ────────────────────────────────────────────────────────────────
t_config_known_keys() {
  conf "# Kommentar" "  MODE = incus  " "HOST_LABEL=Testkiste" "FOO=bar" "export X=1" "SSH_HOSTS=" ""
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" "TESTKISTE sshlobby"; has "$OUT" "Modus incus"
  ! grep -q '== docker@' "$STUB_LOG" || die "incus-Modus fragt Docker ab"
}
t_config_not_sourced() {
  # shellcheck disable=SC2016 # Befehle sollen wörtlich in der Datei stehen
  conf 'MODE=$(touch '"$W"'/pwned1)' 'HOST_LABEL=`touch '"$W"'/pwned2`' 'CVE_CT=x;touch '"$W"'/pwned3' \
    "garbage line" "MODE=bogus" $'\x01\x02binär' "=nur wert"
  menu 'q\n'; rc_is 20; no_err
  [ ! -e "$W/pwned1" ] && [ ! -e "$W/pwned2" ] && [ ! -e "$W/pwned3" ] || die "Config wurde ausgeführt"
  has "$OUT" "Modus layered"                        # ungültiger MODE: still erkannt
  has "$OUT" '`TOUCH'                               # Label wörtlich übernommen
}
t_config_quotes_crlf() {
  conf $'MODE="docker"\r' "HOST_LABEL='Mit Leerzeichen'" 'SSH_HOSTS="a -oProxyCommand=evil b;x c"'
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" "MIT LEERZEICHEN"; has "$OUT" "Modus docker"
  menu '6\n4\nb\nb\nq\n'; rc_is 20; no_err        # Werkzeuge → Anderer Server: nur a und c
  has "$OUT" "ssh a"; has "$OUT" "ssh c"; hasnt "$OUT" "ProxyCommand"; hasnt "$OUT" "b;x"
}
t_config_nothing_written_without_tty() {
  noconf; rm -rf "$CONF"
  menu 'q\n'; rc_is 20; no_err
  [ ! -e "$CONF" ] || die "ohne TTY etwas nach $CONF geschrieben: $(ls -A "$CONF")"
  cli --list; rc_is 0; [ ! -e "$CONF" ] || die "--list schreibt"
}

# ─── Doku / Version ────────────────────────────────────────────────────────
t_b15_version_docs() {
  grep -q '^VERSION="3.0.3"$' "$PD" || die "VERSION"
  grep -q '^## 3.0.3' "$ROOT/CHANGELOG.md" || die "CHANGELOG"
  local s; for s in -- --version --setup --mode tests/run.sh docs/ARCHITECTURE.md; do
    grep -qF -- "$s" "$ROOT/README.md" || die "README: $s"
  done
  [ -s "$ROOT/docs/ARCHITECTURE.md" ] || die "docs/ARCHITECTURE.md fehlt"
  grep -qF 'ui_menu' "$ROOT/docs/ARCHITECTURE.md" || die "API-Referenz fehlt"
}
t_examples_present() {
  [ -s "$ROOT/examples/descriptions.docker-host" ] && [ -s "$ROOT/examples/descriptions.incus-host" ] || die
  grep -qxF 'nextcloud|Nextcloud at cloud.example.org with MongoDB, Meilisearch, admin panel' \
    "$ROOT/examples/descriptions.docker-host" || die "docker-host-Text"
}
t_lib_override() {
  SSHLOBBY_LIB="$W/nolib" cli --version; rc_is 1; has "$ERR" "missing module: $W/nolib/core.sh"   # vor dem Laden der Sprache: immer Englisch
  mkdir -p "$W/alt"; cp -r "$ROOT/lib" "$W/alt/lib"; sed -i 's/^usage() {/usage() { echo ALT-LIB;/' "$W/alt/lib/cli.sh"
  SSHLOBBY_LIB="$W/alt/lib" cli --help; rc_is 0; has "$OUT" "ALT-LIB"
}
t_tools_extension_loaded() {                        # lib/tools_*.sh werden automatisch geladen
  mkdir -p "$W/alt"; cp -r "$ROOT/lib" "$W/alt/lib"
  cat > "$W/alt/lib/tools_demo.sh" <<'EOF'
_demo_run() { ui_note ok "DEMO-LAEUFT"; }
tool_register demo "Demo-Werkzeug" "nur im Test" "layered" - _demo_run
EOF
  SSHLOBBY_LIB="$W/alt/lib" menu '7\n10\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "10) Demo-Werkzeug"; setup_is_last; has "$OUT" "DEMO-LAEUFT"
}

t_header_sys_values_from_tools_root() {          # Kopfzeile liest /proc über PD_TOOLS_ROOT (wie die Werkzeuge)
  conf "MODE=docker"; export PD_TOOLS_ROOT="$PD_FIX/tools/root"
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" "up 37 T 5 h · load 0.42 0.37 0.31 · RAM 5.2/8Gi"
}
