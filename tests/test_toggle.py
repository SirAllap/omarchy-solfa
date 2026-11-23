#!/usr/bin/env python3
"""The key path (Super+Alt+M) opens and closes the panel.

Super+Alt+M runs `omarchy-shell shell toggle <id>`. The shell finds the bar widget
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


    def test_when_super_m_is_taken_the_panel_key_falls_back_and_settings_shows_it(self):
        # Someone holds Super+Alt+M: Solfa must not touch it, and must
        # register the first free fallback instead. Omarchy's Super+M
        # (minimize) is left alone either way.
        binds = json.dumps([{"modmask": 64, "key": "M", "description": "Minimize window to the dock"},
                            {"modmask": 72, "key": "M", "description": "Another app"}])
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": wm.ENTRY},
                 {"at": 3800, "do": "panelKey"}]
        bridge, calls, log = wm.run_scene(steps, scene_ms=4500, stub_panel=True, binds=binds)
        evals = [c for c in calls if c.startswith("hyprctl eval")]
        self.assertTrue(evals, "no keys were registered:\n" + "\n".join(calls) + wm.tail(log))
        lua = " ".join(evals)
        self.assertIn("hl.bind([[SUPER + SHIFT + M]]", lua)
        self.assertNotIn("[[SUPER + M]]", lua)  # Omarchy's minimize
        self.assertNotIn("hl.bind([[SUPER + ALT + M]]", lua)  # never take the other app's key
        self.assertNotIn("unbind, [[SUPER + ALT + M]]", lua)
        self.assertIn("hl.bind([[SUPER + ALT + N]]", lua)
        self.assertIn("hl.bind([[SUPER + ALT + P]]", lua)  # play/pause moved here
        found = json.loads(re.search(r"PANELKEY (\{.*\})", log).group(1))
        self.assertEqual(found["label"], "Super+Shift+M")
        self.assertEqual(found["options"], ["", "SUPER + SHIFT + M", "SUPER + CTRL + M"])

    def test_super_alt_m_is_the_default_panel_key(self):
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": wm.ENTRY},
                 {"at": 3800, "do": "panelKey"}]
        bridge, calls, log = wm.run_scene(steps, scene_ms=4500, stub_panel=True)
        lua = " ".join(c for c in calls if c.startswith("hyprctl eval"))
        self.assertIn("hl.bind([[SUPER + ALT + M]]", lua)
        self.assertNotIn("[[SUPER + M]]", lua)
        self.assertEqual(json.loads(re.search(r"PANELKEY (\{.*\})", log).group(1))["label"], "Super+Alt+M")


if __name__ == "__main__":
    unittest.main()
