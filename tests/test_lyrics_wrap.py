#!/usr/bin/env python3
"""Lyrics lines wrap instead of being cut short with "...".

Renders tests/qml/LyricsWrapScene.qml (the real Panel.qml on its Lyrics tab,
a fake service answering with invented lyrics, some lines wider than the
panel) in a private Quickshell, offscreen, at the shell's default font and at
base size 10. Synced lyrics: at several current lines no line is truncated,
the long ones wrap to more than one line and fit their row, rows never overlap,
a row keeps its height whether it is current or not (a line that wraps only at
the current line's bigger size included), the current row sits in the middle
of the list (the first and the last too, and after far jumps in a list of 120 lines), and a click covers the whole row.
Plain lyrics: no line is truncated, the long ones wrap. The shell's
KeyboardPanel is swapped for tests/qml/stub/KeyboardPanel.qml, a plain card:
nothing is mapped on the desktop. Skips when Quickshell, the Omarchy shell or
a desktop session is missing.
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

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))

# Rows of the scene's lyrics (tests/qml/LyricsWrapScene.qml): the first, one
# wrapping to 3 lines, the one that wraps only at the current line's size, one
# word wider than the panel, and the last.
FIRST, LONG, BORDER, WORD, LAST = 0, 3, 4, 8, 11
TOLERANCE = 1.0  # px: the current row's middle against the list's middle


def no_core():
    # A crash leaves no core dump: the kernel gives up on one at a limit of
    # 1 byte, before any core handler runs (0 still reaches systemd-coredump).
    resource.setrlimit(resource.RLIMIT_CORE, (1, 1))


def render(workdir, mode, base=None):
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
                         ("shell.qml", os.path.join(HERE, "qml", "LyricsWrapScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    # A home of its own for each render, with the shell's font size if asked.
    home = os.path.join(workdir, "home")
    os.makedirs(os.path.join(home, ".config", "omarchy"))
    if base:
        with open(os.path.join(home, ".config", "omarchy", "shell.toml"), "w") as f:
            f.write("[font]\nbase-size = %d\n" % base)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR="1", XDG_RUNTIME_DIR=workdir, HOME=home,
               SOLFA_LYRICS=mode, QS_DISABLE_CRASH_HANDLER="1")
    env.pop("SOLFA_SCENE_OUT", None)
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=90, preexec_fn=no_core)
    log = run.stdout + run.stderr
    return {"stops": [json.loads(m) for m in re.findall(r"STATE (\{.*\})", log)], "log": log[-3000:]}


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class LyricsWrap(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-lyricswrap-")
        cases = [(mode, base) for mode in ("timed", "plain", "long") for base in (None, 10)]

        def one(case):
            w = os.path.join(cls.workdir, "-".join(str(c) for c in case))
            os.makedirs(w)
            return case, render(w, *case)

        with ThreadPoolExecutor(max_workers=4) as pool:
            cls.found = dict(pool.map(one, cases))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def stops(self, mode, base, n):
        f = self.found[(mode, base)]
        self.assertEqual(len(f["stops"]), n, "the scene did not render (%s, %s):\n%s" % (mode, base, f["log"]))
        return f["stops"]

    def synced(self, base):
        return self.stops("timed", base, 8)

    @staticmethod
    def row(stop, i):
        return next((r for r in stop["rows"] if r["i"] == i), None)

    def test_no_synced_line_is_truncated(self):
        for base in (None, 10):
            for s in self.synced(base):
                self.assertGreater(len(s["rows"]), 5, (base, s))
                self.assertEqual([r["i"] for r in s["rows"] if r["truncated"]], [], (base, s["stop"], "truncated lines"))

    def test_long_synced_lines_wrap_and_fit_their_row(self):
        for base in (None, 10):
            for s in self.synced(base):
                for i in (LONG, WORD):
                    r = self.row(s, i)
                    if r is None:
                        continue
                    self.assertGreater(r["lineCount"], 1, (base, s["stop"], i, r))
                    # Not cut by the row's edge: the text fits inside it.
                    self.assertLessEqual(r["painted"], r["h"], (base, s["stop"], i, r))
                for r in s["rows"]:
                    self.assertLessEqual(r["painted"], r["h"], (base, s["stop"], r))

    def test_short_rows_keep_their_height(self):
        for base in (None, 10):
            for s in self.synced(base):
                r = self.row(s, 1)
                if r:
                    self.assertEqual(r["h"], 46, (base, s["stop"], r))

    def test_rows_do_not_overlap_and_the_click_covers_the_row(self):
        for base in (None, 10):
            for s in self.synced(base):
                rows = sorted(s["rows"], key=lambda r: r["i"])
                for a, b in zip(rows, rows[1:]):
                    if b["i"] == a["i"] + 1:
                        self.assertLessEqual(a["y"] + a["h"], b["y"] + 0.5, (base, s["stop"], a, b))
                for r in rows:
                    self.assertEqual(r["mouseH"], r["h"], (base, s["stop"], r))

    def test_a_row_does_not_change_height_when_it_turns_current(self):
        # The row that wraps only at the current line's size: 1 line, then 2,
        # in a row that stays as tall as it was.
        for base in (None, 10):
            stops = self.synced(base)
            heights = {r["h"] for r in (self.row(s, BORDER) for s in stops) if r}
            self.assertEqual(len(heights), 1, (base, heights))
            away = self.row(stops[0], BORDER)
            current = self.row(next(s for s in stops if s["line"] == BORDER), BORDER)
            # At the default font it is 1 line, then 2 (at base size 10 the
            # panel is narrower and both wrap).
            self.assertEqual((away["lineCount"], current["lineCount"]), (1, 2) if base is None else (2, 2), (base, away, current))
            self.assertGreater(away["h"], 46, (base, away))

    def test_the_current_row_is_in_the_middle(self):
        for base in (None, 10):
            for s in self.synced(base):
                r = self.row(s, s["line"])
                self.assertIsNotNone(r, (base, s))
                self.assertAlmostEqual(r["y"] + r["h"] / 2, s["listH"] / 2, delta=TOLERANCE, msg=(base, s["stop"], s["line"], r, s["listH"]))
        stops = self.synced(None)
        self.assertIn(FIRST, [s["line"] for s in stops])
        self.assertIn(LAST, [s["line"] for s in stops])

    def test_far_jumps_in_a_long_list_end_centred_and_clear(self):
        # 120 mixed lines (short, empty, wrapping at 18 px, at 22 px only, 2 and
        # 3 rows): 3 -> 100, 100 -> 5, the last line, the first, 60. Measured
        # after the 320 ms move (the scene waits 900 ms at each stop).
        for base in (None, 10):
            stops = self.stops("long", base, 6)
            self.assertEqual([s["line"] for s in stops], [3, 100, 5, 119, 0, 60])
            for s in stops:
                r = self.row(s, s["line"])
                self.assertIsNotNone(r, (base, s["stop"], "the current row is not built"))
                self.assertAlmostEqual(r["y"] + r["h"] / 2, s["listH"] / 2, delta=TOLERANCE, msg=(base, s["stop"], s["line"], r, s["listH"]))
                self.assertEqual([x["i"] for x in s["rows"] if x["truncated"]], [], (base, s["stop"]))
                rows = sorted(s["rows"], key=lambda x: x["i"])
                for a, b in zip(rows, rows[1:]):
                    if b["i"] == a["i"] + 1:
                        self.assertLessEqual(a["y"] + a["h"], b["y"] + 0.5, (base, s["stop"], a, b))
                for x in rows:
                    self.assertLessEqual(x["painted"], x["h"], (base, s["stop"], x))
                    self.assertGreaterEqual(x["h"], 46, (base, s["stop"], x))

    def test_no_plain_line_is_truncated(self):
        for base in (None, 10):
            (s,) = self.stops("plain", base, 1)
            self.assertGreater(len(s["texts"]), 8, (base, s))
            self.assertEqual([t["i"] for t in s["texts"] if t["truncated"]], [], (base, "truncated lines", s))
            long_lines = [t for t in s["texts"] if t["text"].startswith(("Every window", "Supercalifra", "Tidal lights"))]
            self.assertEqual(len(long_lines), 3, (base, s))
            for t in long_lines:
                self.assertGreater(t["lineCount"], 1, (base, t))
                self.assertLessEqual(t["painted"], t["h"] + 1, (base, t))


if __name__ == "__main__":
    unittest.main()
