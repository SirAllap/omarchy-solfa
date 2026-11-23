#!/usr/bin/env python3
"""Now Playing's "Remove from <playlist>": the real Panel.qml, a fake service.

Renders tests/qml/RemovePlayingScene.qml (the real Panel.qml, its real
views, with a fake service) in a private Quickshell, offscreen. The shell's KeyboardPanel
(a layer-shell window that takes the keyboard) is swapped for
tests/qml/stub/KeyboardPanel.qml, a plain card: nothing is mapped on the
desktop and no keyboard is grabbed. Skips when Quickshell, the Omarchy
shell or a desktop session is missing.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))


def render(workdir, scale="1", out=None):
    cfg = os.path.join(workdir, "scene")
    ui = os.path.join(cfg, "Ui")
    os.makedirs(ui)
    # The shell's Ui module, file by file, with KeyboardPanel.qml swapped.
    shell_ui = os.path.join(SHELL_DIR, "Ui")
    for name in os.listdir(shell_ui):
        src = os.path.join(HERE, "qml", "stub", name) if name == "KeyboardPanel.qml" else os.path.join(shell_ui, name)
        os.symlink(src, os.path.join(ui, name))
    for name, target in (("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("SolfaPanel.qml", os.path.join(ROOT, "Panel.qml")),
                         ("shell.qml", os.path.join(HERE, "qml", "RemovePlayingScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR=scale, XDG_RUNTIME_DIR=workdir)
    env.pop("SOLFA_SCENE_OUT", None)
    if out:
        env["SOLFA_SCENE_OUT"] = out
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=60)
    m = re.search(r"STATE (\{.*\})", run.stdout + run.stderr)
    return {"STATE": json.loads(m.group(1)) if m else None, "log": (run.stdout + run.stderr)[-3000:]}


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class RemovePlaying(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-remove-playing-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"), os.environ.get("SOLFA_REMOVE_PLAYING_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_the_button_sits_after_save_and_share_and_names_the_playlist(self):
        o = self.state["open"]
        self.assertTrue(o["shown"])
        self.assertEqual(o["browsed"], ["VLPLmine"], "one look at the playlist the song plays from")
        lay = o["layout"]
        self.assertTrue(lay["sameRow"], lay)
        # Save, Share where the panel has it, then this one, last in the row.
        share = ["shareButton"] if "shareButton" in lay["fromSave"] else []
        self.assertEqual(lay["fromSave"], ["saveButton"] + share + ["removeButton"])
        self.assertEqual(lay["tip"], "Remove from Road trip")

    def test_the_row_of_eight_takes_no_more_room_than_the_row_of_seven(self):
        lay = self.state["open"]["layout"]
        self.assertLessEqual(lay["rowWidth"], lay["sevenWidth"], lay)
        boxes = lay["boxes"]
        for (x, w, h), (nx, _, _) in zip(boxes, boxes[1:]):
            self.assertLessEqual(x + w, nx, ("hit boxes overlap", boxes))
        for x, w, h in boxes:
            self.assertGreaterEqual(min(w, h), 38, ("a transport button under 38 px", boxes))
        self.assertTrue(lay["sliderShown"], "the volume line under it is untouched")
        self.assertGreaterEqual(lay["sliderWidth"], 48)

    def test_the_queue_meaning_is_the_same_button_in_the_same_place(self):
        q, lay = self.state["queue"], self.state["open"]["layout"]
        self.assertEqual(q["meaning"], "queue")
        self.assertTrue(q["visible"] and q["enabled"])
        self.assertEqual(q["tip"], "Remove from queue")
        self.assertEqual(q["icon"], ["close"], "the queue row's glyph")
        self.assertEqual((q["rowWidth"], q["x"]), (lay["rowWidth"], lay["x"]), "no jump when the meaning changes")

    def test_the_queue_meaning_skips_and_removes_once_and_says_so(self):
        q = self.state["queue"]
        self.assertEqual(q["sent"], [{"index": 2}], "one request while the first is out")
        self.assertEqual(q["flash"], "Removed from the queue")
        self.assertEqual(q["playlistRemoves"], 0)
        self.assertEqual(q["signedOut"], "queue", "no account needed")
        self.assertEqual(q["firstMeaning"], "queue")
        self.assertEqual(q["first"], [{"index": 0}], "the first entry of the queue too")

    def test_the_last_song_keeps_the_button_but_it_does_nothing(self):
        last = self.state["queue"]["last"]
        self.assertTrue(last["visible"])
        self.assertFalse(last["enabled"])
        self.assertEqual(last["meaning"], "")
        self.assertEqual(last["tip"], "Nothing after it in the queue")
        self.assertEqual(last["asked"], 0)

    def test_a_queue_error_is_reported_and_an_advert_hides_the_button(self):
        q = self.state["queue"]
        self.assertEqual(q["failed"], {"reported": ["moved"], "flash": ""})
        self.assertFalse(q["ad"])

    def test_the_playlist_is_looked_up_once(self):
        self.assertEqual(self.state["pushes"]["browsed"], ["VLPLmine"])
        self.assertEqual(self.state["otherCopy"]["browsed"].count("VLPLmine"), 2, "the page's own browse, and no other")

    def test_a_press_takes_out_that_row_once_and_the_song_keeps_playing(self):
        t = self.state["twice"]
        self.assertEqual(t["sent"], [{"playlistId": "PLmine", "videoId": "AAAAAAAAAAA", "setVideoId": "SET3"}])
        self.assertTrue(t["shownWhileWaiting"])
        r = self.state["removed"]
        self.assertFalse(r["shown"], "that row is gone: no button for it")
        self.assertEqual(r["flash"], "Removed from Road trip")
        self.assertEqual(r["player"], "AAAAAAAAAAA")
        self.assertEqual(r["others"], [], "nothing but lookups and the removal: no skip, no pause, no queue edit")

    def test_the_open_page_loses_the_row_without_a_reload(self):
        self.assertEqual(self.state["pageBefore"], ["One/SET1", "Two/SET2", "One/SET3", "Four/SET4"])
        r = self.state["removed"]
        self.assertEqual(r["page"], ["One/SET1", "Two/SET2", "Four/SET4"], "the other copy of the song stays")
        self.assertEqual(r["pageInfo"], 3)
        self.assertEqual(r["browsed"], ["VLPLmine", "VLPLmine"])

    def test_a_page_kept_in_memory_loses_the_row_too(self):
        o = self.state["otherCopy"]
        self.assertTrue(o["shown"], "the other copy is a row of its own")
        self.assertEqual(o["sent"], {"playlistId": "PLmine", "videoId": "AAAAAAAAAAA", "setVideoId": "SET1"})
        self.assertEqual(o["flash"], "Removed from Road trip")
        b = self.state["back"]
        self.assertEqual(b["page"], ["Two/SET2", "Four/SET4"])
        self.assertEqual(b["browsed"], o["browsed"], "back to it without a reload")

    def test_an_error_keeps_everything_and_is_reported(self):
        f = self.state["failed"]
        self.assertEqual(f["asked"], 1)
        self.assertTrue(f["shown"])
        self.assertEqual(f["reported"], ["failed"])
        self.assertEqual(f["flash"], "")
        self.assertEqual(f["page"], ["Two/SET2", "Four/SET4"])

    def test_no_button_unless_it_is_a_row_of_a_playlist_of_the_users(self):
        h = self.state["hidden"]
        for name in ("noRow", "liked", "radio", "album", "theirs", "otherList", "otherSong", "ad", "signedOut"):
            self.assertFalse(h[name]["shown"], name)
        for name in ("noRow", "liked", "radio", "album", "otherSong", "ad", "signedOut"):
            self.assertEqual(h[name]["browsed"], [], name + ": nothing to look up")
        self.assertEqual(h["theirs"]["browsed"], ["VLPLtheirs"])
        self.assertEqual(h["otherList"]["browsed"], ["VLPLodd"])

    def test_signing_in_again_looks_the_playlist_up_afresh(self):
        s = self.state["signedInAgain"]
        self.assertTrue(s["shown"])
        self.assertEqual(s["browsed"], ["VLPLmine"])

    def test_the_music_video_of_the_rows_song_playing_is_still_that_row(self):
        t = self.state["twin"]
        self.assertTrue(t["shown"])
        self.assertEqual(t["videoId"], "DDDDDDDDDDD", "the removal names the row's own video")
        self.assertFalse(t["stranger"], "an entry whose videos are not the row's")

    def test_removing_the_playing_row_from_the_page_takes_the_button_away(self):
        f = self.state["fromPage"]
        self.assertEqual(f["sent"], {"playlistId": "PLmine", "videoId": "DDDDDDDDDDD", "setVideoId": "SET4"})
        self.assertFalse(f["shown"])
        self.assertEqual(f["page"], ["Two/SET2"])


if __name__ == "__main__":
    unittest.main()
