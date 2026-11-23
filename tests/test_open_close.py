#!/usr/bin/env python3
"""Open then close the panel: it must end hidden and the queue must load.

Renders tests/qml/OpenCloseScene.qml (the real Panel.qml and its real views,
fake service, the shell's KeyboardPanel swapped for tests/qml/stub) in a
private Quickshell, offscreen. The open animation only touches the content's
own opacity and scale; this guards that closing still hides the panel, the
queue view still loads (a list, not the skeleton), and a second open works.
Skips when Quickshell, the Omarchy shell or a desktop session is missing.
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
    ui = os.path.join(cfg, "Ui")
    os.makedirs(ui)
    shell_ui = os.path.join(SHELL_DIR, "Ui")
    for name in os.listdir(shell_ui):
        src = os.path.join(HERE, "qml", "stub", name) if name == "KeyboardPanel.qml" else os.path.join(shell_ui, name)
        os.symlink(src, os.path.join(ui, name))
    for name, target in (("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("SolfaPanel.qml", os.path.join(ROOT, "Panel.qml")),
                         ("shell.qml", os.path.join(HERE, "qml", "OpenCloseScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir,
               SOLFA_SCENE_OUT0="1")  # the fake service answers "queue" with a list
    env.pop("SOLFA_SCENE_OUT", None)
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
class PanelOpenClose(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-openclose-")
        cls.found = render(cls.workdir)
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_open_shows_the_queue_not_the_skeleton(self):
        for key in ("open1", "open2"):
            s = self.state[key]
            self.assertTrue(s["opened"], key)
            self.assertTrue(s["card"], key)
            self.assertTrue(s["queue"], key)
            self.assertTrue(s["active"], key)
            self.assertFalse(s["loading"], key + ": queue still on the skeleton")
            self.assertFalse(s["skeleton"], key + ": skeleton visible")
            self.assertEqual(s["opacity"], 1, key)

    def test_close_ends_hidden(self):
        for key in ("closed1", "closed2"):
            s = self.state[key]
            self.assertFalse(s["opened"], key)
            self.assertFalse(s["card"], key + ": card still visible")


if __name__ == "__main__":
    unittest.main()
