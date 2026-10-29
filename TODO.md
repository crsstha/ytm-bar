# TODO

## Replace Pear Desktop with ytmusicapi + mpv

Run YouTube Music without the Pear (Electron) app: free, ad-free, and lighter.
The bar widget and popup stay the same; only the backend changes.

**Why**
- Memory: Pear uses ~550 MB (PSS, measured 2026-10-28); mpv streaming audio ~50–80 MB.
- No ads without Premium: yt-dlp fetches the audio stream directly, so YouTube's
  player-side ads never play. (Pear plays ads unless its Ad Blocker plugin is on.)
- No app or hidden window to manage.

**Shape**
- `ytmusicapi` (`python-ytmusicapi`, extra repo) — search, radio/up-next
  (`get_watch_playlist`), likes, library. Data only; it can't play audio.
- `mpv` + `yt-dlp` (both installed) — plays the stream; controlled over mpv's
  JSON IPC socket. `mpv-mpris` (installed) keeps media keys and `omarchy.media` working.
- `ytm-bar` becomes a small background service (systemd user unit) that owns the
  queue and the mpv process. Panel.qml talks to it instead of Pear's API.

**Trade-offs to accept**
- Unofficial: both libraries mimic the website and break when YouTube changes
  things (fixes usually land within days); against YouTube's terms.
- Free accounts stream ~128–160 kbps; 256 kbps needs Premium cookies for yt-dlp.
- Age-restricted songs need login cookies; region-locked songs won't play.
- Pear extras are lost (lyrics, its plugins); queue/autoplay must be rebuilt.

**Open questions** (grilling paused at Q2)
- [ ] Connect the YouTube Music account (likes, playlists, library, personal
      radio; one-time browser-headers login) or stay anonymous?
      Leaning: connect.
- [ ] Where the queue lives (service memory vs. a file), and autoplay/radio when it runs out.
- [ ] How Panel.qml gets live state (poll the service, or watch a state file).
- [ ] Keep Pear support as a fallback backend, or remove it.
- [ ] Migration: what happens to the Pear token, window rule and tray setup.
