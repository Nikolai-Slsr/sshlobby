# shellcheck shell=bash
# Englische Texte der Einstellungen (lib/settings.sh) und des Werkzeugs systemd-Dienste (lib/tools_systemd.sh)
# im Zeilenmodus. Das Werkzeug wird über „Zuletzt“ geöffnet, damit der Test nicht von den Texten anderer
# Module (Hauptmenü, Werkzeug-Liste) abhängt.

# Nummer des ersten Menüeintrags, dessen Zeile den Text enthält
i18s_nr() { awk -v l="$2" 'index($0, l) && match($0, /^ *[0-9]+\)/) { s = substr($0, RSTART, RLENGTH); gsub(/[ )]/, "", s); print s; exit }' <<< "$1"; }

t_i18n_settings_en_screen() {
  export SSHLOBBY_LANG=en
  menu 'b\n' --settings; rc_is 0; no_err
  has "$OUT" "Settings · ~/.config/sshlobby"; has_re "$OUT" "Mode +layered"; has_re "$OUT" "Start on SSH login +on"
  has_re "$OUT" "Key q in the main menu +Logout \(disconnect\)"; has_re "$OUT" "Entries under Recent +5"
  has_re "$OUT" "CVE monitor CT +security"; has "$OUT" ") Reset everything"; has "$OUT" ") Show config file"
  local w; for w in Einstellungen Anzeigename "Beim SSH-Login" Einträge ZURÜCKSETZEN Beschreibungen Oberfläche; do hasnt "$OUT" "$w"; done
  mkdir -p "$CONF/backups/20250102-030405"; echo "MODE=docker" > "$CONF/backups/20250102-030405/config"
  menu 'b\n' --settings; has_re "$OUT" "Restore backup +1 available"
  local n; n=$(i18s_nr "$OUT" ") Restore backup"); [ -n "$n" ] || die "kein Wiederherstellen-Eintrag:\n$OUT"
  menu "$n\n1\nn\nb\n" --settings; rc_is 0; no_err                  # Datum im englischen Format, Rückfrage abgelehnt
  has "$OUT" "1) 2025-01-02 03:04:05"; has "$OUT" "Restore the state from 2025-01-02 03:04?"; hasnt "$OUT" "Stand vom"
}

t_i18n_settings_en_save() {
  export SSHLOBBY_LANG=en
  menu 'b\n' --settings; local n; n=$(i18s_nr "$OUT" ") Start on SSH login"); [ -n "$n" ] || die "kein Autostart-Eintrag:\n$OUT"
  menu "$n\nb\n" --settings; rc_is 0; no_err
  has "$OUT" "Saved: AUTOSTART=no"; has "$OUT" "Takes effect on the next SSH login."; has_re "$OUT" "Start on SSH login +off"
  hasnt "$OUT" "Gespeichert"; hasnt "$OUT" "Wirkt beim"
}

t_i18n_settings_en_services() {
  export SSHLOBBY_LANG=en PD_TOOLS_ROOT="$PD_FIX/tools/root"
  printf '%s|@tool|services|tool\n' "$(date +%s)" > "$CONF/recents"
  menu 'q\n'; local tw n s; tw=$(i18s_nr "$OUT" ") Tools"); [ -n "$tw" ] || die "kein Tools-Eintrag:\n$OUT"
  menu "$tw\nb\nq\n"; n=$(i18s_nr "$OUT" " systemd services"); eq "$n" 1 "Werkzeug oben unter Recent"
  has "$OUT" "▌ RECENT"; has "$OUT" "▌ ALL TOOLS"
  menu "$tw\n$n\nb\nb\nq\n"; rc_is 20; no_err
  has "$OUT" "▌ FAILED"; has "$OUT" "▌ OWN / IMPORTANT"; has "$OUT" "▌ RUNNING"; has "$OUT" "▌ OTHER (INACTIVE, EXITED)"
  has_re "$OUT" "Services +[0-9]+ total · [0-9]+ running · [0-9]+ own"
  local w sec; sec=$(awk '/┌─ systemd services/ { f = 1 } f { print } f && / b\) / { exit }' <<< "$OUT")  # bis zur Tastenzeile
  has "$sec" "reload"; for w in FEHLGESCHLAGEN LAUFEND gesamt "neu laden"; do hasnt "$sec" "$w"; done
  s=$(i18s_nr "$OUT" "● hermes-gateway "); [ -n "$s" ] || die "Dienst fehlt:\n$OUT"
  menu "$tw\n$n\n$s\n5\nn\nb\nb\nb\nq\n"; rc_is 20; no_err
  has_re "$OUT" "Status +● active \(running\) since "; has_re "$OUT" "Main PID +1"; has "$OUT" "service  (own)"
  has "$OUT" ") Follow logs"; has "$OUT" ") Disable autostart"; has "$OUT" "Restart hermes-gateway?"
  for w in Haupt-PID Speicher seit eigene "mit Rückfrage" "neu starten"; do hasnt "$OUT" "$w"; done
}
