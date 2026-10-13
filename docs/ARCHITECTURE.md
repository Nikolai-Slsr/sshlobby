# sshlobby architecture and API (2.0 and later)

Reference for anyone extending sshlobby: the look (UI), new tools, new backends.
Ground rules: **screens never call `incus` or `docker` directly**, only the backend
functions, and **rendering lives only in the `_ui_render_*` and `_ui_tui_*` functions** of `lib/ui.sh`.
**User-facing text lives only in `lang/*.txt`**, the code refers to it by key (see [Languages](#languages-i18n)).

## Modules

| File | Responsibility |
|---|---|
| `sshlobby.sh` | Launcher: finds `lib/` via `readlink -f` (override `SSHLOBBY_LIB`), loads `core.sh`, selects and loads the language, loads the remaining modules and `lib/tools_*.sh`, calls `pd_main` |
| `lib/core.sh` | Exit codes, language selection and lookup (`i18n_*`, `TX`, `t`, `tf`), config parser (`cfg_load`, `cfg_set`), descriptions, recents/favorites, system values (`sys_stats`), `have` |
| `lib/ui.sh` | Menu engine (TUI and line mode), keyboard, rendering, theme, dialogs, foreground commands, terminal hygiene |
| `lib/backend_incus.sh` | Incus CTs: load list, status/IP, CT shell, start/stop/restart, info, log, resources, images, launch |
| `lib/backend_docker.sh` | Docker through the context wrapper `dk` (host or CT), container data, preflight, shell, logs, actions, Compose project |
| `lib/screens.sh` | Main menu per mode, CT screen, project screen, container screen, tools menu |
| `lib/tools.sh` | Tool registry, shared tool helpers, the tools ported from v1.1 and the "Settings" entry |
| `lib/setup.sh` | Mode detection (`setup_detect`), mode selection for the run (`mode_resolve`), setup screen (mode, display name `HOST_LABEL`, example descriptions) |
| `lib/settings.sh` | Settings menu (key `e` in the main menu, `--settings`, `--reset`): mode, start behaviour, display, language, release check, reset and restore with backups |
| `lib/update.sh` | Release check (`upd_auto` in the background once a day, cache `~/.config/sshlobby/update-check`), main menu hint and key `u` (`upd_banner`, `upd_tui`), `sshlobby update` (`cli_update`): download, archive check, `install.sh --update`, restore on failure |
| `lib/cli.sh` | Arguments, `--list`, `--go`, `--setup`, `--settings`, `--reset`, `--mode`, `update`, `pd_main` |
| `lib/tools_*.sh` | (optional) more tools, loaded automatically after all other modules and before `pd_main` runs |
| `lang/*.txt` | All UI texts, one block per key with one line per language (format in the header of `lang/strings.txt`) |
| `examples/descriptions.<name>` | Example descriptions. The setup offers all of them and preselects the one matching `hostname -s` |
| `tools/dev/` | Developer tools: `screenshots.sh` (HTML preview of all screens, built from the test stubs), `ansi2html.py` |

Load order: `core`, then `i18n_detect` and `i18n_load`, then `ui`, `backend_incus`,
`backend_docker`, `screens`, `tools`, `setup`, `settings`, `update`, `cli`, then `tools_*.sh` in
alphabetical order. All modules contain only function definitions and globals. Only `tools.sh`
(and extensions) run `tool_register` while loading. Because the language is loaded before the
other modules, `${TX[key]}` is available at load time, for example in `tool_register` calls.

## Modes

| Mode | Main menu | Levels | Docker context | Recents/favorites group |
|---|---|---|---|---|
| `docker` | Compose projects (label `com.docker.compose.project`), "standalone containers" | project → container | `""` (host) | project or `-` |
| `incus` | Incus CTs | CT (actions) | none | CT, target always `-` |
| `layered` | Incus CTs | CT → Docker container | `<ct>` | CT |

Mode selection: `--mode` > `SSHLOBBY_MODE` > `MODE` from the config > detection. Without a
config, only the interactive menu on a terminal shows the setup screen. Without a TTY, and with
`--list` or `--go`, sshlobby detects the mode silently and writes nothing. Detection
(`setup_detect`): a CT with reachable Docker → `layered`, otherwise host Docker with containers →
`docker`, otherwise Incus reachable → `incus`, otherwise `docker`.

## Languages (i18n)

Every text the user sees comes from `lang/*.txt`. The format is described in the header of
`lang/strings.txt`. In short: one block per key, one line per language.

```ini
# lang/strings.txt
[settings.language.saved]
de = Sprache: %s. Die Oberfläche startet neu.
en = Language: %s. The interface restarts.
```

Rules:

- Keys use lowercase letters, digits, `.` and `_`, grouped by area (`main.*`, `settings.*`, ...).
- English (`en`) is the base. Every key needs an `en` line. A missing translation falls back to English.
- Placeholders are printf style: `%s` (text), `%d` (number). Every language has the same placeholders
  in the same order. `%%` is a literal percent sign, `\n` a line break.
- Spaces around the text are trimmed.
- All `lang/*.txt` files are read together. A key must exist in only one file.

### Language selection

`i18n_detect` (in `lib/core.sh`) sets `PD_LANG` and `PD_LANG_SRC`:

1. `SSHLOBBY_LANG` from the environment (`PD_LANG_SRC=env`)
2. `LANGUAGE=<code>` in `~/.config/sshlobby/config` (`config`)
3. System locale from `LC_ALL`, `LC_MESSAGES` or `LANG`: `de*` → `de`, anything else → `en` (`locale`)

A value that is not a two-letter lowercase code falls back to `en`. The settings menu writes
`LANGUAGE` with `cfg_set` (the "automatic" entry writes an empty value, which means the
locale). The TUI then restarts itself with the new language, line mode applies it on the next
start. `SSHLOBBY_LANG` in the environment still wins over the saved value.

### API

| Name | Behaviour |
|---|---|
| `i18n_detect` | Selects the language as described above, sets `PD_LANG` and `PD_LANG_SRC` (`env`, `config`, `locale`) |
| `i18n_load` | Reads `$PD_LANGDIR/*.txt` with one `awk` pass and fills the associative array `TX[key]`: the `PD_LANG` text if present, else the `en` text |
| `i18n_langs` | All language codes that occur in `lang/*.txt`, `en` first (used by the settings menu) |
| `i18n_sys_lang` | Language derived from the locale alone (`de` or `en`) |
| `"${TX[key]}"` | Fixed text. No subshell, use it in hot paths (rendering, menu building) |
| `tf var key args...` | Formats the text with `printf -v` into `var` |
| `t key args...` | Prints the formatted text. For `$(...)` outside hot paths |
| `PD_LANGDIR` | Directory with the language files. Default `lang/` next to `lib/`, override `SSHLOBBY_LANGDIR` |

An unknown key prints the key itself, so a missing text shows up as `area.name` in the UI
instead of an empty line.

```bash
# in a screen or tool
ui_item item reload "${TX[main.reload]}"           # fixed text
tf msg settings.language.saved "$name"             # formatted, into $msg
ui_msg ok "$msg"
ui_note info "$(t settings.language.next_start "$name")"
```

`tests/test_i18n.sh` checks that every key has `en` and `de` with matching placeholders, that
every key used in the code (`TX[...]`, `t key`, `tf var key`) exists in `lang/`, the fallback to
English and the language selection. How to add a language is described in
[TRANSLATING.md](TRANSLATING.md).

## UI engine (`lib/ui.sh`)

Two presentations with the same API and the same numbers (design and fallbacks: `docs/UI.md`):

- `UI_MODE=tui`: stdin and stdout are a terminal. Alternate screen, arrow keys.
- `UI_MODE=line`: pipe, tests, scripts. Numbered lines, input read line by line from stdin.
- `SSHLOBBY_UI=line` forces line mode (useful for debugging on a terminal).

### Menu

```bash
ui_item header "" "${TX[main.containers]}" "" main     # section, not selectable
ui_item item "c:$name" "$name" "$image" run            # selectable entry
ui_item item "c:$name" "$name" "$image" run "$image"$'\t'"$(ui_cell p-ok healthy)"   # with TUI columns
ui_item disabled "" "${TX[docker.none]}"               # hint, not selectable
ui_item sep                                            # blank line
ui_info "Image" "$image"                               # info line below the title
UI_KEYS=("r|${TX[key.reload]}" "f|${TX[key.fav_add]}") # hotkeys
ui_menu "$title" "$subtitle"
case "$UI_ACT" in
  select) ... "$UI_SEL" ...;;   # value of the selected entry
  key)    ... "$UI_SEL" ...;;   # hotkey that was pressed
  back|quit|eof) return;;
esac
```

The key names in this example are placeholders. Look up the real ones in `lang/*.txt`.

| Name | Meaning |
|---|---|
| `UI_ITEMS=("type\|value\|label\|right\|status[\|columns]" ...)` | Entries. `type`: `item`, `header`, `disabled`, `sep`. `status`: `run`, `stop`, `warn`, `err`, `fav`, `gone`, `danger` or empty (marker in front of the label; `danger` marks a dangerous action and is visible only in the TUI; for `header` it sets the colour: `recent`, `fav`, otherwise green) |
| `ui_item type value label [right] [status] [columns]` | Appends to `UI_ITEMS`, replaces `\|` and line breaks in texts. `columns` (optional): table cells for the TUI, separated by tabs. They are aligned across all entries; narrow terminals drop columns from the right. Without `columns` the TUI shows `right` as one dimmed column. Line mode always shows `right` |
| `ui_cell style text` | Styled cell for `columns`, `right` and `ui_info` values: `ok warn err info dim acc bold`, pills `p-ok p-warn p-err p-info`. Line mode and search see only the text |
| `UI_INFO=("label\|value[\|status]" ...)`, `ui_info label value [status]` | Info lines below the title, labels are aligned. The value may contain cells (`ui_cell`, tabs) |
| `UI_KEYS=("key\|description" ...)` | Hotkeys. Reserved: `b h j k l q /`, digits |
| `UI_STAT="running\|total\|unhealthy\|unit"` | Counter in the header (set by the main menu, stays until the next change) |
| `UI_ROOT=1` | Main menu: `q` = quit, back keys do nothing, footer shows "q Logout" (or "q Shell" with `Q_ACTION=shell`) |
| `UI_STYLE=main` | Dashboard header instead of the title line (uses `HOST_LABEL`, `VERSION`, `MODE`, `SYS_*`) |
| `UI_PRESEL=value` | Initial cursor position. Without it: the value selected last under the same title, else the first entry |
| `ui_menu title [subtitle]` | Shows the menu. Sets `UI_ACT` to `select`, `key`, `back`, `quit` (only with `UI_ROOT=1`) or `eof`, plus `UI_SEL`. Always returns 0. Afterwards `UI_ITEMS UI_INFO UI_KEYS UI_ROOT UI_STYLE UI_PRESEL` are empty |

Numbers: selectable entries are numbered from 1, identically in both presentations.
Values (`value`) must not contain `|`. The screens use `kind:a:b` (names of CTs, projects and
containers contain no `:`).

TUI keys: ↑/↓, `k`/`j`, PgUp/PgDn, Home/End; Enter/→/`l` select; ←/`h`/Esc/Backspace/`b` go
back; `q` goes back (main menu: logout). Digits jump to an entry. Multi-digit numbers are
accepted as long as a longer number is possible, finished after 0.8 s or with Enter (Enter
opens the entry directly). Headers and hints are skipped, long lists scroll, `SIGWINCH`
redraws (polled every 0.25 s because the signal does not interrupt `read`).

`/` filters any list live (label, right column, cells; case-insensitive). Enter keeps the
filter, Esc clears it (while typing and afterwards), Backspace deletes. Sections without
matches and hint lines are hidden, the numbers stay the original ones.

Keyboard: after Esc the engine waits 0.1 s for the `[` or `O` of an arrow key sequence. Any
other character (for example a second Esc) is not discarded but becomes the next key
(`_UI_PEND`). Earlier, a fast Esc Esc lost a key this way.

Line mode: number + Enter selects, hotkey + Enter, `b` or an empty line = back, `q` = back or
logout in the main menu, EOF = `eof`. Invalid input shows the menu again.

### Dialogs

| Function | Behaviour |
|---|---|
| `ui_confirm question` | Returns 0 only for `j`/`J`/`y`/`Y`. Line mode reads a line from stdin, the TUI a single key. TUI: box with the highlighted default "N No"; questions about stopping, restarting, removing or deleting get a red "Warning" frame |
| `ui_msg level text` | Message (`info`, `ok`, `warn`, `err`, multi-line allowed), then waits ("[Enter] continue"). TUI: box in the colour of the level |
| `ui_note level text` | Message without waiting. Line mode: one line. TUI: status line until the next key |
| `ui_pause` | "[Enter] continue". Line mode: `/dev/tty` if available, else stdin |
| `ui_input prompt [default]` | Reads a line into `UI_INPUT`, returns 1 on EOF or Esc (TUI). With a default: the TUI prefills it for editing, line mode shows `prompt [default]:`, an empty answer means the default |
| `ui_loading [text]` | TUI: "text..." in the status line until the next frame (the menu shows "loading..." automatically as soon as it returns a selection). Line mode: nothing |

### Foreground commands

All of them set `trap 'PD_INT=1' INT` while the command runs (not `trap '' INT`, otherwise
children inherit the ignored signal). Ctrl-C ends only the command, afterwards `PD_INT=1`.

| Function | Behaviour |
|---|---|
| `ui_run_fg cmd...` | Leaves the TUI (cursor on, alternate screen off, stty restored), runs `cmd`, restores the TUI. Returns the exit code. For shells, `logs -f`, ssh |
| `ui_run_page title cmd...` | Runs `cmd` with `</dev/null` and shows the output (stdout and stderr) in the viewer. TUI: an immediate fresh frame with title and loading hint, then a scrollable view inside the TUI without line wrapping (↑↓ jk, PgUp/PgDn, Home/End, ←→ sideways, `/` search, `n`/`N`, q/Esc/Enter closes). Colours (SGR) are kept, tabs are expanded. Line mode: title line, output, `ui_pause`. For output (tools, `incus info`) |
| `ui_run_task text cmd...` | Non-interactive (`</dev/null`), collects the output, shows "text...". On an exit code other than 0: `ui_msg err` with the exit code and the output. For restart, stop, start |
| `ui_check_rc rc what [output]` | Error message if rc is not 0, except 130 or after Ctrl-C |
| `ui_suspend` / `ui_resume` | Leave and restore the TUI manually (no effect in line mode) |

### Terminal

`ui_init` selects the presentation and sets traps: `EXIT` → `ui_cleanup`, `INT`/`TERM`/`HUP` →
clean up and exit 130/143/129, `WINCH` → redraw. A signal during `read -s` is handled only
after the `read` returns, otherwise `read` would restore "no echo" while unwinding.
`ui_cleanup` restores the `stty` state saved at start, turns the cursor on and leaves the
alternate screen.

### Rendering

Only these functions produce visible output. The logic only calls them:

| Function | Draws |
|---|---|
| `ui_theme` | Capabilities (`_UI_UTF8`, `_UI_NCOL` 256/8/0), colours `C_*` (empty when stdout is not a terminal, only attributes with `NO_COLOR`), symbols `UI_SYM_*` (ASCII without UTF-8) |
| `UI_SYM_SEL UI_SYM_DOT UI_SYM_FAV UI_SYM_GONE UI_SYM_HDR UI_SYM_DANGER UI_SYM_CRUMB UI_SYM_ELL UI_SYM_ARR` | Symbols. `tests/test_tui.sh` finds the cursor through `TUI_SEL` (❯; › with `NO_COLOR`, > in ASCII) |
| `_ui_tui_top width` | Header: host, mode badge, version; on the right the counter (`UI_STAT`, unhealthy in red), RAM, disk, load (colour levels), uptime. Values are dropped by priority |
| `_ui_tui_crumb width subtitle` | Breadcrumb (`_UI_CRUMB`, built from the call depth of `ui_menu`), subtitle dimmed on the right |
| `_ui_tui_info width` | Info lines |
| `_ui_tui_layout width` | Column layout (label, cells) for the current width |
| `_ui_tui_entry index marked width` → `_UI_OUT` | One list line, the selection as a full-width bar |
| `_ui_tui_status width`, `_ui_tui_footer width last` | Status line (message, filter), footer with key hints by priority |
| `_ui_box level title footer lines...` | Dialog box (confirmation, message) drawn over the frame |
| `_ui_pager_draw ...` | Viewer of `ui_run_page` |
| `_ui_render_header`, `_ui_render_dash`, `_ui_render_info`, `_ui_render_entry`, `_ui_render_keys_line`, `_ui_render_prompt` | Line mode (plain, no colours without a TTY, stable format, tests depend on it) |
| `_ui_mark status`, `_ui_hdr_col status`, `_ui_lvl_col level`, `_ui_cellr cell width colour` | Status → symbol/colour, cell → styled text |

Helpers: `_ui_w` (display width: characters instead of bytes, East Asian and emoji characters
count double), `_ui_fit` (cut to display width, `…` at the end), `_ui_pad`, `_ui_plain`
(strip markup). TUI lines are at most width − 1 characters wide. A frame is built completely in
`_UI_LINES` and written with one `printf` (cursor home, `\e[K` per line). The screen is cleared
completely only after a resize or when entering the alternate screen. Dialogs draw over the
frame and then restore the saved frame (`_UI_FRAME`).
Frame: header, breadcrumb, blank line, info (+ blank line), visible list, status line, footer.

**Tests that depend on the look** (update them when you change it): the test runner sets
`SSHLOBBY_LANG=de`, so the tests match the German texts. Line mode tests look for, among
others, `┌─ <title>`, `" 1) label"`, `★ group/target`, aligned info labels (`Image    value`),
the pause prompt, the `[j/N]` suffix of confirmations and `▌ HEADING`. TUI tests look for the
cursor `❯`, the title at the end of the breadcrumb line (`tui_title`), the dashboard title
(main menu only), the footer `q Logout` and info lines with two spaces after the label.
`tests/test_ui.sh` checks the layout (60x20, 80x24, 120x40), filter, resize, viewer, dialogs,
`NO_COLOR` and ASCII.

## Backends

### Docker (`lib/backend_docker.sh`)

Context: `""` = host Docker, `"<ct>"` = `incus exec <ct> -- docker`.

| Function | Behaviour |
|---|---|
| `dk ctx args...` | Non-interactive docker, stdin `</dev/null` |
| `dk_tty ctx args...` | Interactive docker (stdin kept), only inside `ui_run_fg` |
| `dk_argv ctx` → `DK_ARGV` | Command array, for example for `exec "${DK_ARGV[@]}" ...` |
| `dk_ps ctx format [opts]` | `docker ps`. Returns 0 ok, 1 CT not running, 2 Docker not reachable, 3 Docker not installed |
| `dk_msg ctx rc` | Text for 1/2/3 |
| `dk_load ctx` → `DK_ROWS`, `DK_RC` | All containers: `name\|state\|status\|image\|ports\|project\|service\|dir` |
| `dk_row name`, `dk_dir name` | Exact row or Compose directory from `DK_ROWS` |
| `dk_projects` | `project\|total\|running\|unhealthy\|dir`, `-` = no project |
| `dk_rows_of project` | Rows of one project, sorted by service and name |
| `dk_state_status state status`, `dk_health status` | Marker (`run`, ...) or health |
| `dk_restart_policy ctx c` | Restart policy via `docker inspect` |
| `dk_preflight ctx c` → `PF_MSG` | Before every shell: context reachable, container exists and is running |
| `dk_shell ctx group c` | Preflight, recents entry, `docker exec -it c sh -c 'bash or sh'` |
| `dk_logs ctx c` | `logs -f --tail 100`, Ctrl-C returns |
| `dk_action ctx restart\|stop\|start c` | Through `ui_run_task` (the screen asks for confirmation) |
| `dk_compose_shell ctx dir group [c]` | Shell in the Compose directory (host: `$SHELL -l`, CT: path as argument) |
| `dk_compose_logs ctx p`, `dk_compose_ps ctx p`, `dk_compose_action ctx p restart\|stop\|start` | `docker compose -p p ...` without a Compose file. There is deliberately no `up`, `pull` or `down` |
| `dk_state_show ctx c`, `dk_state_page ctx c` | State and health check of a container from `docker inspect` (JSON, parsed with jq): state, times, exit code, restarts, policy, OOM kill, error, health check command and log. The page is the last entry of the container screen |

### Incus (`lib/backend_incus.sh`)

| Function | Behaviour |
|---|---|
| `ct_load` → `CTS_RAW` | Lines `name,status,ip` (JSON + jq, first IPv4 on eth0) |
| `ct_status ct`, `ct_ip ct`, `ct_names`, `ct_exists ct`, `ct_running_count` | Data from `CTS_RAW` |
| `ct_shell ct` | Preflight (running?), recents entry, `incus exec ct -- bash -l` |
| `ct_action ct start\|stop\|restart` | Through `ui_run_task` |
| `ct_info ct`, `ct_log ct`, `ct_resources ct` | Output through `ui_run_page` |
| `ct_images`, `ct_valid_name n`, `ct_name_taken n`, `ct_launch image name` | For "New project" |

Always run non-interactive `incus exec` with `</dev/null` (otherwise incus forwards stdin into
the CT and reads it empty).

## Tool registry (`lib/tools.sh`)

```bash
# lib/tools_example.sh
_t_units_avail() { have systemctl; }
_t_units_list() { systemctl list-units --type=service --state=failed --no-pager; }
_t_units() { ui_run_page "${TX[tools.units.title]}" _t_units_list; }
tool_register units "${TX[tools.units.title]}" "systemctl --failed" "all" _t_units_avail _t_units
```

`tools.units.title` stands for a key you add to `lang/*.txt` together with the tool.

| Function | Behaviour |
|---|---|
| `tool_register id title description modes avail-fn run-fn [prio]` | `modes`: list of `docker incus layered` or `all`. `avail-fn` takes no arguments, 0 = show, `-` = always. `prio`: sort order (default 50; v1.1 tools 10 to 18, server tools 91 to 100, settings 999). Registering the same `id` again overwrites it |
| `tool_list` | IDs of the tools available in the current mode, sorted by prio |
| `tool_available id`, `tool_run id` | Check or run. If a tool sets `PD_RELOAD=1`, the tools menu returns to the main menu afterwards |

A tool may open its own submenus with `ui_menu` (for example "Other server (SSH)" with several
`SSH_HOSTS`). Put your own tools in separate files `lib/tools_<name>.sh` so `tools.sh` stays
unchanged. `install.sh` copies all `lib/*.sh` and `lang/*.txt`. Texts of a new tool go into
`lang/*.txt` like all other texts.

## State and config (`lib/core.sh`)

| File | Format |
|---|---|
| `~/.config/sshlobby/config` | `KEY=value`, never sourced. Keys: `MODE`, `HOST_LABEL` (display name, asked by the setup; the fast-path hint uses it only if it can be an SSH alias), `CVE_CT`, `CVE_DIR`, `SSH_HOSTS`, `AUTOSTART`, `Q_ACTION`, `UI`, `COLOR`, `SYMBOLS`, `RECENT_MAX`, `HERMES_SCAN_CTS`, `LANGUAGE`. Meaning and defaults are documented at `cfg_load`. Unknown keys and broken lines are ignored, quotes and CRLF are tolerated |
| `~/.config/sshlobby/descriptions` | `name\|text` for CTs, projects, containers (`PD_DESC[name]`) |
| `~/.config/sshlobby/recents` | `epoch\|group\|target\|action`, at most 200, actions `shell logs compose` (container), `ctshell` (CT), `project` (Compose project, target `-`), `tool` (group `@tool`, target = tool id) |
| `~/.config/sshlobby/favorites` | `group\|target` |
| `~/.config/sshlobby/service-favorites` | Favourite systemd units of the "systemd services" tool |
| `~/.config/sshlobby/backups/<YYYYMMDD-hhmmss>/` | Backups made by the settings menu before a reset or restore, the newest 10 are kept |

`cfg_set KEY value` changes exactly one line (atomically), comments and unknown keys stay.
`state_add_recent`, `state_recents`, `state_favorites`, `is_fav` and `fav_toggle` compare
fields exactly and replace files atomically. Target `-` = the CT itself (action `ctshell`) or
the whole Compose project (action `project`), group `-` = a container without a Compose project.
Entries of the same second keep their file order (newest last in the file, first in the list).
The main menu hides entries that do not fit the mode and all tool entries; the tools menu shows
the tool entries. Opening a recent container that no longer exists removes the entry
(`state_del_recent`).
Favourites pointing to targets that no longer exist are marked and can be removed.

Exit codes: `PD_EXIT_OK=0`, `PD_EXIT_ERR=1`, `PD_EXIT_USAGE=2`, `PD_EXIT_SHELL=10` (host shell),
`PD_EXIT_LOGOUT=20` (only this one logs out in the `~/.bashrc` hook).

## Tests

```bash
# Terminal, in the repository root
bash tests/run.sh            # all tests
bash tests/run.sh i18n docker  # only tests whose name contains "i18n" or "docker"
```

The runner loads `tests/lib.sh` and all `tests/test_*.sh` and runs every function `t_*` with a
fresh `HOME` and fresh fixtures. Arguments filter test functions by substring. For a new area,
add a file `tests/test_<name>.sh`, `run.sh` stays unchanged. `skip "reason"` reports SKIP.

In tests, `PATH` consists only of `tests/stubs` and individually linked system tools. Stubs
exist for `docker incus ssh systemctl journalctl mutagen hostname` and `$SHELL` (`hostshell`);
real binaries with these names are not reachable. New tools that call other programs need a
stub or an entry in the `SYSBIN` list of `run.sh`. The runner sets `SSHLOBBY_LANG=de`.

Fixtures: `tests/fixtures/cts` (CTs), `docker/<ct>` (Docker inside a CT), `host-docker` (host
Docker, modelled on a real host: Compose projects, standalone containers with random names,
exited containers, containers without a health check), `fs/` (file system for `ls`/`test -d`).
