#!/usr/bin/env python3
"""The queue's next page: the real QueueView, a fake service.

Renders tests/qml/QueueScene.qml (the real views/QueueView.qml on a long
list, with a fake service) in a private Quickshell, offscreen: nothing is
mapped on the desktop. Skips when Quickshell, the Omarchy shell or a desktop
session is missing.
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


def render(workdir):
    cfg = os.path.join(workdir, "scene")
    os.makedirs(cfg)
    for name, target in (("Ui", os.path.join(SHELL_DIR, "Ui")), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("shell.qml", os.path.join(HERE, "qml", "QueueScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir)
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
class QueueMore(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-queue-")
        cls.found = render(cls.workdir)
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_nothing_is_asked_away_from_the_end(self):
        self.assertEqual(self.state["start"], {"rows": 50, "more": True, "asked": 0})
        self.assertEqual(self.state["before"], {"cursor": 46, "asked": 0, "atYEnd": False})

    def test_the_cursor_near_the_end_asks_for_one_page_with_no_arguments(self):
        r = self.state["reached"]
        self.assertEqual(r["cursor"], 47)
        self.assertEqual(r["asked"], 1)
        self.assertEqual(r["args"], {})

    def test_more_moves_before_the_page_lands_ask_nothing_more(self):
        self.assertEqual(self.state["held"], {"cursor": 49, "asked": 1})

    def test_the_page_lands_and_the_cursor_stays_on_its_song(self):
        self.assertEqual(self.state["landed"], {"rows": 99, "cursorId": "S0000000049", "asked": 1})

    def test_scrolling_to_the_bottom_asks_for_the_next_page(self):
        self.assertEqual(self.state["scrolled"], {"atYEnd": True, "asked": 2})

    def test_a_failed_request_can_be_asked_again(self):
        self.assertEqual(self.state["failed"]["retried"], 1)

    def test_no_request_once_the_queue_says_there_is_no_more(self):
        self.assertEqual(self.state["last"], {"rows": 109, "more": False, "asked": 0})


if __name__ == "__main__":
    unittest.main()
