# shellcheck shell=bash
# backend_docker.sh: Docker über einen Kontext-Wrapper, damit docker- und layered-Modus denselben
# Code nutzen. Kontext "" = Docker auf dem Host, Kontext "<ct>" = incus exec <ct> -- docker.
# Daten (dk_load, dk_row, dk_projects …) ohne Ausgabe, Aktionen über die UI-Primitive.
# shellcheck disable=SC2034,SC1111 # DK_* lesen die Screens (SC1111: „…“ sind gewollte Anführungszeichen)

# Eine Zeile pro Container, Arbeitsordner zuletzt (darf als einziges Feld | enthalten):
# name|state|status|image|ports|projekt|service|ordner
DK_FMT='{{.Names}}|{{.State}}|{{.Status}}|{{.Image}}|{{.Ports}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}|{{.Label "com.docker.compose.project.working_dir"}}'
DK_ROWS="" DK_RC=0
DK_SHELL_CMD='command -v bash >/dev/null && exec bash || exec sh'

dk_argv() { # kontext → DK_ARGV (Aufruf von docker im Kontext)
  if [ -z "$1" ]; then DK_ARGV=(docker); else DK_ARGV=(incus exec "$1" -- docker); fi
}
dk() { # kontext args… : nicht-interaktiv, stdin </dev/null
  local -a DK_ARGV; dk_argv "$1"; shift
  "${DK_ARGV[@]}" "$@" </dev/null
}
dk_tty() { # kontext args… : interaktiv (Shell, logs -f), stdin bleibt beim Terminal
  local -a DK_ARGV; dk_argv "$1"; shift
  "${DK_ARGV[@]}" "$@"
}

# docker ps im Kontext. Exit: 0 ok, 1 CT läuft nicht oder fehlt, 2 Docker nicht erreichbar,
# 3 kein Docker installiert (incus exec reicht 127 vom fehlenden Befehl durch)
dk_ps() { # kontext format [optionen…]
  local ctx=$1 fmt=$2 rc; shift 2
  if [ -n "$ctx" ]; then
    [ "$(ct_status "$ctx")" = "Running" ] || return 1
  elif ! command -v docker >/dev/null 2>&1; then
    return 3
  fi
  dk "$ctx" ps "$@" --format "$fmt" 2>/dev/null && return 0
  rc=$?; [ "$rc" -eq 127 ] && return 3
  return 2
}
dk_msg() { # kontext rc → Text
  case "$2" in
    1) printf '%s' "${TX[docker.err.ct_down]}";;
    3) printf '%s' "${TX[docker.err.not_installed]}";;
    *) if [ -n "$1" ]; then printf '%s' "${TX[docker.err.unreachable_ct]}"; else printf '%s' "${TX[docker.err.unreachable]}"; fi;;
  esac
}
dk_in() { [ -n "$1" ] && printf ' %s' "$(t docker.in "$1")"; } # kontext → " in <ct>" für Meldungen

# Alle Container eines Kontexts → DK_ROWS (Format DK_FMT), DK_RC wie dk_ps
dk_load() { # kontext
  DK_ROWS=$(dk_ps "$1" "$DK_FMT" -a); DK_RC=$?
  [ "$DK_RC" -eq 0 ] || DK_ROWS=""
}
dk_row() { printf '%s\n' "$DK_ROWS" | awk -F'|' -v n="$1" '$1==n{print; exit}'; } # exakter Name
dk_dir() { # container → Compose-Ordner aus DK_ROWS (alles nach dem 7. Trenner)
  dk_row "$1" | awk '{ for (i=1; i<=7; i++) sub(/^[^|]*\|/, ""); if ($0!="" && $0!="<no value>") print }'
}
# Compose-Projekte aus DK_ROWS: "projekt|gesamt|laufend|unhealthy|ordner", "-" = ohne Projekt
dk_projects() {
  printf '%s\n' "$DK_ROWS" | awk -F'|' '$1!="" {
      p = ($6=="" || $6=="<no value>") ? "-" : $6; t[p]++
      if ($2=="running") r[p]++
      if ($3 ~ /unhealthy/) u[p]++
      d=$0; for (i=1; i<=7; i++) sub(/^[^|]*\|/, "", d)
      if (dir[p]=="" && d!="<no value>") dir[p]=d
    }
    END { for (p in t) printf "%s|%d|%d|%d|%s\n", p, t[p], r[p], u[p], dir[p] }' | sort -t'|' -k1,1
}
dk_rows_of() { # projekt ("-" = ohne Projekt) → Zeilen aus DK_ROWS, nach Service und Name
  printf '%s\n' "$DK_ROWS" | awk -F'|' -v p="$1" \
    '$1!="" { q = ($6=="" || $6=="<no value>") ? "-" : $6; if (q==p) print }' | sort -t'|' -k7,7 -k1,1
}
dk_state_status() { # state status → Markierung für ui_item (run stop warn err)
  case "$1" in
    running) case "$2" in *unhealthy*) printf err;; *) printf run;; esac;;
    exited|dead|created) printf stop;;
    *) printf warn;;
  esac
}
dk_health() { # status-text → healthy | unhealthy | starting | ""
  case "$1" in *unhealthy*) printf unhealthy;; *"health: starting"*) printf starting;; *healthy*) printf healthy;; esac
}
dk_restart_policy() { # kontext container
  dk "$1" inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$2" 2>/dev/null | head -n1
}

dk_preflight() { # kontext container → 0 bereit, sonst Text in PF_MSG
  local ctx=$1 line rc
  PF_MSG=""
  line=$(dk_ps "$ctx" '{{.Names}}|{{.State}}' -a); rc=$?
  if [ "$rc" -ne 0 ]; then PF_MSG="${ctx:-Docker}: $(dk_msg "$ctx" "$rc")"; return 1; fi
  line=$(printf '%s\n' "$line" | awk -F'|' -v n="$2" '$1==n{print $2; exit}')
  if [ -z "$line" ]; then tf PF_MSG docker.preflight.missing "$2" "$(dk_in "$ctx")"; return 1; fi
  if [ "$line" != "running" ]; then tf PF_MSG docker.preflight.not_running "$2" "$line"; return 1; fi
}

# ─── Container-Aktionen ────────────────────────────────────────────────────
dk_shell() { # kontext gruppe container (tty-adaptiv)
  local tflag="-it"; [ -t 0 ] || tflag="-i"
  dk_preflight "$1" "$3" || { ui_msg err "$PF_MSG"; return 0; }
  state_add_recent "$2" "$3" shell
  ui_run_fg dk_tty "$1" exec "$tflag" "$3" sh -c "$DK_SHELL_CMD"
}

_dk_follow() { # kontext args… (logs -f, bis Ctrl-C)
  local rc
  dk_tty "$@"; rc=$?
  printf '\n%s%s%s\n' "$C_GRY" "${TX[docker.logs.ended]}" "$C_R"
  return "$rc"
}
dk_logs() { # kontext container
  ui_run_fg _dk_follow "$1" logs -f --tail 100 "$2"
  ui_check_rc $? "$(t docker.logs.label "${1:+$1/}$2")"
}

dk_action() { # kontext restart|stop|start container
  local verb
  case "$2" in start|stop|restart) verb=${TX[docker.verb.$2]};; *) return 1;; esac
  ui_run_task "$3: $verb" dk "$1" "$2" "$3"
}

_pd_shell_in() { ( cd -- "$1" && exec "${SHELL:-/bin/bash}" -l ); } # Host-Shell in einem Ordner

dk_compose_shell() { # kontext ordner gruppe container (container leer = kein Verlaufseintrag)
  local ctx=$1 dir=$2
  if [ -z "$dir" ]; then ui_msg err "${TX[docker.compose.no_dir]}"; return 0; fi
  if [ -z "$ctx" ]; then
    if [ ! -d "$dir" ]; then ui_msg err "$(t docker.compose.dir_missing "$dir")"; return 0; fi
    [ -n "$4" ] && state_add_recent "$3" "$4" compose
    ui_run_fg _pd_shell_in "$dir"
    return 0
  fi
  if [ "$(ct_status "$ctx")" != "Running" ]; then ui_msg err "$(t docker.compose.ct_down "$ctx")"; return 0; fi
  if ! incus exec "$ctx" -- test -d "$dir" </dev/null 2>/dev/null; then
    ui_msg err "$(t docker.compose.dir_missing_ct "$dir" "$ctx")"; return 0
  fi
  [ -n "$4" ] && state_add_recent "$3" "$4" compose
  # Pfad als Positionsargument, nie in den Befehlsstring (Quotes, Labels aus Docker)
  # shellcheck disable=SC2016 # $1 soll erst im CT expandieren
  ui_run_fg incus exec "$ctx" -- sh -c 'cd "$1" && { command -v bash >/dev/null && exec bash -l || exec sh -l; }' sh "$dir"
}

# ─── Compose-Projekt (docker compose -p ohne Compose-Datei: logs, ps, restart, stop, start) ─
dk_compose_logs() { # kontext projekt
  ui_run_fg _dk_follow "$1" compose -p "$2" logs -f --tail 100
  ui_check_rc $? "$(t docker.logs.project "$2")"
}
dk_compose_ps() { ui_run_page "compose ps: $2" dk "$1" compose -p "$2" ps; } # kontext projekt
dk_compose_action() { # kontext projekt restart|stop|start
  local verb
  case "$3" in start|stop|restart) verb=${TX[docker.verb.$3]};; *) return 1;; esac
  ui_run_task "$(t docker.task.project "$2" "$verb")" dk "$1" compose -p "$2" "$3"
}

# ─── Zustand und Healthcheck (docker inspect) ──────────────────────────────
_dk_kv() { # label wert [farbe] → eingerückte Zeile, Label auf DK_KVW Zeichen aufgefüllt (UTF-8-sicher)
  local l=$1 pad
  printf -v pad '%*s' $((DK_KVW - ${#l})) ''
  printf '  %s%s%s%s %s%s%s\n' "$C_GRY" "$l" "$pad" "$C_R" "${3:-}" "$2" "${3:+$C_R}"
}
# Zustand, Neustarts, OOM-Kill, Fehler, Healthcheck und dessen letzte Prüfungen (neueste zuerst)
dk_state_show() { # kontext container
  local json key a b c lbl v k logs=0 hc=0
  json=$(dk "$1" inspect "$2" 2>/dev/null)
  if [ -z "$json" ] || ! jq -e '.[0].State' >/dev/null 2>&1 <<< "$json"; then
    printf '  %s%s%s\n' "$C_YLW" "$(t docker.state.failed "$2")" "$C_R"; return 0
  fi
  DK_KVW=0
  for k in state started finished exit restarts policy oom error health check; do
    lbl=${TX[docker.state.$k]}; [ ${#lbl} -gt "$DK_KVW" ] && DK_KVW=${#lbl}
  done
  while IFS=$'\x1f' read -r key a b c; do               # Trenner US: leere Felder bleiben erhalten
    lbl=${TX[docker.state.$key]:-}
    case "$key" in
      state)    case "$a" in running) v=$C_GRN;; restarting|dead) v=$C_RED;; *) v=$C_YLW;; esac; _dk_kv "$lbl" "$a" "$v";;
      exit)     if [ "$a" = 0 ]; then _dk_kv "$lbl" "$a"; else _dk_kv "$lbl" "$a" "$C_YLW"; fi;;
      restarts) if [ "$a" -ge 3 ] 2>/dev/null; then _dk_kv "$lbl" "$a" "$C_YLW"; else _dk_kv "$lbl" "$a"; fi;;
      oom)      if [ "$a" = true ]; then _dk_kv "$lbl" "${TX[docker.state.yes]}" "$C_RED"; else _dk_kv "$lbl" "${TX[docker.state.no]}"; fi;;
      health)   [ -n "$a" ] || continue; hc=1; tf v docker.state.health_val "$a" "$b"
                case "$a" in healthy) _dk_kv "$lbl" "$v" "$C_GRN";; unhealthy) _dk_kv "$lbl" "$v" "$C_RED";; *) _dk_kv "$lbl" "$v" "$C_YLW";; esac;;
      check)    [ -n "$a" ] && { hc=1; _dk_kv "$lbl" "$a"; };;
      log)      [ "$logs" = 1 ] || { printf '\n  %s%s%s\n' "$C_B" "${TX[docker.state.log_head]}" "$C_R"; logs=1; }
                if [ "$b" = 0 ]; then v=$C_GRN; else v=$C_RED; fi
                tf k docker.state.log_exit "$b"; printf '  %s  %s%s%s  %s\n' "$a" "$v" "$k" "$C_R" "$c";;
      *)        [ -n "$a" ] && [ -n "$lbl" ] && _dk_kv "$lbl" "$a";;
    esac
  done < <(jq -r 'def ts: if . == null or . == "" or startswith("0001-") then ""
                          else sub("\\.[0-9]+"; "") | sub("T"; " ") | sub("Z$"; " UTC") end;
      .[0] as $c | $c.State as $s
      | (["state", ($s.Status // "?")],
         ["started", ($s.StartedAt | ts)],
         ["finished", (if $s.Status == "running" then "" else ($s.FinishedAt | ts) end)],
         ["exit", ($s.ExitCode // 0 | tostring)],
         ["restarts", ($c.RestartCount // 0 | tostring)],
         ["policy", ($c.HostConfig.RestartPolicy.Name // "")],
         ["oom", ($s.OOMKilled // false | tostring)],
         ["error", ($s.Error // "" | gsub("[\t\r\n]+"; " "))],
         (if $s.Health then ["health", ($s.Health.Status // "?"), ($s.Health.FailingStreak // 0 | tostring)] else empty end),
         ["check", ($c.Config.Healthcheck.Test // [] | if length == 0 or .[0] == "NONE" then ""
                    elif .[0] == "CMD-SHELL" or .[0] == "CMD" then .[1:] | join(" ") else join(" ") end)]),
        ($s.Health.Log // [] | reverse | .[]
          | ["log", (.Start | ts), (.ExitCode // 0 | tostring), (.Output // "" | gsub("[\t\r\n]+"; " ") | .[0:300])])
      | map(tostring) | join("\u001f")' <<< "$json" 2>/dev/null)
  [ "$hc" = 1 ] || printf '\n  %s%s%s\n' "$C_GRY" "${TX[docker.state.no_check]}" "$C_R"
  return 0
}
dk_state_page() { ui_run_page "$(t docker.state.title "$2")" dk_state_show "$1" "$2"; } # kontext container
