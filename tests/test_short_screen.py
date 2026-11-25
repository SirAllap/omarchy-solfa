#!/usr/bin/env python3
"""Short screens: the rows of a playlist a page shows, and the compact layout.

Renders tests/qml/ShortScreenScene.qml (the real Panel.qml, its real
views, with a fake service: a song playing, a 40-song playlist open) in a
private Quickshell, offscreen, at screen heights from 720 to 1440, at the
shell's default font and at base size 10, for each compactPanel setting.
The shell's KeyboardPanel (a layer-shell window that takes the keyboard) is
swapped for tests/qml/stub/KeyboardPanel.qml, a plain card capped at the
screen's room (SOLFA_CARD_MAX_H): nothing is mapped on the desktop and no
keyboard is grabbed. Skips when Quickshell, the Omarchy shell or a desktop
session is missing.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import json
import os
import re
import resource
import shutil
import subprocess
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))


def no_core():
    # A crash leaves no core dump: the kernel gives up on one at a limit of
    # 1 byte, before any core handler runs (0 still reaches systemd-coredump).
    resource.setrlimit(resource.RLIMIT_CORE, (1, 1))


def render(workdir, card_h, mode=None, base=None, out=None, late=False, nowindow=False):
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
                         ("shell.qml", os.path.join(HERE, "qml", "ShortScreenScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR="1", XDG_RUNTIME_DIR=workdir, SOLFA_CARD_MAX_H=str(card_h))
    env.pop("SOLFA_COMPACT_PANEL", None)
    if mode:
        env["SOLFA_COMPACT_PANEL"] = mode
    # The shell's own font size, as ~/.config/omarchy/shell.toml sets it
    # (Commons reads it): a home of its own for each render, so no font
    # setting of the machine's leaks in.
    home = os.path.join(workdir, "home")
    os.makedirs(os.path.join(home, ".config", "omarchy"))
    if base:
        with open(os.path.join(home, ".config", "omarchy", "shell.toml"), "w") as f:
            f.write("[font]\nbase-size = %d\n" % base)
    env["HOME"] = home
    env.pop("SOLFA_LATE_TRACK", None)
    if late:
        env["SOLFA_LATE_TRACK"] = "1"
    # A crash ends the run at once (no crash reporter left behind).
    env["QS_DISABLE_CRASH_HANDLER"] = "1"
    env.pop("SOLFA_NO_WINDOW", None)
    if nowindow:
        env["SOLFA_NO_WINDOW"] = "1"
    env.pop("SOLFA_SCENE_OUT", None)
    if out:
        env["SOLFA_SCENE_OUT"] = out
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=60, preexec_fn=no_core)
    m = re.search(r"STATE (\{.*\})", run.stdout + run.stderr)
    return {"STATE": json.loads(m.group(1)) if m else None, "log": (run.stdout + run.stderr)[-3000:],
            "png": out if out and os.path.exists(out) else None, "code": run.returncode}


def card_height(screen_h, base=None):
    """The card the shell gives the panel on a screen this tall: less a bar
    of 26 px at the top (22 at the shell's font base size 10, the bar scales
    with the font) and Omarchy's 10 px gaps on both sides of the card."""
    bar = 22 if base == 10 else 26
    return screen_h - bar - 10 - 10


def whole_rows(list_h, row_h, spacing):
    """Rows of row_h with spacing between them that fit whole in list_h."""
    return int((list_h + spacing) // (row_h + spacing)) if list_h > 0 else 0


# Screen heights (logical px), at the shell's default font (12) and at base
# size 10 (Style.space(n) = n * 10/12), with a song playing and a playlist of
# 40 songs open.
SCREENS = (720, 810, 900, 1080, 1440)
BASES = (None, 10)
MODES = ("auto", "always", "never")
CASES = {(h, b, m): (card_height(h, b), m, b) for h in SCREENS for b in BASES for m in MODES}
CASES.update({(h, b, None): (card_height(h, b), None, b) for h in (810, 1440) for b in BASES})
# The song starting with the panel already open (the layout full until then).
LATE = {(h, b, "late"): (card_height(h, b), "auto", b) for h in (810, 1080) for b in BASES}
# The panel made out of any window, a song already there, and put in one
# later (the shell makes the panel's window after the panel).
NOWIN = {(h, None, "nowin-" + m): (card_height(h, None), m, None) for h in (810, 1440) for m in ("auto", "always")}
# Whole rows the compact layout shows at the least: 4, but 2 on a 720 px
# screen at the default font (the fonts and buttons keep their size there).
MIN_ROWS = {(720, None): 2}


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class ShortScreen(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-short-")

        def one(item):
            key, (h, mode, base) = item
            w = os.path.join(cls.workdir, "-".join(str(k) for k in key))
            os.makedirs(w)
            return key, render(w, h, mode, base, out=os.path.join(w, "card.png"), late=key in LATE, nowindow=key in NOWIN)

        with ThreadPoolExecutor(max_workers=4) as pool:
            cls.found = dict(pool.map(one, list(CASES.items()) + list(LATE.items()) + list(NOWIN.items())))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def state(self, key):
        f = self.found[key]
        self.assertIsNotNone(f["STATE"], "the scene did not render (%r):\n%s" % (key, f["log"]))
        return f["STATE"]

    def assertFits(self, key, s):
        self.assertLessEqual(s["card"]["h"], s["maxCard"], (key, "the card is taller than the screen allows", s))
        self.assertLessEqual(s["hero"]["y"] + s["hero"]["h"], s["tabs"]["y"], (key, "the song's part runs into the tabs", s))
        self.assertLessEqual(s["tabs"]["y"] + s["tabs"]["h"], s["back"]["y"], (key, "the tabs run into the page", s))
        self.assertLessEqual(s["back"]["y"] + s["back"]["h"], s["head"]["y"], (key, "Back runs into the page's head", s))
        self.assertLessEqual(s["head"]["y"] + s["head"]["h"], s["list"]["y"], (key, "the page's head runs into the list", s))
        self.assertLessEqual(s["list"]["y"] + s["list"]["h"], s["footer"]["y"], (key, "the list runs into the footer", s))
        self.assertEqual(s["clipped"], [], (key, "texts cut short", s))
        # Play: in the full layout under the title, compact on Back's line at the right.
        p = s["play"]
        self.assertIsNotNone(p, (key, "no Play button", s))
        if s["compact"]:
            self.assertEqual((p["y"], p["h"]), (s["back"]["y"], s["back"]["h"]), (key, "Play is not on Back's line", s))
        else:
            self.assertGreaterEqual(p["y"], s["head"]["y"], (key, s))
            self.assertLessEqual(p["y"] + p["h"], s["head"]["y"] + s["head"]["h"], (key, s))
        self.assertLessEqual(p["x"] + p["w"], s["card"]["w"], (key, "Play runs off the card", s))
        # And drawn there: its accent fill, not the card behind it.
        f = self.found[key]
        if Image is not None and f["png"]:
            img = Image.open(f["png"]).convert("RGB")
            fill = img.getpixel((p["x"] + 4 * s["fontScale"] + 2, p["y"] + p["h"] // 2))
            card = img.getpixel((p["x"] - 6, p["y"] + p["h"] // 2))
            self.assertGreater(sum(abs(a - b) for a, b in zip(fill, card)), 120, (key, "Play is not drawn", fill, card))

    def test_rows_are_counted_with_their_spacing(self):
        # The list's own rows: 58 px apart by 8 at base 12, 48 by 7 at 10.
        for key in list(CASES) + list(LATE):
            s = self.state(key)
            self.assertEqual((s["rowH"], s["spacing"]), (48, 7) if key[1] == 10 else (58, 8), (key, s))
            self.assertEqual(s["rows"], whole_rows(s["list"]["h"], s["rowH"], s["spacing"]), (key, s))

    def test_the_full_layout_shows_fewer_than_four_rows_on_short_screens(self):
        # What the compact layout is for: 720, 810 and 900 at the default font,
        # 720 and 810 at base size 10.
        for key in ((720, None), (810, None), (900, None), (720, 10), (810, 10)):
            self.assertLess(self.state(key + ("never",))["rows"], 4, key)
        for key in ((1080, None), (1440, None), (900, 10), (1080, 10), (1440, 10)):
            self.assertGreaterEqual(self.state(key + ("never",))["rows"], 4, key)

    def test_auto_goes_compact_only_where_the_full_layout_shows_fewer_than_four_rows(self):
        for h in SCREENS:
            for base in BASES:
                a, n = self.state((h, base, "auto")), self.state((h, base, "never"))
                if n["rows"] >= 4:
                    # As before: the same card, the same places, the same rows.
                    self.assertFalse(a["compact"], ((h, base), a))
                    self.assertEqual((a["card"], a["hero"], a["tabs"], a["back"], a["head"], a["list"]),
                                     (n["card"], n["hero"], n["tabs"], n["back"], n["head"], n["list"]), (h, base))
                else:
                    self.assertGreaterEqual(a["rows"], MIN_ROWS.get((h, base), 4), ((h, base), a))
                    self.assertGreater(a["rows"], n["rows"], (h, base))
                    self.assertTrue(a["compact"], ((h, base), a, n))
                self.assertFits((h, base, "auto"), a)
                # Weighed on the full layout as it is, whatever is on screen now.
                self.assertEqual(a["fullChrome"], n["fullChrome"], (h, base))

    def test_a_song_starting_with_the_panel_open_is_weighed_too(self):
        for (h, base, _) in LATE:
            s, a = self.state((h, base, "late")), self.state((h, base, "auto"))
            self.assertEqual((s["compact"], s["fullChrome"], s["rows"]), (a["compact"], a["fullChrome"], a["rows"]), (h, base, s))

    def test_a_panel_made_before_its_window_does_not_crash_and_ends_the_same(self):
        for key in NOWIN:
            f = self.found[key]
            self.assertEqual(f["code"], 0, (key, "the shell died", f["code"], f["log"]))
            s, a = self.state(key), self.state((key[0], None, key[2][len("nowin-"):]))
            self.assertEqual((s["compact"], s["fullChrome"], s["rows"], s["card"], s["play"]),
                             (a["compact"], a["fullChrome"], a["rows"], a["card"], a["play"]), (key, s))

    def test_auto_is_the_default(self):
        for h in (810, 1440):
            for base in BASES:
                a, d = self.state((h, base, "auto")), self.state((h, base, None))
                self.assertEqual((d["compact"], d["card"], d["list"], d["rows"]), (a["compact"], a["card"], a["list"], a["rows"]), (h, base))

    def test_always_is_compact_on_every_screen(self):
        for h in SCREENS:
            for base in BASES:
                key = (h, base, "always")
                s = self.state(key)
                least = max(MIN_ROWS.get((h, base), 4), self.state((h, base, "never"))["rows"])
                self.assertGreaterEqual(s["rows"], least, (key, s))
                self.assertTrue(s["compact"], (key, s))
                self.assertFits(key, s)

    def test_never_keeps_the_full_layout(self):
        for h in SCREENS:
            for base in BASES:
                key = (h, base, "never")
                s = self.state(key)
                self.assertFalse(s["compact"], (key, s))
                self.assertFits(key, s)


if __name__ == "__main__":
    unittest.main()
