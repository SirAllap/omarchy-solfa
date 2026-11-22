#!/usr/bin/env python3
"""Remove from a playlist: the real Panel.qml, a fake service.

Renders tests/qml/RemoveScene.qml (the real Panel.qml, its real views, with a
fake service) in a private Quickshell, offscreen. The shell's KeyboardPanel
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
                         ("shell.qml", os.path.join(HERE, "qml", "RemoveScene.qml"))):
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
class RemoveFromPlaylist(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-remove-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"), os.environ.get("SOLFA_REMOVE_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_your_playlist_has_a_button_on_every_row_and_x_in_the_hints(self):
        m = self.state["mine"]
        self.assertEqual(m["rows"], 4)
        self.assertEqual(m["buttons"], 4)
        self.assertEqual(m["tip"], "Remove from this playlist (x)")
        self.assertEqual(m["hints"], ["\u21b5", "x", "e", "esc"])

    def test_x_removes_the_row_under_the_cursor_with_its_own_ids_and_says_so(self):
        x = self.state["x"]
        self.assertEqual(x["sent"], [{"playlistId": "PLmine", "videoId": "AAAAAAAAAAA", "setVideoId": "SET1"}])
        self.assertEqual(x["rows"], ["Two/SET2", "One/SET3", "Four/SET4"])
        self.assertEqual(x["cursor"], 0)
        self.assertEqual(x["flash"], "Removed from Road trip")
        self.assertEqual(x["pageRows"], 3, "the page the panel goes back to loses it too")
        self.assertEqual(x["browses"], 1, "no reload")
        self.assertEqual(x["subtitle"], "4 songs", "the count in the header is left alone")

    def test_delete_removes_one_copy_of_a_song_that_is_in_twice(self):
        d = self.state["del"]
        self.assertEqual(d["sent"][1], {"playlistId": "PLmine", "videoId": "AAAAAAAAAAA", "setVideoId": "SET3"})
        self.assertEqual(d["rows"], ["Two/SET2", "Four/SET4"])
        self.assertEqual(d["cursor"], 1, "the cursor stays on the same place")
        self.assertEqual(d["flash"], "Removed from Road trip")

    def test_the_row_button_removes_and_the_cursor_falls_back_to_the_last_row(self):
        b = self.state["button"]
        self.assertEqual(b["count"], 2)
        self.assertEqual(b["sent"][2], {"playlistId": "PLmine", "videoId": "DDDDDDDDDDD", "setVideoId": "SET4"})
        self.assertEqual(b["rows"], ["Two/SET2"])
        self.assertEqual(b["cursor"], 0)
        self.assertEqual(b["flash"], "Removed from Road trip")

    def test_an_error_keeps_the_row_and_is_reported(self):
        f = self.state["failed"]
        self.assertEqual(f["asked"], 1)
        self.assertEqual(f["rows"], ["Two/SET2"])
        self.assertEqual(f["reported"], ["failed"])
        self.assertEqual(f["flash"], "")

    def test_a_second_press_while_the_request_is_on_its_way_sends_nothing(self):
        t = self.state["twice"]
        self.assertEqual(t["asked"], 1)
        self.assertEqual(t["rowsWhileWaiting"], ["Two/SET2"])
        self.assertEqual(t["rowsAfter"], [])
        self.assertEqual(t["cursor"], -1)
        self.assertEqual(t["flash"], "Removed from Road trip")

    def test_someone_elses_playlist_an_album_and_liked_songs_have_nothing(self):
        for name in ("theirs", "album", "liked"):
            s = self.state[name]
            self.assertEqual(s["rows"], 4, name)
            self.assertEqual(s["buttons"], 0, name)
            self.assertNotIn("x", s["hints"], name)
            self.assertEqual(s["asked"], 0, name)
            self.assertEqual(s["left"], 4, name)
            self.assertEqual(s["flash"], "", name)

    def test_the_queue_still_removes_with_x_and_delete(self):
        q = self.state["queue"]
        self.assertEqual(q["sent"], [{"index": 1, "automix": False}, {"index": 1, "automix": False}])
        self.assertGreater(q["removeButtons"], 0)
        self.assertEqual(q["playlistRemoves"], 0, "the queue's x is not a playlist's")


if __name__ == "__main__":
    unittest.main()
