# ytm-bar

YouTube Music in the [Omarchy](https://omarchy.org/) bar — no app, no browser tab.

<img src="docs/pill.png" alt="The now-playing pill in the bar" height="26">

<p>
  <img src="docs/popup.png" alt="The player: cover, waveform seek bar, controls and the up-next covers" width="380">
  <img src="docs/search.png" alt="Search before you type: moods and genres to browse" width="380">
</p>

A now-playing pill and a player popup that takes its colour from the cover:
a waveform seek bar, the up-next queue as covers, search with moods and genres
to browse, your saved music and playlists, likes, a sleep timer, equalizer and
volume boost — plus `ytm-tui`, the same player in a terminal. Search and radio come from
[ytmusicapi](https://github.com/sigma67/ytmusicapi); audio plays through
[mpv](https://mpv.io/) + [yt-dlp](https://github.com/yt-dlp/yt-dlp) in a small
user service.

## Install

From the Omarchy plugin marketplace, or straight from GitHub:

```bash
omarchy pkg add mpv yt-dlp python-ytmusicapi python-pillow
omarchy plugin add https://github.com/crsstha/ytm-bar --enable
```

The widget appears in the bar, and the player service starts by itself when the
bar loads.

**Dependencies** — required: `mpv`, `yt-dlp`, `python-ytmusicapi`. Optional:
`mpv-mpris` (media keys), `python-pillow` (cover colours, cover art in the
terminal), Chromium, Chrome or Brave (Sign in with Google). Without
`python-pillow` the card stays amber instead of taking the cover's colour.

**Then run `install.sh` for the rest.** `omarchy plugin add` (and `omarchy
plugin update`) only fetch the plugin; they never run its scripts. Without
`install.sh` you have the bar widget and the player, but **no blur, no
`Super+Alt+M`** and none of the rest below. Run it yourself, and again after an
update:

```bash
~/.config/omarchy/plugins/crsstha.ytmusic/install.sh
omarchy restart shell
```

It adds:

- **Blur behind the popup.** If Hyprland's blur is off (Omarchy's default), it
  turns it on, with a window rule (`no_blur` for every window) that keeps app
  windows unblurred, so only the popup changes. Blur rules of your own in
  `looknfeel.lua` load later and still win. `--no-blur` leaves Hyprland's blur
  as it is.
- **`Super+Alt+M`** to open and close the player.
- Floating windows for Sign in with Google and `ytm-tui`.
- The `ytm-bar` and `ytm-tui` commands in `~/.local/bin`.
- A `ytm-bar.service` user unit, so the player, and your queue, are back at
  login.

The Hyprland lines go in one block in `~/.config/hypr/bindings.lua`, between
`ytm-bar` marker lines (`--no-bindings` leaves it out); `uninstall.sh` removes
it. If those marker lines have been edited, both scripts leave the file alone
and say so. Besides that block, `install.sh` only:

- adds the widget to the bar, in `~/.config/omarchy/shell.json`, with `omarchy
  plugin enable` (if it isn't there yet), and runs `hyprctl reload`;
- removes the old ytm-bar block (between the same markers) that the Pear
  Desktop version put in `~/.config/hypr/autostart.lua`;
- restarts the player service when it's older than the files (after an
  update); the music comes back paused, at the same spot.

**Log in (optional)** — for likes, your library and a personal home page:
⚙ Settings → **Sign in with Google**. A small window opens on Google's sign-in
page; once you're through to YouTube Music it closes by itself, within a few
seconds. No Chromium? Use **Paste headers** instead.

**What's kept, and where.** The login (YouTube Music's cookies) is in
`~/.config/ytm-bar/browser.json`. The sign-in window keeps its own Chromium
profile in `~/.config/ytm-bar/chromium`, still signed in to your Google account,
so it can sign you back in when YouTube ends the login. Recent searches and the
queue are in `~/.local/state/ytm-bar`. Only you can read any of it (folders
`0700`, files `0600`). Keep `~/.config/ytm-bar` out of backups or dotfiles you
share. **Log out** (Settings, or `ytm-bar logout`) deletes the login and the
Chromium profile. None of it leaves the machine, except in requests to YouTube
Music.

## Use

| In the bar | |
|---|---|
| Click | open the popup |
| Right-click · `Super+Alt+M` | open the popup in search |
| Middle-click | play / pause |
| Scroll | previous / next |

- **Playing** — controls, volume and the up-next queue (drag to reorder, hover to
  play next or remove). The radio for the current song keeps the queue going.
- **Search** — recent searches and mood and genre tiles before you type, then
  results by type. **Saved · For you** — your library and YouTube's picks.
  Click a song to play it; albums, artists, playlists and moods open as a page.
- **Playlists** — the playlist button next to the hearts adds the current song
  to one of your playlists, or to a new one; **Saved → New playlist** makes an
  empty one. New playlists are private. On someone else's playlist (say, from
  For you), **Save** adds it to Saved.
- **⚙ Settings** — sleep timer, equalizer, volume boost, **Open in TUI**, account.

Media keys work too. When another app plays sound — a video, a call — the
music pauses, and carries on once it stops (Settings → **Pause for other
sounds**, or `ytm-bar autopause`). After a restart or reboot your queue comes
back, paused where you left it.

### In a terminal

<img src="docs/tui.png" alt="ytm-tui: now playing, the queue and the key hints" width="640">

Open it from Settings → **Open in TUI**, or run `ytm-tui` (after `install.sh`;
otherwise it's `~/.config/omarchy/plugins/crsstha.ytmusic/bin/ytm-tui`). With
`install.sh`'s window rule it floats in the middle of the screen. The key hints
are always at the bottom; the main ones:

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

Everything also works from the shell (`ytm-bar` after `install.sh`, otherwise
`~/.config/omarchy/plugins/crsstha.ytmusic/bin/ytm-bar`); each command prints JSON:

```
ytm-bar toggle | next | previous | like | shuffle | repeat
ytm-bar search QUERY | play VIDEO_ID | volume PERCENT | sleep MINUTES|end|off
ytm-bar playlists | newplaylist TITLE [VIDEO_ID] | addto PLAYLIST_ID VIDEO_ID
ytm-bar save | unsave PLAYLIST_ID
ytm-bar song | queue | stats | signin | logout  # ytm-bar --help for all
```

## Troubleshooting

- **Pill stays dimmed** — the service is stopped. Click the pill to start it, or
  `systemctl --user status ytm-bar` if you ran `install.sh`.
- **"YouTube ended this login"** — sign in again from Settings.
- **Search fails or songs skip** — ytmusicapi or yt-dlp needs an update
  (`omarchy update`); YouTube changes break them for a few days at a time.
- **No blur behind the popup** — run `install.sh` (it adds the blur rule, and
  turns Hyprland's blur on for the popup if it's off), then `omarchy restart
  shell`. Updating from an earlier version? Run it again: the rule changed.
- **Card stays amber** — `python-pillow` is missing: `omarchy pkg add
  python-pillow`, then `systemctl --user restart ytm-bar`.
- **Edited the code?** `omarchy restart shell` for the QML,
  `systemctl --user restart ytm-bar` for `bin/ytm-bar`.

## Notes

- Audio is ~130 kbps Opus; age-restricted songs don't play, and plays aren't
  added to your YouTube Music history.
- Your login is stored only in `~/.config/ytm-bar` (readable by you alone).
- Fonts: [Geist](https://github.com/vercel/geist-font), under the SIL Open Font
  License (`fonts/OFL.txt`).
- Tests: `python3 tests/test_cli.py`.
- Built by crsstha with [Claude](https://claude.ai) (Anthropic) as co-author.

## Remove

```bash
~/.config/omarchy/plugins/crsstha.ytmusic/uninstall.sh   # only if you ran install.sh
omarchy plugin remove crsstha.ytmusic
```

`uninstall.sh` stops the service and removes what `install.sh` added. Your
login stays in `~/.config/ytm-bar` — `uninstall.sh --purge` removes it too
(or delete that folder).
