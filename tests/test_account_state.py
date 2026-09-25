#!/usr/bin/env python3
"""Account UI follows the sign-in state: header button, Premium badge, Settings.

Renders tests/qml/AccountScene.qml offscreen, like tests/test_settings.py,
and reads its "STATE {...}" line. Also keeps the evidence frames when
SOLFA_EVIDENCE_DIR is set. Skips when Quickshell, the Omarchy shell or a
desktop session is missing.
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
    os.mkdir(cfg)
    for name, target in (("Ui", os.path.join(SHELL_DIR, "Ui")), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("shell.qml", os.path.join(HERE, "qml", "AccountScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    frames = [os.path.join(workdir, n) for n in ("signed-out.png", "signed-in-free.png", "signed-in-premium.png")]
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir,
               SOLFA_SCENE_OUT=frames[0], SOLFA_SCENE_OUT2=frames[1], SOLFA_SCENE_OUT3=frames[2])
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=60)
    m = re.search(r"STATE (\{.*\})", run.stdout + run.stderr)
    evidence = os.environ.get("SOLFA_EVIDENCE_DIR")
    if evidence:
        os.makedirs(evidence, exist_ok=True)
        for f in frames:
            if os.path.exists(f):
                shutil.copy(f, evidence)
    return json.loads(m.group(1)) if m else None, run.stdout + run.stderr


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class AccountState(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-account-")
        cls.state, cls.log = render(cls.workdir)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render: " + self.log[-800:])

    def test_signed_out_settings_offers_sign_in(self):
        s = self.state["signedOut"]
        self.assertTrue(s["accountSignIn"])
        self.assertFalse(s["accountSwitch"])
        self.assertFalse(s["accountSignOut"])
        self.assertEqual(s["handlers"], 1)

    def test_signed_out_header_has_the_sign_in_button_and_no_badge(self):
        s = self.state["signedOut"]
        self.assertTrue(s["signInButton"])
        self.assertFalse(s["premiumBadge"])
        self.assertFalse(s["overlaps"])

    def test_sign_in_works_by_header_click_settings_click_and_keyboard(self):
        self.assertEqual(self.state["callsAfterHeaderClick"], 1)
        self.assertEqual(self.state["callsAfterSettingsClick"], 2)
        self.assertEqual(self.state["callsAfterKey"], 3)

    def test_no_account_lookup_while_signed_out(self):
        self.assertEqual(self.state["infoCallsSignedOut"], 0)

    def test_signed_in_free_shows_no_button_no_badge_and_both_account_actions(self):
        s = self.state["free"]
        self.assertFalse(s["signInButton"])
        self.assertFalse(s["premiumBadge"])
        self.assertFalse(s["accountSignIn"])
        self.assertTrue(s["accountSwitch"])
        self.assertTrue(s["accountSignOut"])
        self.assertEqual(s["handlers"], 2)
        self.assertGreaterEqual(self.state["infoCallsSignedIn"], 1)

    def test_premium_shows_the_badge_and_no_sign_in_button(self):
        s = self.state["premium"]
        self.assertTrue(s["premiumBadge"])
        self.assertFalse(s["signInButton"])
        self.assertFalse(s["overlaps"])

    def test_signing_out_shrinks_the_rows_and_resets_the_cursor(self):
        s = self.state["afterSignOut"]
        self.assertEqual((s["handlers"], s["cursor"]), (1, 0))
        self.assertFalse(s["premiumBadge"], "a stale Premium flag must not show signed out")
        self.assertTrue(s["signInButton"])

    def test_no_sign_in_button_while_the_engine_starts_or_the_window_is_open(self):
        self.assertFalse(self.state["engineStarting"]["signInButton"])
        self.assertFalse(self.state["signingIn"]["signInButton"])

    def test_no_badge_while_the_engine_is_down(self):
        self.assertFalse(self.state["premiumEngineDown"]["premiumBadge"])


if __name__ == "__main__":
    unittest.main()
