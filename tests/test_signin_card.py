#!/usr/bin/env python3
"""The sign-in card says when a sign-in window closed without the account in.

Renders tests/qml/SignInCardScene.qml offscreen, like tests/test_account_state.py,
and reads its "STATE {...}" line. Also keeps the evidence frame when
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
                         ("shell.qml", os.path.join(HERE, "qml", "SignInCardScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    frames = [os.path.join(workdir, "signin-failed.png")]
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir,
               SOLFA_SCENE_OUT=frames[0])
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
class SignInCard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-signin-card-")
        cls.state, cls.log = render(cls.workdir)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render: " + self.log[-800:])

    def test_signed_out_card_invites_to_sign_in(self):
        self.assertEqual(self.state["signedOut"]["title"], "Sign in to YouTube Music")

    def test_a_failed_sign_in_is_said_on_the_card(self):
        self.assertEqual(self.state["failed"]["title"], "Signing in did not finish")
        self.assertIn("still signed out", self.state["failed"]["body"])

    def test_a_new_try_shows_the_window_not_the_old_failure(self):
        self.assertEqual(self.state["retrying"]["title"], "Sign in in the Google window")

    def test_a_landed_window_says_the_sign_in_is_being_saved(self):
        self.assertEqual(self.state["saving"]["title"], "Saving your sign-in")


if __name__ == "__main__":
    unittest.main()
