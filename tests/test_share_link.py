#!/usr/bin/env python3
"""Copy link: the button and `c` in the panel, and what reaches wl-copy.

Renders tests/qml/ShareScene.qml (the real Panel.qml and its views with a fake
service) offscreen: the button, the key, the message, and the cases where there
is nothing to share. Nothing here touches the real clipboard. Skips when
Quickshell, the Omarchy shell or a desktop session is missing.
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
WAYLAND = os.environ.get("WAYLAND_DISPLAY", "")


def render_scene(workdir, out=None):
    """tests/test_save_picker.render, with ShareScene.qml as the scene."""
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
                         ("shell.qml", os.path.join(HERE, "qml", "ShareScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir)
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


ENV_OK = bool(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and WAYLAND)


@unittest.skipUnless(ENV_OK, "Quickshell, the Omarchy shell or a desktop session is missing")
class ShareScene(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-share-")
        cls.found = render_scene(cls.workdir, os.environ.get("SOLFA_SHARE_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_the_button_is_in_now_playing_with_its_key_in_the_tooltip(self):
        b = self.state["button"]
        self.assertTrue(b["shown"])
        self.assertTrue(b["enabled"])
        self.assertEqual(b["tip"], "Copy link (c)")
        self.assertEqual(self.state["hint"], ["copy the song's link"])

    def test_c_and_the_button_copy_the_playing_song_and_say_so(self):
        self.assertEqual(self.state["key"], {"copied": ["AAAAAAAAAAA"], "flash": "Link copied"})
        self.assertEqual(self.state["click"], {"copied": ["AAAAAAAAAAA", "AAAAAAAAAAA"], "flash": "Link copied"})

    def test_a_service_that_made_no_link_does_not_say_copied(self):
        self.assertEqual(self.state["failed"]["flash"], "Nothing to share")

    def test_an_advert_or_no_song_leaves_nothing_to_share(self):
        self.assertEqual(self.state["ad"], {"shown": False, "flash": "Nothing to share", "asked": 0})
        self.assertEqual(self.state["none"], {"shown": False, "flash": "Nothing to share", "asked": 0})

    def test_c_is_a_letter_in_the_search_field(self):
        self.assertEqual(self.state["inField"], {"asked": 0, "flash": ""})


if __name__ == "__main__":
    if not ENV_OK:
        print("Quickshell, the Omarchy shell or a desktop session is missing; skipping")
    else:
        unittest.main()
