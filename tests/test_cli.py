"""Checks ytm-bar's queue parsing and error JSON:  python3 tests/test_cli.py"""
import json
import os
import socket
import subprocess
import tempfile
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

CLI = str(Path(__file__).resolve().parent.parent / "bin" / "ytm-bar")
spec = spec_from_loader("ytm_bar", SourceFileLoader("ytm_bar", CLI))
bar = module_from_spec(spec)
spec.loader.exec_module(bar)


def video(title, selected=False):
    return {
        "title": {"runs": [{"text": title}]},
        "shortBylineText": {"runs": [{"text": "Artist " + title}]},
        "lengthText": {"simpleText": "3:00"},
        "selected": selected,
    }


assert bar.text_of({"runs": [{"text": "a"}, {"text": "b"}]}) == "ab"
assert bar.text_of({"simpleText": "x"}) == "x"
assert bar.text_of(None) == ""

# Plain and wrapped (song/video switcher) renderers; unknown items are skipped
# but keep their slot, so "index" still matches Pear's queue position.
raw = {"items": [
    {"playlistPanelVideoRenderer": video("A")},
    {"automixPreviewVideoRenderer": {}},
    {"playlistPanelVideoWrapperRenderer": {"primaryRenderer": {"playlistPanelVideoRenderer": video("B", selected=True)}}},
    {"playlistPanelVideoRenderer": video("C")},
]}
rows = bar.simplify_queue(raw)
assert [r["title"] for r in rows] == ["B", "C"]  # starts at the current song
assert rows[0] == {"index": 2, "title": "B", "artist": "Artist B", "length": "3:00", "current": True}
assert rows[1]["index"] == 3

# Current song plus QUEUE_LIMIT after it.
many = {"items": [{"playlistPanelVideoRenderer": video(str(i), selected=(i == 5))} for i in range(40)]}
rows = bar.simplify_queue(many)
assert len(rows) == bar.QUEUE_LIMIT + 1 and rows[0]["title"] == "5"

def result(title, subtitle, video_id=None):
    item = {"flexColumns": [
        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": title}]}}},
        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [{"text": t} for t in subtitle]}}},
    ]}
    if video_id:
        item["playlistItemData"] = {"videoId": video_id}
    return {"musicResponsiveListItemRenderer": item}


# Shaped like a real response: a top-result card, then a section; albums have
# no videoId, episodes are skipped, and repeats of a song are dropped.
search = {"contents": {"tabbedSearchResultsRenderer": {"tabs": [{"tabRenderer": {"content": {"sectionListRenderer": {"contents": [
    {"musicCardShelfRenderer": {"contents": [result("Crack Baby", ["Song", " • ", "4:53"], "a1")]}},
    {"itemSectionRenderer": {"contents": [
        result("Be the Cowboy", ["Album", " • ", "Mitski", " • ", "2018"]),
        result("I Want You", ["Song", " • ", "Mitski"], "b2"),
        result("Crack Baby", ["Song", " • ", "Mitski"], "a1"),
        result("Interview", ["Episode", " • ", "Aug 3, 2018"], "c3"),
        result("Washing Machine Heart", ["Video", " • ", "Someone", " • ", "14M views"], "d4"),
    ]}},
]}}}}]}}}
found = bar.simplify_search(search)
assert [r["videoId"] for r in found] == ["a1", "b2", "d4"]
assert found[0] == {"videoId": "a1", "title": "Crack Baby", "kind": "Song", "detail": "4:53"}
assert found[1]["detail"] == "Mitski"
assert found[2] == {"videoId": "d4", "title": "Washing Machine Heart", "kind": "Video", "detail": "Someone · 14M views"}
assert bar.simplify_search({}) == []

assert bar.simplify_queue(None) == []
assert bar.simplify_queue({"items": [{"playlistPanelVideoRenderer": video("only")}]})[0]["title"] == "only"

# Error JSON, against a port nothing listens on.
with socket.socket() as s:
    s.bind(("127.0.0.1", 0))
    free_port = s.getsockname()[1]

with tempfile.TemporaryDirectory() as home:
    def cli(*args):
        env = {**os.environ, "HOME": home, "YTM_BAR_PORT": str(free_port)}
        out = subprocess.run([CLI, *args], capture_output=True, text=True, env=env)
        return out.returncode, json.loads(out.stdout)

    code, result = cli("next")
    assert code == 1 and result["code"] == "unauthorized"  # no token yet

    token = Path(home) / ".config/ytm-bar/token"
    token.parent.mkdir(parents=True)
    token.write_text("abc\n")
    code, result = cli("next")
    assert code == 1 and result["code"] == "offline"

    assert cli("seek", "soon")[1]["error"] == "Usage: ytm-bar seek NUMBER"
    assert cli("search", " ")[1]["error"] == "Usage: ytm-bar search QUERY"
    assert cli("play")[1]["error"] == "Usage: ytm-bar play VIDEO_ID"
    assert cli("dance")[1]["code"] == "failed"

    # save_token writes 0600.
    bar.TOKEN = Path(home) / "saved/token"
    bar.CONFIG = bar.TOKEN.parent
    bar.save_token("xyz")
    assert bar.read_token() == "xyz"
    assert oct(bar.TOKEN.stat().st_mode & 0o777) == "0o600"

print("ok")
