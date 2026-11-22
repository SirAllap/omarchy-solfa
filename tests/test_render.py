#!/usr/bin/env python3
"""The bar cover sits in the middle of its ring at every bar size and scale.

Renders tests/qml/BarCoverScene.qml offscreen with Qt's own `qml` tool on
OpenGL (MultiEffect needs a GPU backend), a red picture in a green ring,
and compares where the red and the green are centred. Skips when the tool
or an OpenGL context is not available.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SCENE = os.path.join(HERE, "qml", "BarCoverScene.qml")
QML = os.environ.get("QML_TOOL", "/usr/lib/qt6/bin/qml")
SCALES = ("1", "1.25", "1.5", "2")
BAR_SIZES = (22, 26, 30, 34)
# The antialiased edges of a ring and a circle drawn by different
# renderers may differ by a fraction of a pixel; the old bug was 0.8 to 1.4.
TOLERANCE = 0.3


def write_png(path, w, h, colour_at):
    raw = b"".join(b"\0" + b"".join(colour_at(x, y) for x in range(w)) for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


RED, BLUE = b"\xff\x00\x00", b"\x00\x00\xff"


def pictures(workdir):
    """red.png, and a wide and a tall picture: a red square in the middle,
    blue beyond it. Cropped the way a cover must be, no blue shows."""
    write_png(os.path.join(workdir, "red.png"), 64, 64, lambda x, y: RED)
    write_png(os.path.join(workdir, "wide.png"), 160, 90, lambda x, y: RED if 35 <= x < 125 else BLUE)
    write_png(os.path.join(workdir, "tall.png"), 90, 160, lambda x, y: RED if 35 <= y < 125 else BLUE)
    # Red runs 40..240 from left to right; blue marks the picture.
    write_png(os.path.join(workdir, "ramp.png"), 256, 256, lambda x, y: bytes((40 + x * 200 // 255, 0, 255)))


def read_ppm(path):
    data = open(path, "rb").read()
    magic, w, h, _maxval, pixels = data.split(maxsplit=4)
    assert magic == b"P6"
    return int(w), int(h), pixels


def centre(w, h, pixels, weight):
    sx = sy = total = 0
    for y in range(h):
        for x in range(w):
            i = 3 * (y * w + x)
            v = weight(pixels[i], pixels[i + 1], pixels[i + 2])
            sx += v * x
            sy += v * y
            total += v
    return (sx / total, sy / total) if total else None


def render(workdir, scale, bar_size, picture="red.png", dim=False):
    out = os.path.join(workdir, "out-%s-%d-%s%s.ppm" % (scale, bar_size, picture, "-dim" if dim else ""))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi",
               QSG_RHI_BACKEND="opengl", QT_SCALE_FACTOR=scale)
    subprocess.run([QML, os.path.join(workdir, "BarCoverScene.qml"), "--", str(bar_size), out, picture, "dim" if dim else ""],
                   env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    return out if os.path.exists(out) else None


class BarCoverCentred(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.access(QML, os.X_OK):
            raise unittest.SkipTest("Qt's qml tool is missing")
        cls.tmp = tempfile.mkdtemp(prefix="solfa-render.")
        # The scene imports ../../views: rebuild that layout around a copy.
        root = os.path.dirname(HERE)
        os.makedirs(os.path.join(cls.tmp, "tests", "qml"))
        for d in ("views", "lib"):
            os.symlink(os.path.join(root, d), os.path.join(cls.tmp, d))
        cls.work = os.path.join(cls.tmp, "tests", "qml")
        shutil.copy(SCENE, cls.work)
        pictures(cls.work)
        if render(cls.work, "1", 26) is None:
            raise unittest.SkipTest("no offscreen OpenGL context for Qt Quick")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_cover_is_centred_in_ring(self):
        for scale in SCALES:
            for bar_size in BAR_SIZES:
                for dim in (False, True):
                    with self.subTest(scale=scale, bar_size=bar_size, paused=dim):
                        out = render(self.work, scale, bar_size, dim=dim)
                        self.assertIsNotNone(out, "the scene did not render")
                        w, h, px = read_ppm(out)
                        red = centre(w, h, px, lambda r, g, b: max(0, r - g))
                        ring = centre(w, h, px, lambda r, g, b: max(0, g - r))
                        self.assertIsNotNone(red, "no cover drawn")
                        self.assertIsNotNone(ring, "no ring drawn")
                        dx, dy = red[0] - ring[0], red[1] - ring[1]
                        self.assertLessEqual(abs(dx), TOLERANCE, "cover off by %.2f px across" % dx)
                        self.assertLessEqual(abs(dy), TOLERANCE, "cover off by %.2f px down" % dy)

    def test_wide_and_tall_pictures_are_cropped_to_their_middle(self):
        for scale in SCALES:
            for picture in ("wide.png", "tall.png"):
                with self.subTest(scale=scale, picture=picture):
                    out = render(self.work, scale, 30, picture)
                    self.assertIsNotNone(out, "the scene did not render")
                    w, h, px = read_ppm(out)
                    blue = sum(1 for i in range(0, len(px), 3) if px[i + 2] > 100 and px[i] < 100)
                    red = sum(1 for i in range(0, len(px), 3) if px[i] > 100 and px[i + 1] < 100)
                    slot = round(30 * 0.78)
                    radius = (slot - 2 * max(2, round(30 * 0.1))) / 2 * float(scale)
                    self.assertEqual(blue, 0, "the picture's sides show: stretched or not centred")
                    self.assertGreater(red, 0.85 * 3.14159 * radius * radius, "the circle is not filled")


    def test_square_picture_is_not_zoomed(self):
        # A cover zoomed in shows only the middle of the ramp; the whole
        # picture shows it from end to end.
        for scale in SCALES:
            with self.subTest(scale=scale):
                out = render(self.work, scale, 34, "ramp.png")
                self.assertIsNotNone(out, "the scene did not render")
                w, h, px = read_ppm(out)
                reds = [px[i] for i in range(0, len(px), 3) if px[i + 2] > 240 and px[i + 1] < 20]
                self.assertTrue(reds, "no cover drawn")
                self.assertLessEqual(min(reds), 60, "the left edge of the picture is cut off")
                self.assertGreaterEqual(max(reds), 220, "the right edge of the picture is cut off")


if __name__ == "__main__":
    unittest.main(verbosity=1)
