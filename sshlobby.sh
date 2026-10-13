#!/usr/bin/env bash
# sshlobby: interaktives Projekt-Dashboard für Server mit Docker, Incus oder Incus+Docker
# (Modi docker, incus, layered). Auto-Start beim SSH-Login über den Bashrc-Hook (install.sh).
# Dieser Starter lädt nur die Module aus lib/: Pfad über readlink -f des eigenen Pfads
# (funktioniert aus dem Repo und installiert), Override mit SSHLOBBY_LIB.
# Exit-Codes Menü: 0 Ende/EOF, 10 Host-Shell (s), 20 Logout (q). Nur 20 loggt im Hook aus.
set -u

# shellcheck disable=SC2034 # VERSION und PD_EXAMPLES nutzen die Module
VERSION="3.1.1"
PD_SELF=$(readlink -f "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034 # PD_CALLED: aufgerufener Pfad (meist der Starter-Symlink), braucht sshlobby update
PD_CALLED=${BASH_SOURCE[0]}
PD_LIB=${SSHLOBBY_LIB:-$(dirname "$PD_SELF")/lib}
# shellcheck disable=SC2034
PD_EXAMPLES=${SSHLOBBY_EXAMPLES:-$(dirname "$PD_LIB")/examples}
# shellcheck disable=SC2034 # PD_ARGV (Neustart nach Sprachwechsel) und PD_LANGDIR lesen die Module
PD_ARGV=("$@")

# core zuerst: Config-Pfade und Sprache, damit alle weiteren Module übersetzte Texte nutzen können
if [ ! -r "$PD_LIB/core.sh" ]; then printf 'sshlobby: missing module: %s\n' "$PD_LIB/core.sh" >&2; exit 1; fi
# shellcheck source=/dev/null
. "$PD_LIB/core.sh"
# Sprachdateien: SSHLOBBY_LANGDIR, sonst lang/ neben lib/, sonst lang/ neben diesem Starter
# (z. B. wenn SSHLOBBY_LIB auf eine Kopie von lib/ ohne lang/ zeigt)
PD_LANGDIR=${SSHLOBBY_LANGDIR:-$(dirname "$PD_LIB")/lang}
if [ -z "${SSHLOBBY_LANGDIR:-}" ] && ! compgen -G "$PD_LANGDIR/*.txt" > /dev/null; then
  PD_LANGDIR=$(dirname "$PD_SELF")/lang
fi
i18n_detect
i18n_load

for _m in ui backend_incus backend_docker screens tools setup settings update cli; do
  if [ ! -r "$PD_LIB/$_m.sh" ]; then printf 'sshlobby: missing module: %s\n' "$PD_LIB/$_m.sh" >&2; exit 1; fi
  # shellcheck source=/dev/null
  . "$PD_LIB/$_m.sh"
done
# Erweiterungen (z. B. weitere Werkzeuge): lib/tools_*.sh
for _m in "$PD_LIB"/tools_*.sh; do
  # shellcheck source=/dev/null
  [ -r "$_m" ] && . "$_m"
done
unset _m

pd_main "$@"
