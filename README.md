# ytm-bar

YouTube Music in the [Omarchy](https://omarchy.org/) bar — no app, no browser tab.

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
⚙ Settings → **Sign in with Google**. A small window opens on Google's sign-in
page; once you're through to YouTube Music it closes by itself, within a few
seconds. No Chromium? Use **Paste headers** instead.

## Use

| In the bar | |
|---|---|
| Click | open the popup |
| Right-click · `Super+Alt+M` | open the popup in search |
| Middle-click | play / pause |
| Scroll | previous / next |

- **Playing** — controls, volume and the up-next queue (drag to reorder, hover to
  play next or remove). The radio for the current song keeps the queue going.
- **Search · Saved · For you** — click a song to play it; albums, artists and
  playlists open as a page.
- **Playlists** — the playlist button next to the hearts adds the current song
  to one of your playlists, or to a new one; **Saved → New playlist** makes an
  empty one. New playlists are private. On someone else's playlist (say, from
  For you), **Save** adds it to Saved.
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
| `[` / `]` or `1`–`4` · `,` | previous / next tab · settings |
| `/` · `Esc` · `g` / `G` · `q` | type a search · leave the box or go back · top / end of a list · quit |

## Command line

Everything also works from the shell; each command prints JSON:

```
ytm-bar toggle | next | previous | like | shuffle | repeat
ytm-bar search QUERY | play VIDEO_ID | volume PERCENT | sleep MINUTES|end|off
ytm-bar playlists | newplaylist TITLE [VIDEO_ID] | addto PLAYLIST_ID VIDEO_ID
ytm-bar save | unsave PLAYLIST_ID
ytm-bar song | queue | stats | signin | logout  # ytm-bar --help for all
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
