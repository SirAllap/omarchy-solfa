#!/usr/bin/env python3
"""Makes the PR screenshots of the Off state (#33) from the real QML, offscreen, at 2x.

Usage: python3 tests/bar_off_shots.py [--set before|after] [--src repo_dir] [out_dir]
  --set after (default): this tree. --set before: pass --src with a checkout of main, e.g.
  git worktree add --detach /path/main-shots main
out_dir defaults to mockups/bar-off. Renders tests/qml/BarOffShots.qml (the real bar widget and
the real Panel.qml) in a private Quickshell with an INVENTED song ("Glass Harbour", "The Quiet
Tides") and a generated gradient cover. Never touches the live desktop.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import argparse
import os
import shutil
import struct
import subprocess
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))


def gradient_png(path, size=256):
    """A warm diagonal gradient (amber to plum), written with the standard library only."""
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            t = (x + y) / (2.0 * (size - 1))
            r = int(245 + (110 - 245) * t)
            g = int(170 + (40 - 170) * t)
            b = int(95 + (85 - 95) * t)
            row += bytes((r, g, b))
        rows.append(bytes(row))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--set", choices=("before", "after"), default="after")
    parser.add_argument("--src", default=ROOT)
    parser.add_argument("out", nargs="?", default=os.path.join(ROOT, "mockups", "bar-off"))
    args = parser.parse_args()
    src_root = os.path.abspath(args.src)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    work = tempfile.mkdtemp(prefix="solfa-shots-")
    try:
        cfg = os.path.join(work, "scene")
        os.mkdir(cfg)
        ui = os.path.join(cfg, "UiStub")
        os.makedirs(ui)
        for name in os.listdir(os.path.join(SHELL_DIR, "Ui")):
            src = os.path.join(HERE, "qml", "stub", name) if name == "KeyboardPanel.qml" else os.path.join(SHELL_DIR, "Ui", name)
            os.symlink(src, os.path.join(ui, name))
        for name, target in (("Ui", ui), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                             ("views", os.path.join(src_root, "views")), ("lib", os.path.join(src_root, "lib")),
                             ("SolfaBar.qml", os.path.join(src_root, "BarWidget.qml")), ("SolfaPanel.qml", os.path.join(src_root, "Panel.qml")),
                             ("shell.qml", os.path.join(HERE, "qml", "BarOffShots.qml"))):
            os.symlink(target, os.path.join(cfg, name))
        # Omarchy's own tokyo-night values (dark), as test_bar_states.py uses.
        theme = os.path.join(os.environ["HOME"], ".local", "state", "omarchy", "current", "theme")
        os.makedirs(theme, exist_ok=True)
        with open(os.path.join(theme, "colors.toml"), "w") as f:
            f.write('foreground = "#a9b1d6"\nbackground = "#1a1b26"\naccent = "#7aa2f7"\n')
        with open(os.path.join(theme, "shell.toml"), "w") as f:
            f.write('[bar]\nbackground = "#13141c"\ntext = "#a9b1d6"\n[popups]\nbackground = "#1a1b26"\ntext = "#a9b1d6"\n')
        cover = os.path.join(work, "glass-harbour.png")
        gradient_png(cover)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR="2", QT_QPA_PLATFORMTHEME="",
                   QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl",  # the software backend draws no shader effects (shadow, blur, grey)
                   XDG_RUNTIME_DIR=work,
                   SOLFA_SHOT_OUT=out, SOLFA_SHOT_SET=args.set, SOLFA_SHOT_COVER=cover)
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        display = os.environ.get("WAYLAND_DISPLAY", "")
        if runtime and display and not os.path.isabs(display):
            env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
        run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                             capture_output=True, text=True, timeout=90)
        text = run.stdout + run.stderr
        shots = [l for l in text.splitlines() if "SHOT " in l]
        print(text if os.environ.get("SOLFA_SHOT_VERBOSE") else "\n".join(shots) if shots else text[-2000:])
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
