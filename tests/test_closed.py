#!/usr/bin/env python3
"""Closed looks closed: the bar pill and the panel's power button.

Renders tests/qml/ClosedScene.qml (the real bar widget and the panel's
corner, running and closed, with fake services) in a private Quickshell,
offscreen, and reads what they show from its log. Skips when Quickshell,
the Omarchy shell or a desktop session is not available.
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


def render(workdir, scale="1"):
    cfg = os.path.join(workdir, "scene")
    os.mkdir(cfg)
    # The shell's KeyboardPanel is a layer-shell window an offscreen Quickshell cannot make: the
    # tests' plain-card stub stands in, so the bar pill's click can really open the panel.
    ui = os.path.join(cfg, "UiStub")
    os.makedirs(ui)
    for name in os.listdir(os.path.join(SHELL_DIR, "Ui")):
        src = os.path.join(HERE, "qml", "stub", name) if name == "KeyboardPanel.qml" else os.path.join(SHELL_DIR, "Ui", name)
        os.symlink(src, os.path.join(ui, name))
    for name, target in (("Ui", ui), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("SolfaBar.qml", os.path.join(ROOT, "BarWidget.qml")), ("Panel.qml", os.path.join(ROOT, "Panel.qml")),
                         ("shell.qml", os.path.join(HERE, "qml", "ClosedScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    out = os.environ.get("SOLFA_SCENE_OUT") or os.path.join(workdir, "scene.png")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR=scale, SOLFA_SCENE_OUT=out,
               XDG_RUNTIME_DIR=workdir)
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=60)
    found = {"log": (run.stdout + run.stderr)[-3000:]}
    for key in ("STATE", "CLICKS", "PILLCLICK"):
        m = re.search(key + r" (\{.*\})", run.stdout + run.stderr)
        found[key] = json.loads(m.group(1)) if m else None
    return found


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class Closed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-closed-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.found["STATE"], "the scene did not render:\n" + self.found["log"])

    def test_a_closed_bar_shows_only_solfa(self):
        s = self.found["STATE"]
        self.assertEqual(s["barRunning"]["label"], "Northern Lights")
        self.assertTrue(s["barRunning"]["controls"])
        self.assertEqual(s["barClosed"]["label"], "Solfa", "no stale song")
        self.assertTrue(s["barClosed"]["controls"], "the player's room is kept (buttons not drawn): the pill does not change shape")

    def test_off_with_a_last_song_shows_it_asleep_and_wakes_on_hover(self):
        a = self.found["STATE"]["barAsleep"]
        self.assertTrue(a["asleepSong"])
        self.assertEqual(a["rest"]["label"], "Northern Lights")
        self.assertFalse(a["rest"]["mark"], "the cover slot, not the Solfa mark")
        self.assertTrue(a["rest"]["italic"])
        self.assertEqual(a["rest"]["opacity"], 0.5)
        w = a["awake"]
        self.assertTrue(w["awake"], "the pointer on the pill wakes the song")
        self.assertFalse(w["italic"])
        self.assertEqual(w["opacity"], 1)
        self.assertEqual(w["tip"], "Solfa is off · click to play Northern Lights")

    def test_off_with_no_last_song_keeps_the_mark_and_no_power_glyph(self):
        s = self.found["STATE"]["barAsleep"]
        self.assertFalse(s["bareAsleep"])
        self.assertTrue(s["bareMark"])

    def test_a_click_on_the_off_pill_opens_the_panel_and_starts_solfa(self):
        p = self.found["PILLCLICK"]
        self.assertIsNotNone(p, "the pill click was not logged:\n" + self.found["log"])
        self.assertTrue(p["opened"], "the panel did not open: " + str(p))
        self.assertEqual(p["calls"], ["startEngine"], "a click on the off pill starts Solfa: " + str(p))

    def test_the_power_button_is_lit_when_closed_and_starts_solfa(self):
        s = self.found["STATE"]
        self.assertEqual(s["powerClosed"]["tooltip"], "Turn Solfa on")
        self.assertTrue(s["powerClosed"]["selected"])
        self.assertEqual(s["powerClosed"]["opacity"], 1)
        self.assertTrue(s["powerHover"]["hot"])
        self.assertEqual(self.found["CLICKS"]["closed"], ["toggleEngine"])


if __name__ == "__main__":
    unittest.main()
