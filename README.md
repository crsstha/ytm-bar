# ytm-bar

YouTube Music in the [Omarchy](https://omarchy.org/) bar — or polybar on i3 — no app, no browser tab.

<img src="docs/pill.png" alt="The now-playing pill in the bar" height="26">

<p>
  <img src="docs/popup.png" alt="The player popup" width="380">
  <img src="docs/tui.png" alt="ytm-tui in a terminal" width="430">
</p>

A now-playing pill and a player popup with search, your library, home, likes,
an editable queue, sleep timer, equalizer and volume boost — plus `ytm-tui`, the
same player in a terminal. Search and radio come from
[ytmusicapi](https://github.com/sigma67/ytmusicapi); audio plays through
[mpv](https://mpv.io/) + [yt-dlp](https://github.com/yt-dlp/yt-dlp) in a small
user service.

## Install

```bash
omarchy pkg add mpv yt-dlp python-ytmusicapi mpv-mpris
./install.sh            # --no-bindings to skip Super+Alt+M
```

The installer links the `ytm-bar` and `ytm-tui` commands, enables
`ytm-bar.service`, and adds the widget to the bar.

**Log in (optional)** — for likes, your library and a personal home page:
⚙ Settings → **Sign in with Google**. A browser window opens; sign in and it
closes by itself. No Chromium? Use **Paste headers** instead.

### On i3 + polybar (Arch)

```bash
sudo pacman -S mpv yt-dlp python-ytmusicapi mpv-mpris webkit2gtk-4.1
./install.sh --i3       # auto-detected on i3; --no-bindings to skip Super+Alt+M
```

Then add [`i3/polybar.ini`](i3/polybar.ini) to your polybar config, put `ytm`
in `modules-right` and restart polybar (`polybar-msg cmd restart`). The pill
and popup are the Omarchy ones: `i3/panel.html` is a port of `Panel.qml`, shown
by `ytm-panel` in a WebKit window (needs `webkit2gtk-4.1`) at the top right.
The bar's clicks, scroll and `Super+Alt+M` work as below. For the glass look,
turn up picom's blur (`blur-method = "dual_kawase"`).

## Use

| In the bar | |
|---|---|
| Click | open the popup |
| Right-click · `Super+Alt+M` | open the popup in search |
| Middle-click | play / pause |
| Scroll | previous / next |

- **Now** — controls, volume and the up-next queue (drag to reorder, hover to
  play next or remove). The radio for the current song keeps the queue going.
- **Search · Library · Home** — click a song to play it; albums, artists and
  playlists open as a page.
- **⚙ Settings** — sleep timer, equalizer, volume boost, **Open in TUI**, account.

Media keys work too. After a restart or reboot your queue comes back, paused
where you left it.

### In a terminal

Run `ytm-tui` (or Settings → **Open in TUI**). The key hints are always at the
bottom; the main ones:

| Keys | |
|---|---|
| `space` · `n` / `p` | play / pause · next / previous |
| `j` / `k` · `Enter` | select · play |
| `J` / `K` · `d` · `u` | move · remove · play next |
| `+` / `-` · `m` · `e` | volume · mute · next eq preset |
| `s` · `r` · `l` | shuffle · repeat · like |
| `1`–`4` · `,` · `/` · `q` | tabs · settings · search · quit |

## Command line

Everything also works from the shell; each command prints JSON:

```
ytm-bar toggle | next | previous | like | shuffle | repeat
ytm-bar search QUERY | play VIDEO_ID | volume PERCENT | sleep MINUTES|end|off
ytm-bar song | queue | signin | logout          # ytm-bar --help for all
```

## Troubleshooting

- **Pill stays dimmed** — the service is stopped: `systemctl --user status ytm-bar`.
- **"YouTube ended this login"** — sign in again from Settings.
- **Search fails or songs skip** — ytmusicapi or yt-dlp needs an update
  (`omarchy update`); YouTube changes break them for a few days at a time.
- **Edited the code?** `omarchy restart shell` for the QML,
  `systemctl --user restart ytm-bar` for `bin/ytm-bar`.

## Notes

- Audio is ~130 kbps Opus; age-restricted songs don't play, and plays aren't
  added to your YouTube Music history.
- Your login is stored only in `~/.config/ytm-bar` (readable by you alone).
- Fonts: [Geist](https://github.com/vercel/geist-font), under the SIL Open Font
  License (`fonts/OFL.txt`).
- Tests: `python3 tests/test_cli.py`. Uninstall: `./uninstall.sh`
  (`--purge` also removes the login).
