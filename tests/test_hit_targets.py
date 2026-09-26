#!/usr/bin/env python3
"""Every clickable control has a hit box, not just a glyph.

Renders tests/qml/ControlsScene.qml (the song and its controls, the tabs, a
queue, the footer's "?") with a fake service in a private Quickshell,
offscreen, and reads the box of every button from its log. Skips when
Quickshell, the Omarchy shell or a desktop session is not available.
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
MIN = 32          # every control
TRANSPORT = 44    # shuffle, previous, play/pause, next, repeat


def render(workdir, scale="1", extra_env=None):
    cfg = os.path.join(workdir, "scene")
    os.mkdir(cfg)
    for name, target in (("Ui", os.path.join(SHELL_DIR, "Ui")), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("shell.qml", os.path.join(HERE, "qml", "ControlsScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    out = os.environ.get("SOLFA_SCENE_OUT") or os.path.join(workdir, "scene.png")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR=scale, SOLFA_SCENE_OUT=out,
               XDG_RUNTIME_DIR=workdir, **(extra_env or {}))
    # Its own runtime dir keeps the scene out of the live shell's instance
    # list; GTK, loaded by Quickshell, still wants the desktop's display.
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=60)
    found = {}
    for key in ("GEOM", "CLICKS"):
        m = re.search(key + r" (\{.*\})", run.stdout + run.stderr)
        found[key] = json.loads(m.group(1)) if m else None
    return found


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class HitTargets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-hit-")
        found = render(cls.workdir)
        cls.geom, cls.clicks = found["GEOM"], found["CLICKS"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.geom, "the scene did not render")
        self.assertIsNotNone(self.clicks, "the scene did not click")

    def test_every_control_is_at_least_32_px_square(self):
        buttons = self.geom["buttons"]
        self.assertGreaterEqual(len(buttons), 15)
        for b in buttons:
            self.assertGreaterEqual(min(b["w"], b["h"]), MIN, b)

    def test_the_transport_row_is_44_px_and_play_is_the_largest(self):
        tips = ("Shuffle the queue (s)", "Previous (p)", "Pause (space)", "Next (n)", "Repeat")
        transport = [b for b in self.geom["buttons"] if b["tip"].startswith(tips)]
        self.assertEqual(len(transport), 5, transport)
        # One centre line.
        self.assertEqual(len({b["y"] + b["h"] / 2 for b in transport}), 1, transport)
        for b in transport:
            self.assertGreaterEqual(min(b["w"], b["h"]), TRANSPORT, b)
        play = transport[2]
        self.assertEqual(max(b["w"] for b in transport), play["w"])

    def test_hit_boxes_do_not_overlap(self):
        shown = [b for b in self.geom["buttons"] if b["shown"]]
        for i, a in enumerate(shown):
            for b in shown[i + 1:]:
                apart = (a["x"] + a["w"] <= b["x"] or b["x"] + b["w"] <= a["x"]
                         or a["y"] + a["h"] <= b["y"] or b["y"] + b["h"] <= a["y"])
                self.assertTrue(apart, (a, b))

    def test_row_actions_keep_their_room_so_the_title_does_not_jump(self):
        # Row 1 has the cursor (actions shown), row 2 the same actions hidden:
        # their titles get the same width.
        long_titles = [t["w"] for t in self.geom["titles"] if t["text"].startswith("A Much Longer")]
        self.assertEqual(len(long_titles), 2)
        self.assertEqual(long_titles[0], long_titles[1])

    def test_the_whole_box_clicks_not_just_the_glyph(self):
        want = {"Shuffle the queue (s)": "shuffle", "Previous (p)": "previous", "Pause (space)": "togglePlaying",
                "Next (n)": "next", "Repeat all (r)": "cycleRepeat", "Mute (m)": "toggleMute",
                "Remove the like (f)": "toggleLike", "Queue": "tab:queue", "Search": "tab:search",
                "Library": "tab:library", "Lyrics": "tab:lyrics", "Remove (x)": "action:remove:1", "?": "allKeys"}
        for name, call in want.items():
            # The middle, and 3 px in from two opposite corners: one call each.
            self.assertEqual(self.clicks["clicked"].get(name), [call] * 3, name)

    def test_a_hidden_row_action_does_nothing_the_click_plays_its_row(self):
        self.assertTrue([b for b in self.geom["buttons"] if not b["shown"]])
        self.assertEqual(self.clicks["hiddenClick"], "row:2")

    def test_hovering_a_row_then_its_action_keeps_it_and_the_click_is_the_action(self):
        self.assertEqual(self.clicks.get("hoverShown"), 1)
        self.assertEqual(self.clicks.get("hoverClick"), "action:remove:2")

    def test_pressed_shrinks_a_little_and_comes_back(self):
        self.assertAlmostEqual(self.clicks["pressedScale"], 0.94, places=2)
        self.assertEqual(self.clicks["releasedScale"], 1)


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class AdSkipButton(unittest.TestCase):
    """During an advert the old top "Skip advert" HitButton is gone; a filled
    "Skip ad" pill sits by the advert's own clock instead (SOLFA_SCENE_AD=1)."""

    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-hit-ad-")
        found = render(cls.workdir, extra_env={"SOLFA_SCENE_AD": "1"})
        cls.geom, cls.clicks = found["GEOM"], found["CLICKS"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.geom, "the scene did not render")
        self.assertIsNotNone(self.clicks, "the scene did not click")

    def test_the_old_top_skip_advert_button_is_gone(self):
        self.assertFalse(any(b["label"] == "Skip advert" for b in self.geom["buttons"]))

    def test_skip_ad_pill_has_a_proper_hit_box_next_to_the_clock(self):
        pills = [b for b in self.geom["buttons"] if b["label"] == "Skip ad"]
        self.assertEqual(len(pills), 1, self.geom["buttons"])
        pill = pills[0]
        self.assertTrue(pill["shown"])
        self.assertGreaterEqual(min(pill["w"], pill["h"]), MIN, pill)
        # It sits inside the hero, above the tabs row below it — not off in
        # the footer or the queue.
        queue_tab = next(b for b in self.geom["buttons"] if b["label"] == "Queue")
        self.assertLess(pill["y"], queue_tab["y"], "still part of the hero, above the tabs")

    def test_clicking_the_skip_ad_pill_skips_it(self):
        self.assertEqual(self.clicks["clicked"].get("Skip ad"), ["skipAd"] * 3)

    def test_the_skip_ad_pill_does_not_overlap_anything_shown(self):
        shown = [b for b in self.geom["buttons"] if b["shown"]]
        for i, a in enumerate(shown):
            for b in shown[i + 1:]:
                apart = (a["x"] + a["w"] <= b["x"] or b["x"] + b["w"] <= a["x"]
                         or a["y"] + a["h"] <= b["y"] or b["y"] + b["h"] <= a["y"])
                self.assertTrue(apart, (a, b))


class PanelUsesHitButtons(unittest.TestCase):
    """The tabs, Back and the footer's "?" are the same HitButton the scene measures."""

    def test_panel_controls(self):
        with open(os.path.join(ROOT, "Panel.qml")) as f:
            src = f.read()
        self.assertIn("delegate: Views.HitButton {", src)
        self.assertRegex(src, r"Views\.HitButton \{\s*iconText: Icons\.back")
        self.assertRegex(src, r"Views\.HitButton \{\s*id: allKeysButton")
        self.assertNotRegex(src, r"\bButton \{")


if __name__ == "__main__":
    unittest.main()
