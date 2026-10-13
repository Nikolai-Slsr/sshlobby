# shellcheck shell=bash
# tools_health.sh: Werkzeug „Docker-Health“ (Modi docker und layered), ersetzt den Health-Scan bis 3.0.
# docker:  Menü mit zwei Abschnitten, Compose-Projekte (eine Zeile pro Projekt) und Einzelcontainer
#          (eine Zeile pro Container), jeweils Probleme zuerst. Enter öffnet den Projekt- bzw.
#          Container-Screen (Logs, Shell, Restart, Zustand und Healthcheck).
# layered: zuerst eine Zeile pro Incus-CT, Probleme zuerst. Enter öffnet dieselbe Ansicht für das
#          Docker im CT, bei gestopptem CT, ohne Docker oder ohne erreichbares Docker den CT-Screen.
# Tasten: p nur Probleme / alle zeigen (gilt für die ganze Sitzung), r neu prüfen, f Favorit der markierten
# Zeile (Projekt nur im docker-Modus, Einzelcontainer, CT), / filtern.
# Stufen, dieselben Regeln wie tl_ctr_issues im Server-Check: 3 Fehler = unhealthy, Neustart-Schleife,
# OOM-Kill, tot; 2 Warnung = Exit-Code ≠ 0, mindestens 3 Neustarts durch Docker, Healthcheck startet;
# 1 gestoppt (exited mit 0, created, paused); 0 ok.
# Daten: docker ps -a (dk_load) und ein docker inspect für alle Container eines Kontexts (Neustarts,
# OOM-Kill, Exit-Code). Die CT-Übersicht kommt ohne inspect aus (Exit-Code aus dem Status-Text), damit
# sie auch bei vielen CTs schnell bleibt.
# shellcheck disable=SC1111,SC2034 # „…“ sind gewollte Anführungszeichen, UI_* liest ui.sh

HL_ONLY=0   # 1 = nur Einträge mit Problemen (Stufe ≥ 1)
HL_ROWS=""  # stufe|grund|name|projekt|service|state|status|image|neustarts, eine Zeile pro Container
HL_TXT=""   # Rückgabe der Text-Helfer
HL_M=""     # Rückgabe von _hl_mark

# Container eines Kontexts einstufen → HL_ROWS. Rückgabe wie dk_ps (0 ok, 1 CT läuft nicht,
# 2 Docker nicht erreichbar, 3 kein Docker). inspect 0 = ohne docker inspect (CT-Übersicht).
hl_load() { # kontext [inspect]
  local -a names=()
  HL_ROWS=""
  dk_load "$1"
  [ "$DK_RC" -eq 0 ] || return "$DK_RC"
  [ -n "$DK_ROWS" ] || return 0
  [ "${2:-1}" = 1 ] && mapfile -t names < <(printf '%s\n' "$DK_ROWS" | cut -d'|' -f1 | grep .)
  HL_ROWS=$({ printf '%s\n' "$DK_ROWS"; echo "--"
      [ ${#names[@]} -eq 0 ] || dk "$1" inspect --format '{{.Name}}|{{.RestartCount}}|{{.State.OOMKilled}}|{{.State.ExitCode}}' "${names[@]}" 2>/dev/null
    } | awk -F'|' '
    $0 == "--" { x = 1; next }
    !x { if ($1 == "") next
         n[++c] = $1; st[$1] = $2; stat[$1] = $3; img[$1] = $4
         p = $6; if (p == "<no value>") p = ""; pr[$1] = p
         s = $7; if (s == "<no value>") s = ""; sv[$1] = s; next }
    { nm = $1; sub(/^\//, "", nm); rs[nm] = $2; oom[nm] = $3; code[nm] = $4 }
    END {
      for (i = 1; i <= c; i++) { k = n[i]; lv = 0; why = "ok"; ec = code[k]
        if (ec == "" && match(stat[k], /^Exited \([0-9]+\)/)) ec = substr(stat[k], 9, RLENGTH - 9)
        if (stat[k] ~ /\(unhealthy\)/)               { lv = 3; why = "unhealthy" }
        else if (st[k] == "restarting")              { lv = 3; why = "restarting" }
        else if (oom[k] == "true")                   { lv = 3; why = "oom" }
        else if (st[k] == "dead")                    { lv = 3; why = "dead" }
        else if (st[k] == "exited" && ec + 0 != 0)   { lv = 2; why = "exit:" ec }
        else if (rs[k] + 0 >= 3)                     { lv = 2; why = "restarts:" rs[k] }
        else if (stat[k] ~ /health: starting/)       { lv = 2; why = "starting" }
        else if (st[k] != "running")                 { lv = 1; why = "stopped" }
        printf "%d|%s|%s|%s|%s|%s|%s|%s|%d\n", lv, why, k, pr[k], sv[k], st[k], stat[k], img[k], rs[k] + 0 } }')
  return 0
}

# Compose-Projekte aus HL_ROWS → "stufe|projekt|gesamt|laufend|grund|probleme" (probleme: "name:grund,…",
# schlimmste zuerst), sortiert nach Stufe absteigend, dann Name
_hl_projects() {
  printf '%s\n' "$HL_ROWS" | sort -t'|' -s -k1,1nr | awk -F'|' '$3 != "" && $4 != "" { p = $4; t[p]++
      if ($6 == "running") r[p]++
      if (!(p in m)) { m[p] = $1 + 0; w[p] = $2 }
      if ($1 + 0 > 0) b[p] = b[p] (b[p] == "" ? "" : ",") ($5 != "" ? $5 : $3) ":" $2 }
    END { for (p in t) printf "%d|%s|%d|%d|%s|%s\n", m[p], p, t[p], r[p], w[p], b[p] }' | sort -t'|' -k1,1nr -k2,2
}
_hl_singles() { printf '%s\n' "$HL_ROWS" | awk -F'|' '$3 != "" && $4 == ""' | sort -t'|' -k1,1nr -k3,3; } # ohne Projekt

_hl_mark() { case "$1" in 3) HL_M=err;; 2) HL_M=warn;; 1) HL_M=stop;; *) HL_M=run;; esac; } # stufe → Markierung
_hl_why() { # grund → HL_TXT (Klartext)
  case "$1" in
    exit:*)     tf HL_TXT health.why.exit "${1#exit:}";;
    restarts:*) tf HL_TXT health.why.restarts "${1#restarts:}";;
    *)          HL_TXT=${TX[health.why.$1]:-$1};;
  esac
}
_hl_pill() { # grund stufe → HL_TXT, FMT (Pill in der Farbe der Stufe, „kein Docker“ und „leer“ gedimmt)
  _hl_why "$1"
  case "$1" in none|nodocker) _cell dim "$HL_TXT"; return;; esac
  case "$2" in 3) _cell p-err "$HL_TXT";; 2) _cell p-warn "$HL_TXT";; 1) _cell dim "$HL_TXT";; *) _cell p-ok "$HL_TXT";; esac
}
_hl_problems() { # "name:grund,…" → HL_TXT „name (grund), …“
  local -a parts; local x out=""
  IFS=',' read -ra parts <<< "$1"
  for x in "${parts[@]}"; do _hl_why "${x#*:}"; out+="${out:+, }${x%%:*} ($HL_TXT)"; done
  HL_TXT=$out
}
_hl_count() { # laufend gesamt → FMT
  if [ "$1" -eq "$2" ]; then _cell ok "$1/$2"; elif [ "$1" -eq 0 ]; then _cell dim "$1/$2"; else _cell warn "$1/$2"; fi
}
_hl_keys() { # Hotkeys und Untertitel (HL_SUB) je nach Filter
  if [ "$HL_ONLY" = 1 ]; then UI_KEYS=("p|${TX[health.key.all]}"); HL_SUB=${TX[health.sub.only]}
  else UI_KEYS=("p|${TX[health.key.only]}"); HL_SUB=${TX[health.sub.all]}; fi
  UI_KEYS+=("r|${TX[health.key.rescan]}" "f|$(t screens.key.fav_row "$UI_SYM_FAV")")
}

# Docker eines Kontexts: Compose-Projekte und Einzelcontainer
_hl_view() { # kontext ("" = Host-Docker)
  local ctx=$1 lv why p total run bad name svc state status image rs cnt pill wt txt v st
  local all nrun ne nw ns np nc
  while true; do
    _ui_tui_on && ui_loading "${TX[health.loading]}"
    hl_load "$ctx"
    if [ "$DK_RC" -ne 0 ]; then ui_msg err "${ctx:+$ctx: }$(dk_msg "$ctx" "$DK_RC")."; return 0; fi
    read -r all nrun ne nw ns < <(printf '%s\n' "$HL_ROWS" | awk -F'|' '$3 != "" { a++; if ($6 == "running") r++
        if ($1 == 3) e++; else if ($1 == 2) w++; else if ($1 == 1) s++ } END { printf "%d %d %d %d %d\n", a, r, e, w, s }')
    tf v health.summary "$nrun" "$all" "$ne" "$nw" "$ns"
    if [ "$ne" -gt 0 ]; then st=err; elif [ "$nw" -gt 0 ]; then st=warn; else st=run; fi
    ui_info "${TX[health.info.status]}" "$v" "$st"
    np=0 nc=0
    while IFS='|' read -r lv p total run why bad; do
      [ -n "$p" ] || continue
      [ "$HL_ONLY" = 1 ] && [ "$lv" -eq 0 ] && continue
      [ $np -eq 0 ] && ui_item header "" "${TX[screens.section.compose_projects]}" "" main
      np=$((np + 1))
      _hl_mark "$lv"; _hl_count "$run" "$total"; cnt=$FMT
      _hl_pill "$why" "$lv"; pill=$FMT wt=$HL_TXT
      if [ -n "$bad" ]; then _hl_problems "$bad"; txt=$HL_TXT; else txt=${PD_DESC[$p]:-}; fi
      ui_item item "p:$p" "$p" "$run/$total  $wt${txt:+  $txt}" "$HL_M" "$cnt"$'\t'"$pill"$'\t'"$txt"
    done < <(_hl_projects)
    while IFS='|' read -r lv why name p svc state status image rs; do
      [ -n "$name" ] || continue
      [ "$HL_ONLY" = 1 ] && [ "$lv" -eq 0 ] && continue
      [ $nc -eq 0 ] && ui_item header "" "${TX[health.section.standalone]}" "" main
      nc=$((nc + 1))
      _hl_mark "$lv"; _hl_pill "$why" "$lv"; pill=$FMT wt=$HL_TXT
      fmt_status "$status"; if [ "$state" = running ]; then _cell info "$FMT"; else _cell dim "$FMT"; fi
      ui_item item "c:$name" "$name" "$image  $wt  $status" "$HL_M" "$image"$'\t'"$pill"$'\t'"$FMT"   # Pill in Spalte 2 wie bei Projekten
    done < <(_hl_singles)
    if [ "$all" -eq 0 ]; then ui_item disabled "" "${TX[health.none]}"
    elif [ $((np + nc)) -eq 0 ]; then ui_item disabled "" "${TX[health.all_ok]}"; fi
    _hl_keys
    ui_menu "${ctx:-${TX[health.title]}}" "$HL_SUB"
    case "$UI_ACT" in
      key)    case "$UI_SEL" in                              # r: Schleife prüft neu
                p) HL_ONLY=$((1 - HL_ONLY));;
                f) fav_need_row || continue
                   case "$UI_KEYROW" in
                     p:*) if [ -z "$ctx" ]; then fav_key "${UI_KEYROW#p:}" "-" "${UI_KEYROW#p:}"; else fav_key ""; fi;;
                     c:*) fav_key "${ctx:--}" "${UI_KEYROW#c:}" "${UI_KEYROW#c:}";;
                   esac;;
              esac;;
      select) case "$UI_SEL" in
                p:*) screen_project "${UI_SEL#p:}" "$ctx";;
                c:*) screen_container "$ctx" "${ctx:--}" "${UI_SEL#c:}";;
              esac;;
      *)      return 0;;
    esac
  done
}

# layered: eine Zeile pro CT
_hl_cts() {
  local ct rc line lv why total run bad cnt pill wt txt v st n ne nw shown sel
  local -a rows
  while true; do
    _ui_tui_on && ui_loading "${TX[health.loading_cts]}"
    ct_load
    rows=()
    for ct in $(ct_names); do
      hl_load "$ct" 0; rc=$?
      case $rc in
        0) line=$(printf '%s\n' "$HL_ROWS" | sort -t'|' -s -k1,1nr | awk -F'|' '$3 != "" { t++; if ($6 == "running") r++
               if (w == "") { m = $1 + 0; w = $2 }; if ($1 + 0 > 0) b = b (b == "" ? "" : ",") $3 ":" $2 }
             END { printf "%d|%s|%d|%d|%s", m, (t == 0 ? "none" : w), t, r, b }')
           rows+=("${line%%|*}|$ct|${line#*|}");;
        1) rows+=("1|$ct|ctdown|0|0|");;
        3) rows+=("0|$ct|nodocker|0|0|");;
        *) rows+=("2|$ct|unreachable|0|0|");;
      esac
    done
    n=0 ne=0 nw=0 shown=0
    while IFS='|' read -r lv ct why total run bad; do
      [ -n "$ct" ] || continue
      n=$((n + 1)); [ "$lv" -eq 3 ] && ne=$((ne + 1)); [ "$lv" -eq 2 ] && nw=$((nw + 1))
      [ "$HL_ONLY" = 1 ] && [ "$lv" -eq 0 ] && continue
      [ $shown -eq 0 ] && ui_item header "" "${TX[health.section.cts]}" "" main
      shown=$((shown + 1))
      _hl_mark "$lv"; _hl_pill "$why" "$lv"; pill=$FMT wt=$HL_TXT
      case "$why" in
        ctdown|unreachable|nodocker) _cell dim "–"; cnt=$FMT v="";;
        *) _hl_count "$run" "$total"; cnt=$FMT v="$run/$total  ";;
      esac
      if [ -n "$bad" ]; then _hl_problems "$bad"; txt=$HL_TXT; else txt=${PD_DESC[$ct]:-}; fi
      ui_item item "ct:$ct:$why" "$ct" "$v$wt${txt:+  $txt}" "$HL_M" "$cnt"$'\t'"$pill"$'\t'"$txt"
    done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1nr -k2,2)
    [ "$n" -gt 0 ] || ui_item disabled "" "${TX[screens.main.no_cts]}"
    [ "$n" -gt 0 ] && [ "$shown" -eq 0 ] && ui_item disabled "" "${TX[health.all_ok]}"
    tf v health.summary_cts "$n" "$ne" "$nw"
    if [ "$ne" -gt 0 ]; then st=err; elif [ "$nw" -gt 0 ]; then st=warn; else st=run; fi
    ui_info "${TX[health.info.status]}" "$v" "$st"
    _hl_keys
    ui_menu "${TX[health.title]}" "$HL_SUB"
    case "$UI_ACT" in
      key)    case "$UI_SEL" in
                p) HL_ONLY=$((1 - HL_ONLY));;
                f) fav_need_row && { sel=${UI_KEYROW#ct:}; fav_key "${sel%%:*}" "-" "${sel%%:*}"; };;
              esac;;
      select) sel=${UI_SEL#ct:}; ct=${sel%%:*} why=${sel#*:}
              case "$why" in ctdown|unreachable|nodocker) screen_ct "$ct";; *) _hl_view "$ct";; esac;;
      *)      return 0;;
    esac
  done
}

_t_health() { if [ "$MODE" = layered ]; then _hl_cts; else _hl_view ""; fi; }

tool_register health "${TX[health.title]}" "${TX[health.desc]}" "docker layered" - _t_health 13
