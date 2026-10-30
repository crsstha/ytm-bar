"""Checks ytm-bar's result parsing, the service's request guard and error JSON:
python3 tests/test_cli.py   (needs no network, mpv or ytmusicapi)"""
import json
import os
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

CLI = str(Path(__file__).resolve().parent.parent / "bin" / "ytm-bar")
spec = spec_from_loader("ytm_bar", SourceFileLoader("ytm_bar", CLI))
bar = module_from_spec(spec)
spec.loader.exec_module(bar)

assert bar.seconds_of("3:05") == 185
assert bar.seconds_of("1:02:03") == 3723
assert bar.seconds_of("") == 0 and bar.seconds_of("live") == 0
assert bar.clock(185) == "3:05"
assert bar.video_id_of("https://music.youtube.com/watch?v=12rsVkwSsXU") == "12rsVkwSsXU"
assert bar.video_id_of("https://example.com/a.mp3") is None

# Album art asks for a bigger square; video thumbnails take the widest.
assert bar.image_of({"thumbnails": [{"url": "https://lh3/x=w60-h60-l90-rj", "width": 60},
                                    {"url": "https://lh3/x=w120-h120-l90-rj", "width": 120}]}) \
    == "https://lh3/x=w544-h544-l90-rj"
assert bar.image_of({"thumbnail": [{"url": "a.jpg", "width": 400}, {"url": "b.jpg", "width": 800}]}) == "b.jpg"
assert bar.image_of({}) == ""

mitski = [{"name": "Mitski", "id": "UC1"}]
# A search result (duration, album) and a radio track (length, likeStatus).
song = {"videoId": "12rsVkwSsXU", "title": "Washing Machine Heart", "artists": mitski,
        "album": {"name": "Be the Cowboy"}, "duration": "2:09", "duration_seconds": 129,
        "thumbnails": [{"url": "https://lh3/a=w60-h60", "width": 60}], "resultType": "song"}
radio = {"videoId": "nonJBN_w9Z0", "title": "I Bet on Losing Dogs", "length": "2:51",
         "artists": mitski, "likeStatus": "LIKE", "thumbnail": [{"url": "t.jpg", "width": 400}]}
assert bar.track_of(song) == {"videoId": "12rsVkwSsXU", "title": "Washing Machine Heart",
                              "artist": "Mitski", "album": "Be the Cowboy", "length": "2:09",
                              "duration": 129, "image": "https://lh3/a=w544-h544", "like": None}
track = bar.track_of(radio)
assert track["duration"] == 171 and track["like"] == "LIKE" and track["album"] == ""
assert bar.track_of({**radio, "likeStatus": None})["like"] is None
# Album tracks name their album as a plain string.
assert bar.track_of({**radio, "album": "Puberty 2"})["album"] == "Puberty 2"

# Equalizer: flat is no filter; others lower the level by the biggest boost.
assert bar.eq_filter("flat") == ""
assert bar.eq_filter("bass") == ("lavfi=[volume=-5dB,equalizer=f=60:t=o:w=1.5:g=5,"
                                 "equalizer=f=230:t=o:w=1.5:g=4,equalizer=f=910:t=o:w=1.5:g=1]")
assert bar.eq_filter("night").startswith("lavfi=[volume=-2dB,")

# Login headers: Chromium's name/value lines and the raw "name: value" form.
chromium = ":authority\nmusic.youtube.com\n:method\nPOST\naccept\n*/*\ncookie\nSID=a; b=c\nx-goog-authuser\n0\n"
raw = ":authority: music.youtube.com\naccept: */*\ncookie: SID=a; b=c\nx-goog-authuser: 0"
expected = "accept: */*\ncookie: SID=a; b=c\nx-goog-authuser: 0"
assert bar.normalize_headers(chromium) == expected
assert bar.normalize_headers(raw) == expected
assert bar.normalize_headers("") == ""

# Every kind of item becomes a row; things the player can't use are dropped.
video = {"videoId": "3vjkh-acmTE", "title": "Washing Machine Heart", "artists": mitski,
         "views": "187M", "resultType": "video"}
album = {"resultType": "album", "title": "Be the Cowboy", "type": "Album", "year": "2018",
         "artists": mitski, "browseId": "MPREb_1", "playlistId": "OLAK5uy_1"}
artist = {"category": "Top result", "resultType": "artist", "subscribers": "68M", "artists": [{"name": "Mitski", "id": "UC1"}]}
playlist = {"resultType": "playlist", "title": "Sad songs", "author": "Someone", "browseId": "VLPL1"}
home_playlist = {"title": "Mix", "playlistId": "RDCLAK1"}
assert bar.entry_of(song) == {"type": "song", "id": "12rsVkwSsXU", "title": "Washing Machine Heart",
                              "subtitle": "Mitski", "length": "2:09", "image": "https://lh3/a=w120-h120"}
assert bar.entry_of(video)["type"] == "video" and bar.entry_of(video)["subtitle"] == "Mitski · 187M views"
assert bar.entry_of({**song, "artists": None})["subtitle"] == "Song"  # artist missing in the results
assert bar.entry_of(radio)["type"] == "song"  # album/playlist tracks have no resultType
assert bar.entry_of(album) == {"type": "album", "id": "MPREb_1", "title": "Be the Cowboy",
                               "subtitle": "Album · Mitski · 2018", "length": "", "image": ""}
assert bar.entry_of(artist)["type"] == "artist" and bar.entry_of(artist)["id"] == "UC1"
assert bar.entry_of(artist)["title"] == "Mitski" and bar.entry_of(artist)["subtitle"] == "Artist · 68M subscribers"
assert bar.entry_of(playlist)["id"] == "PL1" and bar.entry_of(playlist)["subtitle"] == "Playlist · Someone"
assert bar.entry_of(home_playlist)["type"] == "playlist" and bar.entry_of(home_playlist)["id"] == "RDCLAK1"
assert bar.entry_of({"resultType": "episode", "videoId": "x" * 11}) is None
assert bar.entry_of({**song, "isAvailable": False}) is None
assert bar.entry_of({"title": "Nothing to open"}) is None

# Numbered rows (album/playlist songs) count only the rows kept.
rows = bar.entries_of([song, {"title": "No id"}, song, radio], numbered=True)
assert [(r["id"], r["index"]) for r in rows] == [("12rsVkwSsXU", 0), ("nonJBN_w9Z0", 1)]

# "All": the top result, then one section per type, without repeating the top result.
sections = bar.search_sections([artist, song, album, video, {**artist, "category": None}, playlist])
assert [s["title"] for s in sections] == ["Top result", "Songs", "Videos", "Albums", "Playlists"]
many = [{**song, "videoId": f"s{i:010d}"} for i in range(20)]
assert len(bar.search_sections(many)[0]["items"]) == bar.FILTERS["songs"][2]
assert len(bar.search_sections(many, "songs")[0]["items"]) == bar.FILTERS["songs"][3]
assert bar.search_sections([], "albums") == [] and bar.search_sections(None) == []


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


with tempfile.TemporaryDirectory() as home:
    port = free_port()
    env = {**os.environ, "HOME": home, "YTM_BAR_PORT": str(port),
           "XDG_STATE_HOME": home + "/state", "XDG_RUNTIME_DIR": home}

    def cli(*args):
        out = subprocess.run([CLI, *args], capture_output=True, text=True, env=env)
        return out.returncode, json.loads(out.stdout)

    # Nothing listens yet.
    code, result = cli("next")
    assert code == 1 and result["code"] == "offline"
    assert cli("seek", "soon")[1]["error"] == "Usage: ytm-bar seek NUMBER"
    assert cli("search", " ")[1]["error"] == bar.USAGE["search"]
    assert cli("search", "x", "--filter", "podcasts")[1]["error"] == bar.USAGE["search"]
    assert cli("open", "song", "x")[1]["error"] == bar.USAGE["open"]
    assert cli("playall", "album")[1]["error"] == bar.USAGE["playall"]
    assert cli("play")[1]["error"] == "Usage: ytm-bar play VIDEO_ID"
    assert cli("dance")[1]["code"] == "failed"

    # The service, with nothing playing (mpv only starts on first play).
    daemon = subprocess.Popen([CLI, "daemon"], env=env)
    try:
        for _ in range(50):
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.1)

        def get(headers):
            req = urllib.request.Request(f"http://127.0.0.1:{port}/song", headers=headers)
            try:
                with urllib.request.urlopen(req) as resp:
                    return resp.status
            except urllib.error.HTTPError as e:
                return e.code

        assert get({bar.HEADER: "1"}) == 204
        assert get({}) == 403  # a web page can't send the header
        assert get({bar.HEADER: "1", "Host": "evil.example:80"}) == 403  # DNS rebinding

        assert cli("song") == (0, {"ok": True, "song": None})
        code, state = cli("state")
        assert code == 0 and state["queue"] == [] and state["loggedIn"] is False
        assert cli("toggle") == (0, {"ok": True})  # nothing loaded: a no-op
        assert cli("account") == (0, {"ok": True, "loggedIn": False, "name": "", "photo": ""})
        assert cli("library")[1]["code"] == "unauthorized"
        assert cli("repeat") == (0, {"ok": True}) and cli("state")[1]["repeat"] == "ALL"
        assert cli("volume", "250") == (0, {"ok": True}) and cli("state")[1]["volume"] == 100
        assert json.loads(Path(home, "state/ytm-bar/state.json").read_text()) == {"volume": 100, "eq": "flat", "boost": False,
                                                                                 "normalize": False, "notify": True, "device": "auto"}

        # Boost raises the limit to 150; turning it off brings the volume back to 100.
        assert cli("boost") == (0, {"ok": True})
        assert cli("volume", "140") == (0, {"ok": True}) and cli("state")[1]["volume"] == 140
        assert cli("state")[1]["maxVolume"] == 150
        cli("boost")
        assert cli("state")[1]["volume"] == 100 and cli("state")[1]["boost"] is False

        assert cli("eq", "Bass") == (0, {"ok": True}) and cli("state")[1]["eq"] == "bass"
        assert cli("eq", "disco")[1]["error"] == bar.USAGE["eq"]
        assert json.loads(Path(home, "state/ytm-bar/state.json").read_text())["eq"] == "bass"

        assert cli("sleep", "30") == (0, {"ok": True})
        assert cli("state")[1]["sleep"] == {"mode": "min", "left": 1800, "minutes": 30}
        cli("sleep", "end")
        assert cli("state")[1]["sleep"] == {"mode": "end"}
        cli("sleep", "off")
        assert cli("state")[1]["sleep"] is None
        assert cli("sleep", "soon")[1]["error"] == bar.USAGE["sleep"]

        assert cli("mute") == (0, {"ok": True}) and cli("state")[1]["muted"] is True
        assert cli("remove", "3")[1]["error"] == "That song isn't in the queue any more"
        assert cli("move", "3")[1]["error"] == bar.USAGE["move"]
        assert not Path(home, "ytm-bar-mpv.sock").exists()
    finally:
        daemon.terminate()
        daemon.wait(5)

# The polybar pill: dimmed when stopped or paused, % escaped, long titles cut.
assert bar.polybar_label(None) == "%{F#707880}󰝚%{F-}"
assert bar.polybar_label({"title": "100% Pure", "isPaused": False}, 0).endswith("%{F-} 100%% Pure")
assert bar.polybar_label({"title": "100% Pure", "isPaused": False}, 0) != \
    bar.polybar_label({"title": "100% Pure", "isPaused": False}, 1.8)  # the wave moves
assert bar.polybar_label({"title": "x" * 40, "isPaused": True}) == "%{F#707880}▁▁▁▁ " + "x" * 29 + "…%{F-}"

# ytm-tui: input parsing and fitting text into cells.
spec = spec_from_loader("ytm_tui", SourceFileLoader("ytm_tui", str(Path(CLI).parent / "ytm-tui")))
tui = module_from_spec(spec)
spec.loader.exec_module(tui)
assert tui.read_keys("a\r\x1b[A\x1b\x7f\t\x1b[Z") == ["a", "enter", "up", "esc", "backspace", "tab", "shift-tab"]
assert tui.read_keys("\x1b[<0;20;2M\x1b[<65;3;4M") == [("mouse", 0, 19, 1, True), ("mouse", 65, 2, 3, True)]
assert tui.text_width("夜に駆ける") == 10 and tui.clip("夜に駆ける", 6) == "夜に…"
assert tui.clip("Short", 10) == "Short" and tui.clip("A long title", 6) == "A lon…"
canvas = tui.Canvas(6, 1)
canvas.put(0, 0, "ab夜cdef", fg=tui.WHITE)
assert canvas.chars[0] == ["a", "b", "夜", "", "c", "d"]
assert tui.clock(185) == "3:05" and tui.white(0) == tui.BASE

print("ok")
