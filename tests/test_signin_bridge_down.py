#!/usr/bin/env python3
"""Sign in clicked while the bridge is not connected says so.

Sign in is on offer while the bridge is still starting (a fresh install, a
shell restart). Runs the real Service.qml (tests/qml/ServiceLifecycleScene.qml,
through tests/test_widget_move.py's run_scene) against a fake bridge that
comes up late: a click before it is up must be reported, not dropped without
a word, and a click once it is up must reach it. Skips when Quickshell or a
desktop session is not available.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import os
import unittest

from test_widget_move import ENTRY, QS, SHELL_DIR, run_scene, tail


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class SignInBridgeDown(unittest.TestCase):
    def test_a_sign_in_before_the_bridge_is_up_is_reported_and_one_after_reaches_it(self):
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": ENTRY},
                 {"at": 1500, "do": "signIn"},   # the bridge is not up yet
                 {"at": 6000, "do": "signIn"}]   # it is
        bridge, calls, log = run_scene(steps, bridge_delay=4.0, scene_ms=7500)
        self.assertIn("SIGNIN bridgeUp=false", log)
        self.assertIn("SIGNIN bridgeUp=true", log)
        told = [c for c in calls if c.startswith("notify-send") and "Solfa's helper is restarting" in c]
        self.assertEqual(len(told), 1, "\n".join(calls) + "\n" + tail(log))
        signins = [o for o in bridge.ops if o[1] == "signin.begin"]
        self.assertEqual(len(signins), 1, str(bridge.ops))
        self.assertGreater(signins[0][0], 4.0, "only the click made once the bridge was up")


if __name__ == "__main__":
    unittest.main()
