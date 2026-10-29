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

# Songs first, then videos; no videoId or repeats are skipped.
video = {"videoId": "3vjkh-acmTE", "title": "Washing Machine Heart", "artists": mitski,
         "views": "187M", "resultType": "video"}
results = bar.merge_results([song, {"title": "No id"}, song], [video, song])
assert results == [
    {"videoId": "12rsVkwSsXU", "title": "Washing Machine Heart", "kind": "Song", "detail": "Mitski · 2:09"},
    {"videoId": "3vjkh-acmTE", "title": "Washing Machine Heart", "kind": "Video", "detail": "Mitski · 187M views"},
]
many = [{**song, "videoId": f"s{i:010d}"} for i in range(20)]
assert len(bar.merge_results(many, None)) == bar.SONG_RESULTS
assert bar.merge_results(None, None) == []


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
    assert cli("search", " ")[1]["error"] == "Usage: ytm-bar search QUERY"
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
        assert cli("repeat") == (0, {"ok": True}) and cli("state")[1]["repeat"] == "ALL"
        assert cli("volume", "250") == (0, {"ok": True}) and cli("state")[1]["volume"] == 100
        assert json.loads(Path(home, "state/ytm-bar/state.json").read_text()) == {"volume": 100}
        assert not Path(home, "ytm-bar-mpv.sock").exists()
    finally:
        daemon.terminate()
        daemon.wait(5)

print("ok")
