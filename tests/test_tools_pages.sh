# shellcheck shell=bash
# Werkzeuge außer systemd-Dienste: Verfügbarkeit (Befehl fehlt / falscher Modus → nicht im Menü),
# Ausgabe aus fixtures/tools (Beispieldaten, Doku-IPs), Gruppierung und Sortierung, und dass kein
# Werkzeug etwas verändert. Helfer tt_open, tt_tools, tt_nr aus test_tools_services.sh.
# shellcheck disable=SC2015,SC2034,SC1111 # „a && b || die“ ist in Tests gewollt; RC/OUT lesen die Helfer

dmode_t() { conf "MODE=docker"; }
line_of() { grep -nF -- "$2" <<< "$1" | head -n 1 | cut -d: -f1; } # erste Zeilennummer mit Text
before() { # ausgabe a b → a steht vor b
  local x y; x=$(line_of "$1" "$2"); y=$(line_of "$1" "$3")
  [ -n "$x" ] && [ -n "$y" ] && [ "$x" -lt "$y" ] || die "»$2« nicht vor »$3«:\n$1"
}

t_tools_menu_order_kept() {                         # v1.1-Nummern bleiben, neue Werkzeuge danach, Setup am Ende
  tt_tools; rc_is 20; no_err
  has "$OUT" "10) Server-Check"; has "$OUT" "11) systemd-Dienste"; setup_is_last
  for t in "Ports & Listener" "Container-Ressourcen" "Speicherplatz" "Sicherheits-Check" "Updates" \
           "Timer & Cron" "Netzwerk & Zugänge"; do has "$OUT" ") $t"; done
  hasnt "$OUT" "Container-Hygiene"                  # nur Modus docker
  dmode_t; tt_tools; has "$OUT" ") Container-Hygiene"; setup_is_last
}
t_tools_availability_by_command() {
  path_without ss apt tailscale cloudflared wg crontab
  export PD_TOOLS_ROOT="$W/empty"; mkdir -p "$W/empty"
  menu 'q\n'; menu "$(tt_nr "$OUT" ") Werkzeuge")\nb\nq\n"; rc_is 20; no_err
  for t in "Ports & Listener" "Updates" "Netzwerk & Zugänge"; do hasnt "$OUT" ") $t"; done
  has "$OUT" ") Timer & Cron"                        # systemctl reicht
  rm -rf "${W:?}/bin"; path_without docker; dmode_t; menu 'q\n'; menu "$(tt_nr "$OUT" ") Werkzeuge")\nb\nq\n"
  hasnt "$OUT" "Container-Hygiene"; hasnt "$OUT" "Container-Ressourcen"
  rm -rf "${W:?}/bin"; path_without incus; conf "MODE=incus"; menu 'q\n'; menu "$(tt_nr "$OUT" ") Werkzeuge")\nb\nq\n"
  hasnt "$OUT" "Container-Ressourcen"; has "$OUT" "Speicherplatz"
  rm -rf "${W:?}/bin"; path_without journalctl sshd; menu 'q\n'; menu "$(tt_nr "$OUT" ") Werkzeuge")\nb\nq\n"
  hasnt "$OUT" "Sicherheits-Check"; hasnt "$OUT" "Fehler-Log"
}

# ─── Ports ─────────────────────────────────────────────────────────────────
t_tools_ports_grouped() {
  dmode_t; tt_open "Ports & Listener" '\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "── Ports & Listener ──"
  before "$OUT" "Öffentlich erreichbar" "Nur über Tailscale"
  before "$OUT" "Nur über Tailscale" "Privat / Docker-Bridge"
  before "$OUT" "Privat / Docker-Bridge" "Nur localhost"
  has_re "$OUT" "! tcp +0\.0\.0\.0:8642 +docker +hermes → 8643"
  has_re "$OUT" "! tcp +0\.0\.0\.0:22 +sshd +ssh\.service"
  has_re "$OUT" "! tcp +\[2001:db8::10\]:443 +caddy +caddy\.service"
  has_re "$OUT" "tcp +100\.64\.0\.10:25500-25600 +docker +jellyfin_container$"   # Bereich
  has_re "$OUT" "tcp +127\.0\.0\.1:8096 +docker +gitea → 3000"
  has_re "$OUT" "tcp +172\.17\.0\.1:9100 +node_exporter +Container \(Host-Netz\) 0123456789ab"
  has_re "$OUT" "tcp +127\.0\.0\.1:3000 +node-MainThread +hermes-webui\.service"
  has "$OUT" "11 öffentliche Listener: 8642/tcp hermes, 22/tcp sshd"
  has "$OUT" "umgehen ufw"
  eq "$(grep -c '100.64.0.10:255' <<< "$OUT")" 1 "jellyfin-Ports zusammengefasst"
  # passt in 80 Spalten: keine Zeile der Seite länger als 78 Zeichen (Liste und Hinweise umbrochen)
  local long; long=$(awk '/── Ports & Listener ──/ { f = 1; next } f && /\[Enter\]/ { exit } f' <<< "$OUT" |
    sed 's/\x1b\[[0-9;]*m//g' | while IFS= read -r l; do [ ${#l} -gt 78 ] && printf '%s\n' "$l"; done)   # Zeichen, nicht Bytes
  [ -z "$long" ] || die "Zeilen über 78 Zeichen:\n$long"
  has "$OUT" "    443/tcp caddy, 41641/udp tailscaled"           # Folgezeile der Liste
}

# ─── Container-Ressourcen ─────────────────────────────────────────────────
t_tools_resources_docker_sorted() {
  dmode_t; tt_open "Container-Ressourcen" 's\n1\nb\nb\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" " 1\) ● Nextcloud +RAM 313\.5MiB"; has "$OUT" "Sortierung RAM"
  has_re "$OUT" "12\) ● firecrawl-mcp"
  has "$OUT" "Sortierung CPU"; has_re "$OUT" " 1\) ● chat-mongodb +RAM 124\.8MiB .*CPU 0\.69 %"
  has "$OUT" "┌─ chat-mongodb"                                  # Auswahl → Container-Screen
  has_re "$OUT" "Swap +● 1\.8G / 2\.0G \(90 %\)"
}
t_tools_resources_layered_cts() {
  printf '{"Name":"myapp","CPUPerc":"1.50%%","MemUsage":"300MiB / 2GiB","MemPerc":"14.6%%","PIDs":"9"}\n' > "$PD_FIX/tools/docker/stats.alpha"
  tt_open "Container-Ressourcen" '2\nb\n3\n\nb\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" " 1\) ● security +RAM 2\.0G / 4GiB +Swap 1\.0G"
  has_re "$OUT" " 2\) ● alpha +RAM 1\.2G / 2GiB"
  before "$OUT" "▌ LAUFENDE CTS NACH RAM" "▌ GESTOPPT"; has_re "$OUT" "● beta +Stopped"
  has_re "$OUT" "┌─ Container-Ressourcen · alpha · docker stats"; has_re "$OUT" "● myapp +RAM 300MiB"
  has "$OUT" "delta: Docker im CT nicht erreichbar"                   # 3 = delta, Docker down
}

# ─── Speicherplatz ─────────────────────────────────────────────────────────
t_tools_storage_layered() {
  tt_open "Speicherplatz" '\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" "! default +btrfs +50\.0G / 60\.0G \(83 %\)"; has "$OUT" "Loop-Datei /var/lib/incus/disks/default.img"
  has_re "$OUT" "! gamma/vor-update +2026-09-30 10:00"; has "$OUT" "gamma/test"
  has "$OUT" "incus delete <ct>/<snapshot>"; has "$OUT" "2.5G belegt"
  before "$OUT" "8.0G     security" "4.1G     alpha"
  hasnt "$OUT" "docker system df"
  sed -i '/^gamma|/s/|[^|]*$/|/' "$PD_FIX/tools/incus/extra"
  tt_open "Speicherplatz" '\nb\nq\n'; has "$(sed -n '/Incus-Snapshots/,$p' <<< "$OUT")" "✓ keine"
}
t_tools_storage_docker() {
  dmode_t; tt_open "Speicherplatz" '\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Build Cache     99"; hasnt "$OUT" "Incus-Storage-Pools"
  has_re "$OUT" "2\.74GB +\(ohne Namen\) +1 Container"
  has_re "$OUT" "2\.67GB +registry\.example\.org/nextcloud/nextcloud-dev:latest +ungenutzt"
  has "$OUT" "4 Images ohne Container, davon 2 ohne Namen"
  has "$OUT" "Build-Cache: 4.842GB freigebbar"; has "$OUT" "Vorschlag, nicht ausgeführt: docker builder prune"
  ! grep -qx "  prune" "$STUB_LOG" || die "prune ausgeführt"
}

# ─── Sicherheit / Updates ──────────────────────────────────────────────────
t_tools_security() {
  dmode_t; tt_open "Sicherheits-Check" '\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "    4  198.51.100.7"; has "$OUT" "12 Fehlversuche von 7 Adressen"
  has_re "$OUT" "2026-10-12 08:10  root +192\.0\.2\.50 +publickey"
  has_re "$OUT" "PasswordAuthentication +no"; has_re "$OUT" "PermitRootLogin +without-password"
  has "$OUT" "22/tcp sshd"; has "$OUT" "✓ unattended-upgrades aktiv"; has "$OUT" "✓ kein Neustart nötig"
  mkdir -p "$PD_FIX/tools/root/var/run"; echo "linux-image-amd64" > "$PD_FIX/tools/root/var/run/reboot-required.pkgs"
  touch "$PD_FIX/tools/root/var/run/reboot-required"; rm "$PD_FIX/tools/root/etc/apt/apt.conf.d/20auto-upgrades"
  tt_open "Sicherheits-Check" '\nb\nq\n'
  has "$OUT" "! Neustart nötig"; has "$OUT" "! unattended-upgrades nicht eingerichtet"
}
tt_upd_show() { # Werkzeug Updates → Eintrag „Übersicht“ (die frühere Seite) → $OUT
  tt_open "Updates" 'b\nb\nq\n'; local u; u=$(tt_nr "$OUT" ") Übersicht"); [ -n "$u" ] || die "kein Eintrag Übersicht:\n$OUT"
  tt_open "Updates" "$u\n\nb\nb\nq\n"
}
t_tools_updates() {
  tt_upd_show; rc_is 20; no_err
  has_re "$OUT" "Updates offen +124"; has_re "$OUT" "davon Security +59"
  has "$OUT" "bind9-dnsutils bind9-host"; has_re "$OUT" "Paketlisten +aktualisiert (gerade eben|vor [0-9]+ min)"
  hasnt "$OUT" "WARNING: apt"; has_re "$OUT" "Kernel installiert +6\.12\.95\+deb13-amd64"
  [ "$(awk '/^== apt/{getline; print}' "$STUB_LOG" | sort -u)" = "  list" ] || die "apt mit anderem Befehl als list aufgerufen"
  touch -d '10 days ago' "$PD_FIX"/tools/root/var/lib/apt/lists/*Packages
  STUB_UNAME_R=6.12.43+deb13-amd64 tt_upd_show
  has "$OUT" "Liste veraltet"; has "$OUT" "6.12.95+deb13-amd64 (neuer, erst nach Neustart aktiv)"
}

# ─── Timer / Netzwerk / Hygiene ────────────────────────────────────────────
t_tools_timers() {
  tt_open "Timer & Cron" '\nb\nq\n'; rc_is 20; no_err
  before "$OUT" " apt-daily " " fstrim "; before "$OUT" " fstrim " "docker-oom-shields"
  has_re "$OUT" "–  +docker-oom-shields +zuletzt"
  has_re "$OUT" "30 22 \* \* 1-5 +/opt/market-monitor/run\.sh"; has "$OUT" "@reboot"
  has "$OUT" "/etc/cron.d/e2scrub_all"; has_re "$OUT" "17 \* \* \* \* +root +cd / && run-parts"
  hasnt "$OUT" "Example of job"; hasnt "$OUT" "SHELL="; hasnt "$OUT" "m h  dom"
  has_re "$OUT" "cron\.daily +apt-compat dpkg"
}
t_tools_network() {
  tt_open "Netzwerk & Zugänge" '\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" "Dieser Knoten +docker-host 100\.64\.0\.10"; has_re "$OUT" "Exit-Node +wird angeboten"
  has_re "$OUT" "✓ nas-server +100\.64\.0\.15"; has "$OUT" "! Some peers are advertising routes"
  has_re "$OUT" "✓ cloudflared\.service +active/running"; has "$OUT" "agent.example.org → http://localhost:3000"
  has "$OUT" "git.example.org, www.git.example.org → 127.0.0.1:8096"; has "$OUT" "cloud.example.org → 127.0.0.1:3080"
  has "$OUT" "files.example.org Dateien"; hasnt "$OUT" "old.example.org"; hasnt "$OUT" "(common)"; hasnt "$OUT" "email"
  has_re "$OUT" "Schnittstelle +wg0 Port 51820"; has_re "$OUT" "! Peer PeerTwoP… 10\.8\.0\.3/32 .*Handshake nie"
  hasnt "$OUT" "FAKEPRIVATEKEY"
}
t_tools_hygiene() {
  dmode_t; tt_open "Container-Hygiene" '\nb\nq\n'; rc_is 20; no_err
  local s; s=$(sed -n '/^Ohne Projekt und ohne Restart-Policy/,/^Gestoppte/p' <<< "$OUT")
  has "$s" "eager_turing"; has "$s" "quirky_hopper"; hasnt "$s" "hermes"; hasnt "$s" "homepage"
  has_re "$OUT" "! old-demo +Exited \(0\) 4 weeks ago"; has_re "$OUT" "! agent-dev +Exited \(0\) 5 weeks ago, Policy unless-stopped"
  s=$(sed -n '/^Zufallsnamen/,/^Images ohne Namen/p' <<< "$OUT"); hasnt "$s" "jellyfin_container"; has "$s" "eager_turing"
  has "$OUT" "Image 3fc21559a8b7 hat keinen Namen mehr"
  has "$OUT" "docker rm old-demo agent-dev"
  ! grep -qx "  rm" "$STUB_LOG" || die "docker rm ausgeführt"
}

# ─── Erweiterte v1.1-Werkzeuge ─────────────────────────────────────────────
t_tools_errlog_grouped() {
  dmode_t; tt_open "Fehler-Log" '\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "── Fehler-Log (journalctl -p err) ──"
  has_re "$OUT" "✗ backup-nightly\.service +Nightly Restic Backup"
  has_re "$OUT" "40× ssh\.service"; has_re "$OUT" "2× backup-nightly\.service"; has "$OUT" "(2 verschiedene Meldungen)"
  has_re "$OUT" "1× kernel .*Out of memory"
  before "$OUT" "40× ssh.service" "2× backup-nightly.service"
  has_re "$OUT" "✗ hermes +vom OOM-Killer beendet"; has_re "$OUT" "! homepage +7 Neustarts"
  has_re "$OUT" "! agent-dev +beendet mit Exit-Code 137"
  has "$OUT" "STUB-JOURNALCTL -p err -n 40 --no-pager"           # bisherige Rohansicht bleibt
}
t_tools_sysinfo_swap() {
  tt_open "RAM / Disk / Top-Prozesse" '\nb\nq\n'; rc_is 20; no_err
  has_re "$OUT" "Swap belegt +1\.8G von 2\.0G \(90 %\)"; has "$OUT" "Top-Prozesse nach RAM"; has "$OUT" "Dateisysteme"
}
t_tools_ssh_from_config() {
  conf "MODE=docker"; mkdir -p "$HOME/.ssh"
  printf '%s\n' "Host *.lan !bad" "  User x" "Host nas storage" "  HostName 192.0.2.10" "  User admin" \
    "Host -oProxyCommand=evil" "Match all" "  HostName egal" "Host incus-host" > "$HOME/.ssh/config"
  tt_open "Anderer Server (SSH)" '2\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "Hosts aus ~/.ssh/config"; has_re "$OUT" " 1\) nas +ssh nas · admin@192\.0\.2\.10"
  has "$OUT" " 2) storage"; has_re "$OUT" " 3\) incus-host +ssh incus-host$"
  hasnt "$OUT" "*.lan"; hasnt "$OUT" "ProxyCommand"; has "$OUT" "STUB-SSH storage"
}

# ─── Server-Check ─────────────────────────────────────────────────────────
t_tools_check() {
  tt_open "Server-Check" '1\nb\nb\nb\nq\n'; rc_is 20; no_err
  has "$OUT" "┌─ Server-Check"; has_re "$OUT" "Ergebnis +● [1-9] Fehler"
  has_re "$OUT" " 1\) ● Fehlgeschlagene Units \(1\): backup-nightly\.service +systemd-Dienste"
  has_re "$OUT" "Storage-Pool default zu 83 % voll .* Speicherplatz"; has "$OUT" "2 Incus-Snapshots vorhanden"
  has "$OUT" "124 Updates offen, davon 59 Security"; has "$OUT" "Container-Probleme (1): alpha/myapp"
  before "$OUT" "Swap zu 90 %" "RAM zu 66 %"                    # Fehler vor ok
  has "$OUT" "┌─ systemd-Dienste"                                 # Auswahl → Werkzeug
  printf '%s\n' "passwordauthentication yes" "permitrootlogin yes" > "$PD_FIX/tools/sshd-T.txt"
  dmode_t; tt_open "Server-Check" 'b\nb\nq\n'
  has "$OUT" "sshd erlaubt Passwort-Login"; has "$OUT" "sshd erlaubt Root-Login"; hasnt "$OUT" "Incus-Snapshots"
  has "$OUT" "Container ohne Restart-Policy oder gestoppt"
}

# ─── Nur lesend ────────────────────────────────────────────────────────────
t_tools_read_only() {                               # alle Seiten-Werkzeuge: keine ändernden Aufrufe
  local t
  for mode in docker layered; do
    conf "MODE=$mode"
    for t in "Server-Check" "Ports & Listener" "Speicherplatz" "Sicherheits-Check" "Updates" "Timer & Cron" \
             "Netzwerk & Zugänge" "Fehler-Log" "RAM / Disk / Top-Prozesse"; do
      if [ "$t" = "Server-Check" ]; then tt_open "$t" 'b\nb\nq\n'; else tt_open "$t" '\nb\nq\n'; fi
      rc_is 20; no_err
    done
  done
  dmode_t; tt_open "Container-Hygiene" '\nb\nq\n'; tt_open "Container-Ressourcen" 'b\nb\nq\n'
  ! awk '/^== /{f=1; next} f{print; f=0}' "$STUB_LOG" | grep -qxE '  (start|stop|restart|reload|enable|disable|rm|prune|update|upgrade|install|delete|kill)' \
    || die "ändernder Aufruf im Stub-Log:\n$(awk '/^== /{f=1; next} f{print; f=0}' "$STUB_LOG" | sort | uniq -c)"
}
