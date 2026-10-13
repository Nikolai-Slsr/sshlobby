# Changelog

All notable changes to sshlobby. Versions follow [semantic versioning](https://semver.org/).

## 3.0.3 (2026-10-13)

- Recent (main menu): opening a Compose project now adds it to "Recent", and selecting the entry opens
  the project again. Before, only container shells, logs and compose folders were recorded.
- Recently used tools moved to their own "Recent" list at the top of the tools menu. In the main menu
  they took the slots of projects and containers (with `RECENT_MAX=3`, three tools hid everything else).
- Recent entries show what they repeat: "Logs · 5 min ago", "Shell · …", "Compose folder · …".
- Fix (layered): a recent container that no longer exists in its Incus container showed an error on
  every try and stayed in the list. Now the entry is removed with a message.
- Fix: entries recorded in the same second were sorted by name instead of time.
- The header and the breadcrumb say "sshlobby" instead of "Project dashboard".
- Settings and `--help` show the project page on GitHub.

## 3.0.2 (2026-10-12)

- Fix: the release archive of 3.0.1 contained a symbolic link (`tests/stubs/wget`), and the archive check of
  `sshlobby update` rejects links. The repository now has no links, and a test makes sure it stays that way,
  so releases from 3.0.2 on install with `sshlobby update`. 3.0.1 itself installs only with `install.sh`.

## 3.0.1 (2026-10-12)

- Release check: once a day sshlobby asks GitHub in the background whether a newer release exists
  (one HTTPS request to `api.github.com`, the login does not wait for it). If there is one, the main menu
  shows a line with the new version and the key `u`. Turn it off in the settings or with
  `UPDATE_CHECK=no`.
- `sshlobby update` checks right away, shows the release notes link and installs the new release after a
  confirmation. `--check` only reports (exit code 3 if a newer release exists), `--yes` skips the question.
  The download is checked before anything changes: one root folder, only plain files and folders, the
  version inside matches the tag, no syntax errors. If the installation fails, the previous version is
  restored. A copy that runs from a git checkout is never replaced.
- Key `u` in the main menu and "Check now" in the settings do the same from the menu and restart sshlobby
  with the new version.
- New config keys `UPDATE_CHECK` and `UPDATE_REPO`, environment variable `SSHLOBBY_UPDATE_CHECK`.
- `install.sh --update`: updates the program and an existing login hook, but does not add a hook that was
  removed. `install.sh` now rejects unknown arguments.

## 3.0.0 (2026-10-12)

First public release.

- The project is now called sshlobby: command `sshlobby`, settings in `~/.config/sshlobby/`, environment
  variables `SSHLOBBY_*`. `install.sh` migrates an installation of the internal predecessor: it copies the
  settings, replaces the old login hook in place and removes the old program files.
- English and German interface. All texts live in `lang/*.txt`; the language comes from the settings menu,
  `SSHLOBBY_LANG` or the system locale. Missing translations fall back to English. See `docs/TRANSLATING.md`.
- Documentation in English, README with screenshots, `CLAUDE.md` with installation steps for coding agents.
- Test fixtures and example descriptions use neutral sample data.

## 2.2.0 (2026-10-12)

- Settings menu (key `e`, `sshlobby --settings`): mode, display name, descriptions, start on SSH login,
  what `q` does, line mode, colors, ASCII symbols, number of recent entries, SSH targets, CVE monitor.
- Reset options with a backup first (`~/.config/sshlobby/backups/`, newest 10 kept) and restore from the menu.
  `sshlobby --reset` resets everything and runs the first-start setup.
- New config keys `AUTOSTART`, `Q_ACTION`, `UI`, `COLOR`, `SYMBOLS`, `RECENT_MAX`, `HERMES_SCAN_CTS`.
- The login hook sets `SSHLOBBY_LOGIN=1`, so `AUTOSTART=no` only affects login starts.
- Updates tool: a finished run in the tmux session is no longer reported as still running.

## 2.1.0 (2026-10-12)

- Hermes agent instances tool: finds instances on the host (systemd, Docker) and inside Incus containers,
  groups gateway and web UI per data folder, shows status, logs, cron jobs, profiles and a masked `config.yaml`.
- Updates tool: refresh package lists, install security updates or all updates, reboot after typing the
  hostname. Runs in a tmux session, so a dropped SSH connection does not stop it.
- Recently used tools appear under "Recent" in the main menu.

## 2.0.0 (2026-10-12)

- Arrow-key interface with header, breadcrumb, key hints, filter (`/`), pager and fallbacks for
  `NO_COLOR`, ASCII terminals and narrow windows. Line mode with the same numbers when there is no terminal.
- Three modes: `docker` (containers on the host, grouped by Compose project), `incus` (Incus containers) and
  `layered` (Incus containers with Docker inside). First-start setup detects the mode.
- Server tools: server check, systemd services, ports, container resources, storage, security check, updates,
  timers and cron, network and access, container hygiene.
- Config file parsed safely (never sourced), descriptions file, favorites and history.

## 1.x

Internal versions: numbered menu for Incus containers with Docker inside.
