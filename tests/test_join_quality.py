#!/usr/bin/env python3
"""The join's two necks are smooth (anti-aliased) and the same on both sides.

Renders tests/qml/JoinScene.qml offscreen at scales 1, 1.25, 1.5 and 2 and at fractional
pill positions, then asserts:
  1. left vs mirrored right differ by at most 8/255 (the outlined picture);
  2. each neck's edge is anti-aliased: the number of edge pixels whose coverage is
     strictly between 0.1 and 0.9 is at least 0.8 x the arc's steps (its radius in device
     pixels, one soft pixel per step); a stair-stepped edge has almost none;
  3. the metric can tell: the same scene drawn with the aliased geometry renderer must
     fail check 2, so a pass means something.
Skips when the qml tool, an OpenGL context or Pillow is missing.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import math
import os
import shutil
import tempfile
import unittest

import test_join as J

try:
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover
    Image = None

R = 16                      # the neck's design radius (logical px), as in Panel.qml
PILL_TOP, PILL_BOTTOM, CARD_TOP = 6, 30, 33   # JoinScene.qml
BG_G, FILL_G = 0xB6, 0xF1   # green channel of the wallpaper and of the shape
AA_LO, AA_HI, AA_SHARE = 0.1, 0.9, 0.8
FRACTIONS = (0.0, 0.25, 0.5, 0.75)


def snap(v, s):
    return math.floor(v * s + 0.5) / s


def aa_edge_pixels(img, scale, left):
    """(count, arc length) of partly covered pixels along the left neck."""
    s = float(scale)
    x0 = int((snap(left, s) - R) * s)
    x1 = int(snap(left, s) * s)
    y0 = int((CARD_TOP - R) * s) + 2          # below the pill's rounded top
    y1 = int(CARD_TOP * s)
    px = img.convert("RGB").load()
    n = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            a = (px[x, y][1] - BG_G) / (FILL_G - BG_G)
            if AA_LO < a < AA_HI:
                n += 1
    # A 1-px soft edge has about one partly covered pixel per pixel step along the arc's dominant
    # axis, and that is r device px (measured 1.1 r when anti-aliased, 0 when not): the expected
    # count is r_dev, not the 1.57 r of the arc's true length.
    return n, R * s


class JoinQuality(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if Image is None:
            raise unittest.SkipTest("Pillow is missing")
        if not os.access(J.QML, os.X_OK):
            raise unittest.SkipTest("Qt's qml tool is missing")
        cls.tmp = tempfile.mkdtemp(prefix="solfa-joinq.")
        root = os.path.dirname(J.HERE)
        os.makedirs(os.path.join(cls.tmp, "tests", "qml"))
        os.makedirs(os.path.join(cls.tmp, "lib"))
        for f in ("Bridge.qml", "Pixel.js"):
            os.symlink(os.path.join(root, "lib", f), os.path.join(cls.tmp, "lib", f))
        cls.work = os.path.join(cls.tmp, "tests", "qml")
        shutil.copy(J.SCENE, cls.work)
        if J.render(cls.work, "1", 60, 83) is None:
            raise unittest.SkipTest("no offscreen OpenGL context for Qt Quick")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_mirror(self):
        for scale in J.SCALES:
            for frac in FRACTIONS:
                left, width = 60 + frac, 83 + frac / 2
                with self.subTest(scale=scale, left=left, width=width):
                    img = Image.open(J.render(self.work, scale, left, width)).convert("RGB")
                    a, b = J.halves(img, scale, left, width)
                    diff = max(max(p) for p in ImageChops.difference(a, b).getdata())
                    self.assertLessEqual(diff, J.MAX_DIFF)

    def test_edges_are_antialiased(self):
        for scale in J.SCALES:
            for frac in FRACTIONS:
                left = 60 + frac
                with self.subTest(scale=scale, left=left):
                    img = Image.open(J.render(self.work, scale, left, 83, "plain"))
                    n, length = aa_edge_pixels(img, scale, left)
                    self.assertGreaterEqual(n, AA_SHARE * length,
                        "%d soft edge pixels on an arc of %.0f steps: stair-stepped" % (n, length))

    def test_mirror_check_catches_the_old_placement(self):
        # ef99967 snapped the join to whole logical px while the pill sat at a fractional device
        # px: the mirror check must see that (scene mode "legacy").
        worst = 0
        for scale in ("1.25", "1.5"):
            for frac in FRACTIONS:
                left, width = 60 + frac, 83 + frac / 2
                img = Image.open(J.render(self.work, scale, left, width, "legacy")).convert("RGB")
                c2 = round((left + width / 2) * float(scale) * 2)
                n = int(J.HALF * float(scale))
                lo = (c2 - 1) // 2 - n + 1
                rlo = c2 - 1 - (lo + n - 1)
                a = img.crop((lo, 0, lo + n, img.height))
                b = img.crop((rlo, 0, rlo + n, img.height)).transpose(Image.FLIP_LEFT_RIGHT)
                worst = max(worst, max(max(p) for p in ImageChops.difference(a, b).getdata()))
        self.assertGreater(worst, J.MAX_DIFF, "the old placement passed the mirror check")

    def test_metric_catches_aliased_edges(self):
        for scale in ("1.25", "2"):
            with self.subTest(scale=scale):
                img = Image.open(J.render(self.work, scale, 60.25, 83, "aliased"))
                n, length = aa_edge_pixels(img, scale, 60.25)
                self.assertLess(n, AA_SHARE * length, "the aliased control passed: the metric is blind")


if __name__ == "__main__":
    unittest.main()
