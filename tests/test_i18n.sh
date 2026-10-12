# shellcheck shell=bash
# shellcheck disable=SC2016 # Code in bash -c läuft erst im Kindprozess
# Sprachen: lang/*.txt vollständig (jeder Key mit en und de, gleiche Platzhalter), alle im Code
# benutzten Keys vorhanden, Fallback auf en, Sprachwahl in den Einstellungen.

i18n_table() { # → key<TAB>lang<TAB>text für alle Zeilen aller Sprachdateien
  awk '/^[[:space:]]*(#|$)/ { next }
    /^\[/ { key = $0; sub(/^\[/, "", key); sub(/\][[:space:]]*$/, "", key); next }
    match($0, /^[[:space:]]*[a-z][a-z][[:space:]]*=/) { l = $0; sub(/^[[:space:]]*/, "", l)
      v = substr($0, RLENGTH + 1); sub(/^[[:space:]]+/, "", v); print key "\t" substr(l, 1, 2) "\t" v }' "$ROOT"/lang/*.txt
}

t_i18n_file_complete() {                            # jeder Key: en + de, Platzhalter gleich, keine Doppel
  local bad
  bad=$(awk '/^\[/ { k = $0; sub(/^\[/, "", k); sub(/\][[:space:]]*$/, "", k)
      if (!(k ~ /^[a-z0-9_.]+$/)) print "Key-Format: " k; if (seen[k]++) print "doppelt: " k }' "$ROOT"/lang/*.txt)
  [ -z "$bad" ] || die "$bad"
  bad=$(i18n_table | awk -F'\t' '{ keys[$1] = 1; has[$1, $2] = 1; v = $3; ph = ""
        while (match(v, /%[-0-9.]*[sd%]/)) { ph = ph substr(v, RSTART, RLENGTH); v = substr(v, RSTART + RLENGTH) }
        p[$1, $2] = ph }
      END { for (k in keys) { if (!((k, "en") in has)) print "ohne en: " k; if (!((k, "de") in has)) print "ohne de: " k
            else if (p[k, "de"] != p[k, "en"]) print "Platzhalter de≠en: " k } }' | sort)
  [ -z "$bad" ] || die "$bad"
}

t_i18n_used_keys_exist() {                         # TX[key], t key, tf var key im Code → Key in lang/
  local missing
  missing=$(cat "$ROOT"/sshlobby.sh "$ROOT"/lib/*.sh | grep -v '^[[:space:]]*#' |
    grep -oE 'TX\[[a-z0-9_.]+\]|(^|[^a-zA-Z_])t [a-z][a-z0-9_]*\.[a-z0-9_.]+|tf [A-Za-z_][A-Za-z0-9_]* [a-z][a-z0-9_]*\.[a-z0-9_.]+' |
    sed -E 's/^TX\[//; s/\]$//; s/^.*t //; s/^tf [A-Za-z0-9_]+ //' | sort -u |
    while read -r k; do grep -qxF "[$k]" "$ROOT"/lang/*.txt || echo "$k"; done)
  [ -z "$missing" ] || die "Keys fehlen in lang/: $missing"
}

t_i18n_fallback_and_invalid() {                    # fehlende Übersetzung → en, ungültiger Code → en
  mkdir -p "$W/lang"
  printf '%s\n' '[a.b]' 'en = english text' 'xx = xx-Text' '[a.c]' 'en = only english %s' > "$W/lang/strings.txt"
  local out
  out=$(SSHLOBBY_LANG=xx bash -c 'CONF_FILE=/nonexistent; . "$1/lib/core.sh"; PD_LANGDIR=$2; i18n_detect; i18n_load
    printf "%s|%s|%s\n" "$PD_LANG" "${TX[a.b]}" "$(t a.c 42)"' _ "$ROOT" "$W/lang")
  eq "$out" "xx|xx-Text|only english 42"
  out=$(SSHLOBBY_LANG='../x' bash -c 'CONF_FILE=/nonexistent; . "$1/lib/core.sh"; PD_LANGDIR=$2; i18n_detect; i18n_load; echo "$PD_LANG"' _ "$ROOT" "$W/lang")
  eq "$out" "en"
}

t_i18n_language_from_config_and_locale() {
  local out
  printf 'LANGUAGE=en\n' > "$CONF/config"
  out=$(env -u SSHLOBBY_LANG bash -c 'CONF_FILE=$2; . "$1/lib/core.sh"; i18n_detect; echo "$PD_LANG $PD_LANG_SRC"' _ "$ROOT" "$CONF/config")
  eq "$out" "en config"
  : > "$CONF/config"
  out=$(env -u SSHLOBBY_LANG LC_ALL=de_DE.UTF-8 bash -c 'CONF_FILE=$2; . "$1/lib/core.sh"; i18n_detect; echo "$PD_LANG $PD_LANG_SRC"' _ "$ROOT" "$CONF/config")
  eq "$out" "de locale"
}

t_i18n_settings_switch() {                         # Einstellungen → Sprache → English (Zeilenmodus: ab nächstem Start)
  # Sprache aus Config/Locale statt aus der Test-Umgebung. LANG statt LC_ALL: ohne erzeugte de_DE-Locale
  # schreibt bash bei LC_ALL eine setlocale-Warnung nach stderr, bei LANG nicht
  unset SSHLOBBY_LANG LC_ALL LC_MESSAGES LC_CTYPE; export LANG=de_DE.UTF-8
  conf "MODE=docker"
  menu 'e\nb\nq\n'; local s; s=$(st_nr "Sprache / Language"); [ -n "$s" ] || die "kein Spracheintrag:\n$OUT"
  menu "e\n$s\nb\nb\nq\n"; rc_is 20; no_err; has "$OUT" "automatisch (Systemsprache"; has "$OUT" "English"
  local n; n=$(awk '/┌─ Sprache \/ Language/ { f = 1 } f && /\) English/ { match($0, /[0-9]+\)/); print substr($0, RSTART, RLENGTH - 1); exit }' <<< "$OUT")
  [ -n "$n" ] || die "English nicht wählbar:\n$OUT"
  menu "e\n$s\n$n\nb\nq\n"; rc_is 20; no_err
  cfg_has "LANGUAGE=en"; has "$OUT" "Language: English. Takes effect on the next start."
}

t_i18n_langdir_fallback_without_lang_next_to_lib() { # SSHLOBBY_LIB auf eine Kopie ohne lang/ → lang/ neben dem Starter
  mkdir -p "$W/alt"; cp -r "$ROOT/lib" "$W/alt/lib"
  printf '%s\n' '_fb_run() { ui_note ok "${TX[lang.name]}-FB"; }' 'tool_register fb "${TX[lang.name]}-Werkzeug" "x" "docker layered incus" - _fb_run' > "$W/alt/lib/tools_fb.sh"
  conf "MODE=docker"
  SSHLOBBY_LIB="$W/alt/lib" menu 'q\n'; rc_is 20; no_err
}
