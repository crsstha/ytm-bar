# ytm-bar

YouTube Music in the [Omarchy](https://omarchy.org/) bar: a now-playing pill and a
player popup with search, like/dislike, shuffle, repeat, volume, seeking and the
up-next queue. There's no app or window — the bar is the whole UI.

It plays YouTube Music without the YouTube Music app:
[ytmusicapi](https://github.com/sigma67/ytmusicapi) searches and builds the radio
queue, and [mpv](https://mpv.io/) with [yt-dlp](https://github.com/yt-dlp/yt-dlp)
plays the audio. The player runs as a small user service, `ytm-bar.service`.

## Install

1. Install the packages:

   ```bash
   omarchy pkg add mpv yt-dlp python-ytmusicapi mpv-mpris
   ```

   `mpv-mpris` is optional; it gives the player media keys and shows it to
   other MPRIS widgets.

2. Install the widget:

   ```bash
   ./install.sh    # --no-bindings to skip the keybinding
   ```

   This links `bin/ytm-bar` into `~/.local/bin`, links and enables
   `systemd/ytm-bar.service` (it starts with your session), links this repo as the
   `crsstha.ytmusic` plugin, puts the widget after the clock, and adds a keybinding
   to `~/.config/hypr/bindings.lua`.

3. Optional — log in to like and dislike songs:

   ```bash
   ytm-bar login
   ```

   It asks you to paste request headers from a signed-in music.youtube.com tab
   (the steps are printed). They're saved to `~/.config/ytm-bar/browser.json` (0600).
   Search, playback and radio work without logging in.

## Using it

| Action | What it does |
|---|---|
| Left-click | Open the player popup (or start the player service, if it's stopped) |
| Middle-click | Play / pause |
| Scroll up / down | Previous / next track |
| Right-click | Open the popup with the cursor in the search box |
| `Super + Alt + M` | Open / close the player popup, cursor in the search box |

The pill shows the play state and the song title, dimmed while paused.

In the popup:
- **Search** — type to search songs and videos; click a result to play it now
  (its radio follows, like in YouTube Music), or 󰐕 to play it next.
  Esc clears the search, a second Esc closes the popup.
- Click or drag the progress bar to seek.
- Click a song under **Up next** to jump to it. When the queue runs low, the
  radio for the current song is added.
- Disliking a song skips it.

## How it works

- `ytm-bar daemon` (the service) keeps one mpv process, started on the first
  play, and drives it over its JSON IPC socket. mpv's playlist is the queue.
  It serves a small JSON API on `127.0.0.1:26539`; every request must carry an
  `X-Ytm-Bar` header, so web pages can't drive it.
- `omarchy/Panel.qml` polls `GET /song` for the live display: every second while
  music plays or the popup is open, otherwise every 2 s, or every 5 s while the
  service is stopped.
- Everything else goes through `bin/ytm-bar`. Every command prints one JSON object:

  ```
  ytm-bar start | login | logout
  ytm-bar song | state | queue
  ytm-bar toggle | next | previous | like | dislike | shuffle | repeat
  ytm-bar seek SECONDS | volume PERCENT | jump INDEX
  ytm-bar search QUERY | play VIDEO_ID | add VIDEO_ID
  ```

- The volume is remembered in `~/.local/state/ytm-bar/state.json`. The queue
  isn't: it starts empty after a restart.
- Set `YTM_BAR_PORT` for the service and CLI if 26539 is taken (the QML side
  uses 26539).

## Limits

- ytmusicapi and yt-dlp are unofficial: they break when YouTube changes things,
  usually for a few days until an update lands (`omarchy update`).
- Audio is ~130 kbps Opus; 256 kbps needs YouTube Premium cookies, which isn't
  supported yet. Age-restricted songs need cookies too and won't play.
- What you play isn't added to your YouTube Music history.

## Troubleshooting

- **Pill stays a dimmed 󰝚** — the service is stopped: `systemctl --user status ytm-bar`,
  logs with `journalctl --user -u ytm-bar`.
- **Search says "YouTube Music: …"** — ytmusicapi failed; check the network, or
  update it. `ytm-bar search test` shows the full error.
- **A song is skipped right away** — yt-dlp couldn't get it (region-locked,
  age-restricted, or yt-dlp needs an update).
- **Edited the QML and nothing changed** — the shell doesn't notice edits made
  through the plugin symlink. Run `omarchy restart shell`.
- Edited `bin/ytm-bar`? `systemctl --user restart ytm-bar`.

## Tests

```bash
python3 tests/test_cli.py
```

## Uninstall

```bash
./uninstall.sh            # keeps the login; --purge removes ~/.config/ytm-bar
```
