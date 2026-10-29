# TODO

The Pear Desktop backend was replaced by ytmusicapi + mpv + yt-dlp (branch
`ytmusicapi`; `master` still has the Pear version). Decisions taken:

- Account: optional. Anonymous by default; `ytm-bar login` (browser headers)
  enables like/dislike.
- Queue: mpv's playlist, in the service's memory; radio for the current song is
  appended when 3 or fewer songs are left. Not saved across restarts.
- Live state: Panel.qml polls the service's `GET /song` (port 26539).
- Pear support: removed on this branch.
- Migration: `install.sh` removes the old autostart block; the Pear window rule
  goes with the new bindings block. `~/.config/ytm-bar/token` is unused and can
  be deleted.

## Later

- [ ] Save the queue and position, and restore them (paused) after a restart.
- [ ] Premium/age-restricted playback: pass browser cookies to yt-dlp.
- [ ] Add played songs to the YouTube Music history when logged in
      (`add_history_item`), so recommendations stay personal.
- [ ] Keep the radio coming with repeat on (now it only extends with repeat off).
