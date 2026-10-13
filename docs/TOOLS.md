# sshlobby tools

The **Tools** menu in the main menu collects admin tools for the server sshlobby runs on.
When the menu opens, each tool checks whether it applies (command present, mode fits). Tools
that do not apply are not shown.

Principles:

- **Read-only by default.** Only "systemd services", "Updates" and "Hermes instances" have
  actions that change something, and every one of them asks first (except Start). There is no
  `docker prune` and no deletion. Cleanup commands appear at most as a line "Suggestion, not
  run: ...".
- All queries run with a timeout and without input, so a hanging service does not block sshlobby.
- Longer output opens as a page (back with Enter), lists open as a menu with the usual keys.
  Some details (processes behind ports, `sshd -T`, `wg show`, swap per process) are visible
  only to root.

Tool names below are the English UI texts. They come from `lang/*.txt` like every other text.

## Overview

| Tool | Modes | Data source | Changes something |
|---|---|---|---|
| RAM / disk / top processes | all | `/proc/meminfo`, `/proc/*/status`, `df`, `ps` | no |
| Error log | all (with journalctl) | `systemctl list-units --state=failed`, `journalctl -p err -o json`, `docker inspect` | no |
| Other server (SSH) | all | `SSH_HOSTS` from the config, else `~/.ssh/config` | no (opens ssh) |
| Server check | all | all sources listed below | no |
| systemd services | all (with systemctl) | `systemctl list-units -o json`, `list-unit-files`, `show`, `journalctl -u` | yes, with confirmation |
| Ports & listeners | all (with ss) | `ss -tulpnH`, `/proc/<pid>/cgroup`, Docker port mappings | no |
| Container resources | docker (docker), incus/layered (incus) | `docker stats --no-stream`, `incus list --format json` | no |
| Storage | all | `df`, `journalctl --disk-usage`, `docker system df [-v]`, `incus query /1.0/storage-pools...` | no |
| Security check | all (journalctl or sshd) | `journalctl -t sshd -t sshd-session`, `sshd -T`, `ss`, apt configuration, `reboot-required` | no |
| Hermes instances | all (systemd, Docker or Incus) | `systemctl show`, `docker inspect`, `incus exec ... sh -c`, data directory (`logs/`, `config.yaml`) | gateway/WebUI restart, stop, start, `hermes update`, `docker pull` (all with confirmation except start) |
| Updates | all (with apt) | `apt list --upgradable`, `/var/lib/apt/lists`, `/var/run/reboot-required`, `uname -r`, `/boot` | `apt-get update/upgrade`, security install, `systemctl reboot` (all with confirmation) |
| Timers & cron | all | `systemctl list-timers -o json`, `crontab -l`, `/etc/crontab`, `/etc/cron.d`, `/etc/cron.*` | no |
| Network & access | all (if any of them is present) | `tailscale status`, cloudflared units and `/etc/cloudflared/*.yml`, `/etc/caddy/Caddyfile`, `wg show all dump` | no |
| Container hygiene | docker | `docker ps -a`, `docker inspect` | no |
| Docker health | docker, layered | `docker ps -a`, one `docker inspect` per Docker (restarts, OOM, exit code); container page: `docker inspect <container>` | no (opens the project and container screens, whose actions ask first) |

The other tools from v1.1 (Incus overview, Mutagen, CVE monitor, Incus
resources, New project) work as before. The last entry, "Settings", opens the settings menu
(also key `e` in the main menu).

## Server check

One traffic light across all areas: failed units, full file systems (from 80 %), RAM and swap,
Incus pool usage (from 75 %) and existing snapshots, container problems, hygiene, pending
updates (security updates count as errors), required reboot, public ports, insecure sshd
options, failed SSH logins, errors in the journal. Errors come first, then warnings, then what
is fine. **Selecting a line opens the matching tool**, `r` checks again.

## systemd services

List of all services, grouped:

1. **Favourites** (your own, set with `f` in the service screen; file `~/.config/sshlobby/service-favorites`)
2. **Failed**
3. **Custom / important**: unit file under `/etc/systemd/system` or `/usr/local`, so not from
   the package manager (for example cloudflared, mutagen, your own services)
4. **Running**
5. **Other**: inactive or finished one-shot units, also installed services that were never loaded

Hidden: templates (`foo@.service`), aliases and references to units that do not exist.
Each line: name, `active/sub`, description. `r` reloads.

The service screen shows description, status with timestamp, main PID, memory, restarts,
autostart, unit file (marked as custom), drop-ins. Actions:

| Action | Command | Confirmation |
|---|---|---|
| Follow logs | `journalctl -u <unit> -f -n 100` | no, Ctrl-C returns |
| Recent warnings and errors | `journalctl -u <unit> -p warning -n 50` | no |
| systemctl status | `systemctl status <unit>` | no |
| Show unit file | `systemctl cat <unit>` | no |
| Start | `systemctl start` | no |
| Restart, stop | `systemctl restart/stop` | yes |
| Enable/disable autostart | `systemctl enable/disable` | yes |

**Units that carry the SSH session or sshlobby** (`ssh`, `sshd`, `systemd-logind`, `dbus`,
`dbus-broker`, `user@*`, `user-runtime-dir@*`, `systemd-networkd`, `networking`, `NetworkManager`,
`tailscaled`, `wg-quick@*`): restart, stop and disable show a warning, ask for confirmation and
also require you to type the name of the unit.

## Ports & listeners

All TCP/UDP listeners, each with its process and owner (systemd service from the cgroup, Docker
container through the port mapping, login session, Incus CT). Groups in this order:

1. **Public**: `0.0.0.0`, `::`, `*` or a public IP, highlighted
2. **Tailscale only**: 100.64.0.0/10 and fd7a:115c:a1e0::/48
3. **Private / Docker bridge**: RFC 1918, ULA, link-local
4. **localhost only**

Consecutive ports of the same owner are merged (for example `25500-25600`). Public Docker
ports get a hint: they bypass ufw and INPUT rules. In layered mode, ports of Docker inside the
CTs are visible only if Incus maps them to the host with a proxy device.

## Container resources

- **docker**: `docker stats` as a list, `s` toggles between RAM and CPU sorting, `r` measures
  again, selecting an entry opens the container screen. Host RAM and swap are shown as well.
- **layered**: CTs sorted by RAM, with swap, disk, limit and processes. CTs that use swap are
  marked. Selecting an entry shows `docker stats` inside the CT.
- **incus**: like layered, selecting an entry shows `incus list` for the CT.

## Storage

File systems (warning from 80 %, error from 90 %), journal size. In docker mode also
`docker system df`, the largest images (marked "unused"), volumes (marked "orphaned") and the
build cache. In incus and layered mode the storage pools with usage (loop file pools are named
explicitly, because a full pool stops all CTs), disk per CT and **existing Incus snapshots as
a warning**. Docker usage inside the individual CTs is deliberately not queried (too slow with
many CTs).

## Security check

Failed SSH logins in the last 24 h (total, top 5 addresses), last successful logins, `sshd -T`
(PasswordAuthentication, KbdInteractiveAuthentication, PermitRootLogin, Port), public ports,
whether unattended-upgrades is on, whether a reboot is required.

## Updates

Header: pending updates, how many of them are security updates, age of the package lists,
whether a reboot is required (`/var/run/reboot-required`, or a kernel under `/boot` that is
newer than the running one).

| Entry | What happens |
|---|---|
| Overview | security packages by name, kernel, reboot |
| List all packages | `apt list --upgradable` |
| Refresh package lists | `apt-get update` |
| Install security updates | after confirmation: `apt-get update`, then `apt-get install --only-upgrade` for packages from `*-security` only |
| Install all updates | after confirmation: `apt-get update`, then `apt-get --with-new-pkgs upgrade` |
| Reboot server | only when required, after confirmation and typing the host name: `systemctl reboot` |

apt runs with `DEBIAN_FRONTEND=noninteractive`, keeps modified config files
(`--force-confdef --force-confold`) and waits up to 120 s for a dpkg lock (for example held by
unattended-upgrades). With tmux installed, the installation runs in the session
`sshlobby-apt`: if the SSH connection drops, apt keeps running and the tool offers "Open
running update". If Docker packages are part of the update, sshlobby warns first that the
Docker daemon will restart.

## Hermes instances

Finds Hermes Agent instances on every level and merges gateway and WebUI per data directory
(`HERMES_HOME`) into one instance:

```
System (systemd) ─ Docker (host) ─ Incus CT ─┬─ System (systemd in the CT)
                                             └─ Docker (in the CT)
```

* **systemd:** units whose `ExecStart` contains "hermes". Data directory from `HERMES_HOME` in
  `Environment`, otherwise the home of the unit user + `/.hermes`. Units with "webui" in the
  name are the WebUI.
* **Docker:** image `hermes-agent` or entrypoint `entrypoint-dispatch` (gateway or agent, data =
  mount on `HERMES_HOME`, default `/opt/data`), image `hermes-webui` or cmd `hermeswebui` (WebUI,
  data = mount on `.../.hermes`). Helper containers such as a browser or socat do not count.
  Only `HERMES_HOME` is read from the container environment, never other variables.
* **Incus:** the same script runs in every running CT through `incus exec`, in parallel, at
  most 25 s each. `HERMES_SCAN_CTS=no` in the config turns this off.

Instance screen: status (`hermes status`), diagnostics (`hermes doctor`), cron jobs, profiles,
interactive Hermes CLI, follow gateway logs (journalctl or `docker logs`), `logs/errors.log`
and `logs/agent.log`, `config.yaml` with keys, tokens and passwords masked, disk usage, shell
(data directory or container), restart/stop/start of gateway and WebUI, update (`hermes update`
for systemd installations, `docker pull` of the image for containers, which takes effect only
after the container is recreated). For a stopped container the CLI entries are missing. Logs
and files still work because the data directory lives on the outer level.

## Timers & cron

systemd timers sorted by next run (with "in 3 h" and the last run; timers without a next run at
the end; failed target units marked), the crontab of the current user, `/etc/crontab`, every
file in `/etc/cron.d` and the scripts in `/etc/cron.{hourly,daily,weekly,monthly}`. Comments
and variable lines are hidden.

## Network & access

Each section appears only if the component is present:

- **Tailscale**: this node, whether it offers an exit node, peers (offline dimmed, active
  green), health warnings
- **cloudflared**: services and ingress rules (hostname → target) from `/etc/cloudflared/*.yml`
- **Caddy**: site addresses from the Caddyfile with the first `reverse_proxy` target (snippets,
  global options and commented-out blocks are skipped)
- **WireGuard**: interfaces and peers with endpoint, allowed IPs, last handshake and traffic.
  Private keys are never shown.

## Container hygiene (docker)

Containers without a Compose project and without a restart policy (they do not come back after
a reboot), stopped containers, random names (`docker run` without `--name`), containers whose
image no longer has a name, and images without a fixed tag (`latest`). Suggestions such as
`docker rm ...` or `docker update --restart unless-stopped ...` are shown as text only.

## Docker health (docker, layered)

A menu, not a page. **docker**: two sections, Compose projects (one line per project: running/total,
the worst state as a pill, the containers that cause it) and standalone containers (one line per
container: image, uptime, state). Within each section problems come first, then by name.
**Selecting a project** opens the project screen, **selecting a container** the container screen.
**layered**: first one line per Incus container (problems first). Selecting it opens the same view
for the Docker inside that container; a stopped container, or one without (reachable) Docker,
opens the CT screen instead, where it can be started.

| Level | Cases |
|---|---|
| error (red) | unhealthy, restart loop (`restarting`), OOM-killed, `dead` |
| warning (yellow) | exited with an exit code other than 0, 3 or more restarts by Docker, health check starting |
| stopped (grey) | exited with 0, `created`, `paused` |

These are the same rules the server check and the error log use. Keys: `p` shows only problems
(and back), `r` checks again, `/` filters. The Incus overview in layered mode reads only `docker ps`
per container (exit codes from the status text), restarts and OOM kills appear one level down.

The container screen (from here or from the main menu) has the entry **State and health check**:
state, start and finish time, exit code, restarts, restart policy, OOM kill, the error text, the
health check command and its last results (newest first, from `docker inspect`), or a note that
the container has no health check.

## Error log, RAM / disk, other server

- **Error log**: failed units, errors of the last 24 h grouped by unit (count, time and text of
  the last message, number of distinct messages), containers that are unhealthy, OOM-killed,
  restarting often or exited with an error (docker: host, layered: every running CT), then the
  last 40 messages as before.
- **RAM / disk / top processes**: RAM and swap with percentages, swap usage per process, file
  systems, top processes by RAM and CPU.
- **Other server (SSH)**: targets from `SSH_HOSTS`. Without `SSH_HOSTS`, the `Host` entries
  from `~/.ssh/config` without wildcards and negations, with HostName and User as extra info.

```ini
# ~/.config/sshlobby/config
SSH_HOSTS=docker-host incus-host admin@192.0.2.10
```

## For developers

Tools live in one file per topic, `lib/tools_<name>.sh`, and register with `tool_register`
(see `docs/ARCHITECTURE.md`). Their texts go into `lang/*.txt`. Shared helpers in `lib/tools.sh`:

| Helper | Purpose |
|---|---|
| `tl_head`, `tl_line level text`, `tl_kv label value [level]`, `tl_text`, `tl_dim`, `tl_hint` | Page output with the theme colours `C_*` |
| `tl_pad text width`, `tl_cut text width`, `tl_human bytes`, `tl_lvl percent warn err` | Formatting (per character, UTF-8 safe) |
| `tq sec cmd...` | Command with timeout, no stdin, stderr silenced |
| `tp path` | System path, redirected under `PD_TOOLS_ROOT` in tests |
| `tl_failed_units`, `tl_journal_errs`, `tl_ctr_issues`, `tl_ports`, `tl_public_ports`, `tl_pools`, `tl_snapshots`, `tl_updates`, `tl_reboot`, `tl_sshd`, `tl_ssh_fails`, `tl_hygiene`, `tl_df_rows`, `tl_meminfo` | Data functions, also used by the server check |

Tests: `tests/test_tools_services.sh`, `tests/test_tools_pages.sh`, `tests/test_tools_hermes.sh`.
Fixtures in `tests/fixtures/tools/` are based on real command output with IPs replaced by
documentation addresses. Stubs for `ss apt sshd tailscale wg crontab uname cloudflared` live in
`tests/stubs/`.

```bash
# Terminal, in the repository root
bash tests/run.sh tools hermes
```
