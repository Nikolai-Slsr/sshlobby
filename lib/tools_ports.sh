# shellcheck shell=bash
# tools_ports.sh: Werkzeug „Ports & Listener“ (rein lesend).
# ss -tulpnH, jeder Listener zugeordnet zu Prozess, systemd-Dienst (über /proc/<pid>/cgroup)
# bzw. Docker-Container (Portmappings aus dk_load, nur Host-Docker), eingeteilt in
#   1 öffentlich (0.0.0.0, ::, *, öffentliche IP)  2 nur Tailscale (100.64.0.0/10, fd7a:115c:a1e0::/48)
#   3 privat / Docker-Bridge (RFC 1918, ULA, link-local)  4 nur localhost
# Aufeinanderfolgende Ports desselben Besitzers werden zu Bereichen zusammengefasst.

_ports_avail() { have ss; }

# Docker-Portmappings des Hosts → "hostip|port|proto|container|containerport" (Bereiche aufgelöst)
_ports_docker_map() {
  [ "$MODE" = docker ] && have docker || return 0
  dk_load ""
  [ "$DK_RC" -eq 0 ] || return 0
  printf '%s\n' "$DK_ROWS" | awk -F'|' '{
    n = split($5, p, /, */)
    for (i = 1; i <= n; i++) {
      m = p[i]; if (m !~ /->/) continue
      hp = m; sub(/->.*/, "", hp); cp = m; sub(/.*->/, "", cp)
      proto = cp; sub(/.*\//, "", proto); sub(/\/.*/, "", cp)
      ip = hp; sub(/:[^:]*$/, "", ip); gsub(/\[|\]/, "", ip); hports = hp; sub(/.*:/, "", hports)
      split(hports, h, "-"); if (h[2] == "") h[2] = h[1]
      split(cp, k, "-")
      for (x = h[1] + 0; x <= h[2] + 0; x++) print ip "|" x "|" proto "|" $1 "|" (k[1] + x - h[1])
    } }'
}

# → Zeilen "kat|proto|adresse|port|prozess|pid|besitzer", sortiert und zu Bereichen zusammengefasst
# (port dann "von-bis")
tl_ports() {
  local map
  map=$(_ports_docker_map)
  tq 10 ss -tulpnH | awk -v map="$map" -v root="${PD_TOOLS_ROOT:-}" \
      -v hostnet="${TX[ports.owner.hostnet]}" -v session="${TX[ports.owner.session]}" '
    BEGIN { n = split(map, L, "\n")
      for (i = 1; i <= n; i++) { split(L[i], f, "|"); dm[f[1] "|" f[2] "|" f[3]] = f[4] "|" f[5]; dp[f[2] "|" f[3]] = f[4] "|" f[5] } }
    function cls(a,   o) {
      if (a == "0.0.0.0" || a == "*" || a == "::") return 1
      if (a ~ /^127\./ || a == "::1") return 4
      if (a ~ /^100\./) { split(a, o, "."); if (o[2] >= 64 && o[2] <= 127) return 2 }
      if (tolower(a) ~ /^fd7a:115c:a1e0:/) return 2
      if (a ~ /^10\./ || a ~ /^192\.168\./ || a ~ /^172\.(1[6-9]|2[0-9]|3[01])\./ || a ~ /^169\.254\./) return 3
      if (tolower(a) ~ /^(f[cd]|fe80:)/) return 3
      return 1
    }
    function owner_of(pid,   f, l, cg, p) {
      f = root "/proc/" pid "/cgroup"; cg = ""
      while ((getline l < f) > 0) if (l ~ /^0::/ || (cg == "" && l ~ /name=systemd/)) cg = l
      close(f)
      if (cg == "") return ""
      if (cg ~ /lxc\.(payload|monitor)\./) { p = cg; sub(/.*lxc\.(payload|monitor)\./, "", p); sub(/\/.*/, "", p); return "CT " p }
      p = cg; sub(/.*\//, "", p)
      if (p ~ /^docker-[0-9a-f]+\.scope$/) return hostnet " " substr(p, 8, 12)
      if (p ~ /^session-.*\.scope$/) return session
      if (p ~ /\.service$/) return p
      return ""
    }
    NF >= 5 {
      proto = $1; loc = $5
      port = loc; sub(/.*:/, "", port); addr = loc; sub(/:[^:]*$/, "", addr)
      gsub(/\[|\]/, "", addr); sub(/%.*/, "", addr)
      proc = "?"; pid = ""
      if (match($0, /users:\(\("[^"]*",pid=[0-9]+/)) {
        s = substr($0, RSTART + 9, RLENGTH - 9); proc = s; sub(/".*/, "", proc); pid = s; sub(/.*pid=/, "", pid) }
      own = ""
      if (proc == "docker-proxy") {
        k = addr "|" port "|" proto; o = ""
        if (k in dm) o = dm[k]; else if ((port "|" proto) in dp) o = dp[port "|" proto]
        if (o != "") { split(o, q, "|"); own = "Container " q[1] (q[2] != port ? " → " q[2] : "") }
      }
      if (own == "" && pid != "") own = owner_of(pid)
      print cls(addr) "|" proto "|" addr "|" port "|" proc "|" pid "|" own
    }' | sort -t'|' -k1,1n -k2,2 -k3,3 -k5,5 -k7,7 -k4,4n | awk -F'|' '
    function flush() { if (key != "") print c1 "|" c2 "|" c3 "|" (lo == hi ? lo : lo "-" hi) "|" c5 "|" c6 "|" c7 }
    { k = $1 "|" $2 "|" $3 "|" $5 "|" $7
      if (k == key && $4 == hi + 1) { hi = $4; next }
      if (k == key && $4 == hi) next
      flush(); key = k; c1 = $1; c2 = $2; c3 = $3; lo = $4; hi = $4; c5 = $5; c6 = $6; c7 = $7 }
    END { flush() }'
}

# Öffentliche Ports kurz: "22/tcp sshd, 443/tcp caddy, …" (IPv4/IPv6 zusammengefasst)
tl_public_ports() {
  tl_ports | awk -F'|' '$1 == 1 { o7 = $7; sub(/ → .*/, "", o7); k = $4 "/" $2 " " (o7 ~ /^Container / ? substr(o7, 11) : $5); if (!(k in s)) { s[k] = 1; o = o (o == "" ? "" : ", ") k } }
    END { print o }'
}

# Lange Zeilen umbrechen, damit sie in die Seite passen. trenner „, “ (Liste) oder „ “ (Wörter)
_ports_split() { # trenner text → Zeilen (höchstens UI_COLS-8 Zeichen, mindestens 40)
  local w=$(( ${UI_COLS:-80} - 8 )); [ "$w" -ge 40 ] || w=40
  awk -v w="$w" -v sep="$1" '{ n = split($0, a, sep); l = ""
      for (i = 1; i <= n; i++) { s = a[i] ((sep == ", " && i < n) ? "," : "")
        if (l != "" && length(l) + 1 + length(s) > w) { print l; l = s } else l = (l == "" ? s : l " " s) }
      print l }' <<< "$2"
}
_ports_wrap() { # stufe text: Liste an „, “ umbrechen, Folgezeilen eingerückt, gleiche Farbe
  local i; local -a parts
  mapfile -t parts < <(_ports_split ", " "$2")
  tl_line "$1" "${parts[0]}"
  _tl_lvl "$1"
  for ((i = 1; i < ${#parts[@]}; i++)); do printf '    %s%s%s\n' "$_TL_C" "${parts[i]}" "$C_R"; done
}
_ports_hint() { local l; while IFS= read -r l; do tl_dim "$l"; done < <(_ports_split " " "$1"); } # Hinweis, an Wörtern umbrochen

# Seite: Spaltenbreiten je Abschnitt aus den Daten (statt fest 30/16), veröffentlichte Docker-Ports als
# Prozess „docker“ und Besitzer ohne „Container “, damit der Container-Name auch bei 80 Spalten sichtbar ist.
_t_ports_page() {
  local rows cat proto addr port proc own last="" lvl n_pub docker_pub=0 noproc=0 aw=0 pw=0
  local -a title=("" "${TX[ports.cat.public]}" "${TX[ports.cat.tailscale]}" "${TX[ports.cat.private]}" "${TX[ports.cat.local]}")
  rows=$(tl_ports)
  if [ -z "$rows" ]; then tl_line warn "${TX[ports.none]}"; return 0; fi
  n_pub=$(printf '%s\n' "$rows" | awk -F'|' '$1 == 1' | grep -c .)
  if [ "$n_pub" -gt 0 ]; then _ports_wrap warn "$(t ports.public_n "$n_pub" "$(tl_public_ports)")"
  else tl_line ok "${TX[ports.public_none]}"; fi
  printf '%s\n' "$rows" | awk -F'|' '$1 == 1 && $5 == "docker-proxy" { f = 1 } END { exit !f }' && docker_pub=1
  rows=$(printf '%s\n' "$rows" | awk -F'|' -v OFS='|' '{ if ($3 ~ /:/) $3 = "[" $3 "]"
      if ($5 == "docker-proxy" && $7 ~ /^Container /) { $5 = "docker"; $7 = substr($7, 11) }
      print }')
  while IFS="|" read -r cat proto addr port proc _ own; do
    if [ "$cat" != "$last" ]; then
      tl_head "${title[cat]}"; last=$cat
      read -r aw pw < <(printf '%s\n' "$rows" | awk -F'|' -v c="$cat" '$1 == c { a = length($3 ":" $4); p = length($5)
          if (a > aw) aw = a; if (p > pw) pw = p } END { print aw + 0, pw + 0 }')
    fi
    [ "$proc" = "?" ] && noproc=1
    if [ "$cat" = 1 ]; then lvl=warn; else lvl=""; fi
    tl_line "$lvl" "$(tl_pad "$proto" 4) $(tl_pad "$addr:$port" "$aw")  $(tl_pad "$proc" "$pw")  $own"
  done <<< "$rows"
  echo
  [ "$docker_pub" = 1 ] && _ports_hint "${TX[ports.hint.docker_bypass]}"
  [ "$noproc" = 1 ] && _ports_hint "${TX[ports.hint.noproc]}"
  [ "$MODE" = layered ] && _ports_hint "${TX[ports.hint.layered]}"
  return 0
}
_t_ports() { ui_run_page "${TX[ports.title]}" _t_ports_page; }

tool_register ports "${TX[ports.title]}" "${TX[ports.desc]}" "all" _ports_avail _t_ports 93
