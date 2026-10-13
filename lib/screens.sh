# shellcheck shell=bash
# screens.sh: Hauptmenü und alle Screens. Nutzt nur die UI-API (ui.sh), die Backends
# (backend_incus.sh, backend_docker.sh) und Zustand/Config aus core.sh, nie incus/docker direkt.
# Werte der Menüeinträge: "art:a:b:c" (Namen von CTs, Projekten und Containern enthalten kein :).
# shellcheck disable=SC2034,SC1111 # UI_* gehören zur Menü-API (SC1111: „…“ sind gewollte Anführungszeichen)

mode_ctx() { if [ "$MODE" = docker ]; then printf ''; else printf '%s' "$1"; fi; } # gruppe → Docker-Kontext

# Anzeige eines Verlaufs-/Favoritenziels
target_label() { # gruppe ziel trenner
  if [ "$2" = "-" ]; then t screens.target.ctshell "$1"
  elif [ "$MODE" = docker ] && [ "$1" = "-" ]; then printf '%s' "$2"
  else printf '%s%s%s' "$1" "$3" "$2"; fi
}
# Fastpath-Hinweis: HOST_LABEL nur, wenn es ein SSH-Alias sein kann, sonst hostname -s
fastpath() {
  local h=$HOST_LABEL
  [[ $h =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || h=$PD_HOST
  printf 'ssh -t %s sshlobby --go %s' "$h" "$1"
}

# ─── Darstellung: TUI-Zellen (ui_item spalten). Der Zeilenmodus zeigt weiter die Rohtexte ───
_cell() { FMT=$'\001'"$1"$'\002'"$2"; } # stil text → FMT (wie ui_cell, ohne Subshell)
fmt_dur() { # "4 weeks" | "About an hour" → FMT "4 W" | "1 h"
  local -a w; read -ra w <<< "$1"
  local n=${w[0]:-} u=${w[${#w[@]}-1]:-}
  [[ $n =~ ^[0-9]+$ ]] || n=1
  case "$u" in
    second*) u=${TX[screens.unit.second]};; minute*) u=${TX[screens.unit.minute]};; hour*) u=${TX[screens.unit.hour]};;
    day*) u=${TX[screens.unit.day]};; week*) u=${TX[screens.unit.week]};; month*) u=${TX[screens.unit.month]};;
    year*) u=${TX[screens.unit.year]};;
    *) FMT=$1; return;;
  esac
  FMT="$n $u"
}
fmt_status() { # docker-Status → FMT kompakt: "5 T", "exit 0 · vor 4 W"
  local s=$1 code
  case "$s" in
    Up\ *)      s=${s#Up }; fmt_dur "${s%% (*}";;
    Exited\ *)  code=${s#Exited (}; code=${code%%)*}; s=${s#*) }; fmt_dur "${s% ago}"; tf FMT screens.status.exited "$code" "$FMT";;
    Restarting*) FMT=${TX[screens.status.restarting]};;
    *)          FMT=${s,,};;
  esac
}
fmt_ports() { # "127.0.0.1:3080->3080/tcp, 3000/tcp" → FMT "3080→3080 3000" (höchstens 3, dann +n)
  local p x h n=0 more=0 seen=" "; local -a arr
  FMT=""
  IFS=',' read -ra arr <<< "$1"
  for p in "${arr[@]}"; do
    p=${p# }; p=${p%/tcp}; [ -n "$p" ] || continue
    if [[ $p == *'->'* ]]; then h=${p%%->*}; x="${h##*:}$UI_SYM_ARR${p#*->}"; else x=$p; fi
    [[ $seen == *" $x "* ]] && continue
    seen+="$x "
    if [ $n -lt 3 ]; then FMT+="${FMT:+ }$x"; n=$((n + 1)); else more=$((more + 1)); fi
  done
  [ $more -gt 0 ] && FMT+=" +$more"
  return 0
}
dk_cells() { # erste status ports → FMT: Zellen erste, Laufzeit, Health-Pill, Ports
  local up hp=""
  fmt_status "$2"
  case "$2" in Up*) _cell info "$FMT";; *) _cell dim "$FMT";; esac; up=$FMT
  case "$(dk_health "$2")" in
    healthy) _cell p-ok healthy; hp=$FMT;; unhealthy) _cell p-err unhealthy; hp=$FMT;; starting) _cell p-warn starting; hp=$FMT;;
  esac
  fmt_ports "$3"
  FMT="$1"$'\t'"$up"$'\t'"$hp"$'\t'"$FMT"
}
count_cells() { # laufend gesamt unhealthy text → FMT: Zähler, Unhealthy-Pill, Text
  local c hp=""
  if [ "$1" -eq "$2" ]; then _cell ok "$1/$2"; elif [ "$1" -eq 0 ]; then _cell dim "$1/$2"; else _cell warn "$1/$2"; fi; c=$FMT
  [ "$3" -gt 0 ] && { _cell p-err "$3 unhealthy"; hp=$FMT; }
  FMT="$c"$'\t'"$hp"$'\t'"$4"
}

# ─── Hauptmenü ─────────────────────────────────────────────────────────────
screen_main() {
  upd_auto                     # einmal pro Start: Release-Prüfung im Hintergrund, wenn fällig
  while true; do
    MAIN_SUB=""
    if [ "$MODE" = docker ]; then main_items_docker; else main_items_incus; fi
    ui_item sep
    ui_item item tools "${TX[screens.main.tools]}" "${TX[screens.main.tools_desc]}"
    sys_stats
    UI_ROOT=1 UI_STYLE=main
    UI_KEYS=("s|${TX[screens.key.host_shell]}" "e|${TX[screens.key.settings]}" "r|${TX[screens.key.reload]}")
    upd_banner                 # neueres Release bekannt: Hinweiszeile und Taste u
    if [ "$Q_ACTION" = shell ]; then UI_QUIT_LABEL=${TX[screens.main.quit_shell]}; else UI_QUIT_LABEL=${TX[screens.main.quit_logout]}; fi
    ui_menu "${HOST_LABEL^^}" "$MAIN_SUB"
    case "$UI_ACT" in
      eof)    return "$PD_EXIT_OK";;
      quit)   if [ "$Q_ACTION" = shell ]; then return "$PD_EXIT_SHELL"; fi; return "$PD_EXIT_LOGOUT";;
      key)    case "$UI_SEL" in
                s) return "$PD_EXIT_SHELL";;
                e) screen_settings;;
                u) upd_tui;;
              esac;;
      select) main_open "$UI_SEL";;
    esac
  done
}

# Beschreibung eines Verlaufseintrags: zeit aktion → d (Aktion und Alter, CT-Shell nur das Alter)
rec_desc() {
  case "$2" in
    shell|logs|compose|project) tf d "screens.recent.$2" "$(rel_time "$1")";;
    *) d=$(rel_time "$1");;
  esac
}

# incus und layered: Verlauf, Favoriten, CTs. Im incus-Modus nur CT-Einträge (ziel "-").
# Werkzeuge stehen im Verlauf des Werkzeug-Menüs, Compose-Projekte gibt es nur im docker-Modus.
main_items_incus() {
  local ts g t a ct st n d
  ct_load
  n=0
  while IFS='|' read -r ts g t a; do
    [ "$n" -lt "$RECENT_MAX" ] || break
    [ "$g" = "@tool" ] || [ "$a" = project ] || [ "$a" = tool ] && continue
    ct_exists "$g" || continue
    [ "$MODE" = incus ] && [ "$t" != "-" ] && continue
    [ $n -eq 0 ] && ui_item header "" "${TX[screens.section.recent]}" "" recent
    rec_desc "$ts" "$a"
    ui_item item "rec:$g:$t:$a" "$(target_label "$g" "$t" " / ")" "$d"
    n=$((n+1))
  done < <(state_recents)
  # Favoriten: CTs, die es nicht mehr gibt, markiert (Auswahl bietet Entfernen an)
  n=0
  while IFS='|' read -r g t; do
    [ "$MODE" = incus ] && [ "$t" != "-" ] && continue
    [ $n -eq 0 ] && ui_item header "" "${TX[screens.section.favorites]}" "" fav
    if ct_exists "$g"; then ui_item item "fav:$g:$t" "$(target_label "$g" "$t" /)" "${PD_DESC[$g]:-}" fav
    else ui_item item "favgone:$g:$t" "$(target_label "$g" "$t" /)" "${TX[screens.fav.ct_gone]}" gone; fi
    n=$((n+1))
  done < <(state_favorites)
  ui_item header "" "${TX[screens.section.projects_cts]}" "" main
  [ -z "$CTS_RAW" ] && ui_item disabled "" "${TX[screens.main.no_cts]}"
  local ip total=0
  while IFS=, read -r ct st ip; do
    [ -z "$ct" ] && continue
    total=$((total + 1))
    if [ "$st" = Running ]; then st=run; else st=stop; fi
    [ "$ip" = "-" ] && ip=""
    ui_item item "ct:$ct" "$ct" "${PD_DESC[$ct]:-}" "$st" "$ip"$'\t'"${PD_DESC[$ct]:-}"
  done <<< "$CTS_RAW"
  n=$(ct_running_count)
  tf MAIN_SUB screens.main.cts_active "$n"
  UI_STAT="$n|$total|0|${TX[screens.unit.cts]}"
}

# docker: Verlauf, Favoriten, Compose-Projekte, Einzelcontainer
main_items_docker() {
  local ts g t a n p total run bad dir st name lbl d
  local -A have_c=() have_p=()
  dk_load ""
  while IFS='|' read -r name _ _ _ _ p _; do
    [ -n "$name" ] || continue
    have_c[$name]=1; have_p[${p:--}]=1
  done <<< "$DK_ROWS"
  n=0
  while IFS='|' read -r ts g t a; do
    [ "$n" -lt "$RECENT_MAX" ] || break
    [ "$g" = "@tool" ] || [ "$a" = tool ] && continue
    if [ "$a" = project ]; then                    # ganzes Compose-Projekt (ziel "-")
      if [ "$t" != "-" ] || [ "$g" = "-" ] || [ -z "${have_p[$g]+x}" ]; then continue; fi
      lbl=$g
    else
      if [ "$t" = "-" ] || [ -z "${have_c[$t]+x}" ]; then continue; fi
      lbl=$(target_label "$g" "$t" " / ")
    fi
    [ $n -eq 0 ] && ui_item header "" "${TX[screens.section.recent]}" "" recent
    rec_desc "$ts" "$a"
    ui_item item "rec:$g:$t:$a" "$lbl" "$d"
    n=$((n+1))
  done < <(state_recents)
  # Favoriten anderer Modi (CT-Gruppen) ausblenden, fehlende Container markieren
  n=0
  while IFS='|' read -r g t; do
    [ "$t" != "-" ] || continue
    [ "$g" = "-" ] || [ -n "${have_p[$g]+x}" ] || [ -n "${have_c[$t]+x}" ] || continue
    [ $n -eq 0 ] && ui_item header "" "${TX[screens.section.favorites]}" "" fav
    lbl=$(target_label "$g" "$t" /)
    if [ -n "${have_c[$t]+x}" ]; then ui_item item "fav:$g:$t" "$lbl" "${PD_DESC[$t]:-${PD_DESC[$g]:-}}" fav
    else ui_item item "favgone:$g:$t" "$lbl" "${TX[screens.fav.container_gone]}" gone; fi
    n=$((n+1))
  done < <(state_favorites)
  ui_item header "" "${TX[screens.section.compose_projects]}" "" main
  if [ "$DK_RC" -ne 0 ]; then ui_item disabled "" "($(dk_msg "" "$DK_RC"))"
  elif [ -z "$DK_ROWS" ]; then ui_item disabled "" "${TX[screens.main.no_containers]}"; fi
  local single=""
  while IFS='|' read -r p total run bad dir; do
    [ -n "$p" ] || continue
    if [ "$p" = "-" ]; then single="$total|$run|$bad"; continue; fi
    if [ "$bad" -gt 0 ]; then st=err; elif [ "$run" -eq "$total" ]; then st=run; elif [ "$run" -eq 0 ]; then st=stop; else st=warn; fi
    count_cells "$run" "$total" "$bad" "${PD_DESC[$p]:-$dir}"
    ui_item item "proj:$p" "$p" "$run/$total  ${PD_DESC[$p]:-$dir}" "$st" "$FMT"
  done < <(dk_projects)
  if [ -n "$single" ]; then
    IFS='|' read -r total run bad <<< "$single"
    if [ "$bad" -gt 0 ]; then st=err; elif [ "$run" -eq "$total" ]; then st=run; elif [ "$run" -eq 0 ]; then st=stop; else st=warn; fi
    count_cells "$run" "$total" "$bad" "${TX[screens.main.no_project]}"
    ui_item item "proj:-" "${TX[screens.main.standalone]}" "$run/$total  ${TX[screens.main.no_project]}" "$st" "$FMT"
  fi
  run=$(printf '%s\n' "$DK_ROWS" | awk -F'|' '$2=="running"' | grep -c .)
  total=$(printf '%s\n' "$DK_ROWS" | grep -c .)
  bad=$(printf '%s\n' "$DK_ROWS" | awk -F'|' '$3 ~ /unhealthy/' | grep -c .)
  tf MAIN_SUB screens.main.containers_running "$run" "$total"
  UI_STAT="$run|$total|$bad|${TX[screens.unit.containers]}"
}

main_open() { # wert
  local kind a b c a2
  IFS=: read -r kind a b c <<< "$1"
  case "$kind" in
    ct)      screen_ct "$a";;
    proj)    screen_project "$a";;
    tools)   screen_tools;;
    rec)     open_recent "$a" "$b" "$c";;
    fav)     if [ "$b" = "-" ]; then ct_shell "$a"; else dk_shell "$(mode_ctx "$a")" "$a" "$b"; fi;;
    favgone) if [ "$MODE" = docker ]; then tf a2 screens.favgone.container "$b"; else tf a2 screens.favgone.ct "$a"; fi
             ui_confirm "$(t screens.favgone.confirm "$a2" "$(target_label "$a" "$b" /)")" && fav_toggle "$a" "$b";;
  esac
}

open_recent() { # gruppe ziel aktion
  local ctx; ctx=$(mode_ctx "$1")
  case "$3" in
    ctshell) ct_shell "$1"; return 0;;
    project) screen_project "$1"; return 0;;
  esac
  rec_gone "$ctx" "$1" "$2" && return 0
  case "$3" in
    logs)    state_add_recent "$1" "$2" logs; dk_logs "$ctx" "$2";;
    compose) dk_compose_shell "$ctx" "$(dk_dir "$2")" "$1" "$2";;
    *)       dk_shell "$ctx" "$1" "$2";;
  esac
}
# Container aus dem Verlauf fehlt sicher (Docker erreichbar, Name nicht da): Eintrag entfernen, melden.
# Lädt DK_ROWS für den Kontext. Rückgabe 0 = fehlt (erledigt), 1 = weiter mit der Aktion
rec_gone() { # kontext gruppe container
  dk_load "$1"
  [ "$DK_RC" -eq 0 ] && [ -z "$(dk_row "$3")" ] || return 1
  state_del_recent "$2" "$3"
  ui_msg err "$(t screens.recent.gone "$3" "$(dk_in "$1")")"
}

# ─── CT-Screen (incus, layered) ────────────────────────────────────────────
screen_ct() { # ct
  local ct=$1 st ip n state status image k
  while true; do
    st=$(ct_status "$ct")
    if [ -z "$st" ]; then ui_msg err "$(t screens.ct.missing "$ct")"; return 0; fi
    ip=$(ct_ip "$ct")
    [ -n "${PD_DESC[$ct]:-}" ] && ui_info "${TX[screens.info.info]}" "${PD_DESC[$ct]}"
    if [ "$MODE" = layered ]; then
      dk_load "$ct"
      ui_item header "" "${TX[screens.ct.section_docker]}" "" main
      if [ "$DK_RC" -ne 0 ]; then ui_item disabled "" "($(dk_msg "$ct" "$DK_RC"))"
      elif [ -z "$DK_ROWS" ]; then ui_item disabled "" "${TX[screens.ct.no_containers]}"
      else
        while IFS='|' read -r n state status image ports _; do
          [ -n "$n" ] || continue
          dk_cells "$image" "$status" "$ports"
          ui_item item "c:$n" "$n" "$image  $status" "$(dk_state_status "$state" "$status")" "$FMT"
        done <<< "$DK_ROWS"
      fi
      ui_item header "" "${TX[screens.ct.section_ct]}" "" main
    fi
    ui_item item ctshell "${TX[screens.ct.shell]}" "incus exec $ct -- bash"
    ui_item item ctstart "${TX[screens.ct.start]}"
    ui_item item ctstop "${TX[screens.ct.stop]}" "" danger
    ui_item item ctrestart "${TX[screens.ct.restart]}" "" danger
    ui_item item ctinfo "incus info"
    ui_item item ctlog "${TX[screens.ct.log]}" "incus info --show-log"
    ui_item item ctres "${TX[screens.ct.resources]}" "${TX[screens.ct.resources_desc]}"
    UI_KEYS=("r|${TX[screens.key.reload]}")
    if is_fav "$ct" "-"; then tf k screens.key.fav_remove "$UI_SYM_FAV"; else tf k screens.key.fav_add "$UI_SYM_GONE"; fi
    UI_KEYS+=("f|$k")
    ui_menu "$ct" "$ip · $st"
    case "$UI_ACT" in
      back|quit|eof) return 0;;
      key) case "$UI_SEL" in r) ct_load;; f) fav_toggle "$ct" "-";; esac;;
      select)
        case "$UI_SEL" in
          c:*)       screen_container "$ct" "$ct" "${UI_SEL#c:}";;
          ctshell)   ct_shell "$ct"; ct_load;;
          ctstart)   ct_action "$ct" start; ct_load;;
          ctstop)    ui_confirm "$(t screens.ct.confirm_stop "$ct")" && { ct_action "$ct" stop; ct_load; };;
          ctrestart) ui_confirm "$(t screens.ct.confirm_restart "$ct")" && { ct_action "$ct" restart; ct_load; };;
          ctinfo)    ct_info "$ct";;
          ctlog)     ct_log "$ct";;
          ctres)     ct_resources "$ct";;
        esac;;
    esac
  done
}

# ─── Compose-Projekt bzw. Einzelcontainer (docker; layered nur aus Docker-Health) ─
# kontext leer = Host-Docker (docker-Modus), sonst der CT. Verlauf und Favoriten-Gruppe wie beim
# Container-Screen: docker = Projekt bzw. "-", layered = CT. Verlaufseintrag nur im docker-Modus.
screen_project() { # projekt ("-" = Einzelcontainer) [kontext]
  local p=$1 ctx=${2:-} rows n state status image proj svc d dir total run title
  [ "$p" = "-" ] || [ -n "$ctx" ] || state_add_recent "$p" "-" project   # Projekt öffnen = Verlaufseintrag
  while true; do
    dk_load "$ctx"
    rows=$(dk_rows_of "$p")
    if [ -z "$rows" ]; then
      if [ "$DK_RC" -ne 0 ]; then ui_msg err "${ctx:+$ctx: }$(dk_msg "$ctx" "$DK_RC")."
      else ui_msg err "$(t screens.project.no_containers "$p")"; fi
      return 0
    fi
    dir="" total=0 run=0
    ui_item header "" "${TX[screens.project.section_containers]}" "" main
    while IFS='|' read -r n state status image ports proj svc d; do
      total=$((total+1)); [ "$state" = running ] && run=$((run+1)); [ -z "$dir" ] && dir=$d
      if [ "$p" = "-" ]; then
        dk_cells "$image" "$status" "$ports"
        ui_item item "c:$n" "$n" "$image  $status" "$(dk_state_status "$state" "$status")" "$FMT"
      else
        dk_cells "$n" "$status" "$ports"
        ui_item item "c:$n" "${svc:-$n}" "$n  $status" "$(dk_state_status "$state" "$status")" "$FMT"
      fi
    done <<< "$rows"
    title=$p
    if [ "$p" = "-" ]; then
      title=${TX[screens.main.standalone]}
      ui_info "${TX[screens.info.info]}" "${TX[screens.project.standalone_info]}"
    else
      [ -n "${PD_DESC[$p]:-}" ] && ui_info "${TX[screens.info.info]}" "${PD_DESC[$p]}"
      [ -n "$dir" ] && ui_info "${TX[screens.info.dir]}" "$dir"
      ui_item header "" "${TX[screens.project.section_project]}" "" main
      ui_item item plogs "${TX[screens.project.logs]}" "${TX[screens.project.logs_desc]}"
      ui_item item pps "compose ps"
      ui_item item prestart "${TX[screens.action.restart]}" "${TX[screens.project.all_services]}" danger
      ui_item item pstop "${TX[screens.action.stop]}" "${TX[screens.project.all_services]}" danger
      ui_item item pstart "${TX[screens.action.start]}" "${TX[screens.project.all_services]}"
      if [ -n "$dir" ] && [ -n "$ctx" ]; then ui_item item pdir "${TX[screens.action.open_compose_dir]}" "$(t screens.project.dir_desc_ct "$ctx" "$dir")"
      elif [ -n "$dir" ]; then ui_item item pdir "${TX[screens.action.open_compose_dir]}" "$(t screens.project.dir_desc "$dir")"; fi
    fi
    UI_KEYS=("r|${TX[screens.key.reload]}")
    ui_menu "$title" "$(t screens.project.running "$run" "$total")"
    case "$UI_ACT" in
      back|quit|eof) return 0;;
      select)
        case "$UI_SEL" in
          c:*)      screen_container "$ctx" "${ctx:-$p}" "${UI_SEL#c:}";;
          plogs)    dk_compose_logs "$ctx" "$p";;
          pps)      dk_compose_ps "$ctx" "$p";;
          prestart) ui_confirm "$(t screens.project.confirm_restart "$p")" && dk_compose_action "$ctx" "$p" restart;;
          pstop)    ui_confirm "$(t screens.project.confirm_stop "$p")" && dk_compose_action "$ctx" "$p" stop;;
          pstart)   dk_compose_action "$ctx" "$p" start;;
          pdir)     dk_compose_shell "$ctx" "$dir" "$p" "";;
        esac;;
    esac
  done
}

# ─── Container-Screen (docker und layered, gleicher Code) ──────────────────
screen_container() { # kontext gruppe container
  local ctx=$1 grp=$2 c=$3 line state status image ports proj svc dir policy health target k
  while true; do
    dk_load "$ctx"
    line=$(dk_row "$c")
    if [ -z "$line" ]; then
      if [ "$DK_RC" -ne 0 ]; then ui_msg err "${ctx:-Docker}: $(dk_msg "$ctx" "$DK_RC")."
      else ui_msg err "$(t screens.container.missing "$c" "$(dk_in "$ctx")")"; fi
      return 0
    fi
    IFS='|' read -r _ state status image ports proj svc _ <<< "$line"
    dir=$(dk_dir "$c")
    policy=$(dk_restart_policy "$ctx" "$c")
    health=$(dk_health "$status")
    if [ -n "$ctx" ]; then target="$ctx/$c"; elif [ "$grp" = "-" ]; then target=$c; else target="$grp/$c"; fi
    ui_info "${TX[screens.info.image]}" "$image"
    ui_info "${TX[screens.info.status]}" "$status" "$(dk_state_status "$state" "$status")"
    case "$health" in
      healthy) _cell p-ok healthy;; unhealthy) _cell p-err unhealthy;; starting) _cell p-warn starting;;
      *) _cell dim "${TX[screens.container.no_healthcheck]}";;
    esac
    ui_info "${TX[screens.info.health]}" "$FMT"
    [ -n "${ports// /}" ] && ui_info "${TX[screens.info.ports]}" "$ports"
    [ -n "$proj" ] && [ "$proj" != "<no value>" ] && ui_info "${TX[screens.info.project]}" "$proj${svc:+ / $svc}"
    [ -n "$dir" ] && ui_info "${TX[screens.info.compose]}" "$dir${ctx:+  ${TX[screens.container.dir_in_ct]}}"
    [ -n "$policy" ] && ui_info "${TX[screens.info.restart_policy]}" "$policy"
    ui_info "${TX[screens.info.fastpath]}" "$(fastpath "$target")"
    ui_item item shell "${TX[screens.container.shell]}" "docker exec, bash→sh"
    ui_item item logs "${TX[screens.container.logs]}" "${TX[screens.container.logs_desc]}"
    ui_item item restart "${TX[screens.action.restart]}" "" danger
    ui_item item stop "${TX[screens.action.stop]}" "" danger
    ui_item item start "${TX[screens.action.start]}"
    [ -n "$dir" ] && ui_item item compose "${TX[screens.action.open_compose_dir]}" "$dir"
    ui_item item hstate "${TX[screens.container.state]}" "${TX[screens.container.state_desc]}"
    if is_fav "$grp" "$c"; then tf k screens.key.fav_remove "$UI_SYM_FAV"; else tf k screens.key.fav_add "$UI_SYM_GONE"; fi
    UI_KEYS=("f|$k")
    ui_menu "$c" "${ctx:-${proj:-Docker}}"
    case "$UI_ACT" in
      back|quit|eof) return 0;;
      key) [ "$UI_SEL" = f ] && fav_toggle "$grp" "$c";;
      select)
        case "$UI_SEL" in
          shell)   dk_shell "$ctx" "$grp" "$c";;
          logs)    state_add_recent "$grp" "$c" logs; dk_logs "$ctx" "$c";;
          restart) ui_confirm "$(t screens.container.confirm_restart "$c")" && dk_action "$ctx" restart "$c";;
          stop)    ui_confirm "$(t screens.container.confirm_stop "$c")" && dk_action "$ctx" stop "$c";;
          start)   dk_action "$ctx" start "$c";;
          compose) dk_compose_shell "$ctx" "$dir" "$grp" "$c";;
          hstate)  dk_state_page "$ctx" "$c";;
        esac;;
    esac
  done
}

# ─── Werkzeuge ─────────────────────────────────────────────────────────────
# Oben „Zuletzt“ (zuletzt benutzte Werkzeuge, höchstens RECENT_MAX), darunter alle Werkzeuge.
screen_tools() {
  local id ts g t a n
  while true; do
    n=0
    while IFS='|' read -r ts g t a; do
      [ "$n" -lt "$RECENT_MAX" ] || break
      if [ "$g" != "@tool" ] || [ -z "${TOOL_TITLE[$t]+x}" ] || ! tool_available "$t"; then continue; fi
      [ $n -eq 0 ] && ui_item header "" "${TX[screens.section.recent]}" "" recent
      ui_item item "rec:$t" "${TOOL_TITLE[$t]}" "$(rel_time "$ts")"
      n=$((n+1))
    done < <(state_recents)
    [ $n -gt 0 ] && ui_item header "" "${TX[screens.tools.section_all]}" "" main
    for id in $(tool_list); do ui_item item "$id" "${TOOL_TITLE[$id]}" "${TOOL_DESC[$id]}"; done
    ui_menu "${TX[screens.tools.title]}" "$(t screens.tools.mode "$MODE")"
    case "$UI_ACT" in
      select) PD_RELOAD=0; tool_run "${UI_SEL#rec:}"; [ "$PD_RELOAD" = 1 ] && return 0;;
      *) return 0;;
    esac
  done
}
