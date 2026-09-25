#!/usr/bin/env python3
"""Settings replaces the whole panel: the real Panel.qml, settings open.

Renders tests/qml/PanelScene.qml (the real Panel.qml, its real views, with a
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
                         ("shell.qml", os.path.join(HERE, "qml", "PanelScene.qml"))):
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
class PanelSettings(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-panel-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"), os.environ.get("SOLFA_PANEL_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_closed_settings_show_the_normal_panel(self):
        self.assertEqual(self.state["closed"], {"hero": True, "tabs": True, "settings": False})

    def test_settings_replace_the_whole_body(self):
        s = self.state["open"]
        self.assertFalse(s["hero"], "no now-playing hero or transport under Settings")
        self.assertFalse(s["tabs"], "no tabs under Settings")
        self.assertTrue(s["settings"])
        self.assertTrue(s["brand"], "the brand corner (gear, power) stays")

    def test_the_back_row_sits_on_the_top_row_with_the_brand_corner(self):
        s = self.state["open"]
        self.assertTrue(s["back"])
        self.assertLessEqual(s["backTop"], s["brandTop"] + 24, s)
        self.assertLessEqual(abs(s["backMid"] - s["brandMid"]), 8, s)

    def test_off_shows_only_the_way_back_on(self):
        s = self.state["off"]
        self.assertEqual({k: s[k] for k in ("offCard", "turnOn", "tabs", "hero")},
                         {"offCard": True, "turnOn": True, "tabs": False, "hero": True})

    def test_enter_turns_solfa_on_when_off(self):
        self.assertEqual(self.state["off"]["startsAfterEnter"], 1)

    def test_keys_do_nothing_while_signing_in(self):
        # A key that lands in the panel while Google's window is open (or
        # hidden, saving the sign-in) neither cancels it nor opens another.
        self.assertEqual(self.state["signing"]["calls"], [])

    def test_esc_brings_the_panel_back(self):
        self.assertEqual(self.state["afterEsc"], {"hero": True, "tabs": True, "settings": False})


if __name__ == "__main__":
    unittest.main()
