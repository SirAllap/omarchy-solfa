#!/usr/bin/env python3
"""A song with several artists: "Go to artist" opens a picker, and the artist text in a row is plain.

Renders tests/qml/ArtistPickScene.qml (the real Panel.qml, its real views, a fake
service) in a private Quickshell, offscreen, like test_undo_remove.py. Checks that
g / the row's button open the artist at once with one name and a picker listing every
name with several (Down + Enter, a click, Esc, a click outside), that the artist text in a row is not a link, and the now-playing line opens the same picker.
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


def render(workdir, scale="1", out=None, picker_out=None):
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
                         ("shell.qml", os.path.join(HERE, "qml", "ArtistPickScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR=scale, XDG_RUNTIME_DIR=workdir)
    env.pop("SOLFA_SCENE_OUT", None)
    env.pop("SOLFA_PICKER_OUT", None)
    if out:
        env["SOLFA_SCENE_OUT"] = out
    if picker_out:
        env["SOLFA_PICKER_OUT"] = picker_out
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
class ArtistPick(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-artist-pick-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"),
                           os.environ.get("SOLFA_MULTI_OUT"), os.environ.get("SOLFA_PICKER_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_g_on_three_artists_lists_all_three(self):
        g = self.state["g"]
        self.assertTrue(g["shown"])
        self.assertEqual(g["names"], ["berlioz", "Ted Jasper", "Third Artist"])
        self.assertEqual(g["pages"], 1, "nothing opened before a choice")

    def test_enter_opens_the_chosen_one(self):
        g = self.state["g"]
        self.assertEqual(g["cursor"], 2)
        self.assertFalse(g["afterEnter"]["shown"])
        # The third has no id: the artist search, as before.
        self.assertEqual(g["afterEnter"]["search"], [{"q": "Third Artist", "filter": "artists"}])
        s = self.state["second"]
        self.assertFalse(s["shown"])
        self.assertEqual((s["pages"], s["id"], s["title"]), (2, "UCa2", "Ted Jasper"))

    def test_esc_closes_and_opens_nothing(self):
        e = self.state["esc"]
        self.assertTrue(e["opened"])
        self.assertTrue(e["closed"])
        self.assertTrue(e["pages"])

    def test_one_artist_opens_at_once(self):
        o = self.state["one"]
        self.assertFalse(o["shown"])
        self.assertEqual((o["pages"], o["id"]), (1, "UCsolo"))

    def test_the_button_opens_the_picker_next_to_it(self):
        b = self.state["button"]
        self.assertTrue(b["shown"])
        self.assertTrue(b["hasAnchor"])
        self.assertTrue(b["inside"], "the menu stays inside the card")
        self.assertTrue(b["nextToIt"], "its right edge is level with the button's")
        self.assertTrue(b["closedByClick"], "a click outside closes it")
        self.assertEqual(b["clickOpened"], {"shown": False, "pages": 1, "id": "UCa1"})

    def test_artist_text_in_a_row_is_not_a_link(self):
        self.assertFalse(self.state["plain"]["links"])
        self.assertTrue(self.state["plain"]["text"], "the names are there as plain text")
        self.assertFalse(self.state["plain"]["pickerShown"])
        self.assertEqual(self.state["plain"]["pages"], 0, "a click on the names opens no artist")

    def test_the_now_playing_line_opens_the_same_picker(self):
        n = self.state["now"]
        self.assertTrue(n["shown"])
        self.assertEqual(n["names"], ["berlioz", "Ted Jasper", "Third Artist"])
        self.assertEqual(n["cursor"], 1, "the picker starts on the name that was clicked")
        self.assertEqual(n["opened"], {"shown": False, "pages": 1, "id": "UCa1"})


if __name__ == "__main__":
    unittest.main()
