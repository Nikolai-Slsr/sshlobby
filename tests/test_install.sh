# shellcheck shell=bash
# install.sh / uninstall.sh / Bashrc-Hook. Nur mit umgebogenen BIN_DST, LIB_DST, BASHRC, HOME.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

# shellcheck disable=SC2016 # alter Hook-Block (Vorgänger projdash) wörtlich, nichts soll expandieren
OLD_HOOK='# >>> projdash dashboard >>>
if [ -n "$PS1" ] && [ -t 0 ] && [ -t 1 ] && [ -z "$PROJDASH_SKIP" ] && [ "$SSH_TTY" ] && [[ $- == *i* ]] && ! [[ "${SSH_ORIGINAL_COMMAND:-}" ]]; then
  PROJDASH_SKIP=1 projdash
fi
# <<< projdash dashboard <<<'

# Alle Pfade, die install.sh/uninstall.sh anfassen dürfen, zeigen in den Testordner.
inst_env() {
  INST_ENV=(BASHRC="$W/bashrc" BIN_DST="$W/bin/sshlobby" LIB_DST="$W/lib/sshlobby" CONF_DST="$HOME/.config/sshlobby"
            OLD_BIN="$W/old/bin/projdash" OLD_LIB="$W/old/lib/projdash" OLD_CONF="$HOME/.config/projdash")
}
# Sperre gegen echte Systempfade: jede Variable, die das Skript in rm/rmdir/cp/cat-Ziel/ln/install benutzt,
# muss überschreibbar sein (VAR="${VAR:-…}") UND von inst_env umgebogen werden. Sonst wird das Skript
# gar nicht erst ausgeführt.
safe_paths() {
  local v used e ok
  inst_env
  used=$(grep -E '^[^#]*\b(rm|rmdir|cp|ln|install|mkdir|touch)\b|> "\$[A-Z_]+"' "$1" | grep -oE '\$\{?[A-Z][A-Z_]+' | tr -d '${' | sort -u)
  for v in $used; do
    case "$v" in SCRIPT_DIR|HOOK_BLOCK|HOOK_START|HOOK_END|HOME) continue;; esac
    # shellcheck disable=SC2016 # gesucht wird der Quelltext
    grep -qF "$v=\"\${$v:-" "$1" || die "$1: $v ist nicht überschreibbar, NICHT ausgeführt (würde echte Pfade ändern)"
    ok=0; for e in "${INST_ENV[@]}"; do [ "${e%%=*}" = "$v" ] && ok=1; done
    [ "$ok" = 1 ] || die "$1: $v wird in den Tests nicht umgebogen, NICHT ausgeführt (würde echte Pfade ändern)"
  done
}
inst()   { safe_paths "$ROOT/install.sh"; env "${INST_ENV[@]}" bash "$ROOT/install.sh" > "$W/iout" 2>&1; }
uninst() { safe_paths "$ROOT/uninstall.sh"; env "${INST_ENV[@]}" bash "$ROOT/uninstall.sh" "$@" > "$W/iout" 2>&1; }

t_install_guard_catches_unredirected_path() {     # ein neuer, nicht umgebogener Pfad stoppt den Test
  sed 's|^OLD_LIB=.*|OLD_LIB="${OLD_LIB:-/usr/local/lib/projdash}"\nNEW_THING="/usr/local/lib/x"\nrm -f "$NEW_THING"|' "$ROOT/install.sh" > "$W/inst-bad.sh"
  ( safe_paths "$W/inst-bad.sh" ) && die "Sperre hat NEW_THING nicht erkannt"
  safe_paths "$ROOT/install.sh"; safe_paths "$ROOT/uninstall.sh"
}

t_install_migrates_projdash() {                   # Vorgänger: Hook ersetzt, Config kopiert, alte Dateien weg
  rm -rf "$HOME/.config/sshlobby"                   # setup() legt den neuen Ordner an, hier soll er fehlen
  mkdir -p "$W/bin" "$W/old/bin" "$W/old/lib/projdash/lib" "$W/old/lib/projdash/examples" "$HOME/.config/projdash"
  echo 'VERSION="2.2.0" # projdash' > "$W/old/lib/projdash/projdash.sh"; echo x > "$W/old/lib/projdash/lib/core.sh"
  ln -s "$W/old/lib/projdash/projdash.sh" "$W/old/bin/projdash"
  printf 'MODE=docker\nHOST_LABEL=Alt\n' > "$HOME/.config/projdash/config"; echo "1|@tool|updates|tool" > "$HOME/.config/projdash/recents"
  echo "0 1" > "$HOME/.config/projdash/apt-last"
  printf '%s\n' "# vorher" "$OLD_HOOK" "# nachher" > "$W/bashrc"
  inst || die "install: $(cat "$W/iout")"
  has "$(cat "$W/iout")" "Settings migrated"; has "$(cat "$W/iout")" "Removed predecessor"
  grep -qx "HOST_LABEL=Alt" "$HOME/.config/sshlobby/config" || die "Config nicht übernommen"
  [ -s "$HOME/.config/sshlobby/recents" ] || die "Verlauf nicht übernommen"; [ ! -e "$HOME/.config/sshlobby/apt-last" ] || die "apt-last übernommen"
  [ -d "$HOME/.config/projdash" ] || die "alte Config gelöscht"
  [ ! -e "$W/old/bin/projdash" ] && [ ! -e "$W/old/lib/projdash" ] || die "Vorgänger nicht entfernt"
  ! grep -q projdash "$W/bashrc" || die "alter Hook noch da"
  eq "$(sed -n 1p "$W/bashrc")" "# vorher"; eq "$(sed -n 2p "$W/bashrc")" "# >>> sshlobby >>>"; eq "$(tail -n1 "$W/bashrc")" "# nachher"
  printf 'MODE=layered\n' > "$HOME/.config/sshlobby/config"; inst                # vorhandene Config nie überschreiben
  grep -qx "MODE=layered" "$HOME/.config/sshlobby/config" || die "vorhandene Config überschrieben"
}

t_b16_install_fresh() {
  mkdir -p "$W/bin"; printf 'alias ll="ls -l"\nexport A=1' > "$W/bashrc"   # ohne Newline am Ende
  inst || die "install: $(cat "$W/iout")"
  [ -x "$W/bin/sshlobby" ] || die "Starter fehlt"
  [ -L "$W/bin/sshlobby" ] || die "Starter ist kein Symlink"
  cmp -s "$W/bin/sshlobby" "$PD" || die "Starter zeigt nicht auf sshlobby.sh"
  local m; for m in "$ROOT"/lib/*.sh; do cmp -s "$m" "$W/lib/sshlobby/lib/${m##*/}" || die "Modul fehlt: ${m##*/}"; done
  [ -s "$W/lib/sshlobby/examples/descriptions.docker-host" ] || die "examples fehlen"
  eq "$(sed -n 2p "$W/bashrc")" "export A=1" "letzte Zeile nicht verklebt"
  eq "$(grep -cxF '# >>> sshlobby >>>' "$W/bashrc")" 1
  grep -qF '[ $? -eq 20 ] && exit' "$W/bashrc" || die "neuer Hook fehlt"
}
t_install_runs_from_bin() {                        # lib/ wird über readlink -f des Starters gefunden
  mkdir -p "$W/bin"; : > "$W/bashrc"; inst || die "install: $(cat "$W/iout")"
  "$W/bin/sshlobby" --version > "$W/v" 2>&1 || die "Start aus BIN_DST: $(cat "$W/v")"
  eq "$(cat "$W/v")" "sshlobby 3.1.1"
  printf 'q\n' | env --default-signal=INT setsid -w "$W/bin/sshlobby" > "$W/v" 2>&1; eq $? 20
  has "$(cat "$W/v")" "Modus layered"
}
t_install_upgrade_from_v1() {                      # v1.1: BIN_DST war eine Datei, kein Symlink
  mkdir -p "$W/bin"; : > "$W/bashrc"
  printf '#!/bin/bash\necho alt\n' > "$W/bin/sshlobby"; chmod +x "$W/bin/sshlobby"
  mkdir -p "$W/lib/sshlobby/lib"; echo 'veraltet' > "$W/lib/sshlobby/lib/old_module.sh"
  inst || die "install: $(cat "$W/iout")"
  [ -L "$W/bin/sshlobby" ] || die "alte Datei nicht durch Symlink ersetzt"
  [ ! -e "$W/lib/sshlobby/lib/old_module.sh" ] || die "veraltetes Modul liegt noch"
}
t_install_refuses_odd_lib_dst() {
  mkdir -p "$W/bin"; : > "$W/bashrc"
  BASHRC="$W/bashrc" BIN_DST="$W/bin/sshlobby" LIB_DST="$W/usrlocallib" bash "$ROOT/install.sh" > "$W/iout" 2>&1 \
    && die "install mit LIB_DST ohne /sshlobby am Ende müsste abbrechen"
  [ ! -e "$W/usrlocallib" ] || die "trotzdem angelegt"
  BASHRC="$W/bashrc" BIN_DST="$W/bin/sshlobby" LIB_DST="$W/usrlocallib" bash "$ROOT/uninstall.sh" > "$W/iout" 2>&1 \
    && die "uninstall mit fremdem LIB_DST müsste abbrechen"
  true
}
t_b16_install_upgrade_idempotent() {
  mkdir -p "$W/bin"
  printf '%s\n' "# vorher" "alias ll='ls -l'" "$OLD_HOOK" "export NACHHER=1" "" "# ende" > "$W/bashrc"
  inst || die "install: $(cat "$W/iout")"; has "$(cat "$W/iout")" "updated"
  eq "$(grep -cxF '# >>> sshlobby >>>' "$W/bashrc")" 1 "genau ein Block"
  eq "$(grep -cxF '# <<< sshlobby <<<' "$W/bashrc")" 1
  grep -qF '[ $? -eq 20 ] && exit' "$W/bashrc" || die "neuer Hook fehlt"
  grep -qxF '  SSHLOBBY_SKIP=1 sshlobby' "$W/bashrc" && die "alter Hook noch da"
  eq "$(sed '/# >>> sshlobby/,/# <<< sshlobby/d' "$W/bashrc")" $'# vorher\nalias ll=\'ls -l\'\nexport NACHHER=1\n\n# ende' "Rest unverändert"
  cp "$W/bashrc" "$W/bashrc.1"
  inst; has "$(cat "$W/iout")" "is up to date"
  cmp -s "$W/bashrc" "$W/bashrc.1" || die "zweites install ändert die Bashrc"
  uninst || die "uninstall: $(cat "$W/iout")"
  [ ! -e "$W/bin/sshlobby" ] && [ ! -L "$W/bin/sshlobby" ] || die "Starter nicht entfernt"
  [ ! -e "$W/lib/sshlobby" ] || die "LIB_DST nicht entfernt: $(find "$W/lib/sshlobby")"
  eq "$(cat "$W/bashrc")" $'# vorher\nalias ll=\'ls -l\'\nexport NACHHER=1\n\n# ende' "Block weg, Rest unverändert"
  uninst; has "$(cat "$W/iout")" "No bashrc hook"
}
t_uninstall_keeps_foreign_files() {
  mkdir -p "$W/bin"; : > "$W/bashrc"; inst
  echo mein > "$W/lib/sshlobby/notiz.txt"
  uninst || die "uninstall: $(cat "$W/iout")"
  [ -e "$W/lib/sshlobby/notiz.txt" ] || die "fremde Datei gelöscht"
  [ ! -e "$W/lib/sshlobby/sshlobby.sh" ] && [ ! -e "$W/lib/sshlobby/lib" ] || die "sshlobby-Dateien nicht entfernt"
}
t_b16_broken_block_untouched() {
  mkdir -p "$W/bin"; printf '%s\n' "# >>> sshlobby dashboard >>>" "wichtig=1" "noch_wichtiger=2" > "$W/bashrc"
  cp "$W/bashrc" "$W/bashrc.orig"
  inst && die "install müsste abbrechen"
  uninst; cmp -s "$W/bashrc" "$W/bashrc.orig" || die "Bashrc ohne Endmarker verändert"
}
t_b16_purge() {
  mkdir -p "$W/bin" "$CONF"; : > "$W/bashrc"
  inst; uninst; [ -d "$CONF" ] || die "Config ohne --purge gelöscht"
  uninst --purge; [ ! -e "$CONF" ] || die "Config mit --purge nicht gelöscht"
}
t_b6_hook_logout_only_on_20() {
  mkdir -p "$W/bin"; : > "$W/bashrc"; inst
  local line code out
  line=$(grep -F 'SSHLOBBY_LOGIN=1 sshlobby' "$W/bashrc")
  for code in 0 1 10 20 127 130; do
    out=$(bash -c "sshlobby() { return $code; }; $line; echo weiter")
    if [ "$code" -eq 20 ]; then eq "$out" "" "Code 20 muss ausloggen"
    else eq "$out" "weiter" "Code $code darf nicht ausloggen"; fi
  done
}
