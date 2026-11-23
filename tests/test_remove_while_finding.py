#!/usr/bin/env python3
"""Remove a song while the find field is open: the real Panel.qml and DetailView.

Renders tests/qml/RemoveFindScene.qml (the real Panel.qml, its real views, with a
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
                         ("shell.qml", os.path.join(HERE, "qml", "RemoveFindScene.qml"))):
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
class RemoveWhileFinding(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-removefind-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"), os.environ.get("SOLFA_REMOVEFIND_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_the_footer_says_x_remove_and_F_find_on_a_playlist_of_your_own(self):
        self.assertEqual(self.state["beforeX"]["hints"][1:3], [["x", "remove"], ["F", "find", True]])
    def test_x_takes_out_the_filtered_song_the_cursor_is_on(self):
        a = self.state["afterX"]
        self.assertTrue(a["accepted"])
        self.assertEqual(a["removed"], ["SV0000000007"], "the request carries that row's own setVideoId")
        self.assertEqual(a["titles"], ["Sunrise"])
        self.assertEqual(a["status"], "1 of 249", "the count of the whole list goes down with it")
        self.assertEqual(a["loaded"], 249)
        self.assertEqual(a["flash"], "Removed from Mine mix")
        self.assertTrue(a["finding"] and a["query"] == "zoe", "the filter stays open")

    def test_the_cursor_stays_on_its_place_and_falls_back_at_the_end(self):
        self.assertEqual(self.state["beforeMid"]["cursor"], 1)
        d = self.state["afterDelete"]
        self.assertEqual(d["removed"][-1], "SV0000000115", "Delete is x")
        self.assertEqual((d["cursor"], d["current"]), (1, "Song 150"), "the next row takes the place")
        self.assertEqual(d["status"], "12 of 248")
        b = self.state["afterButton"]
        self.assertEqual(b["removed"][-1], "SV0000000215", "the row button, on the last row")
        self.assertEqual((b["count"], b["cursor"]), (11, 10), "the cursor falls back to the new last row")

    def test_closing_the_filter_shows_the_list_without_the_removed_songs(self):
        self.assertEqual(self.state["pageKept"], {"tracks": 247, "pageInfo": 247})
        self.assertEqual(self.state["closed"], {"finding": False, "rows": 247, "gone": True})

    def test_x_and_delete_in_the_find_field_remove_nothing(self):
        f = self.state["inField"]
        self.assertEqual(f["removed"], 0)
        self.assertEqual(f["accepted"], [False, False], "the panel leaves them to the field")
        self.assertEqual(f["text"], "un", "Delete deleted a letter of the text")
        self.assertTrue(f["focus"] and f["finding"])

    def test_a_removal_on_its_way_while_pages_arrive_keeps_both(self):
        i = self.state["inFlight"]
        self.assertEqual(i["removed"], 1, "a second x on the same row sends nothing")
        self.assertEqual((i["loaded"], i["pendingPages"]), (100, 1))
        self.assertEqual(self.state["pageFirst"], {"loaded": 200, "hasRow0": True, "pendingPages": 1})
        t = self.state["thenRemoval"]
        self.assertEqual((t["loaded"], t["hasRow0"], t["has150"]), (199, False, True), "the page that came first is not lost")
        a = self.state["allPages"]
        self.assertEqual((a["loaded"], a["hasRow0"], a["has249"], a["continuation"]), (249, False, True, ""), "the last page does not bring the song back")
        self.assertEqual((a["status"], a["pageInfo"]), ("249 songs", 249))

    def test_a_page_that_arrives_after_the_removal_does_not_undo_it(self):
        self.assertEqual(self.state["removedFirst"]["loaded"], 99)
        t = self.state["thenPages"]
        self.assertEqual((t["loaded"], t["hasRow0"], t["has249"], t["pageInfo"]), (249, False, True, 249))

if __name__ == "__main__":
    unittest.main()
