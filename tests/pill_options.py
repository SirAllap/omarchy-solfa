#!/usr/bin/env python3
"""Design study, not a test: render the closed bar pill in its look options.

Runs tests/qml/PillStyleScene.qml (the real BarWidget.qml) in a private Quickshell,
offscreen at 3x, on a light and on a dark bar stub, and prints the text contrast of
each look. Usage: pill_options.py OUT_DIR   (writes OUT_DIR/raw/<theme>-<style>.png and
OUT_DIR/contrast.json; the labelled sheet is composed by the caller).
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))


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


def over(top, under):
    a = top[3]
    return [top[i] * a + under[i] * (1 - a) for i in range(3)]


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


THEMES = {
    # Values from Omarchy's own themes: "white" (light) and "tokyo-night" (dark).
    "light": ('foreground = "#000000"\nbackground = "#ffffff"\naccent = "#6e6e6e"\n',
              '[bar]\nbackground = "#f5f5f5"\ntext = "#000000"\n[popups]\nbackground = "#ffffff"\ntext = "#000000"\n'),
    "dark": ('foreground = "#a9b1d6"\nbackground = "#1a1b26"\naccent = "#7aa2f7"\n',
             '[bar]\nbackground = "#13141c"\ntext = "#a9b1d6"\n[popups]\nbackground = "#1a1b26"\ntext = "#a9b1d6"\n'),
}


def write_theme(theme):
    d = os.path.join(os.environ["HOME"], ".local", "state", "omarchy", "current", "theme")
    os.makedirs(d, exist_ok=True)
    colors, shell = THEMES[theme]
    open(os.path.join(d, "colors.toml"), "w").write(colors)
    open(os.path.join(d, "shell.toml"), "w").write(shell)


def render(theme, out, workdir):
    write_theme(theme)
    cfg = os.path.join(workdir, "scene-" + theme)
    os.mkdir(cfg)
    for name, target in (("Ui", os.path.join(SHELL_DIR, "Ui")), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("SolfaBar.qml", os.path.join(ROOT, "BarWidget.qml")), ("Panel.qml", os.path.join(ROOT, "Panel.qml")),
                         ("shell.qml", os.path.join(HERE, "qml", "PillStyleScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR="3", QT_QPA_PLATFORMTHEME="", SOLFA_THEME=theme,
               SOLFA_COVER="file://" + os.path.join(workdir, "cover.png"), SOLFA_OUT_DIR=out, XDG_RUNTIME_DIR=workdir)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=90)
    m = re.search(r"PILL (\{.*\})", run.stdout + run.stderr)
    if not m:
        sys.exit("no PILL line:\n" + (run.stdout + run.stderr)[-2000:])
    return json.loads(m.group(1))


def main():
    out = os.path.abspath(sys.argv[1])
    raw = os.path.join(out, "raw")
    os.makedirs(raw, exist_ok=True)
    workdir = tempfile.mkdtemp(prefix="solfa-pill-")
    try:
        cover(os.path.join(workdir, "cover.png"))
        result = {}
        for theme in ("light", "dark"):
            info = render(theme, raw, workdir)
            for style in list(info):
                os.rename(os.path.join(raw, "bar-%s.png" % style), os.path.join(raw, "%s-%s.png" % (theme, style)))
                d = info[style]
                bg = d["bar"][:3]
                eff = over(d["fill"], bg)
                d["effective_fill"] = eff
                d["contrast"] = round(contrast(d["ink"][:3], eff), 2)
            result[theme] = info
        json.dump(result, open(os.path.join(out, "contrast.json"), "w"), indent=1)
        for theme, info in result.items():
            print(theme, {s: d["contrast"] for s, d in info.items()})
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


main()
