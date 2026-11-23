#!/usr/bin/env python3
"""The keyboard path of the panel, walked offscreen.

Renders tests/qml/KeysScene.qml (the real Panel.qml, fake service, stub
KeyboardPanel) and feeds Panel.onKey the keys the shell would deliver: the
1..5 tab keys, / for search, Tab and Shift+Tab across the tabs (no other bar
panel to switch to), left and right, space, n and p reaching the service, ?
and Esc closing the overlay first, Settings opening and closing with Esc, and
Esc closing the panel. Skips when Quickshell or a desktop session is missing.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import json
import re
import unittest

import test_open_close as oc


@unittest.skipUnless(oc.QS and oc.os.path.isdir(oc.os.path.join(oc.SHELL_DIR, "Ui")) and oc.os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class KeyboardPath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scene = oc.os.path.join(oc.HERE, "qml", "KeysScene.qml")
        work = oc.tempfile.mkdtemp(prefix="solfa-keys-")
        cls.work = work
        cls.log = cls.run_scene(work, scene)
        m = re.search(r"KEYS (\{.*\})", cls.log)
        cls.k = json.loads(m.group(1)) if m else None

    @staticmethod
    def run_scene(workdir, scene):
        cfg = oc.os.path.join(workdir, "scene")
        ui = oc.os.path.join(cfg, "Ui")
        oc.os.makedirs(ui)
        shell_ui = oc.os.path.join(oc.SHELL_DIR, "Ui")
        for name in oc.os.listdir(shell_ui):
            src = oc.os.path.join(oc.HERE, "qml", "stub", name) if name == "KeyboardPanel.qml" else oc.os.path.join(shell_ui, name)
            oc.os.symlink(src, oc.os.path.join(ui, name))
        for name, target in (("Commons", oc.os.path.join(oc.SHELL_DIR, "Commons")),
                             ("views", oc.os.path.join(oc.ROOT, "views")), ("lib", oc.os.path.join(oc.ROOT, "lib")),
                             ("SolfaPanel.qml", oc.os.path.join(oc.ROOT, "Panel.qml")), ("shell.qml", scene)):
            oc.os.symlink(target, oc.os.path.join(cfg, name))
        env = dict(oc.os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir)
        runtime, display = oc.os.environ.get("XDG_RUNTIME_DIR", ""), oc.os.environ.get("WAYLAND_DISPLAY", "")
        if runtime and display and not oc.os.path.isabs(display):
            env["WAYLAND_DISPLAY"] = oc.os.path.join(runtime, display)
        run = oc.subprocess.run([oc.QS, "-p", oc.os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=60)
        return run.stdout + run.stderr

    @classmethod
    def tearDownClass(cls):
        oc.shutil.rmtree(cls.work, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.k, "the scene did not run:\n" + self.log[-3000:])

    def test_tab_keys_and_slash(self):
        self.assertEqual(self.k["numbers"], ["queue", "search", "library", "lyrics", "history"])
        self.assertEqual(self.k["slash"], "search")

    def test_tab_and_shift_tab_walk_the_tabs(self):
        self.assertEqual(self.k["tabFwd"], "search")
        self.assertEqual(self.k["tabBack"], "queue")
        self.assertEqual(self.k["right"], "search")
        self.assertEqual(self.k["left"], "queue")

    def test_the_all_keys_sheet_shows_the_real_global_keys(self):
        self.assertEqual(self.k["sheetKeys"], ["Super + Shift + M", "Super + Alt + P"])

    def test_transport_keys_reach_the_service(self):
        self.assertEqual(self.k["calls"], ["togglePlaying", "next", "previous"])

    def test_escape_goes_back_one_layer_at_a_time(self):
        self.assertTrue(self.k["allKeysOn"])
        self.assertFalse(self.k["allKeysOff"])
        self.assertTrue(self.k["stillOpen"])
        self.assertTrue(self.k["settingsOn"])
        self.assertEqual(self.k["panelKeyShown"], "Super+Shift+M")  # Settings › Keys shows the real key
        self.assertFalse(self.k["settingsOff"])
        self.assertTrue(self.k["openAfterSettings"])
        self.assertTrue(self.k["closedByEsc"])


if __name__ == "__main__":
    unittest.main()
