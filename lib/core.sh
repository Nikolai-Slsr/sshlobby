# shellcheck shell=bash
# core.sh: Konfiguration, Zustand (Verlauf, Favoriten), Beschreibungen, Systemwerte und kleine
# Hilfsfunktionen. Keine Terminal-Ausgabe, keine incus/docker-Aufrufe.
# shellcheck disable=SC2034 # Globals werden in anderen Modulen gelesen

# ─── Exit-Codes des Menüs ──────────────────────────────────────────────────
# Nur 20 loggt im Bashrc-Hook aus; EOF, Absturz, s usw. landen in der Shell.
PD_EXIT_OK=0
PD_EXIT_ERR=1
PD_EXIT_USAGE=2
PD_EXIT_UPDATE=3    # sshlobby update: neueres Release gefunden, aber nicht installiert (--check, Nein)
PD_EXIT_SHELL=10
PD_EXIT_LOGOUT=20

CONF_DIR="$HOME/.config/sshlobby"
CONF_FILE="$CONF_DIR/config"
# Anzeige: Pfade unter $HOME als ~/… (kürzer, und Screenshots verraten keinen Home-Pfad)
CONF_FILE_SHOW=$CONF_FILE
[ -n "${HOME:-}" ] && [[ $CONF_FILE == "$HOME"/* ]] && CONF_FILE_SHOW="~${CONF_FILE#"$HOME"}"
RECENTS="$CONF_DIR/recents"
FAVORITES="$CONF_DIR/favorites"
DESCRIPTIONS="$CONF_DIR/descriptions"

MODE=""        # docker | incus | layered (gesetzt von mode_resolve in setup.sh)

# ─── Sprache ───────────────────────────────────────────────────────────────
# Texte stehen in lang/*.txt (Format dort im Kopf). Beim Start: i18n_detect wählt die Sprache
# (SSHLOBBY_LANG, sonst LANGUAGE aus der Config, sonst Systemsprache de* → de, sonst en),
# i18n_load füllt TX[key] (Basis en, darüber die gewählte Sprache). Zugriff:
#   "${TX[key]}"            fester Text (kein Subshell-Fork, für heiße Pfade)
#   tf var key args…        formatierten Text in eine Variable (printf -v)
#   t key args…             formatierten Text ausgeben (für $(…) außerhalb heißer Pfade)
declare -gA TX=()
PD_LANG=en PD_LANG_SRC=locale
PD_LANGDIR=${SSHLOBBY_LANGDIR:-}
i18n_sys_lang() { case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in de*) printf de;; *) printf en;; esac; }
i18n_detect() {
  local l=${SSHLOBBY_LANG:-} src=env
  if [ -z "$l" ] && [ -r "$CONF_FILE" ]; then
    l=$(awk -F= '/^[[:space:]]*LANGUAGE[[:space:]]*=/ { v = $2; gsub(/[[:space:]"\047]/, "", v); last = v } END { print last }' "$CONF_FILE")
    src=config
  fi
  [ -n "$l" ] || { l=$(i18n_sys_lang); src="locale"; }
  [[ $l =~ ^[a-z]{2}$ ]] || { l=en; src="locale"; }
  PD_LANG=$l PD_LANG_SRC=$src
}
# lang/*.txt lesen: pro Key die Zeile der gewählten Sprache, sonst en. Ausgabe key<TAB>text.
i18n_load() {
  local k v
  TX=()
  while IFS=$'\t' read -r k v; do TX[$k]=$v; done < <(awk -v want="$PD_LANG" '
    /^[[:space:]]*(#|$)/ { next }
    /^\[[a-z0-9_.]+\][[:space:]]*$/ { key = $0; sub(/^\[/, "", key); sub(/\][[:space:]]*$/, "", key); next }
    key != "" && match($0, /^[[:space:]]*[a-z][a-z][[:space:]]*=/) {
      lang = $0; sub(/^[[:space:]]*/, "", lang); lang = substr(lang, 1, 2)
      val = substr($0, RLENGTH + 1); sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val)
      if (lang == "en" && !(key in en)) { en[key] = val; order[++n] = key }
      if (lang == want) mine[key] = val
    }
    END { for (i = 1; i <= n; i++) { k = order[i]; print k "\t" ((k in mine) ? mine[k] : en[k]) } }' "$PD_LANGDIR"/*.txt 2>/dev/null)
}
i18n_langs() { # alle Sprachcodes, die in lang/*.txt vorkommen (en zuerst)
  awk '/^\[/ { next } match($0, /^[[:space:]]*[a-z][a-z][[:space:]]*=/) { l = $0; sub(/^[[:space:]]*/, "", l); seen[substr(l, 1, 2)] = 1 }
    END { if ("en" in seen) print "en"; for (l in seen) if (l != "en") print l }' "$PD_LANGDIR"/*.txt 2>/dev/null | { read -r first; echo "$first"; sort; }
}
# shellcheck disable=SC2059 # das Format kommt absichtlich aus der Sprachdatei
t() { local f=${TX[$1]-$1}; shift; printf -- "$f" "$@"; }                  # key args… → Ausgabe
# shellcheck disable=SC2059
tf() { local _v=$1 f=${TX[$2]-$2}; shift 2; printf -v "$_v" -- "$f" "$@"; } # var key args…
PD_INT=0       # 1 nach Ctrl-C im letzten Vordergrundbefehl
declare -gA PD_DESC=()

have() { command -v "$1" >/dev/null 2>&1; }
mode_valid() { case "${1:-}" in docker|incus|layered) return 0;; esac; return 1; }

# ─── Config ────────────────────────────────────────────────────────────────
# ~/.config/sshlobby/config: KEY=wert, eine Zuweisung pro Zeile, # Kommentar. Wird nie per
# source geladen; nur bekannte Keys, ungültige Werte und kaputte Zeilen werden ignoriert.
#   MODE        docker | incus | layered
#   HOST_LABEL  Name im Header (Default: hostname -s)
#   CVE_CT      Incus-CT des CVE-Monitors (leer = Werkzeug aus)
#   CVE_DIR     Alert-Ordner im CVE-CT (Default /opt/cve-monitor/alerts)
#   SSH_HOSTS   Ziele für „Anderer Server (SSH)“, durch Leerzeichen getrennt
#   AUTOSTART   yes | no: beim SSH-Login starten (Hook setzt SSHLOBBY_LOGIN=1), Default yes
#   Q_ACTION    logout | shell: Taste q im Hauptmenü, Default logout
#   UI          auto | line: line = immer Zeilenmodus (SSHLOBBY_UI hat Vorrang), Default auto
#   COLOR       auto | never: never wirkt wie NO_COLOR, Default auto
#   SYMBOLS     auto | ascii: ascii = keine Unicode-Symbole und Rahmen, Default auto
#   RECENT_MAX  0–10: Einträge unter „Zuletzt“, 0 = ausblenden, Default 5
#   HERMES_SCAN_CTS  yes | no: Werkzeug Hermes-Instanzen durchsucht auch Incus-CTs, Default yes
#   LANGUAGE    Sprachcode aus lang/*.txt (de, en, …), leer = Systemsprache (gelesen von i18n_detect)
#   UPDATE_CHECK  yes | no: einmal am Tag nach einem neuen Release suchen und im Hauptmenü darauf
#               hinweisen (SSHLOBBY_UPDATE_CHECK hat Vorrang; =yes prüft auch ohne Terminal), Default yes
#   UPDATE_REPO GitHub-Repo owner/name, dessen Releases sshlobby update installiert
UPD_DEFAULT_REPO="Nikolai-Slsr/sshlobby"
cfg_load() {
  local line key val re_skip='^[[:space:]]*(#|$)' re_kv='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$'
  local -a words ok
  CFG_MODE="" CFG_EXISTS=0 CFG_ERRORS=0
  HOST_LABEL="" CVE_CT="" CVE_DIR="/opt/cve-monitor/alerts" SSH_HOSTS=""
  LANG_PREF="" AUTOSTART=yes Q_ACTION=logout UI_PREF=auto COLOR_PREF=auto SYMBOLS_PREF=auto RECENT_MAX=5 HERMES_SCAN_CTS=yes
  UPDATE_CHECK=yes UPDATE_REPO=$UPD_DEFAULT_REPO
  if [ -r "$CONF_FILE" ]; then
    CFG_EXISTS=1
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line%$'\r'}
      [[ $line =~ $re_skip ]] && continue
      if ! [[ $line =~ $re_kv ]]; then CFG_ERRORS=$((CFG_ERRORS+1)); continue; fi
      key=${BASH_REMATCH[1]} val=${BASH_REMATCH[2]}
      val=${val#"${val%%[![:space:]]*}"}; val=${val%"${val##*[![:space:]]}"}
      if [ ${#val} -ge 2 ] && { [[ $val == \"*\" ]] || [[ $val == \'*\' ]]; }; then val=${val:1:-1}; fi
      case "$key" in
        MODE)       if mode_valid "$val"; then CFG_MODE=$val; else CFG_ERRORS=$((CFG_ERRORS+1)); fi;;
        HOST_LABEL) HOST_LABEL=${val:0:40};;
        CVE_CT)     if [[ $val =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then CVE_CT=$val; else CVE_CT=""; fi;;
        CVE_DIR)    [[ $val == /* ]] && CVE_DIR=$val;;
        SSH_HOSTS)  # nur harmlose Zielnamen, nichts was ssh als Option lesen könnte
                    read -ra words <<< "$val"; ok=()
                    for val in "${words[@]}"; do [[ $val =~ ^[A-Za-z0-9_][A-Za-z0-9._@:-]*$ ]] && ok+=("$val"); done
                    SSH_HOSTS="${ok[*]}";;
        AUTOSTART)  [[ $val =~ ^(yes|no)$ ]] && AUTOSTART=$val;;
        Q_ACTION)   [[ $val =~ ^(logout|shell)$ ]] && Q_ACTION=$val;;
        UI)         [[ $val =~ ^(auto|line)$ ]] && UI_PREF=$val;;
        COLOR)      [[ $val =~ ^(auto|never)$ ]] && COLOR_PREF=$val;;
        SYMBOLS)    [[ $val =~ ^(auto|ascii)$ ]] && SYMBOLS_PREF=$val;;
        RECENT_MAX) [[ $val =~ ^([0-9]|10)$ ]] && RECENT_MAX=$val;;
        HERMES_SCAN_CTS) [[ $val =~ ^(yes|no)$ ]] && HERMES_SCAN_CTS=$val;;
        LANGUAGE)   [[ $val =~ ^[a-z]{2}$ ]] && LANG_PREF=$val;;
        UPDATE_CHECK) [[ $val =~ ^(yes|no)$ ]] && UPDATE_CHECK=$val;;
        UPDATE_REPO)  [[ $val =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.][A-Za-z0-9_.-]*$ && $val != *..* ]] && UPDATE_REPO=$val;;
        *) ;; # unbekannter Key: ignorieren
      esac
    done < "$CONF_FILE"
  fi
  case "${SSHLOBBY_UPDATE_CHECK:-}" in yes|no) UPDATE_CHECK=$SSHLOBBY_UPDATE_CHECK;; esac
  PD_HOST=$(hostname -s 2>/dev/null) || PD_HOST=""
  [ -n "$PD_HOST" ] || PD_HOST=server
  [ -n "$HOST_LABEL" ] || HOST_LABEL=$PD_HOST
}

# Einen Key setzen, alle anderen Zeilen (Kommentare, unbekannte Keys) bleiben unverändert.
cfg_set() { # key wert
  local tmp
  [[ $2 == *$'\n'* ]] && return 1
  mkdir -p "$CONF_DIR" 2>/dev/null || return 1
  tmp=$(mktemp "$CONF_FILE.XXXXXX") || return 1
  if [ -f "$CONF_FILE" ]; then
    K="$1" V="$2" awk '
      BEGIN { k=ENVIRON["K"]; v=ENVIRON["V"] }
      $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { if (!done) print k "=" v; done=1; next }
      { print }
      END { if (!done) print k "=" v }' "$CONF_FILE" > "$tmp"
  else
    { printf '# %s\n' "${TX[core.config.header]}"
      printf '%s=%s\n' "$1" "$2"
      printf '# HOST_LABEL=%s\n# CVE_CT=security\n# CVE_DIR=/opt/cve-monitor/alerts\n# SSH_HOSTS="host1 host2"\n' "$PD_HOST"
    } > "$tmp"
  fi
  mv "$tmp" "$CONF_FILE" || { rm -f "$tmp"; return 1; }
}

# ─── Beschreibungen ────────────────────────────────────────────────────────
# ~/.config/sshlobby/descriptions: "name|Text", gilt für CTs, Compose-Projekte und Container.
desc_load() {
  local line name
  PD_DESC=()
  [ -r "$DESCRIPTIONS" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ $line == *'|'* ]] || continue
    name=${line%%|*}; name=${name//[[:space:]]/}
    [ -z "$name" ] || [[ $name == \#* ]] && continue
    PD_DESC[$name]=${line#*|}
  done < "$DESCRIPTIONS"
}

# ─── Verlauf / Favoriten ───────────────────────────────────────────────────
# recents:   epoch|gruppe|ziel|aktion   favorites: gruppe|ziel
# gruppe = CT (incus, layered) bzw. Compose-Projekt oder "-" (docker), "@tool" = Werkzeug
# ziel   = Docker-Container, Werkzeug-id oder "-" (CT selbst bzw. ganzes Compose-Projekt)
# aktion = shell logs compose (Container), ctshell (CT), project (Compose-Projekt), tool
# Exakter Feldvergleich, Dateien werden immer atomar ersetzt.
state_add_recent() { # gruppe ziel aktion
  local tmp
  mkdir -p "$CONF_DIR" 2>/dev/null || return 0
  tmp=$(mktemp "$RECENTS.XXXXXX") || return 0
  { [ -f "$RECENTS" ] && awk -F'|' -v g="$1" -v c="$2" '!($2==g && $3==c)' "$RECENTS"
    printf '%s|%s|%s|%s\n' "$(date +%s)" "$1" "$2" "$3"; } | tail -n 200 > "$tmp" && mv "$tmp" "$RECENTS"
}

state_del_recent() { # gruppe ziel → Eintrag aus dem Verlauf entfernen
  local tmp
  [ -f "$RECENTS" ] || return 0
  tmp=$(mktemp "$RECENTS.XXXXXX") || return 0
  awk -F'|' -v g="$1" -v c="$2" '!($2==g && $3==c)' "$RECENTS" > "$tmp" && mv "$tmp" "$RECENTS"
}

# Gültige Einträge, neueste zuerst, je gruppe|ziel nur einmal. Neue Einträge stehen hinten in der
# Datei: umgedreht + stabile Sortierung hält Einträge aus derselben Sekunde in der richtigen Reihenfolge.
state_recents() {
  [ -f "$RECENTS" ] || return 0
  awk -F'|' 'NF==4 && $1~/^[1-9][0-9]*$/ && $2!="" && $3!="" { l[++n]=$0 } END { while (n) print l[n--] }' \
    "$RECENTS" | sort -s -t'|' -k1,1rn | awk -F'|' '!seen[$2"|"$3]++'
}

state_favorites() {
  [ -f "$FAVORITES" ] || return 0
  awk -F'|' 'NF==2 && $1!="" && $2!=""' "$FAVORITES"
}

is_fav() { grep -qxF -- "$1|$2" "$FAVORITES" 2>/dev/null; }

fav_toggle() { # gruppe ziel
  local tmp
  if is_fav "$1" "$2"; then
    tmp=$(mktemp "$FAVORITES.XXXXXX") || return 0
    awk -v k="$1|$2" '$0!=k' "$FAVORITES" > "$tmp" && mv "$tmp" "$FAVORITES"
  else
    mkdir -p "$CONF_DIR" 2>/dev/null && printf '%s|%s\n' "$1" "$2" >> "$FAVORITES"
  fi
}

rel_time() { # epoch → "vor 5 min"
  local diff=$(( $(date +%s) - $1 ))
  if   [ $diff -lt 60 ]; then t core.time.just_now
  elif [ $diff -lt 3600 ]; then t core.time.min_ago $((diff/60))
  elif [ $diff -lt 86400 ]; then t core.time.hours_ago $((diff/3600))
  else t core.time.days_ago $((diff/86400)); fi
}

# ─── Systemwerte für den Header ────────────────────────────────────────────
sys_stats() { # → SYS_UP SYS_LOAD SYS_NCPU SYS_RAM_PCT SYS_RAM SYS_DISK_PCT SYS_DISK
  local up="" pr=${PD_TOOLS_ROOT:-}/proc # Testwurzel wie bei den Werkzeugen (tp), sonst /proc
  { read -r up _ < "$pr/uptime"; } 2>/dev/null; up=${up%%.*}
  if ! [[ $up =~ ^[0-9]+$ ]]; then SYS_UP="?"
  elif [ "$up" -ge 86400 ]; then SYS_UP="$((up / 86400)) ${TX[core.unit.days]} $((up % 86400 / 3600)) h"
  elif [ "$up" -ge 3600 ]; then SYS_UP="$((up / 3600)) h $((up % 3600 / 60)) min"
  else SYS_UP="$((up / 60)) min"; fi
  SYS_NCPU=$(grep -c '^processor' "$pr/cpuinfo" 2>/dev/null); [[ $SYS_NCPU =~ ^[1-9][0-9]*$ ]] || SYS_NCPU=1
  SYS_LOAD=$(cut -d' ' -f1-3 "$pr/loadavg" 2>/dev/null)
  # /proc/meminfo statt free: free ist lokalisiert ("Speicher:" statt "Mem:")
  read -r SYS_RAM_PCT SYS_RAM < <(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2}
    END{if (t>0) printf "%d %.1f/%.0fGi\n", (t-a)*100/t, (t-a)/1048576, t/1048576}' "$pr/meminfo" 2>/dev/null)
  [[ "${SYS_RAM_PCT:-}" =~ ^[0-9]+$ ]] || { SYS_RAM_PCT=0; SYS_RAM="?"; }
  read -r SYS_DISK_PCT SYS_DISK < <(df -h / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5, $3"/"$2}')
  [[ "${SYS_DISK_PCT:-}" =~ ^[0-9]+$ ]] || { SYS_DISK_PCT=0; SYS_DISK="?"; }
}
