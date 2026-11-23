#!/usr/bin/env python3
"""Find in a playlist: the real Panel.qml and DetailView, a fake service.

Renders tests/qml/FindScene.qml (the real Panel.qml, its real views, with a
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
                         ("shell.qml", os.path.join(HERE, "qml", "FindScene.qml"))):
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


BIG = "V%010d"


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class FindInPlaylist(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-find-")
        cls.found = render(cls.workdir, os.environ.get("SOLFA_SCENE_SCALE", "1"), os.environ.get("SOLFA_FIND_OUT"))
        cls.state = cls.found["STATE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render:\n" + self.found["log"])

    def test_a_playlist_page_has_the_button_and_no_field_yet(self):
        p = self.state["page"]
        self.assertEqual(p["pages"], 1)
        self.assertTrue(p["button"])
        self.assertEqual(p["tooltip"], "Find in this playlist (F)")
        self.assertFalse(p["field"])
        self.assertFalse(p["finding"])
        self.assertEqual(p["rows"], 100, "a page holds 100 songs")
        self.assertEqual(p["asked"], [], "nothing more is fetched until the field opens")
        self.assertEqual(p["hints"][1], ["F", "find", True], "the footer says how")

    def test_lower_f_is_still_like(self):
        self.assertEqual(self.state["lowerF"], {"likes": 1, "finding": False})

    def test_capital_f_opens_the_field_with_the_focus(self):
        k = self.state["byKey"]
        self.assertTrue(k["accepted"])
        self.assertTrue(k["finding"])
        self.assertTrue(k["field"])
        self.assertTrue(k["focus"])
        self.assertTrue(k["inputFocused"])
        self.assertEqual(k["hints"], [["↵ ↓", "to the list"], ["esc", "close"]])

    def test_it_says_it_is_loading_and_asks_for_one_page_at_a_time(self):
        k = self.state["byKey"]
        self.assertTrue(k["loadingAll"])
        self.assertEqual(k["pending"], 1)
        self.assertEqual(k["status"], "Loading 100 songs")
        self.assertEqual(self.state["afterFirst"]["pending"], 1, "the next page is asked only when the last one came")
        self.assertEqual(self.state["afterFirst"]["asked"], ["tokB1", "tokB2"])

    def test_letters_typed_in_the_field_are_not_shortcuts(self):
        n = self.state["noShortcuts"]
        self.assertTrue(n["next"])
        self.assertEqual(n["likes"], 1, "only the lower f of the earlier test")
        self.assertEqual((n["pages"], n["tab"]), (1, "queue"))
        self.assertTrue(n["focus"])

    def test_the_list_follows_the_pages_as_they_arrive(self):
        self.assertEqual(self.state["firstPageOnly"]["titles"], ["Crème Brûlée"])
        self.assertEqual(self.state["firstPageOnly"]["status"], "1 of 100 · loading")
        a = self.state["afterFirst"]
        self.assertEqual(a["titles"], ["Crème Brûlée", "Sunrise"], "a song from page 2 shows as soon as it is here")
        self.assertEqual((a["loaded"], a["status"]), (200, "2 of 200 · loading"))

    def test_every_page_is_loaded_and_it_says_how_many_match(self):
        a = self.state["afterSecond"]
        self.assertEqual(a["asked"], ["tokB1", "tokB2"])
        self.assertEqual((a["loaded"], a["pending"], a["continuation"]), (250, 0, ""))
        self.assertFalse(a["loadingAll"])
        self.assertEqual(a["status"], "2 of 250")

    def test_filter_on_title_artists_and_album_without_case_or_accents(self):
        q = self.state["queries"]
        crepe = ["Crème Brûlée"]
        both = ["Crème Brûlée", "Sunrise"]
        self.assertEqual(q["zoe"]["titles"], both)
        self.assertEqual(q["ZOË"]["titles"], both)
        self.assertEqual(q["creme"]["titles"], crepe)
        self.assertEqual(q["CRÈME Brulee"]["titles"], crepe)
        self.assertEqual(q["sessions"]["titles"], crepe, "the album")
        self.assertEqual(q["samples sunrise"]["titles"], ["Sunrise"], "the second artist and the title")

    def test_more_words_must_all_match_in_any_order(self):
        q = self.state["queries"]
        self.assertEqual(q["brulee zoe"]["titles"], ["Crème Brûlée"])
        self.assertEqual(q["zoe brulee"]["titles"], ["Crème Brûlée"])
        self.assertEqual(q["zoe zebra"]["titles"], [])

    def test_a_song_from_the_last_page_is_found(self):
        self.assertEqual(self.state["queries"]["zebra"]["titles"], ["Zebra Crossing"])
        self.assertEqual(self.state["queries"]["zebra"]["status"], "1 of 250")

    def test_no_match_says_so_and_a_blank_field_is_the_whole_list(self):
        n = self.state["queries"]["nothing at all"]
        self.assertEqual((n["titles"], n["empty"], n["status"]), ([], "No song matches", "0 of 250"))
        b = self.state["queries"]["  "]
        self.assertEqual(len(b["titles"]), 250)
        self.assertEqual(b["status"], "250 songs")
        self.assertEqual(len(self.state["queries"]["song 15"]["titles"]), 13, "15, 115, 150 to 159 and 215")

    def test_the_loaded_pages_stay_with_the_page(self):
        self.assertEqual(self.state["pageIsKept"], {"tracks": 250, "pageInfo": 250})

    def test_enter_or_down_in_the_field_goes_to_the_list_on_its_first_song(self):
        self.assertEqual(self.state["beforeList"]["titles"], ["Crème Brûlée", "Sunrise"])
        t = self.state["toList"]
        self.assertEqual((t["cursor"], t["current"]), (0, "Crème Brûlée"))
        self.assertFalse(t["fieldFocus"])
        self.assertFalse(t["inputFocused"])
        self.assertTrue(t["finding"], "the filter stays while you move in the list")
        self.assertEqual(t["hints"][0], ["↵", "play or open"])

    def test_enter_plays_the_song_that_was_filtered_to_in_the_playlist(self):
        self.assertEqual(self.state["afterDown"], {"cursor": 1, "current": "Sunrise"})
        self.assertEqual(self.state["enter"]["play"], {"videoId": BIG % 130, "playlistId": "PLfixtureBig"})
        self.assertEqual(self.state["enter"]["flash"], "Playing Sunrise")

    def test_a_click_acts_on_the_row_that_was_clicked(self):
        self.assertEqual(self.state["click"]["play"], {"videoId": BIG % 7, "playlistId": "PLfixtureBig"})

    def test_row_keys_and_buttons_act_on_the_filtered_song(self):
        self.assertEqual(self.state["playNext"][-1], {"videoId": BIG % 130, "next": True}, "e is for the row under the cursor")
        self.assertTrue(self.state["saveButton"]["open"])
        self.assertEqual(self.state["saveButton"]["item"], {"videoId": BIG % 130, "title": "Sunrise"})
        self.assertEqual(self.state["saveKey"]["item"], {"videoId": BIG % 7, "title": "Crème Brûlée"}, "S on the first filtered row")

    def test_esc_in_the_picker_closes_only_the_picker(self):
        self.assertEqual(self.state["saveEsc"], {"open": False, "finding": True, "pages": 1})

    def test_play_and_shuffle_are_about_the_whole_playlist(self):
        self.assertEqual(self.state["playAll"], {"playlistId": "PLfixtureBig"})
        self.assertEqual(self.state["shuffleAll"], {"playlistId": "PLfixtureBig", "params": "wAEB8gECKAE%3D"})

    def test_esc_from_the_list_closes_the_filter_not_the_page(self):
        e = self.state["escList"]
        self.assertFalse(e["finding"])
        self.assertEqual(e["pages"], 1)
        self.assertEqual(e["rows"], 250)
        self.assertEqual((e["current"], e["cursor"]), ("Sunrise", 130), "the cursor stays on the song, in the whole list")
        self.assertEqual((e["query"], e["field"]), ("", False))
        self.assertEqual(e["hints"][-1], ["esc", "back"])

    def test_the_button_opens_it_and_f_from_the_list_goes_back_to_the_field(self):
        b = self.state["byButton"]
        self.assertTrue(b["finding"] and b["focus"] and b["field"])
        self.assertFalse(b["loadingAll"], "everything is already loaded")
        f = self.state["fFromList"]
        self.assertTrue(f["accepted"] and f["inputFocused"] and f["finding"])
        self.assertEqual(f["text"], "zoe", "the text is kept")

    def test_esc_in_the_field_clears_then_closes_the_filter_then_goes_back(self):
        self.assertEqual(self.state["escField1"], {"text": "", "query": "", "finding": True, "focus": True, "rows": 250, "pages": 1})
        e = self.state["escField2"]
        self.assertEqual((e["finding"], e["inputFocused"], e["pages"], e["field"]), (False, False, 1, False))
        self.assertEqual(self.state["escField3"], {"pages": 0})

    def test_closing_the_page_while_it_loads_stops_it_and_drops_the_late_answer(self):
        self.assertEqual(self.state["loading"], {"pending": 1, "loadingAll": True, "status": "Loading 100 songs"})
        c = self.state["closedWhileLoading"]
        self.assertEqual(c, {"tracks": 100, "asked": 0, "pending": 0, "loadingAll": False, "finding": False, "pages": 0})

    def test_a_late_answer_does_not_touch_the_next_page(self):
        o = self.state["otherPage"]
        self.assertEqual((o["title"], o["tracks"], o["asked"]), ("Small album", 5, 0))
        self.assertFalse(o["finding"] or o["loadingAll"])

    def test_a_page_that_fails_keeps_what_came_and_says_so(self):
        f = self.state["flaky"]
        self.assertEqual(f["tracks"], 200)
        self.assertFalse(f["loadingAll"])
        self.assertEqual(f["error"], "YouTube Music took too long to answer")
        self.assertEqual(f["flash"], f["error"])
        self.assertEqual(f["status"], "200 songs · not all loaded")
        self.assertEqual(f["continuation"], "tokF2")
        self.assertTrue(f["finding"])
        self.assertEqual(self.state["flakyFilter"], {"count": 12, "status": "12 of 200 · not all loaded"})

    def test_an_album_says_album_and_has_nothing_more_to_fetch(self):
        self.assertEqual(self.state["album"], {"tooltip": "Find in this album (F)", "button": True})
        a = self.state["albumFind"]
        self.assertEqual((a["finding"], a["placeholder"], a["requests"]), (True, "Find in this album", self.state["albumFind"]["requests"]))
        self.assertEqual(self.state["albumFilter"]["titles"], ["Song 3"])
        self.assertEqual(self.state["albumFilter"]["status"], "1 of 5")

    def test_an_artist_page_has_no_find(self):
        a = self.state["artist"]
        self.assertFalse(a["button"])
        self.assertFalse(a["finding"])
        self.assertFalse(a["accepted"])
        self.assertEqual(a["hints"], [["↵", "play or open"], ["e", "play next"], ["esc", "back"]])


if __name__ == "__main__":
    unittest.main()
