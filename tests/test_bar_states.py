#!/usr/bin/env python3
"""The bar pill reads on every bar look: opaque, translucent (glassy) and transparent (none),
light and dark, at rest, hovered and open, over a pink wallpaper stub.

Renders tests/qml/BarStatesScene.qml (the real BarWidget.qml) in a private Quickshell, offscreen
at 3x, 12 times over: bar-<theme>-<alpha>-<state>.png into $SOLFA_BAR_STATES_OUT (default: a
throwaway dir; set it to keep the pictures) and, with ImageMagick, the sheet bar-states.png.
Prints the text contrast of each state, worst case over a white, a black and a mid-pink
wallpaper. Asserts the at-rest pill keeps >= 4.5:1 on every bar look. Skips when Quickshell,
the Omarchy shell or a desktop session is missing.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))
MAGICK = shutil.which("magick")
THEMES = {
    # Omarchy's own "white" (light) and "tokyo-night" (dark) values.
    "light": ('foreground = "#000000"\nbackground = "#ffffff"\naccent = "#6e6e6e"\n',
              '[bar]\nbackground = "#f5f5f5"\ntext = "#000000"\n[popups]\nbackground = "#ffffff"\ntext = "#000000"\n'),
    "dark": ('foreground = "#a9b1d6"\nbackground = "#1a1b26"\naccent = "#7aa2f7"\n',
             '[bar]\nbackground = "#13141c"\ntext = "#a9b1d6"\n[popups]\nbackground = "#1a1b26"\ntext = "#a9b1d6"\n'),
}
MODES = (("opaque", "opaque"), ("glassy", "translucent"), ("none", "transparent"))
STATES = ("rest", "hover", "open")
WALLPAPERS = {"white": (1, 1, 1), "black": (0, 0, 0), "pink": (0.91, 0.44, 0.63)}
MIN_REST = 4.5


def cover(path):
    w = h = 96
    rows = b"".join(b"\0" + b"".join(bytes((40 + x * 2 // 3, 60 + y // 2, 170 - x // 2)) for x in range(w)) for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def lin(c):
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])


def over(top, a, under):
    return [top[i] * a + under[i] * (1 - a) for i in range(3)]


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def worst_contrast(d):
    """Ink against the pill (or, with no fill, the bar) over each wallpaper; the lowest."""
    out = {}
    for name, wall in WALLPAPERS.items():
        under = over(d["bar"][:3], d["paintAlpha"], wall)
        under = over(d["fill"][:3], d["fill"][3], under)
        out[name] = contrast(d["ink"][:3], under)
    return min(out.values()), out


def write_theme(theme):
    d = os.path.join(os.environ["HOME"], ".local", "state", "omarchy", "current", "theme")
    os.makedirs(d, exist_ok=True)
    colors, shell = THEMES[theme]
    open(os.path.join(d, "colors.toml"), "w").write(colors)
    open(os.path.join(d, "shell.toml"), "w").write(shell)


def render(theme, mode, out, workdir):
    write_theme(theme)
    cfg = os.path.join(workdir, "scene-%s-%s" % (theme, mode))
    ui = os.path.join(cfg, "Ui")
    os.makedirs(ui)
    shell_ui = os.path.join(SHELL_DIR, "Ui")
    for name in os.listdir(shell_ui):
        src = os.path.join(HERE, "qml", "stub", name) if name == "KeyboardPanel.qml" else os.path.join(shell_ui, name)
        os.symlink(src, os.path.join(ui, name))
    for name, target in (("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("SolfaBar.qml", os.path.join(ROOT, "BarWidget.qml")), ("Panel.qml", os.path.join(ROOT, "Panel.qml")),
                         ("shell.qml", os.path.join(HERE, "qml", "BarStatesScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR="3", QT_QPA_PLATFORMTHEME="",
               SOLFA_THEME=theme, SOLFA_MODE=mode, SOLFA_COVER="file://" + os.path.join(workdir, "cover.png"),
               SOLFA_OUT_DIR=out, XDG_RUNTIME_DIR=workdir)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=90)
    m = re.search(r"STATES (\{.*\})", run.stdout + run.stderr)
    return json.loads(m.group(1)) if m else None, (run.stdout + run.stderr)[-2500:]


def sheet(out, results):
    """bar-states.png: a row per theme and bar look, a column per state, the contrast under each."""
    if not MAGICK:
        return None
    cells = []
    for theme in THEMES:
        for _mode, tag in MODES:
            for state in STATES:
                r = results[(theme, tag)][state]
                cells += ["-label", "%s %s %s  %.1f:1" % (theme, tag, state, r["worst"]),
                          os.path.join(out, "bar-%s-%s-%s.png" % (theme, tag, state))]
    path = os.path.join(out, "bar-states.png")
    cmd = [MAGICK, "montage"] + cells + ["-tile", "3x", "-geometry", "+14+10", "-background", "#26262c",
                                         "-fill", "#e8e8ee", "-pointsize", "22", path]
    subprocess.run(cmd, check=True)
    return path


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class BarStates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-barstates-")
        cls.out = os.environ.get("SOLFA_BAR_STATES_OUT") or os.path.join(cls.workdir, "out")
        os.makedirs(cls.out, exist_ok=True)
        cover(os.path.join(cls.workdir, "cover.png"))
        cls.results = {}
        cls.logs = {}
        for theme in THEMES:
            for mode, tag in MODES:
                info, log = render(theme, mode, cls.out, cls.workdir)
                cls.logs[(theme, tag)] = log
                if info:
                    for state, d in info.items():
                        d["worst"], d["each"] = worst_contrast(d)
                    cls.results[(theme, tag)] = info
        if len(cls.results) == 6:
            cls.sheet = sheet(cls.out, cls.results)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def test_every_state_rendered(self):
        for theme in THEMES:
            for _mode, tag in MODES:
                info = self.results.get((theme, tag))
                self.assertIsNotNone(info, "no STATES line for %s %s:\n%s" % (theme, tag, self.logs[(theme, tag)]))
                self.assertEqual(sorted(info), sorted(STATES))
                for state in STATES:
                    self.assertTrue(os.path.getsize(os.path.join(self.out, "bar-%s-%s-%s.png" % (theme, tag, state))) > 500)

    def test_rest_reads_on_every_bar(self):
        low = 99
        for (theme, tag), info in sorted(self.results.items()):
            for state in STATES:
                d = info[state]
                print("contrast %-5s %-11s %-5s %5.2f  (white %.2f black %.2f pink %.2f)" % (
                    theme, tag, state, d["worst"], d["each"]["white"], d["each"]["black"], d["each"]["pink"]))
            low = min(low, info["rest"]["worst"])
            self.assertGreaterEqual(info["rest"]["worst"], MIN_REST, "%s %s at rest" % (theme, tag))
        print("lowest at-rest contrast: %.2f" % low)

    def test_backdrop_only_when_see_through(self):
        for (theme, tag), info in self.results.items():
            rest = info["rest"]
            if tag == "opaque":
                self.assertEqual(rest["fill"][3], 0, "%s opaque bar: no backdrop" % theme)
            else:
                self.assertGreaterEqual(rest["fill"][3], 0.72 - 1e-3, "%s %s: backdrop alpha" % (theme, tag))  # Qt colours are float32

    def test_hover_and_open_are_the_pills_own(self):
        for (theme, tag), info in self.results.items():
            self.assertTrue(info["hover"]["hot"], "%s %s hover not hot" % (theme, tag))
            self.assertTrue(info["open"]["opened"], "%s %s did not open" % (theme, tag))
            self.assertFalse(info["rest"]["hot"], "%s %s rest is hot" % (theme, tag))


if __name__ == "__main__":
    unittest.main(verbosity=2)
