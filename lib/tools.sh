# shellcheck shell=bash
# tools.sh: Werkzeug-Registry und die aus v1.1 portierten Werkzeuge.
#
# Registry-API:
#   tool_register id titel beschreibung modi verfügbar-fn run-fn [prio]
#     modi        Leerzeichen-Liste aus docker incus layered, oder all
#     verfügbar-fn  Funktion ohne Argumente, 0 = anzeigen ("-" = immer verfügbar)
#     run-fn      Funktion ohne Argumente, läuft im Werkzeug-Menü (nutzt ui_* für Ausgaben)
#     prio        Sortierung im Menü (Default 50; v1.1-Werkzeuge 10–18, Setup 90)
#   tool_list            ids der im aktuellen Modus verfügbaren Werkzeuge, sortiert
#   tool_available id    0 wenn im aktuellen Modus sichtbar
#   tool_run id          Werkzeug ausführen; setzt das Werkzeug PD_RELOAD=1, kehrt das Menü
#                        danach ins Hauptmenü zurück (z. B. nach Moduswechsel)
# Weitere Werkzeuge gehören in eigene Dateien lib/tools_<name>.sh, die der Starter automatisch
# nach dieser Datei lädt (Reihenfolge nach Dateiname, Anzeige nach prio). Gemeinsame Helfer für
# deren Seiten (tl_*, tp, tq) stehen unten unter „Hilfen für Werkzeuge“, Nutzer-Doku: docs/TOOLS.md.
# shellcheck disable=SC2034,SC1111 # TOOL_* liest screens.sh (SC1111: „…“ sind gewollte Anführungszeichen)

declare -ga TOOL_IDS=()
declare -gA TOOL_TITLE=() TOOL_DESC=() TOOL_MODES=() TOOL_AVAIL=() TOOL_RUN=() TOOL_PRIO=()
PD_RELOAD=0

tool_register() { # id titel beschreibung modi verfügbar-fn run-fn [prio]
  local id=$1
  [ -n "${TOOL_TITLE[$id]+x}" ] || TOOL_IDS+=("$id")
  TOOL_TITLE[$id]=$2 TOOL_DESC[$id]=$3 TOOL_MODES[$id]=$4 TOOL_AVAIL[$id]=$5 TOOL_RUN[$id]=$6
  TOOL_PRIO[$id]=${7:-50}
}
tool_available() { # id
  local m=" ${TOOL_MODES[$1]:-} " f=${TOOL_AVAIL[$1]:--}
  [[ $m == *" all "* || $m == *" $MODE "* ]] || return 1
  [ "$f" = "-" ] || "$f"
}
tool_list() {
  local id i=0
  for id in "${TOOL_IDS[@]}"; do
    i=$((i+1)); tool_available "$id" && printf '%03d %03d %s\n' "${TOOL_PRIO[$id]}" "$i" "$id"
  done | sort | awk '{print $3}'
}
tool_run() { # id: ausführen und im Verlauf merken (Gruppe "@tool", Setup nicht)
  [ "$1" = setup ] || state_add_recent "@tool" "$1" tool
  "${TOOL_RUN[$1]}"
}

# ─── 1 Incus-Übersicht ─────────────────────────────────────────────────────
_t_incus_avail() { have incus; }
_t_incus_overview() { ui_run_page "${TX[tools.incus_overview.page]}" incus list -c nsm4; }

# ─── 2 RAM / Disk / Top-Prozesse ───────────────────────────────────────────
_t_sysinfo() {
  local mt ma st sf pct line v
  read -r mt ma st sf < <(tl_meminfo)
  tl_head "${TX[tools.sysinfo.mem_head]}"
  if [ "${mt:-0}" -gt 0 ]; then
    pct=$(( (mt - ma) * 100 / mt ))
    tf v tools.sysinfo.used_of "$(tl_human $(( (mt - ma) * 1024 )))" "$(tl_human $((mt * 1024)))" "$pct"
    tl_kv "${TX[tools.sysinfo.ram_used]}" "$v" "$(tl_lvl "$pct" 80 90)"
  fi
  if [ "${st:-0}" -gt 0 ]; then
    pct=$(( (st - sf) * 100 / st ))
    tf v tools.sysinfo.used_of "$(tl_human $(( (st - sf) * 1024 )))" "$(tl_human $((st * 1024)))" "$pct"
    tl_kv "${TX[tools.sysinfo.swap_used]}" "$v" "$(tl_lvl "$pct" 60 90)"
  else
    tl_kv "${TX[tools.sysinfo.swap]}" "${TX[tools.sysinfo.no_swap]}"
  fi
  if [ "${st:-0}" -gt 0 ] && [ "$sf" -lt "$st" ]; then
    tl_head "${TX[tools.sysinfo.swap_head]}"
    line=$(tl_swap_top 8)
    if [ -n "$line" ]; then printf '%s\n' "$line"; else tl_dim "${TX[tools.sysinfo.swap_no_data]}"; fi
  fi
  tl_head "${TX[tools.sysinfo.fs_head]}"
  tl_df_page
  tl_head "${TX[tools.sysinfo.top_ram]}"
  ps -eo pid,user,%mem,%cpu,rss,comm --sort=-%mem 2>/dev/null | head -n 9 | sed 's/^/  /'
  tl_head "${TX[tools.sysinfo.top_cpu]}"
  ps -eo pid,user,%cpu,%mem,etime,comm --sort=-%cpu 2>/dev/null | head -n 6 | sed 's/^/  /'
}
_t_sysinfo_run() { ui_run_page "${TX[tools.sysinfo.title]}" _t_sysinfo; }

# ─── 3 Fehler-Log ──────────────────────────────────────────────────────────
# Fehlgeschlagene Units, Fehler der letzten 24 h nach Unit, Container-Probleme, dann die letzten
# 40 Meldungen wie bisher.
_t_errlog_avail() { have journalctl; }
_t_errlog_page() {
  local n unit t d msg lvl where name text v
  if have systemctl; then
    tl_head "${TX[tools.errlog.failed_head]}"
    n=0
    while IFS=$'\t' read -r unit msg; do
      [ -n "$unit" ] || continue
      n=$((n+1)); tl_line err "$(tl_pad "$unit" 34) $msg"
    done < <(tl_failed_units)
    [ "$n" -gt 0 ] || tl_line ok "${TX[tools.none]}"
  fi
  tl_head "${TX[tools.errlog.by_unit_head]}"
  n=0
  while IFS=$'\t' read -r cnt unit t d msg; do
    [ -n "$unit" ] || continue
    n=$((n+1))
    printf '  %s%5s×%s %s %s%s%s  %s\n' "$C_YLW" "$cnt" "$C_R" "$(tl_pad "$unit" 28)" "$C_D" \
      "$(date -d "@$t" '+%d.%m. %H:%M' 2>/dev/null)" "$C_R" "$(tl_cut "$msg" 90)"
    [ "$d" -gt 1 ] && { tf v tools.errlog.distinct "$d"; tl_dim "        $(printf '%35s' '')$v"; }
  done < <(tl_journal_errs)
  [ "$n" -gt 0 ] || tl_line ok "${TX[tools.none]}"
  if [ "$MODE" != incus ] && { have docker || have incus; }; then
    tl_head "${TX[tools.errlog.ctr_head]}"
    n=0
    while IFS='|' read -r lvl where name text; do
      [ -n "$name" ] || continue
      n=$((n+1)); tl_line "$lvl" "$(tl_pad "${where:+$where/}$name" 30) $text"
    done < <(tl_ctr_issues)
    [ "$n" -gt 0 ] || tl_line ok "${TX[tools.none]}"
  fi
  tl_head "${TX[tools.errlog.last_head]}"
  journalctl -p err -n 40 --no-pager
}
_t_errlog() { ui_run_page "${TX[tools.errlog.page]}" _t_errlog_page; }

# ─── 4 Docker-Health: eigene Datei lib/tools_health.sh ─────────────────────

# ─── 5 Anderer Server (SSH) ────────────────────────────────────────────────
# Ziele aus SSH_HOSTS, sonst die Host-Einträge aus ~/.ssh/config (ohne Wildcards und Negationen).
_t_ssh_hosts() { # → "host|beschreibung" pro Zeile
  local h
  if [ -n "$SSH_HOSTS" ]; then
    local -a hs; read -ra hs <<< "$SSH_HOSTS"
    for h in "${hs[@]}"; do printf '%s|ssh %s\n' "$h" "$h"; done
    return 0
  fi
  [ -r "$HOME/.ssh/config" ] || return 0
  awk '{ sub(/\r$/, ""); k = tolower($1) }
    k == "host" { n = 0
      for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/ && $i ~ /^[A-Za-z0-9_][A-Za-z0-9._@:-]*$/) {
        cur[++n] = $i; if (!($i in seen)) { seen[$i] = 1; order[++m] = $i } }
      next }
    k == "match" { n = 0; next }
    k == "hostname" || k == "user" { for (i = 1; i <= n; i++) if (!((cur[i], k) in info)) info[cur[i], k] = $2 }
    END { for (i = 1; i <= m; i++) { h = order[i]; u = info[h, "user"]; d = info[h, "hostname"]
            printf "%s|ssh %s%s\n", h, h, (d != "" ? " · " (u != "" ? u "@" : "") d : "") } }' "$HOME/.ssh/config"
}
_t_ssh_avail() { have ssh && [ -n "$(_t_ssh_hosts)" ]; }
_t_ssh() {
  local -a hosts; local h sub=${TX[tools.ssh.sub_config]} v
  mapfile -t hosts < <(_t_ssh_hosts)
  [ ${#hosts[@]} -gt 0 ] || return 0
  [ -n "$SSH_HOSTS" ] || sub=${TX[tools.ssh.sub_ssh_config]}
  h=${hosts[0]%%|*}
  if [ ${#hosts[@]} -gt 1 ] || [ -z "$SSH_HOSTS" ]; then
    for h in "${hosts[@]}"; do ui_item item "${h%%|*}" "${h%%|*}" "${h#*|}"; done
    ui_menu "${TX[tools.ssh.title]}" "$sub"
    [ "$UI_ACT" = select ] || return 0
    h=$UI_SEL
  fi
  ui_run_fg ssh "$h"
  tf v tools.ssh.back "$h"; ui_note info "$v"
}

# ─── 6 Mutagen ─────────────────────────────────────────────────────────────
_t_mutagen_avail() { have mutagen; }
_t_mutagen_list() { mutagen sync list 2>&1 | grep -E 'Name:|Status:|Conflicts|rror' | head -12; }
_t_mutagen() { ui_run_page "${TX[tools.mutagen.title]}" _t_mutagen_list; }

# ─── 7 CVE-Monitor ─────────────────────────────────────────────────────────
# Neue Alerts liegen direkt in CVE_DIR im CT CVE_CT, bearbeitete in archive/
_t_cve_avail() { [ -n "$CVE_CT" ] && have incus; }
_t_cve_alerts() {
  local st out v
  printf '%s%s%s %s(%s:%s)%s\n' "$C_B" "${TX[tools.cve.head]}" "$C_R" "$C_D" "$CVE_CT" "$CVE_DIR" "$C_R"
  ct_load; st=$(ct_status "$CVE_CT")
  if [ -z "$st" ]; then tf v tools.cve.not_found "$CVE_CT"; printf '  %s%s%s\n' "$C_RED" "$v" "$C_R"; return 0; fi
  if [ "$st" != "Running" ]; then tf v tools.cve.not_running "$CVE_CT" "$st"; printf '  %s%s%s\n' "$C_RED" "$v" "$C_R"; return 0; fi
  if ! out=$(incus exec "$CVE_CT" -- ls -lt -- "$CVE_DIR" </dev/null 2>&1); then
    printf '  %s%s%s %s\n' "$C_RED" "${TX[tools.cve.unreadable]}" "$C_R" "$out"; return 0
  fi
  out=$(printf '%s\n' "$out" | grep '^-') # nur Dateien: "total" und archive/ fallen raus
  if [ -z "$out" ]; then printf '  %s✓ %s%s\n' "$C_GRN" "${TX[tools.cve.none]}" "$C_R"; return 0; fi
  tf v tools.cve.count "$(printf '%s\n' "$out" | wc -l)"; printf '  %s%s%s\n' "$C_YLW" "$v" "$C_R"
  printf '%s\n' "$out" | head -10
}
_t_cve() { ui_run_page "${TX[tools.cve.page]}" _t_cve_alerts; }

# ─── 8 Incus-Ressourcen ────────────────────────────────────────────────────
_t_incus_res_list() { incus list -c ns4dM --format table 2>&1 | head -15; }
_t_incus_res() { ui_run_page "${TX[tools.incus_res.title]}" _t_incus_res_list; }

# ─── 9 Neues Projekt (Incus-CT ohne Docker) ────────────────────────────────
_t_new_ct() {
  local -a imgs; local i img desc size name v
  mapfile -t imgs < <(ct_images)
  if [ ${#imgs[@]} -eq 0 ]; then ui_msg err "${TX[tools.new_ct.no_images]}"; return 0; fi
  ui_item header "" "${TX[tools.new_ct.images]}" "" main
  for i in "${!imgs[@]}"; do
    IFS='|' read -r img desc size <<< "${imgs[i]}"
    ui_item item "$i" "$img" "${desc:+$desc · }$size"
  done
  ui_menu "${TX[tools.new_ct.menu]}" "${TX[tools.new_ct.menu_sub]}"
  [ "$UI_ACT" = select ] || return 0
  img=${imgs[UI_SEL]%%|*}
  while true; do
    ui_input "${TX[tools.new_ct.name]}" || return 0
    name=$UI_INPUT
    [ -z "$name" ] && return 0
    if ! ct_valid_name "$name"; then
      ui_note err "${TX[tools.new_ct.invalid]}"
    elif ct_name_taken "$name"; then
      tf v tools.new_ct.taken "$name"; ui_note err "$v"
    else
      break
    fi
  done
  tf v tools.new_ct.confirm "$name" "$img"; ui_confirm "$v" || return 0
  ct_launch "$img" "$name" || return 0
  ct_load
  tf v tools.new_ct.shell "$name"; ui_confirm "$v" && ct_shell "$name"
  return 0
}

# ─── Modus / Setup ─────────────────────────────────────────────────────────

# ─── Hilfen für Werkzeuge (auch für lib/tools_*.sh) ────────────────────────
# Seiten (Ausgabe innerhalb von ui_run_page) formatieren nur über diese Helfer und die Theme-
# Farben C_* aus ui.sh, damit eine neue Optik automatisch auch hier gilt.
# PD_TOOLS_ROOT ist ein Präfix für gelesene Systemdateien (/etc, /proc, /var, /boot), nur für Tests.
tp() { printf '%s%s' "${PD_TOOLS_ROOT:-}" "$1"; }
tq() { local t=$1; shift; timeout "$t" "$@" </dev/null 2>/dev/null; } # sek cmd…: still, mit Timeout
_tl_lvl() { # stufe → _TL_C (Farbe), _TL_S (Symbol)
  case "$1" in
    ok) _TL_C=$C_GRN _TL_S='✓';; warn) _TL_C=$C_YLW _TL_S='!';; err) _TL_C=$C_RED _TL_S='✗';;
    dim) _TL_C=$C_D _TL_S=' ';; *) _TL_C="" _TL_S=' ';;
  esac
}
tl_head() { printf '\n%s%s%s\n' "$C_B" "$1" "$C_R"; }                              # Abschnitt
tl_line() { _tl_lvl "$1"; printf '  %s%s %s%s\n' "$_TL_C" "$_TL_S" "$2" "$C_R"; }  # stufe text
tl_kv() { _tl_lvl "${3:-}"; printf '  %s %s%s%s\n' "$(tl_pad "$1" 20)" "$_TL_C" "$2" "$C_R"; } # label wert [stufe]
tl_text() { printf '  %s\n' "$@"; }
tl_dim() { printf '  %s%s%s\n' "$C_D" "$1" "$C_R"; }
tl_hint() { printf '  %s%s%s %s\n' "$C_D" "${TX[tools.hint]}" "$C_R" "$1"; }
tl_pad() { # text breite: zeichenweise auffüllen (printf zählt Bytes)
  local n=$(( $2 - ${#1} ))
  if [ "$n" -gt 0 ]; then printf '%s%*s' "$1" "$n" ''; else printf '%s' "$1"; fi
}
tl_cut() { if [ ${#1} -gt "$2" ]; then printf '%s…' "${1:0:$(( $2 - 1 ))}"; else printf '%s' "$1"; fi; }
tl_human() { # bytes → 1.5G
  awk -v b="${1:-0}" 'BEGIN { split("B K M G T P", u, " "); i = 1
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    if (i == 1) printf "%d%s", b, u[i]; else printf "%.1f%s", b, u[i] }'
}
tl_lvl() { # prozent warn-ab err-ab → ok|warn|err
  if [ "$1" -ge "$3" ]; then echo err; elif [ "$1" -ge "$2" ]; then echo warn; else echo ok; fi
}
# shellcheck disable=SC2016 # jq-Programm
# jq-Funktion bytes: "93.71MiB" bzw. "2.1GB" → Bytes (Docker-Größenangaben)
TL_JQ_BYTES='def bytes: (capture("^(?<n>[0-9.]+)\\s*(?<u>[A-Za-z]*)") // {n: "0", u: "B"}) as $c
  | ($c.n | tonumber) * ({"B": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
      "KiB": 1024, "MiB": 1048576, "GiB": 1073741824, "TiB": 1099511627776}[$c.u] // 1);'

tl_meminfo() { # → "MemTotal MemAvailable SwapTotal SwapFree" in KiB
  awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} /^SwapTotal:/ {st=$2} /^SwapFree:/ {sf=$2}
    END { print t+0, a+0, st+0, sf+0 }' "$(tp /proc/meminfo)" 2>/dev/null
}
tl_swap_top() { # n → Prozesse (nach Name zusammengefasst) mit der größten Swap-Belegung
  local f; f=$(tp /proc)
  awk '/^Name:/ {n=$2} /^VmSwap:/ { if ($2 > 0) s[n] += $2 }
    END { for (k in s) print s[k], k }' "$f"/[0-9]*/status 2>/dev/null | sort -rn | head -n "$1" |
    while read -r kb name; do printf '  %8s  %s\n' "$(tl_human $((kb * 1024)))" "$name"; done
}
tl_df_rows() { # → "prozent|mount|belegt|größe|typ" (Bytes), ohne tmpfs/overlay & Co.
  df -P -k -T -x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs 2>/dev/null |
    awk 'NR > 1 && $3 > 0 { p = $6; sub(/%/, "", p); printf "%d|%s|%.0f|%.0f|%s\n", p, $7, $4 * 1024, $3 * 1024, $2 }'
}
tl_df_page() {
  local pct mnt used size typ
  while IFS='|' read -r pct mnt used size typ; do
    _tl_lvl "$(tl_lvl "$pct" 80 90)"
    printf '  %s%3d %%%s  %s %8s / %-8s %s%s%s\n' "$_TL_C" "$pct" "$C_R" "$(tl_pad "$mnt" 28)" \
      "$(tl_human "$used")" "$(tl_human "$size")" "$C_D" "$typ" "$C_R"
  done < <(tl_df_rows)
}
tl_failed_units() { # → "unit<TAB>beschreibung" aller fehlgeschlagenen Units (alle Typen)
  have systemctl || return 0
  tq 15 systemctl list-units --state=failed --all -o json --no-pager |
    jq -r '.[]? | [.unit, .description] | @tsv' 2>/dev/null
}
# Fehler der letzten 24 h (bzw. seit Boot) nach Unit:
# → "anzahl<TAB>unit<TAB>letzte-epoch<TAB>verschiedene<TAB>letzte-meldung", häufigste zuerst
tl_journal_errs() {
  tq 30 journalctl -p err -b --since "24 hours ago" -n 5000 -o json --no-pager -q \
      --output-fields=_SYSTEMD_UNIT,SYSLOG_IDENTIFIER,MESSAGE |
    jq -Rr --arg bin "${TX[tools.errlog.binary]}" 'fromjson? | select(type == "object")
      | [(._SYSTEMD_UNIT // .SYSLOG_IDENTIFIER // "?"),
         ((.__REALTIME_TIMESTAMP // "0") | tonumber / 1000000 | floor | tostring),
         (.MESSAGE | if type == "string" then gsub("[\t\r\n]"; " ")
                     elif type == "array" then $bin else "" end)] | @tsv' 2>/dev/null |
    awk -F'\t' '{ n[$1]++; if ($2 >= t[$1]) { t[$1] = $2; m[$1] = $3 }
        if (!(($1, $3) in seen)) { seen[$1, $3] = 1; d[$1]++ } }
      END { for (u in n) printf "%d\t%s\t%s\t%d\t%s\n", n[u], u, t[u], d[u], m[u] }' |
    sort -t "$(printf '\t')" -k1,1nr -k2,2
}
# Container mit Problemen → "stufe|kontext|name|text"
# docker: Host-Docker; layered: Docker in jedem laufenden CT.
tl_ctr_issues() {
  local ct
  case "$MODE" in
    docker) _tl_ctr_issues_ctx "";;
    layered)
      ct_load
      for ct in $(ct_names); do
        [ "$PD_INT" = 1 ] && break
        [ "$(ct_status "$ct")" = Running ] && _tl_ctr_issues_ctx "$ct"
      done;;
  esac
  return 0
}
_tl_ctr_issues_ctx() { # kontext
  local -a names
  dk_load "$1"
  [ "$DK_RC" -eq 0 ] && [ -n "$DK_ROWS" ] || return 0
  mapfile -t names < <(printf '%s\n' "$DK_ROWS" | cut -d'|' -f1 | grep .)
  { printf '%s\n' "$DK_ROWS"; echo "--"
    dk "$1" inspect --format '{{.Name}}|{{.RestartCount}}|{{.State.OOMKilled}}|{{.State.ExitCode}}' "${names[@]}" 2>/dev/null
  } | awk -F'|' -v ctx="$1" -v t_rst="${TX[tools.ctr.restarting]}" -v t_oom="${TX[tools.ctr.oom]}" \
      -v t_rsn="${TX[tools.ctr.restarts]}" -v t_exit="${TX[tools.ctr.exit]}" -v t_kill="${TX[tools.ctr.sigkill]}" '
    $0 == "--" { x = 1; next }
    !x { st[$1] = $2; stat[$1] = $3; order[++n] = $1; next }
    { nm = $1; sub(/^\//, "", nm); rs[nm] = $2; oom[nm] = $3; code[nm] = $4 }
    END {
      for (i = 1; i <= n; i++) { c = order[i]
        if (stat[c] ~ /\(unhealthy\)/) print "err|" ctx "|" c "|unhealthy"
        if (st[c] == "restarting") print "err|" ctx "|" c "|" sprintf(t_rst, stat[c])
        if (oom[c] == "true") print "err|" ctx "|" c "|" t_oom
        if (rs[c] + 0 >= 3) print "warn|" ctx "|" c "|" sprintf(t_rsn, rs[c])
        if (st[c] == "exited" && code[c] + 0 != 0)
          print "warn|" ctx "|" c "|" sprintf(t_exit, code[c]) (code[c] == 137 ? " " t_kill : "")
      } }'
}

tool_register incus_overview "${TX[tools.incus_overview.title]}" "incus list"                "incus layered"  _t_incus_avail   _t_incus_overview 10
tool_register sysinfo        "${TX[tools.sysinfo.title]}"     "free, df, ps"                 "all"            -                _t_sysinfo_run    11
tool_register errlog         "${TX[tools.errlog.title]}"      "${TX[tools.errlog.desc]}"     "all"            _t_errlog_avail  _t_errlog         12
tool_register ssh            "${TX[tools.ssh.title]}"         "${TX[tools.ssh.desc]}"        "all"            _t_ssh_avail     _t_ssh            14
tool_register mutagen        "${TX[tools.mutagen.title]}"     "mutagen sync list"            "all"            _t_mutagen_avail _t_mutagen        15
tool_register cve            "${TX[tools.cve.title]}"         "${TX[tools.cve.desc]}"        "incus layered"  _t_cve_avail     _t_cve            16
tool_register incus_res      "${TX[tools.incus_res.title]}"   "${TX[tools.incus_res.desc]}"  "incus layered"  _t_incus_avail   _t_incus_res      17
tool_register new_ct         "${TX[tools.new_ct.title]}"      "${TX[tools.new_ct.desc]}"     "incus layered"  _t_incus_avail   _t_new_ct         18
tool_register setup          "${TX[tools.setup.title]}"       "${TX[tools.setup.desc]}"      "all"            -                _t_settings       999
