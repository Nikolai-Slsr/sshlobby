# shellcheck shell=bash
# cli.sh: Argumente, --list, --go, --setup, update (→ cli_update in update.sh) und der Einstieg pd_main.

usage() {
  local noarg go
  printf -v noarg '%-18s' "${TX[cli.usage.noarg]}"
  printf -v go '%-18s' "--go <${TX[cli.usage.target]}>"
  cat <<EOF
${TX[cli.usage.synopsis]}
  $noarg${TX[cli.usage.menu]}
  --list            ${TX[cli.usage.list]}
  $go${TX[cli.usage.go]}
                      layered: ${TX[cli.usage.go_layered]}
                      incus:   <ct>
                      docker:  ${TX[cli.usage.go_docker]}
  --setup           ${TX[cli.usage.setup]}
  --settings        ${TX[cli.usage.settings]}
  --reset           ${TX[cli.usage.reset]}
  --mode <m>        ${TX[cli.usage.mode]}
  update            ${TX[cli.usage.update]}
    --check         ${TX[cli.usage.update_check]}
    -y, --yes       ${TX[cli.usage.update_yes]}
  -h, --help        ${TX[cli.usage.help]}
  --version         ${TX[cli.usage.version]}
${TX[cli.usage.exit_codes]}
${TX[cli.usage.update_exit]}

$UPD_WEB/$UPD_DEFAULT_REPO
EOF
}
usage_err() { usage >&2; exit "$PD_EXIT_USAGE"; }

# ─── --list ────────────────────────────────────────────────────────────────
cli_list() {
  local ct dn n status _x proj
  case "$MODE" in
    layered)
      ct_load
      printf '%s%-18s %-10s %-15s %s%s\n' "$C_B" "CT" "STATUS" "IP" "DOCKER" "$C_R"
      for ct in $(ct_names); do
        dn=$(dk_ps "$ct" '{{.Names}}')
        case $? in
          0) dn=$(printf '%s' "$dn" | grep -c .);;
          1) dn="-";;
          3) dn=${TX[cli.list.no_docker]};;
          *) dn="?";;
        esac
        printf '%s%-18s%s %-10s %-15s %s\n' "$C_WHT" "$ct" "$C_R" "$(ct_status "$ct")" "$(ct_ip "$ct")" "$dn"
      done;;
    incus)
      ct_load
      printf '%s%-18s %-10s %s%s\n' "$C_B" "CT" "STATUS" "IP" "$C_R"
      for ct in $(ct_names); do
        printf '%s%-18s%s %-10s %s\n' "$C_WHT" "$ct" "$C_R" "$(ct_status "$ct")" "$(ct_ip "$ct")"
      done;;
    docker)
      dk_load ""
      if [ "$DK_RC" -ne 0 ]; then printf 'sshlobby: %s\n' "$(dk_msg "" "$DK_RC")" >&2; return 1; fi
      printf '%s%-18s %-28s %s%s\n' "$C_B" "${TX[cli.list.project]}" "CONTAINER" "STATUS" "$C_R"
      while IFS='|' read -r proj _x _x _x _x _x; do
        while IFS='|' read -r n _x status _x; do
          printf '%-18s %s%-28s%s %s\n' "$proj" "$C_WHT" "$n" "$C_R" "$status"
        done < <(dk_rows_of "$proj")
      done < <(dk_projects | sort -t'|' -k1,1 | awk -F'|' '$1!="-"{print} $1=="-"{last=$0} END{if (last!="") print last}')
      ;;
  esac
}

# ─── --go ──────────────────────────────────────────────────────────────────
cli_go() { # ziel
  local t=$1 ct c="" tflag="-it" st line proj
  [ -t 0 ] || tflag="-i"
  [ -n "$t" ] || usage_err
  if [ "$MODE" = docker ]; then
    if [[ "$t" == */* ]]; then proj=${t%%/*} c=${t#*/}; else proj="" c=$t; fi
    if [ -z "$c" ] || [[ "$c" == */* ]] || { [[ "$t" == */* ]] && [ -z "$proj" ]; }; then usage_err; fi
    dk_load ""
    [ "$DK_RC" -eq 0 ] || { printf 'sshlobby: %s\n' "$(dk_msg "" "$DK_RC")" >&2; exit 1; }
    line=$(dk_row "$c")
    [ -n "$line" ] || { printf 'sshlobby: %s\n' "$(t cli.err.no_container "$c")" >&2; exit 1; }
    IFS='|' read -r _ _ _ _ _ st _ <<< "$line"; st=${st:--}
    if [ -n "$proj" ] && [ "$proj" != "$st" ]; then
      printf 'sshlobby: %s\n' "$(t cli.err.wrong_project "$c" "$st" "$proj")" >&2; exit 1
    fi
    dk_preflight "" "$c" || { printf 'sshlobby: %s\n' "$PF_MSG" >&2; exit 1; }
    state_add_recent "$st" "$c" shell
    dk_argv ""; exec "${DK_ARGV[@]}" exec "$tflag" "$c" sh -c "$DK_SHELL_CMD"
  fi
  ct="${t%%/*}"
  [[ "$t" == */* ]] && c="${t#*/}"
  [ -n "$ct" ] || usage_err
  if [ "$MODE" = incus ] && [ -n "$c" ]; then
    printf 'sshlobby: %s\n' "${TX[cli.err.incus_go]}" >&2; exit "$PD_EXIT_USAGE"
  fi
  ct_load; st=$(ct_status "$ct")
  [ -n "$st" ] || { printf 'sshlobby: %s\n' "$(t cli.err.no_ct "$ct")" >&2; exit 1; }
  [ "$st" = "Running" ] || { printf 'sshlobby: %s\n' "$(t incus.not_running "$ct" "$st")" >&2; exit 1; }
  if [ -z "$c" ]; then
    state_add_recent "$ct" "-" ctshell
    exec incus exec "$ct" -- bash -l
  fi
  dk_preflight "$ct" "$c" || { printf 'sshlobby: %s\n' "$PF_MSG" >&2; exit 1; }
  state_add_recent "$ct" "$c" shell
  dk_argv "$ct"; exec "${DK_ARGV[@]}" exec "$tflag" "$c" sh -c "$DK_SHELL_CMD"
}

# ─── Einstieg ──────────────────────────────────────────────────────────────
pd_main() {
  local action="" target="" mode_arg="" rc upd_check=0 upd_yes=0
  set_action() { [ -z "$action" ] || usage_err; action=$1; }
  while [ $# -gt 0 ]; do
    case "$1" in
      --list)      set_action list;;
      --go)        [ $# -ge 2 ] || usage_err; set_action go; target=$2; shift;;
      --setup)     set_action setup;;
      --settings)  set_action settings;;
      --reset)     set_action reset;;
      --mode)      [ $# -ge 2 ] || usage_err; mode_arg=$2; shift;;
      --mode=*)    mode_arg=${1#--mode=};;
      update|--update) set_action update;;
      --check)     upd_check=1;;
      -y|--yes)    upd_yes=1;;
      -h|--help)   set_action help;;
      --version)   set_action version;;
      *)           usage_err;;
    esac
    shift
  done
  # --check und --yes gibt es nur zusammen mit update
  if [ "$action" != update ] && [ $((upd_check + upd_yes)) -gt 0 ]; then usage_err; fi
  case "$action" in
    help)    usage; exit 0;;
    version) echo "sshlobby $VERSION"; exit 0;;
  esac
  if [ -n "$mode_arg" ] && ! mode_valid "$mode_arg"; then
    printf 'sshlobby: %s\n' "$(t cli.err.bad_mode "$mode_arg")" >&2; usage_err
  fi
  cfg_load
  desc_load
  cfg_apply
  # Vom Login-Hook gestartet (SSHLOBBY_LOGIN=1) und AUTOSTART=no: still beenden, die Shell läuft weiter.
  # Die Variable nie an Kinder (Host-Shell, Editor) weitergeben, sonst gälte ein späterer Handstart als Login.
  local from_login=${SSHLOBBY_LOGIN:-}
  unset SSHLOBBY_LOGIN
  if [ -z "$action" ] && [ "$from_login" = 1 ] && [ "$AUTOSTART" = no ]; then exit "$PD_EXIT_OK"; fi
  case "$action" in
    update)
      cli_update "$upd_check" "$upd_yes"; exit $?;;
    list|go)
      mode_resolve "$mode_arg" || exit "$PD_EXIT_USAGE"
      if [ "$action" = list ]; then cli_list; exit $?; fi
      cli_go "$target";;
    setup)
      ui_init
      setup_run; exit $?;;
    settings|reset)
      ui_init
      mode_resolve "$mode_arg" 0 || exit "$PD_EXIT_USAGE"
      if [ "$MODE_SRC" = auto ]; then setup_detect; MODE=$DET_MODE; fi
      if [ "$action" = reset ]; then settings_reset all; else screen_settings; fi
      exit "$PD_EXIT_OK";;
  esac
  # Menü: ohne Config am Terminal zuerst der Setup-Screen, sonst still erkennen
  ui_init
  mode_resolve "$mode_arg" 0 || exit "$PD_EXIT_USAGE"
  if [ "$MODE_SRC" = auto ]; then
    if [ "$UI_MODE" = tui ]; then setup_run || MODE=$DET_MODE
    else setup_detect; MODE=$DET_MODE; fi
  fi
  screen_main; rc=$?
  exit "$rc"
}
