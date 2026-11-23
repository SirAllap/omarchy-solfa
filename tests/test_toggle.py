#!/usr/bin/env python3
"""The key path (Super+M) opens and closes the panel.

Super+M runs `omarchy-shell shell toggle <id>`. The shell finds the bar widget
(Bar.findPanelWidget needs open(), close() and a defined 'opened'), then calls
close() on it when it is open and open() otherwise. This builds the real
BarWidget.qml and Panel.qml (tests/qml/ServiceLifecycleScene.qml, offscreen,
fake bridge, no desktop window) and drives that same path twice: it must end
open, then closed, then open, then closed. Skips when Quickshell or a desktop
session is not available.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import json
import re
import unittest

import test_widget_move as wm


@unittest.skipUnless(wm.QS and wm.os.path.isdir(wm.os.path.join(wm.SHELL_DIR, "Ui")) and wm.os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class KeyToggle(unittest.TestCase):
    def test_toggle_opens_and_closes_the_panel(self):
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": wm.ENTRY}]
        for i, at in enumerate((1500, 2200, 2900, 3600)):
            steps.append({"at": at, "do": "toggle", "name": "w1"})
        bridge, calls, log = wm.run_scene(steps, scene_ms=5000, stub_panel=True)
        rows = [json.loads(m) for m in re.findall(r"TOGGLE (\{.*\})", log)]
        self.assertEqual(len(rows), 4, wm.tail(log) + "\n" + log[-2000:])
        for row in rows:
            self.assertTrue(row["contract"], "Bar.findPanelWidget would not find the widget: " + str(row))
        self.assertEqual([(r["before"], r["after"]) for r in rows],
                         [(False, True), (True, False), (False, True), (True, False)], log[-2000:])


if __name__ == "__main__":
    unittest.main()
