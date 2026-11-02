"""Checks ytm-bar's result parsing, the service's request guard and error JSON:
python3 tests/test_cli.py   (needs no network, mpv or ytmusicapi)"""
import http.client
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


# write_private: a new file and folder only this user can open, whatever the umask.
with tempfile.TemporaryDirectory() as tmp:
    old = os.umask(0o022)
    try:
        bar.write_private(Path(tmp, "new/session.json"), "{}")
    finally:
        os.umask(old)
    assert os.stat(Path(tmp, "new")).st_mode & 0o777 == 0o700
    assert os.stat(Path(tmp, "new/session.json")).st_mode & 0o777 == 0o600
    assert os.listdir(Path(tmp, "new")) == ["session.json"]


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

    # What an older version left with umask 022: readable by other accounts.
    state_dir = Path(home, "state/ytm-bar")
    state_dir.mkdir(parents=True, mode=0o755)
    os.chmod(state_dir, 0o755)
    for name in ("state.json", "session.json"):
        Path(state_dir, name).write_text("{}")
        os.chmod(state_dir / name, 0o644)

    def mode(path):
        return os.stat(path).st_mode & 0o777

    # An expired login, and the token 1.0.1 and older kept in ~/.config/ytm-bar.
    config_dir = Path(home, ".config/ytm-bar")
    config_dir.mkdir(parents=True)
    Path(config_dir, "browser.expired").write_text("{}")
    Path(config_dir, "token").write_text("old")

    # The service, with nothing playing (mpv only starts on first play).
    daemon = subprocess.Popen([CLI, "daemon"], env=env, umask=0o022)
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

        token_file = os.path.join(home, "ytm-bar", "token")
        assert mode(token_file) == 0o600
        # Recent searches and the queue are closed up when the service starts.
        assert mode(state_dir) == 0o700
        assert mode(state_dir / "state.json") == 0o600 and mode(state_dir / "session.json") == 0o600
        assert not Path(config_dir, "token").exists()
        token = open(token_file).read()
        assert get({bar.HEADER: token}) == 204
        assert get({}) == 403  # a web page can't send the header
        assert get({bar.HEADER: "1"}) == 403  # another account can't read the secret
        assert get({bar.HEADER: token, "Host": "evil.example:80"}) == 403  # DNS rebinding

        # Bad sizes and bodies get an answer; the service carries on.
        def post(body, length=None):
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.putrequest("POST", "/sleep")
            conn.putheader(bar.HEADER, token)
            conn.putheader("Content-Length", str(len(body) if length is None else length))
            conn.endheaders(body)
            resp = conn.getresponse()
            return resp.status, json.loads(resp.read())
        assert post(b"[1]") == (200, {"ok": False, "code": "failed", "error": 'Bad request: expected {"args": [...]}'})
        assert post(b'{"args": "30"}')[1]["error"] == 'Bad request: expected {"args": [...]}'
        assert post(b'{"args": ["1e400"]}')[1]["ok"] is False
        assert post(b"{}", length=-1)[0] == 413
        assert post(b"{}", length=bar.MAX_BODY + 1)[0] == 413
        assert get({bar.HEADER: token}) == 204

        # Only this user's programs: another account's listener is sent nothing,
        # and the service closes another account's connections unread.
        bar.PORT = port
        assert bar.port_owner() == "me"
        real_getuid = os.getuid
        os.getuid = lambda: real_getuid() + 1
        try:
            assert bar.port_owner() == "other"
            try:
                bar.request("GET", "/song")
                raise AssertionError("sent a request to another account's program")
            except bar.ApiError as e:
                assert e.code == "taken"
            with socket.create_connection(("127.0.0.1", port)) as conn:
                assert not bar.peer_is_me(conn.getsockname()[1])
        finally:
            os.getuid = real_getuid
        with socket.create_connection(("127.0.0.1", port)) as conn:
            assert bar.peer_is_me(conn.getsockname()[1])
        bar.PORT = int(os.environ.get("YTM_BAR_PORT", "26539"))

        # Same version as the files on disk: `start` leaves it running.
        assert cli("state")[1]["version"] == bar.VERSION == json.loads(Path(CLI).parent.parent.joinpath("manifest.json").read_text())["version"]
        assert cli("start")[0] == 0 and daemon.poll() is None

        assert cli("song") == (0, {"ok": True, "song": None})
        code, state = cli("state")
        assert code == 0 and state["queue"] == [] and state["loggedIn"] is False
        assert cli("toggle") == (0, {"ok": True})  # nothing loaded: a no-op
        assert cli("account") == (0, {"ok": True, "loggedIn": False, "name": "", "photo": ""})
        assert cli("library")[1]["code"] == "unauthorized"
        assert cli("repeat") == (0, {"ok": True}) and cli("state")[1]["repeat"] == "ALL"
        assert cli("volume", "250") == (0, {"ok": True}) and cli("state")[1]["volume"] == 100
        assert json.loads(Path(home, "state/ytm-bar/state.json").read_text()) == {"volume": 100, "eq": "flat", "boost": False, "autoPause": True, "recent": []}

        # Recent searches: newest first, no repeats (ignoring case), kept in state.json.
        assert cli("recentadd", "daft", "punk")[1]["recent"] == ["daft punk"]
        assert cli("recentadd", "Nepathya")[1]["recent"] == ["Nepathya", "daft punk"]
        assert cli("recentadd", "DAFT PUNK")[1]["recent"] == ["DAFT PUNK", "Nepathya"]
        assert json.loads(Path(home, "state/ytm-bar/state.json").read_text())["recent"] == ["DAFT PUNK", "Nepathya"]
        assert mode(state_dir / "state.json") == 0o600  # rewritten private, despite umask 022
        assert sorted(f.name for f in state_dir.iterdir()) == ["session.json", "state.json"]  # no temp files left
        assert cli("recentclear") == (0, {"ok": True, "recent": []})
        assert cli("recentadd")[1]["code"] == "failed"
        assert cli("open", "mood")[1]["code"] == "failed" and cli("playall", "mood", "x")[1]["code"] == "failed"

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
        assert not Path(home, "ytm-bar/mpv.sock").exists()

        assert cli("logout") == (0, {"ok": True, "loggedIn": False})
        assert not Path(config_dir, "browser.expired").exists()  # an expired login is forgotten too

        # An update: `start` stops the older service on the port (here one started
        # without systemd, so with SIGTERM), which saves and exits cleanly.
        bar.PORT = port
        assert bar.listener_pid() == daemon.pid
        bar.stop_old_service()
        assert daemon.wait(5) == 0 and bar.port_owner() is None
        bar.PORT = int(os.environ.get("YTM_BAR_PORT", "26539"))
    finally:
        daemon.terminate()
        daemon.wait(5)
    assert not os.path.exists(token_file)  # a stopped service leaves no secret behind

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
canvas = tui.Canvas(6, 1)
canvas.put(0, 0, "a\x1b]52;c;eA==\x07b")  # an escape sequence in a title stays text
assert "\x1b" not in "".join(canvas.chars[0]) and "\x07" not in "".join(canvas.chars[0])
assert tui.clock(185) == "3:05" and tui.white(0) == tui.BASE

print("ok")
