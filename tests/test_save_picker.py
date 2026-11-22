#!/usr/bin/env python3
"""Save to playlist: the real Panel.qml, its picker, a fake service.

Renders tests/qml/SaveScene.qml (the real Panel.qml, its real views, with a
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
                         ("shell.qml", os.path.join(HERE, "qml", "SaveScene.qml"))):
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
class SavePicker(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-save-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"), os.environ.get("SOLFA_SAVE_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_every_track_row_has_a_save_button_and_other_rows_do_not(self):
        a = self.state["actions"]
        self.assertIn("save", a["song"])
        self.assertIn("save", a["video"])
        self.assertNotIn("save", a["album"])
        self.assertIn("save", a["queue"])
        self.assertIn("save", a["queueAutomix"])
        self.assertTrue(self.state["heroButton"], "the now-playing card has the button too")

    def test_s_opens_the_picker_for_the_playing_song(self):
        o = self.state["open"]
        self.assertFalse(self.state["closedAtStart"])
        self.assertTrue(o["shown"])
        self.assertTrue(o["hints"])
        self.assertEqual(o["item"]["videoId"], "AAAAAAAAAAA")
        self.assertEqual(o["asked"], {"videoId": "AAAAAAAAAAA"})

    def test_new_playlist_first_then_recent_and_all_playlists_with_their_sizes(self):
        o = self.state["open"]
        self.assertEqual(o["rows"], ["+", "#Recent", "Road trip", "Study", "#All playlists", "Shared mix", "Liked Music"])
        self.assertEqual(o["counts"], ["", "", "889 tracks", "13 tracks", "", "6 tracks", "206 songs"])
        self.assertEqual(o["cursor"], 2, "it rests on the first playlist, not on a header")

    def test_typing_filters_both_groups_and_new_playlist_stays(self):
        self.assertEqual(self.state["filtered"], {"rows": ["+", "#Recent", "Study"], "cursor": 2})
        self.assertEqual(self.state["nothing"]["rows"], ["+"])
        self.assertEqual(self.state["nothing"]["text"], "No playlist matches")
        self.assertEqual(self.state["moved"], 5, "the cursor steps over the header")

    def test_enter_saves_to_the_playlist_and_says_so(self):
        s = self.state["saved"]
        self.assertEqual(s["add"], {"playlistId": "PLfixtureRoad", "videoId": "AAAAAAAAAAA"})
        self.assertFalse(s["open"])
        self.assertFalse(s["shown"])
        self.assertEqual(s["flash"], "Saved to Road trip")

    def test_a_duplicate_is_refused_once_then_enter_adds_it_anyway(self):
        a = self.state["already"]
        self.assertEqual(a["flash"], "Already in Study · ↵ again to add anyway")
        self.assertTrue(a["open"], "the picker stays so Enter can add anyway")
        self.assertEqual(a["dupId"], "PLfixtureStudy")
        self.assertEqual(a["args"], {"playlistId": "PLfixtureStudy", "videoId": "AAAAAAAAAAA"})
        self.assertEqual(self.state["dupAfterMove"], "", "moving off the row forgets it")
        w = self.state["anyway"]
        self.assertEqual(w["args"], {"playlistId": "PLfixtureStudy", "videoId": "AAAAAAAAAAA", "force": True})
        self.assertEqual(w["sent"], 1)
        self.assertEqual(w["flash"], "Saved to Study")
        self.assertFalse(w["open"])

    def test_new_playlist_asks_for_a_name_then_creates_with_the_song(self):
        self.assertTrue(self.state["naming"]["creating"])
        self.assertFalse(self.state["naming"]["listShown"])
        self.assertEqual(self.state["escFromNaming"], {"creating": False, "open": True})
        e = self.state["emptyName"]
        self.assertTrue(e["creating"], "a blank name creates nothing")
        self.assertEqual(e["flash"], "Give the playlist a name")
        self.assertEqual(e["created"], 0)
        c = self.state["created"]
        self.assertEqual(c["args"], {"title": "Fresh mix", "videoIds": ["AAAAAAAAAAA"]})
        self.assertEqual(c["flash"], "Saved to the new playlist Fresh mix")
        self.assertFalse(c["open"])

    def test_a_failure_keeps_the_picker_and_says_why(self):
        f = self.state["failed"]
        self.assertEqual(f["flash"], "YouTube Music did not save it")
        self.assertTrue(f["open"])
        self.assertFalse(f["busy"])

    def test_esc_closes_the_picker(self):
        self.assertEqual(self.state["escClosed"], {"open": False, "shown": False})

    def test_signed_out_says_to_sign_in_and_asks_nothing(self):
        s = self.state["signedOut"]
        self.assertFalse(s["open"])
        self.assertEqual(s["flash"], "Sign in to save songs to a playlist")
        self.assertEqual(s["asked"], 0)


if __name__ == "__main__":
    unittest.main()
