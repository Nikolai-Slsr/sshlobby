# shellcheck shell=bash
# Modus incus (nur CTs, keine Docker-Abfragen). CT-Screen: 1 CT-Shell, 2 starten, 3 stoppen,
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer
# 4 neu starten, 5 incus info, 6 Log, 7 Ressourcen.

imode() { conf "MODE=incus" "CVE_CT=security"; }

t_incus_main() {
  local now; now=$(date +%s)
  imode
  printf '%s\n' "$((now-10))|alpha|app|shell" "$((now-20))|alpha|-|ctshell" > "$CONF/recents"
  printf '%s\n' "alpha|app" "beta|-" > "$CONF/favorites"
  menu 'q\n'; rc_is 20; no_err
  has "$OUT" " 1) alpha (CT-Shell)"; hasnt "$OUT" "alpha / app"   # Docker-Einträge passen nicht
  has "$OUT" " 2) ★ beta (CT-Shell)"; hasnt "$OUT" "alpha/app"
  has "$OUT" " 3) ● alpha"; has "$OUT" "5 CTs aktiv"
  ! grep -q '== docker@' "$STUB_LOG" || die "incus-Modus fragt Docker ab"
}
t_incus_ct_screen() {
  imode; menu '1\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ alpha · 10.0.0.11 · Running"; hasnt "$OUT" "DOCKER-CONTAINER"
  has "$OUT" " 1) CT-Shell"; has "$OUT" " 7) Ressourcen"
  ! grep -q '== docker@' "$STUB_LOG" || die "CT-Screen fragt Docker ab"
}
t_incus_ct_actions() {
  imode; menu '1\n1\n2\n3\n\n3\nj\n4\nn\n5\n\n6\n\n7\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "STUB-BASH alpha"; has "$OUT" "STUB-CT-start alpha"
  has "$OUT" "CT alpha stoppen? [j/N]"; has "$OUT" "STUB-CT-stop alpha"
  has "$OUT" "CT alpha neu starten? [j/N]"; hasnt "$OUT" "STUB-CT-restart"
  has "$OUT" "Name: alpha"; has "$OUT" "STUB-LOG alpha"; has "$OUT" "STUB-LIST list ^alpha\$ -c nsuNmMD4"
  eq "$(count "$OUT" "STUB-CT-stop")" 1 "Stop genau einmal (erstes Mal abgelehnt)"
}
t_incus_ct_action_error() {
  imode; export STUB_CT_ACTION_RC=1
  menu '2\n2\n\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "CT beta: starte: Exit-Code 1"; has "$OUT" "[Enter] weiter"
}
t_incus_ct_favorite() {
  imode; menu '2\nf\nb\nq\n'; rc_is 20
  eq "$(cat "$CONF/favorites")" "beta|-"
  menu '1\n\nq\n'; rc_is 20; has "$OUT" 'CT „beta“ läuft nicht (Stopped)'   # Favorit: Preflight
}
t_incus_tools() {
  imode; menu '7\nb\nq\n'; rc_is 20; no_err       # 6 CTs, Werkzeuge = 7
  has "$OUT" "Incus-Übersicht"; has "$OUT" "CVE-Monitor"; has "$OUT" "Neues Projekt anlegen"
  hasnt "$OUT" ") Docker-Health"; hasnt "$OUT" "Anderer Server"
}
