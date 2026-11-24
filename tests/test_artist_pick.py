#!/usr/bin/env python3
"""A song with several artists: "Go to artist" opens a picker, and the pointer on a row's text.

Renders tests/qml/ArtistPickScene.qml (the real Panel.qml, its real views, a fake
service) in a private Quickshell, offscreen, like test_undo_remove.py. Checks that
g / the row's button open the artist at once with one name and a picker listing every
name with several (Down + Enter, a click, Esc, a click outside), and that the pointer
on the title or artist text hides the row's buttons and shows every name, panning a
line that is still too long so its last name can be clicked.
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

    def test_the_pointer_on_the_text_hides_the_buttons_and_every_name_shows(self):
        self.assertEqual(self.state["rest"]["buttons"], 0)
        h = self.state["hover"]
        self.assertEqual(h["buttons"], 0, "faded out while the pointer is on the artists")
        self.assertTrue(h["fits"], "all three names are inside the line")

    def test_the_buttons_come_back_off_the_text(self):
        self.assertEqual(self.state["right"]["buttons"], 1)

    def test_a_line_too_long_for_the_row_pans_and_its_last_name_is_clickable(self):
        lg = self.state["long"]
        self.assertTrue(lg["overflow"])
        self.assertTrue(lg["scroll"])
        self.assertTrue(lg["lastVisible"])
        self.assertEqual((lg["pages"], lg["id"]), (1, "UCb3"))


if __name__ == "__main__":
    unittest.main()
