# shellcheck shell=bash
# settings.sh: Einstellungen. Erreichbar über „e“ im Hauptmenü, das letzte Werkzeug „Einstellungen“,
# sshlobby --settings und sshlobby --reset.
# Alle Werte landen über cfg_set in ~/.config/sshlobby/config (KEY=wert, nie als Shell-Code geladen),
# Bedeutung und Defaults stehen bei cfg_load in core.sh. Zurücksetzen und Wiederherstellen legen vorher
# eine Sicherung unter ~/.config/sshlobby/backups/<JJJJMMTT-hhmmss>/ an, die neuesten 10 bleiben.
# shellcheck disable=SC1111,SC2034 # „…“ sind gewollte Anführungszeichen, UI_* liest ui.sh

SET_BACKUPS="$CONF_DIR/backups"
SET_KEEP=10
SET_CFG_FILES=(config descriptions)                          # „Einstellungen zurücksetzen“
SET_ALL_FILES=(config descriptions recents favorites service-favorites) # „Alles zurücksetzen“
SET_ENV_NOCOLOR=${NO_COLOR:-}                                 # NO_COLOR aus der Umgebung bleibt immer gültig

_set_onoff() { if [ "$1" = yes ]; then printf '%s' "${TX[settings.value.on]}"; else printf '%s' "${TX[settings.value.off]}"; fi; }
_set_lines() { local n=0; [ -r "$1" ] && n=$(grep -c . "$1" 2>/dev/null); printf '%s' "${n:-0}"; } # datei → Zeilen
_set_svcfavs() { printf '%s' "${SVC_FAVS:-$CONF_DIR/service-favorites}"; }

# Gelesene Werte anwenden: Farben, Symbole, bevorzugte Oberfläche (die greift erst bei ui_init)
cfg_apply() {
  if [ "$COLOR_PREF" = never ]; then NO_COLOR=1
  elif [ -z "$SET_ENV_NOCOLOR" ]; then unset NO_COLOR; fi
  if [ "$UI_PREF" = line ] && [ -z "${SSHLOBBY_UI:-}" ]; then SSHLOBBY_UI=line; fi
  ui_theme
  _UI_CLR=1
}

_set_save() { # key wert → speichern, neu einlesen, anwenden
  if ! cfg_set "$1" "$2"; then ui_msg err "$(t settings.save.failed "$CONF_FILE")"; return 1; fi
  cfg_load; cfg_apply
  ui_note ok "$(t settings.save.done "$1" "$2")"
}

# Login-Hook in ~/.bashrc: installiert? kennt er SSHLOBBY_LOGIN (ab 2.2.0)? → Hinweistext oder leer
_set_hook_note() {
  local rc=$HOME/.bashrc
  if ! grep -qxF '# >>> sshlobby >>>' "$rc" 2>/dev/null; then printf '%s' "${TX[settings.hook.missing]}" # Marker wie in install.sh
  elif ! grep -q 'SSHLOBBY_LOGIN=1' "$rc" 2>/dev/null; then printf '%s' "${TX[settings.hook.old]}"; fi
}

# ─── Hauptscreen ───────────────────────────────────────────────────────────
screen_settings() {
  local sel="" hook nb v off
  while true; do
    hook=$(_set_hook_note)
    nb=$(_set_backup_list | grep -c .)
    off=${TX[settings.value.off]}
    if [ "$CFG_EXISTS" = 1 ]; then ui_info "${TX[settings.info.config]}" "$CONF_FILE_SHOW"
    else tf v settings.info.config_new "$CONF_FILE_SHOW"; ui_info "${TX[settings.info.config]}" "$v" warn; fi
    ui_info "${TX[settings.info.version]}" "sshlobby $VERSION"
    ui_info "${TX[settings.info.github]}" "$UPD_WEB/$UPD_DEFAULT_REPO"   # Projektseite (Terminals machen Links klickbar)
    ui_item header "" "${TX[settings.group.general]}" "" main
    case "$MODE_SRC" in
      arg) tf v settings.mode.from_arg "$MODE" "${CFG_MODE:-${TX[settings.value.none]}}"; ui_item item mode "${TX[settings.mode]}" "$v";;
      env) tf v settings.mode.from_env "$MODE" "${CFG_MODE:-${TX[settings.value.none]}}"; ui_item item mode "${TX[settings.mode]}" "$v";;
      *)   ui_item item mode "${TX[settings.mode]}" "$MODE";;
    esac
    ui_item item label "${TX[settings.label]}" "$HOST_LABEL"
    if [ "$PD_LANG_SRC" = config ]; then ui_item item language "${TX[settings.language]}" "${TX[lang.name]} ($PD_LANG)"
    else tf v settings.language.auto "${TX[lang.name]}"; ui_item item language "${TX[settings.language]}" "$v"; fi
    tf v settings.value.lines "$(_set_lines "$DESCRIPTIONS")"; ui_item item desc "${TX[settings.desc]}" "$v"
    ui_item header "" "${TX[settings.group.start]}" "" main
    ui_item item autostart "${TX[settings.autostart]}" "$(_set_onoff "$AUTOSTART")${hook:+ · $hook}"
    if [ "$Q_ACTION" = shell ]; then ui_item item qaction "${TX[settings.qaction]}" "${TX[settings.qaction.shell]}"
    else ui_item item qaction "${TX[settings.qaction]}" "${TX[settings.qaction.logout]}"; fi
    if [ "$UI_PREF" = line ]; then ui_item item uimode "${TX[settings.uimode]}" "${TX[settings.uimode.line]}"
    else ui_item item uimode "${TX[settings.uimode]}" "${TX[settings.uimode.auto]}"; fi
    if [ "$COLOR_PREF" = never ]; then ui_item item color "${TX[settings.color]}" "$off"
    else ui_item item color "${TX[settings.color]}" "${TX[settings.value.auto]}"; fi
    if [ "$SYMBOLS_PREF" = ascii ]; then ui_item item symbols "${TX[settings.symbols]}" "${TX[settings.symbols.ascii]}"
    else ui_item item symbols "${TX[settings.symbols]}" "${TX[settings.value.auto]}"; fi
    ui_item header "" "${TX[settings.group.content]}" "" main
    if [ "$RECENT_MAX" -eq 0 ]; then ui_item item recentmax "${TX[settings.recentmax]}" "${TX[settings.recentmax.hidden]}"
    else ui_item item recentmax "${TX[settings.recentmax]}" "$RECENT_MAX"; fi
    have incus && ui_item item hermesct "${TX[settings.hermesct]}" "$(_set_onoff "$HERMES_SCAN_CTS")"
    ui_item item sshhosts "${TX[settings.sshhosts]}" "${SSH_HOSTS:-${TX[settings.sshhosts.default]}}"
    [ "$MODE" != docker ] && ui_item item cvect "${TX[settings.cvect]}" "${CVE_CT:-$off}"
    ui_item header "" "${TX[settings.group.updates]}" "" main
    _set_upd_items
    ui_item header "" "${TX[settings.group.reset]}" "" main
    ui_item item rerun "${TX[settings.rerun]}" "${TX[settings.rerun.desc]}"
    tf v settings.value.entries "$(_set_lines "$RECENTS")"; ui_item item clearrec "${TX[settings.clearrec]}" "$v"
    tf v settings.value.entries "$(( $(_set_lines "$FAVORITES") + $(_set_lines "$(_set_svcfavs)") ))"
    ui_item item clearfav "${TX[settings.clearfav]}" "$v"
    ui_item item resetcfg "${TX[settings.resetcfg]}" "${TX[settings.resetcfg.desc]}" danger
    ui_item item resetall "${TX[settings.resetall]}" "${TX[settings.resetall.desc]}" danger
    if [ "$nb" -gt 0 ]; then tf v settings.restore.count "$nb"; ui_item item restore "${TX[settings.restore]}" "$v"; fi
    ui_item item showcfg "${TX[settings.showcfg]}"
    UI_PRESEL=$sel
    ui_menu "${TX[settings.title]}" "${CONF_DIR/#$HOME/\~}"
    case "$UI_ACT" in
      select) sel=$UI_SEL; settings_do "$UI_SEL";;
      *) return 0;;
    esac
  done
}

settings_do() { # eintrag
  local v
  case "$1" in
    mode)      _set_mode;;
    label)     setup_label; cfg_load;;
    language)  _set_language;;
    desc)      _set_desc;;
    autostart) if [ "$AUTOSTART" = yes ]; then v=no; else v=yes; fi
               _set_save AUTOSTART "$v" && ui_note info "${TX[settings.autostart.note]}";;
    qaction)   if [ "$Q_ACTION" = shell ]; then v=logout; else v=shell; fi; _set_save Q_ACTION "$v";;
    uimode)    if [ "$UI_PREF" = line ]; then v=auto; else v=line; fi
               _set_save UI "$v" && ui_note info "${TX[settings.uimode.note]}";;
    color)     if [ "$COLOR_PREF" = never ]; then v=auto; else v=never; fi; _set_save COLOR "$v";;
    symbols)   if [ "$SYMBOLS_PREF" = ascii ]; then v=auto; else v=ascii; fi; _set_save SYMBOLS "$v";;
    recentmax) _set_recentmax;;
    hermesct)  if [ "$HERMES_SCAN_CTS" = yes ]; then v=no; else v=yes; fi; _set_save HERMES_SCAN_CTS "$v";;
    sshhosts)  _set_sshhosts;;
    cvect)     _set_cvect;;
    updcheck)  if [ "$UPDATE_CHECK" = yes ]; then v=no; else v=yes; fi; _set_save UPDATE_CHECK "$v";;
    updnow)    upd_tui;;
    rerun)     setup_run && { cfg_load; cfg_apply; PD_RELOAD=1; }; return 0;;
    clearrec)  ui_confirm "$(t settings.clearrec.confirm "$(_set_lines "$RECENTS")")" || return 0
               rm -f "$RECENTS" && ui_note ok "${TX[settings.clearrec.done]}";;
    clearfav)  ui_confirm "${TX[settings.clearfav.confirm]}" || return 0
               rm -f "$FAVORITES" "$(_set_svcfavs)" && ui_note ok "${TX[settings.clearfav.done]}";;
    resetcfg)  settings_reset cfg;;
    resetall)  settings_reset all;;
    restore)   _set_restore;;
    showcfg)   if [ -r "$CONF_FILE" ]; then ui_run_page "$(t settings.showcfg.title "$CONF_FILE")" cat "$CONF_FILE"
               else ui_msg info "$(t settings.showcfg.none "$CONF_FILE_SHOW")"; fi;;
  esac
  return 0
}

_set_mode() {
  local m
  for m in docker incus layered; do ui_item item "$m" "$m" "$(setup_mode_desc "$m")"; done
  UI_PRESEL=$MODE
  ui_menu "${TX[settings.mode]}" "$(t settings.value.current "$MODE")"
  [ "$UI_ACT" = select ] && [ "$UI_SEL" != "$MODE" ] || return 0
  _set_save MODE "$UI_SEL" || return 0
  CFG_MODE=$UI_SEL MODE=$UI_SEL MODE_SRC=config
  PD_RELOAD=1
}

_set_language() { # Sprachen aus lang/*.txt; nach dem Wechsel startet die TUI neu (Texte werden beim Start geladen)
  local l name
  ui_item item auto "$(t settings.language.auto "$(i18n_sys_lang)")"
  for l in $(i18n_langs); do
    # shellcheck disable=SC2030,SC2031 # PD_LANG nur in der Subshell umstellen, um den Namen der Sprache zu lesen
    name=$(PD_LANG=$l; i18n_load; printf '%s' "${TX[lang.name]}")
    ui_item item "$l" "$name" "$l"
  done
  # shellcheck disable=SC2031 # PD_LANG ist hier der Wert der Hauptshell
  if [ "$PD_LANG_SRC" = config ]; then UI_PRESEL=$PD_LANG; else UI_PRESEL=auto; fi
  # shellcheck disable=SC2031
  ui_menu "${TX[settings.language]}" "$PD_LANG"
  [ "$UI_ACT" = select ] || return 0
  if [ "$UI_SEL" = auto ]; then cfg_set LANGUAGE "" || return 0; else cfg_set LANGUAGE "$UI_SEL" || return 0; fi
  cfg_load
  i18n_detect; i18n_load
  if [ "$UI_MODE" = tui ]; then
    ui_note ok "$(t settings.language.saved "${TX[lang.name]}")"
    ui_cleanup
    exec bash "$PD_SELF" "${PD_ARGV[@]}"
  fi
  ui_note ok "$(t settings.language.next_start "${TX[lang.name]}")"
}

_set_recentmax() {
  local n
  for n in 0 3 5 8 10; do
    if [ "$n" = 0 ]; then ui_item item "$n" "0" "${TX[settings.recentmax.hide]}"; else ui_item item "$n" "$n"; fi
  done
  UI_PRESEL=$RECENT_MAX
  ui_menu "${TX[settings.recentmax]}" "$(t settings.value.current "$RECENT_MAX")"
  [ "$UI_ACT" = select ] && [ "$UI_SEL" != "$RECENT_MAX" ] || return 0
  _set_save RECENT_MAX "$UI_SEL"
}

_set_sshhosts() {
  local v w ok=()
  ui_input "${TX[settings.sshhosts.prompt]}" "$SSH_HOSTS" || return 0
  v=$UI_INPUT
  [ "$v" = "$SSH_HOSTS" ] && return 0
  if [ "$v" = "-" ]; then _set_save SSH_HOSTS ""; return 0; fi
  for w in $v; do
    if [[ $w =~ ^[A-Za-z0-9_][A-Za-z0-9._@:-]*$ ]]; then ok+=("$w"); else ui_msg err "$(t settings.sshhosts.invalid "$w")"; return 0; fi
  done
  _set_save SSH_HOSTS "\"${ok[*]}\""
}

_set_cvect() {
  ui_input "${TX[settings.cvect.prompt]}" "$CVE_CT" || return 0
  [ "$UI_INPUT" = "$CVE_CT" ] && return 0
  if [ "$UI_INPUT" = "-" ]; then _set_save CVE_CT ""; return 0; fi
  if [[ $UI_INPUT =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then _set_save CVE_CT "$UI_INPUT"
  else ui_msg err "$(t settings.cvect.invalid "$UI_INPUT")"; fi
}

# Gruppe sshlobby-Updates: automatische Prüfung (mit Stand der letzten Prüfung) und „Jetzt prüfen“,
# das zu „sshlobby X installieren“ wird, sobald ein neueres Release bekannt ist (lib/update.sh).
_set_upd_items() {
  local v s
  upd_state
  if [ "$UPDATE_CHECK" = yes ]; then
    case "$UPD_C_STATUS" in
      "")  s=${TX[settings.updcheck.never]};;
      err) s=${TX[settings.updcheck.failed]};;
      *)   tf s settings.updcheck.last "$(rel_time "$UPD_C_CHECKED")";;
    esac
    v="${TX[settings.value.on]} · $s"
  else
    v=${TX[settings.value.off]}
  fi
  ui_item item updcheck "${TX[settings.updcheck]}" "$v"
  if [ -n "$UPD_C_TAG" ] && ver_gt "$UPD_C_TAG" "$VERSION"; then
    tf v settings.updinstall "${UPD_C_TAG#[vV]}"; ui_item item updnow "$v" "github.com/$UPDATE_REPO"
  else
    ui_item item updnow "${TX[settings.updnow]}" "github.com/$UPDATE_REPO"
  fi
}

_set_edit() { # datei: im Editor öffnen ($VISUAL, $EDITOR, nano, vi)
  local e=${VISUAL:-${EDITOR:-}}
  if [ -z "$e" ]; then if have nano; then e="nano"; else e="vi"; fi; fi
  mkdir -p "$CONF_DIR" && [ -e "$1" ] || printf '%s\n' "${TX[settings.desc.template]}" > "$1"
  $e "$1"
}
_set_desc() {
  local v
  while true; do
    ui_info "${TX[settings.desc.file]}" "$DESCRIPTIONS"
    tf v settings.value.lines "$(_set_lines "$DESCRIPTIONS")"; ui_item item show "${TX[settings.desc.show]}" "$v"
    ui_item item edit "${TX[settings.desc.edit]}" "${VISUAL:-${EDITOR:-nano}}"
    ui_item item example "${TX[settings.desc.example]}" "${TX[settings.desc.example_desc]}"
    ui_menu "${TX[settings.desc]}" "${TX[settings.desc.format]}"
    [ "$UI_ACT" = select ] || return 0
    case "$UI_SEL" in
      show)    if [ -r "$DESCRIPTIONS" ]; then ui_run_page "${TX[settings.desc]}" cat "$DESCRIPTIONS"
               else ui_msg info "${TX[settings.desc.none]}"; fi;;
      edit)    ui_run_fg _set_edit "$DESCRIPTIONS"; desc_load;;
      example) setup_offer_descriptions;;
    esac
  done
}

# ─── Sicherungen und Zurücksetzen ──────────────────────────────────────────
_set_backup_list() { # neueste zuerst, nur Ordnernamen
  [ -d "$SET_BACKUPS" ] || return 0
  find "$SET_BACKUPS" -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' 2>/dev/null | sort -r
}

settings_backup() { # dateien… → Sicherungsordner in SET_LAST_BACKUP (leer, wenn nichts zu sichern war)
  local d f n=0 base
  SET_LAST_BACKUP=""
  for f in "$@"; do [ -e "$CONF_DIR/$f" ] && n=$((n + 1)); done
  [ "$n" -gt 0 ] || return 0
  base="$SET_BACKUPS/$(date +%Y%m%d-%H%M%S)"; d=$base; n=1
  while [ -e "$d" ]; do n=$((n + 1)); d="$base-$n"; done
  mkdir -p "$d" || return 1
  chmod 700 "$SET_BACKUPS" "$d" 2>/dev/null
  for f in "$@"; do [ -e "$CONF_DIR/$f" ] && cp -p "$CONF_DIR/$f" "$d/$f"; done
  SET_LAST_BACKUP=$d
  _set_backup_list | tail -n +$((SET_KEEP + 1)) | while IFS= read -r f; do rm -rf "${SET_BACKUPS:?}/$f"; done
  return 0
}

settings_reset() { # cfg|all → Sicherung, löschen, Einrichtung wie beim ersten Start
  local -a files
  if [ "$1" = all ]; then files=("${SET_ALL_FILES[@]}")
    ui_confirm "${TX[settings.resetall.confirm]}" || return 0
  else files=("${SET_CFG_FILES[@]}")
    ui_confirm "${TX[settings.resetcfg.confirm]}" || return 0
  fi
  settings_backup "${files[@]}" || { ui_msg err "${TX[settings.backup.failed_nothing_deleted]}"; return 0; }
  local f
  for f in "${files[@]}"; do
    [ "$f" = service-favorites ] && { rm -f "$(_set_svcfavs)"; continue; }
    rm -f "${CONF_DIR:?}/$f"
  done
  [ -n "$SET_LAST_BACKUP" ] && ui_note ok "$(t settings.backup.saved "${SET_LAST_BACKUP/#$HOME/\~}")"
  cfg_load; desc_load; cfg_apply
  CFG_MODE="" MODE_SRC=auto
  if setup_run; then cfg_load; cfg_apply
  else setup_detect; MODE=$DET_MODE; ui_note info "$(t settings.reset.setup_aborted "$MODE")"; fi
  PD_RELOAD=1
}

# Sicherungsordner (JJJJMMTT-hhmmss[-n]) + date-Format aus der Sprachdatei → lesbarer Zeitpunkt, sonst der Name
_set_stamp() {
  local b=$1
  date -u -d "${b:0:4}-${b:4:2}-${b:6:2} ${b:9:2}:${b:11:2}:${b:13:2}" +"$2" 2>/dev/null || printf '%s' "$b"
}

_set_restore() {
  local b f files
  for b in $(_set_backup_list); do
    files=$(find "$SET_BACKUPS/$b" -maxdepth 1 -type f -printf '%f ' 2>/dev/null)
    ui_item item "$b" "$(_set_stamp "$b" "${TX[settings.restore.date_list]}")" "$files"
  done
  ui_menu "${TX[settings.restore]}" "${TX[settings.restore.newest_first]}"
  [ "$UI_ACT" = select ] || return 0
  b=$UI_SEL
  ui_confirm "$(t settings.restore.confirm "$(_set_stamp "$b" "${TX[settings.restore.date_confirm]}")")" || return 0
  settings_backup "${SET_ALL_FILES[@]}" || { ui_msg err "${TX[settings.backup.failed_nothing_changed]}"; return 0; }
  for f in "${SET_ALL_FILES[@]}"; do
    [ -e "$SET_BACKUPS/$b/$f" ] || continue
    cp -p "$SET_BACKUPS/$b/$f" "$CONF_DIR/$f"
  done
  cfg_load; desc_load; cfg_apply
  if [ -n "$CFG_MODE" ]; then MODE=$CFG_MODE MODE_SRC=config; fi
  PD_RELOAD=1
  ui_note ok "$(t settings.restore.done "$b")"
}

# Werkzeug-Eintrag (immer das letzte Werkzeug); Moduswechsel o. ä. → zurück ins neu geladene Hauptmenü
_t_settings() { PD_RELOAD=0; screen_settings; return 0; }
