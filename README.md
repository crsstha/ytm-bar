# ytm-bar

YouTube Music in the [Omarchy](https://omarchy.org/) bar: a now-playing pill and a
player popup with search, like/dislike, shuffle, repeat, volume, seeking and the
up-next queue. The app itself runs hidden — the bar is the whole UI.

It talks to [Pear Desktop](https://github.com/pear-devs/pear-desktop) (the YouTube
Music desktop app, formerly th-ch/youtube-music) through its **API Server** plugin
on `127.0.0.1:26538`.

## Install

1. Install YouTube Music (Pear Desktop):

   ```bash
   omarchy pkg aur add pear-desktop-bin
   ```

2. Open **YouTube Music** from the launcher and sign in.
3. In the app, open **Plugins → API Server**, enable it, and set authorization to
   **"Authorize at first request"**.
4. Install the widget:

   ```bash
   ./install.sh    # --no-bindings to skip those; --autostart to start the app at login
   ```

   This links `bin/ytm-bar` into `~/.local/bin`, links this repo as the
   `crsstha.ytmusic` plugin, puts the widget after the clock, and adds to
   `~/.config/hypr/`:
   - `bindings.lua`: the keybinding, and a window rule that keeps YouTube Music on
     the hidden `special:music` workspace
   - `autostart.lua` (only with `--autostart`): start YouTube Music at login
5. Turn on the app's tray (**Options → Tray → Enabled**, or `"tray": true` in
   `~/.config/YouTube Music/config.json` while it's closed) so closing its window
   doesn't quit it. `install.sh` tells you if it's off.
6. Click **Connect** on the widget (or run `ytm-bar auth`) and approve
   "ytm-bar" in YouTube Music. The token is saved to `~/.config/ytm-bar/token` (0600).

## Using it

| Action | What it does |
|---|---|
| Left-click | Open the player popup (or start YouTube Music, if it's closed) |
| Middle-click | Play / pause |
| Scroll up / down | Previous / next track |
| Right-click | Show / hide the YouTube Music window |
| `Super + Alt + M` | Open / close the player popup, cursor in the search box |

The pill shows the play state and the song title, dimmed while paused. While
YouTube Music is closed it's a dimmed 󰝚 — click it to start the app (hidden).

In the popup:
- **Search** — type to search songs and videos; click a result to play it now, or
  󰐕 to play it next. Esc clears the search, a second Esc closes the popup.
- Click or drag the progress bar to seek.
- Click a song under **Up next** to jump to it.

## How it works

- `omarchy/Panel.qml` polls `GET /api/v1/song` directly for the live display:
  every second while music plays or the popup is open, otherwise every 2 s,
  or every 5 s while the app is closed.
- Everything else goes through `bin/ytm-bar`, which holds the token and turns
  YouTube's raw queue object into simple rows. Every command prints one JSON object:

  ```
  ytm-bar auth | state | queue
  ytm-bar toggle | next | previous | like | dislike | shuffle | repeat
  ytm-bar seek SECONDS | volume PERCENT | jump INDEX
  ytm-bar search QUERY | play VIDEO_ID | add VIDEO_ID
  ytm-bar start | window
  ```

- Set `YTM_BAR_PORT` if you changed the API Server's port (the QML side uses 26538).

## Troubleshooting

- **Pill says "Connect"** — the token is missing or was revoked. Click it and approve.
- **Pill stays a dimmed 󰝚** — YouTube Music is closed, or its API Server plugin is off.
  `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:26538/api/v1/song`
  should print `401`.
- **Edited the QML and nothing changed** — the shell doesn't notice edits made
  through the plugin symlink. Run `omarchy restart shell`.
- **Can't find the window** — it's on `special:music`; right-click the widget.
- Logs: `journalctl --user -f | grep -i ytmusic`

## Tests

```bash
python3 tests/test_cli.py
```

## Uninstall

```bash
./uninstall.sh            # keeps the token; --purge removes ~/.config/ytm-bar
```
