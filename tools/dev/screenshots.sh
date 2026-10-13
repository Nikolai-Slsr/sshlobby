#!/usr/bin/env bash
# Screenshots for the README: renders the main screens with the test stubs and fixtures in tmux,
# captures them with colors (capture-pane -e -p) and writes one PNG per view to docs/screenshots/.
#   bash tools/dev/screenshots.sh [output-dir]          SHOTS_LANG=de for German screenshots
# Runs isolated like the tests: fixtures are copied to a throwaway folder, PATH contains only the
# stubs and a few linked system tools (no real docker, incus, ssh …), system values (load, RAM,
# uptime, disk) come from the fixtures, own tmux socket that is killed at the end.
# Needs tmux, python3 with Pillow and the DejaVu fonts.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT=${1:-$ROOT/docs/screenshots}
LANG_SHOTS=${SHOTS_LANG:-en}
VERSION_SHOTS=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/sshlobby.sh")
TMUX_BIN=$(type -P tmux) || { echo "tmux missing" >&2; exit 1; }
PY=$(type -P python3) || { echo "python3 missing" >&2; exit 1; }
"$PY" -c 'import PIL' 2>/dev/null || { echo "python3 Pillow missing (apt-get install python3-pil)" >&2; exit 1; }
BASE=$(mktemp -d "${TMPDIR:-/tmp}/sshlobby-shots.XXXXXX") || exit 1
SOCK="sshlobby-shots-$$"
trap '"$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null; rm -rf "$BASE"' EXIT

SYSBIN="$BASE/sysbin"; mkdir -p "$SYSBIN"
# same tools as tests/run.sh, except df (see below)
for c in bash sh env setsid jq awk sed grep cut tr sort head tail wc date mktemp mv cp cat rm rmdir \
         mkdir touch ln readlink dirname basename seq sleep timeout id install cmp find ls tput stty \
         uptime ps free uniq tee chmod stat true false diff od xargs tac tmux kill \
         printf test expr realpath comm paste nl yes mkfifo; do
  p=$(type -P "$c") && ln -s "$p" "$SYSBIN/$c"
done
# df with fixed sample values instead of the disks of the machine that renders the screenshots
cat > "$SYSBIN/df" <<'EOF'
#!/bin/sh
case " $* " in
  *" -T "*) printf '%s\n' "Filesystem     Type 1024-blocks      Used Available Capacity Mounted on" \
              "/dev/vda1      ext4   102687672  42949672  54525952      45% /" \
              "/dev/vda15     vfat      126678     11840    114838      10% /boot/efi" \
              "/dev/vdb1      ext4   515928320 216760320 272957440      45% /srv";;
  *) printf '%s\n' "Filesystem      Size  Used Avail Use% Mounted on" "/dev/vda1        98G   41G   53G  44% /";;
esac
EOF
chmod +x "$SYSBIN/df"
STUBPATH="$ROOT/tests/stubs:$SYSBIN"

T() { "$TMUX_BIN" -L "$SOCK" -f /dev/null "$@"; }
N=0

# New environment (HOME + fixtures) per group of views
fresh() { # config lines…
  E="$BASE/e$N"; mkdir -p "$E/home/.config/sshlobby"
  cp -r "$ROOT/tests/fixtures" "$E/fix"
  sed -i "s|@FS@|/srv|g" "$E/fix/host-docker"
  # some life: one unhealthy container
  sed -i 's/^chat-mongodb|mongo:8.0.20|running|Up 4 weeks|/chat-mongodb|mongo:8.0.20|running|Up 4 weeks (unhealthy)|/' "$E/fix/host-docker"
  # login hook as written by install.sh, so the settings show the normal state
  sed -n '/^# >>> sshlobby >>>$/,/^# <<< sshlobby <<<$/p' "$ROOT/install.sh" > "$E/home/.bashrc"
  # release check done a moment ago, nothing newer: no background check, settings show "on · checked just now"
  update_cache "v$VERSION_SHOTS"
  [ $# -gt 0 ] && printf '%s\n' "$@" > "$E/home/.config/sshlobby/config"
}
update_cache() { # tag → cached result of the daily release check in the current environment
  printf 'checked=%s\nrepo=Nikolai-Slsr/sshlobby\nstatus=ok\ntag=%s\nurl=https://github.com/Nikolai-Slsr/sshlobby/releases/tag/%s\n' \
    "$(date +%s)" "$1" "$1" > "$E/home/.config/sshlobby/update-check"
}
# Take a view: shot file.png "window title" width height "wait-for" keys… [-- env…]
# Keys: @text waits for text, !text waits until text is gone, +text types text, anything else is a tmux key name.
shot() {
  local file=$1 title=$2 w=$3 h=$4 want=$5 k i; shift 5
  local -a keys=() envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do keys+=("$1"); shift; done
  [ "${1:-}" = -- ] && { shift; envs=("$@"); }
  N=$((N + 1))
  # every view starts from the same history (opening a project or tool adds entries and shifts numbers)
  [ -f "$E/recents.fixed" ] && cp "$E/recents.fixed" "$E/home/.config/sshlobby/recents"
  SHELL=$(type -P bash) T new-session -d -x "$w" -y "$h" -s "s$N" \
    "env -i PATH='$STUBPATH' HOME='$E/home' PD_FIX='$E/fix' PD_TOOLS_ROOT='$E/fix/tools/root' STUB_LOG=/dev/null \
     STUB_TTY_INTERACTIVE=1 STUB_HOSTNAME=web-01 LC_ALL=C.UTF-8 TERM=xterm-256color SSHLOBBY_LANG=$LANG_SHOTS \
     SHELL='$ROOT/tests/stubs/hostshell' ${envs[*]} bash '$ROOT/sshlobby.sh'; sleep 60"
  sleep 1
  for k in "${keys[@]}"; do
    case "$k" in
      @*) for ((i=0; i<50; i++)); do T capture-pane -p -t "s$N" | grep -qF -- "${k#@}" && break; sleep 0.1; done;;
      !*) for ((i=0; i<150; i++)); do T capture-pane -p -t "s$N" | grep -qF -- "${k#!}" || break; sleep 0.1; done;;
      +*) T send-keys -t "s$N" -l "${k#+}"; sleep 0.3;;
      *)  T send-keys -t "s$N" "$k"; sleep 0.3;;
    esac
  done
  for ((i=0; i<50; i++)); do T capture-pane -p -t "s$N" | grep -qF -- "$want" && break; sleep 0.1; done
  T capture-pane -p -t "s$N" | grep -qF -- "$want" || echo "warning: '$want' not on screen for $file" >&2
  sleep 0.5
  T capture-pane -e -p -t "s$N" > "$BASE/$file.ans"
  [ -n "${SHOTS_KEEP:-}" ] && cp "$BASE/$file.ans" "$SHOTS_KEEP/"
  T kill-session -t "s$N"
  PYTHONDONTWRITEBYTECODE=1 "$PY" "$ROOT/tools/dev/ansi2png.py" "$OUT/$file" "$w" "$h" "$title" "$BASE/$file.ans" && echo "  $OUT/$file"
}

mkdir -p "$OUT"
case "$LANG_SHOTS" in
  de) W_MAIN="COMPOSE-PROJEKTE" W_TOOLS="Server-Werkzeuge" W_CHECK="Server-Check" W_CONFIRM="[j/N]"
      W_LAYERED="PROJEKTE / CONTAINER" W_SETTINGS="Einstellungen" W_SETUP="Modus" W_CONT="CONTAINER" W_CHECKING="Prüfe den Server"
      W_UPDATE="Neue Version";;
  *)  W_MAIN="COMPOSE PROJECTS" W_TOOLS="Server tools" W_CHECK="Server check" W_CONFIRM="[y/N]"
      W_LAYERED="PROJECTS / CONTAINERS" W_SETTINGS="Settings" W_SETUP="mode" W_CONT="CONTAINERS" W_CHECKING="Checking the server"
      W_UPDATE="New version";;
esac

fresh "MODE=docker" "HOST_LABEL=web-01"
cp "$ROOT/examples/descriptions.docker-host" "$E/home/.config/sshlobby/descriptions"
# history: a Compose project, a container shell and logs in the main menu, two tools in the tools menu
now=$(date +%s)
printf '%s\n' "$((now - 7200))|-|hermes|logs" "$((now - 3600))|@tool|updates|tool" "$((now - 900))|@tool|check|tool" \
  "$((now - 300))|nextcloud|Nextcloud|shell" "$((now - 120))|nextcloud|-|project" > "$E/recents.fixed"
printf 'nextcloud|Nextcloud\n' > "$E/home/.config/sshlobby/favorites"
# main menu: 1 nextcloud (project), 2 nextcloud / Nextcloud, 3 hermes, 4 ★ favorite, projects, tools last (End)
shot main-docker.png "root@web-01: ~" 104 23 "$W_MAIN"
shot project.png "root@web-01: ~" 104 24 "$W_CONT" 1 Enter Down
shot confirm.png "root@web-01: ~" 104 22 "$W_CONFIRM" 1 Enter Down Enter Down Down Down Enter
shot tools.png "root@web-01: ~" 104 26 "$W_TOOLS" End Enter
shot server-check.png "root@web-01: ~" 104 17 "› $W_CHECK" End Enter "@$W_TOOLS" 1 Enter "@› $W_CHECK" "!$W_CHECKING"

# Main menu with the hint for a newer release (cached result of the daily check, no network)
update_cache v3.1.0
shot update.png "root@web-01: ~" 104 14 "$W_UPDATE"

fresh "MODE=layered" "HOST_LABEL=lab-01" "CVE_CT=security"
cp "$ROOT/examples/descriptions.incus-host" "$E/home/.config/sshlobby/descriptions"
shot layered.png "root@lab-01: ~" 104 15 "$W_LAYERED"
shot settings.png "root@lab-01: ~" 104 39 "$W_SETTINGS" e

fresh
shot setup.png "root@web-01: ~" 104 14 "$W_SETUP"

echo "done: $N views in $OUT"
