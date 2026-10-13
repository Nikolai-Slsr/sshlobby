# sshlobby interface (2.0 and later)

What the TUI looks like and why. The API and function names are in `docs/ARCHITECTURE.md`
(section "UI engine"). To preview every screen as HTML, run the generator. It uses the test
stubs and needs tmux and python3:

```bash
# Terminal, in the repository root
bash tools/dev/screenshots.sh /tmp/sshlobby-screens.html
```

The texts in the examples below are the English ones. The language follows `SSHLOBBY_LANG`,
`LANGUAGE` in the config or the system locale (see [TRANSLATING.md](TRANSLATING.md)).

## Frame

Every screen has the same layout across the full terminal width:

```
 DOCKER-HOST  docker  v2.2.0     ● 12/14 containers  ✗ 1 unhealthy  RAM 42%  Disk 63%  Load 0.4  up 84 d 17 h
 Start › nextcloud › nextcloud-db                                                                  nextcloud

   Image     postgres:16.4
   Health    unhealthy

  ▌ CONTAINERS ────────────────────────────────────────────────────────────────────────────────────────────
 ❯  1  ● nextcloud-app   nextcloud:29-apache        5 d   healthy     8080→80
    2  ● nextcloud-redis redis:7-alpine             5 d   healthy

 · Status line (messages, filter, loading hint)
  ↑↓ select  ⏎ open  esc back  / filter  f add favourite ☆  q back                                 1–20/45
```

- **Header** (bar): display name (`HOST_LABEL`), mode as a badge, version. On the right the
  running/total counter (`UI_STAT`), unhealthy in bold red, RAM, disk, load per CPU with colour
  levels (green; yellow from 80 % RAM / 85 % disk / load 0.7 per CPU; red from 92 % / 95 % / 1.0),
  compact uptime. When space runs out, uptime goes first, then load, then RAM and disk. The
  counters stay.
- **Breadcrumb**: path of the open menus, the current title in bold. In the main menu it shows
  "sshlobby". The subtitle is dimmed and right-aligned. If it is too long, it is cut
  at the front with `…`.
- **Info lines** (optional): label dimmed, value with cell styles. In the main menu this is where
  the hint for a newer release appears (`New version  [sshlobby 3.1.0]  installed: 3.0.1 · key u
  or: sshlobby update`, the version as a yellow pill), together with the hotkey `u` in the footer.
- **List**: dimmed number, status dot, label, columns. The selection is a bar across the full
  width (256 colours: dark blue background; 8/16 colours: blue; no colours: reverse) plus the
  marker `❯`. Sections are coloured headings with a thin line.
- **Status line**: messages from `ui_note` (symbol and colour of the level), filter input,
  "loading..." while a screen fetches data.
- **Footer** (bar): key hints for the current screen. If space is short, the least important
  ones go first (`↑↓ select`, `/ filter`). `q` and the screen's hotkeys stay. On the right, the
  position in long lists.

## Tables and status

`ui_item ... columns` passes table cells (separated by tabs). The engine measures each column
across all entries, makes the label as wide as needed (at most about 45 % when space is short)
and drops columns from the right when they no longer fit. Cutting uses `…` and works on display
width, not bytes. Cells have styles (`ui_cell`): health as a pill (`healthy` green, `unhealthy`
red, `starting` yellow), counters green/yellow/grey, secondary values dimmed.

Docker values (in `screens.sh`) are shortened: uptime (`Up 4 days` → `4 d`, `Up About an hour`
→ `1 h`, `Exited (0) 4 weeks ago` → `exit 0, 4 w ago`) and ports (`127.0.0.1:8080->80/tcp` →
`8080→80`, duplicates removed, from four ports on `+n`). Line mode keeps showing the raw text.
The exact unit abbreviations come from the language file.

Dangerous actions (stop, restart, stopping or restarting a CT) carry a red `▲` and red text.
Their confirmation is a box with a red "Warning" frame and the default "N No" highlighted.

## Keys

| Key | Effect |
|---|---|
| ↑↓ `j` `k`, PgUp/PgDn, Home/End | move (headings are skipped) |
| Enter, →, `l` | open |
| Esc, ←, `h`, Backspace, `b` | back (Esc first clears an active filter) |
| `q` | back; in the main menu logout (or host shell with `Q_ACTION=shell`) |
| digits | jump to the entry |
| `/` | filter: typing filters live, Enter keeps the filter, Esc clears it |

Viewer (`ui_run_page`): ↑↓ `j` `k`, PgUp/PgDn/Space, Home/End (`g`/`G`), ←→ sideways, `/`
search, `n`/`N` next/previous match, `q`/Esc/Enter closes. Long lines are not wrapped. A `›` at
the right edge shows that the line continues.

## No flicker

A frame is rendered completely into a buffer and written with a single `printf`: cursor home,
every line ends with `\e[K`, the rest is cleared with `\e[J`. The screen is cleared completely
only after a resize (`SIGWINCH`) and when entering the alternate screen. Dialogs draw over the
frame and restore it afterwards. Between two screens the old frame stays visible and the status
line shows "loading...". `ui_run_page` shows a fresh frame with the title at once, never the
output of the previous page.

Each line is at most width − 1 characters wide (no automatic wrap at the right edge). Bars
still reach the edge: the line ends with the background colour and `\e[K` fills the rest with it.

## Fallbacks

| Situation | Behaviour |
|---|---|
| `NO_COLOR` set (or `COLOR=never` in the config) | no colours; bold, dim and reverse stay. Selection in reverse with `›`, pills as `[healthy]` |
| `tput colors` < 256 | 8/16-colour palette, selection on a blue background |
| locale without UTF-8 (or `SYMBOLS=ascii`) | ASCII: `>` selection, `o` status, `#` heading, `-`/`+`/`\|` for lines and boxes, `~` instead of `…` |
| no terminal (pipe, script) or `SSHLOBBY_UI=line` | line mode: numbered lines, no colours, no frame around the list, stable format |
| narrow (60 columns and up) | columns and header values dropped by priority, hints shortened |

## Tests

`tests/test_ui.sh` (tmux) covers: layout at 60x20, 80x24 and 120x40 (no line wider than the
terminal, correct line count, footer at the bottom, selection bar), header values, unhealthy in
red, scrolling and position, filter (also inside tools), resize, viewer (sideways scrolling,
search, tabs, no wrapping, no stale output while loading), confirmation and message, input,
typed-ahead keys and Esc Esc, `NO_COLOR`, ASCII, a clean terminal after exit and the plain
line mode.

```bash
# Terminal, in the repository root (needs tmux)
bash tests/run.sh ui
```
