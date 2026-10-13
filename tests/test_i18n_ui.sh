# shellcheck shell=bash
# Englische Texte von Menü-Engine, Dialogen, Kernfunktionen, CLI und Incus-Backend (SSHLOBBY_LANG=en).
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

t_i18n_ui_cli_en() {
  export SSHLOBBY_LANG=en
  cli --help; rc_is 0; no_err
  has "$OUT" "--go <target>"; has "$OUT" "(no arguments)    interactive menu"; has "$OUT" "Menu exit codes:"
  has "$OUT" "docker:  <container> or <project>/<container>"
  hasnt "$OUT" "ziel"; hasnt "$OUT" "Übersicht"; hasnt "$OUT" "diese Hilfe"
  cli --go oldsite; rc_is 1; has "$ERR" 'CT "oldsite" not found'
  cli --go beta; rc_is 1; has "$ERR" 'CT "beta" is not running (Stopped)'
  cli --mode bogus --list; rc_is 2; has "$ERR" 'unknown mode "bogus"'
  conf "MODE=docker"
  cli --list; rc_is 0; has "$OUT" "PROJECT"; hasnt "$OUT" "PROJEKT"
  cli --go ghost; rc_is 1; has "$ERR" 'container "ghost" not found'; hasnt "$ERR" "gibt es nicht"
}

t_i18n_ui_menu_en() {                              # Zeilenmodus: Kopf, Prompt, Dialoge, Betrachter, Zeitangaben
  export SSHLOBBY_LANG=en
  conf "MODE=incus" "CVE_CT=security"
  printf '%s\n' "$(($(date +%s) - 10))|alpha|-|ctshell" > "$CONF/recents"
  menu '2\n3\ny\n4\nn\n6\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "sshlobby  v3.1.0 · mode incus"; has "$OUT" "just now"
  has "$OUT" "  Choice: "; has "$OUT" "b) back"; has "$OUT" "[y/N]"; has "$OUT" "[Enter] continue"
  has "$OUT" "CT alpha: stopping"; has "$OUT" "STUB-CT-stop alpha"; hasnt "$OUT" "STUB-CT-restart"
  has "$OUT" "── Log of alpha ──"
  local w; for w in "Auswahl:" "zurück" "[j/N]" "[Enter] weiter" "gerade eben" "Modus incus" "alpha: stoppe" "Log von"; do
    hasnt "$OUT" "$w"
  done
}

t_i18n_ui_errors_en() {                            # Fehlermeldungen aus ui_check_rc und dem Incus-Preflight
  export SSHLOBBY_LANG=en STUB_CT_ACTION_RC=1
  conf "MODE=incus" "CVE_CT=security"
  menu '2\n2\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "CT beta: starting: exit code 1"; hasnt "$OUT" "Exit-Code"
  unset STUB_CT_ACTION_RC
  printf 'beta|-\n' > "$CONF/favorites"
  menu '1\n\nq\n'; rc_is 20; has "$OUT" 'CT "beta" is not running (Stopped)'; hasnt "$OUT" "läuft nicht"
}
