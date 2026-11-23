#!/usr/bin/env python3
"""Undo of a removal from a playlist: the real Panel.qml, a fake service.

Renders tests/qml/UndoRemoveScene.qml (the real Panel.qml, its real
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
                         ("shell.qml", os.path.join(HERE, "qml", "UndoRemoveScene.qml"))):
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
class UndoRemove(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-undo-remove-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"), os.environ.get("SOLFA_UNDO_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_the_notice_offers_undo_for_a_while(self):
        r = self.state["removed"]
        self.assertEqual(r["sets"], ["SET1", "SET3", "SET4", "SET5"])
        self.assertEqual(r["flash"], "Removed from Road trip")
        self.assertTrue(r["offered"])
        self.assertTrue(r["undo"], "Undo on the notice")
        self.assertGreaterEqual(r["ms"], 6000, "long enough to reach for it")

    def test_u_puts_the_song_back_where_it_was_as_a_new_row_once(self):
        u = self.state["u"]
        self.assertTrue(u["handled"])
        self.assertEqual(u["sent"], [{"playlistId": "PLmine", "videoId": "BBBBBBBBBBB", "before": ["SET3", "SET4", "SET5"]}])
        self.assertEqual(u["sets"], ["SET1", "NEW1", "SET3", "SET4", "SET5"])
        self.assertEqual(u["pageSets"], u["sets"], "the page kept by the panel too")
        self.assertEqual(u["flash"], "Restored to Road trip")
        self.assertFalse(u["undo"])
        self.assertFalse(u["again"], "a second u is not taken")
        self.assertEqual(u["asked"], 1)

    def test_the_last_row_comes_back_at_the_end_with_nothing_to_move_before(self):
        last = self.state["last"]
        self.assertEqual(last["sent"], {"playlistId": "PLmine", "videoId": "EEEEEEEEEEE", "before": []})
        self.assertEqual(last["sets"], ["SET1", "NEW1", "SET3", "SET4", "NEW2"])

    def test_only_the_last_removal_can_be_undone(self):
        o = self.state["onlyLast"]
        self.assertEqual(o["sent"]["videoId"], "CCCCCCCCCCC")
        self.assertEqual(o["sent"]["before"], ["SET4", "NEW2"])
        self.assertEqual(o["sets"], ["NEW1", "NEW3", "SET4", "NEW2"])

    def test_no_undo_once_the_notice_is_gone_or_replaced(self):
        g = self.state["gone"]
        self.assertFalse(g["handled"])
        self.assertFalse(g["replaced"])
        self.assertEqual(g["asked"], 0)
        self.assertEqual(g["sets"], ["NEW3", "NEW2"])

    def test_back_but_not_in_place_says_so(self):
        u = self.state["unplaced"]
        self.assertEqual(u["flash"], "Restored to the end of Road trip")
        self.assertEqual(u["sets"], ["NEW2", "NEW4"])

    def test_a_failed_undo_is_reported_and_changes_nothing(self):
        f = self.state["failed"]
        self.assertEqual(f["reported"], ["failed"])
        self.assertTrue(f["same"])
        self.assertFalse(f["undo"], "spent")

    def test_now_playings_removal_has_its_undo_and_the_button_comes_back(self):
        n = self.state["np"]
        self.assertEqual(n["page"], ["NEW2"])
        self.assertEqual(n["renamed"], "NEW2", "the entry names SET5, whose row came back as NEW2")
        self.assertEqual(n["removed"]["sent"], {"playlistId": "PLmine", "videoId": "EEEEEEEEEEE", "setVideoId": "NEW2"})
        self.assertTrue(n["removed"]["undo"])
        self.assertEqual(n["removed"]["flash"], "Removed from Road trip")
        self.assertEqual(n["removed"]["sets"], [])
        self.assertEqual(n["back"]["sent"], {"playlistId": "PLmine", "videoId": "EEEEEEEEEEE", "before": []})
        self.assertEqual(n["back"]["sets"], ["NEW5"])
        self.assertEqual(n["back"]["button"], "NEW5", "the button follows the row to its newest setVideoId")

    def test_a_long_playlist_reads_the_rows_after_the_last_one_loaded(self):
        lng = self.state["long"]
        self.assertEqual(lng["browse"], [{"id": "VLPLlong", "continuation": "fixture-long-2"}])
        self.assertEqual(lng["sent"], {"playlistId": "PLlong", "videoId": "LLLLLLLLLL3", "before": ["LSET4", "LSET5"]})

    def test_with_the_find_field_open_the_found_row_comes_back_once(self):
        f = self.state["finding"]
        self.assertEqual(f["before"], ["LSET2"])
        self.assertEqual(f["removed"], [])
        self.assertEqual(f["back"], ["NEW7"])
        self.assertEqual(f["all"], ["LSET1", "NEW7", "NEW6", "LSET4", "LSET5"])


if __name__ == "__main__":
    unittest.main()
