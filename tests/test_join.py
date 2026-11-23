#!/usr/bin/env python3
"""The join between the pill and the card is the same on the left and on the right.

Renders tests/qml/JoinScene.qml offscreen at fractional pill positions and widths and
at fractional display scales, mirrors the right half onto the left and compares pixel
by pixel. The largest difference must stay within 8/255. Set SOLFA_JOIN_OUT to a
folder to keep the 8x crops (left, and the mirrored right). Skips when the qml tool,
an OpenGL context or Pillow is missing.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import math
import os
import shutil
import subprocess
import tempfile
import unittest

try:
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover
    Image = None

HERE = os.path.dirname(os.path.abspath(__file__))
SCENE = os.path.join(HERE, "qml", "JoinScene.qml")
QML = os.environ.get("QML_TOOL", "/usr/lib/qt6/bin/qml")
SCALES = ("1", "1.25", "1.5", "2")
FRACTIONS = (0.0, 0.25, 0.5, 0.75)
MAX_DIFF = 8
HALF = 64   # logical px each side of the centre line that are compared


def render(workdir, scale, left, width, mode="line"):
    out = os.path.join(workdir, "j-%s-%s-%s-%s.ppm" % (scale, left, width, mode))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi",
               QSG_RHI_BACKEND="opengl", QT_SCALE_FACTOR=scale)
    subprocess.run([QML, os.path.join(workdir, "JoinScene.qml"), "--", out, str(left), str(width), mode],
                   env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    return out if os.path.exists(out) else None


def halves(img, scale, left, width):
    """The left crop and the right crop mirrored, about the pill's centre line."""
    s = float(scale)
    snap = lambda v: math.floor(v * s + 0.5) / s   # JS Math.round: halves go up
    c2 = round((snap(left) + snap(width) / 2) * s * 2)   # twice the centre column, in device px
    n = int(HALF * s)
    # Pixel k mirrors to c2 - 1 - k. Left crop: k in [lo, lo + n); right crop: the mirror of those.
    lo = (c2 - 1) // 2 - n + 1
    left_c = img.crop((lo, 0, lo + n, img.height))
    rlo = c2 - 1 - (lo + n - 1)
    right_c = img.crop((rlo, 0, rlo + n, img.height)).transpose(Image.FLIP_LEFT_RIGHT)
    return left_c, right_c


class JoinMirror(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if Image is None:
            raise unittest.SkipTest("Pillow is missing")
        if not os.access(QML, os.X_OK):
            raise unittest.SkipTest("Qt's qml tool is missing")
        cls.tmp = tempfile.mkdtemp(prefix="solfa-join.")
        root = os.path.dirname(HERE)
        os.makedirs(os.path.join(cls.tmp, "tests", "qml"))
        # Only the two files the scene needs: the lib folder's qmldir pulls in the shell's modules.
        os.makedirs(os.path.join(cls.tmp, "lib"))
        for f in ("Bridge.qml", "Pixel.js"):
            os.symlink(os.path.join(root, "lib", f), os.path.join(cls.tmp, "lib", f))
        cls.work = os.path.join(cls.tmp, "tests", "qml")
        shutil.copy(SCENE, cls.work)
        if render(cls.work, "1", 60, 83) is None:
            raise unittest.SkipTest("no offscreen OpenGL context for Qt Quick")
        cls.keep = os.environ.get("SOLFA_JOIN_OUT")
        if cls.keep:
            os.makedirs(cls.keep, exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_left_and_right_are_mirror_images(self):
        worst = 0
        for scale in SCALES:
            for frac in FRACTIONS:
                for wfrac in (0.0, 0.4):
                    left, width = 60 + frac, 83 + wfrac
                    with self.subTest(scale=scale, left=left, width=width):
                        out = render(self.work, scale, left, width)
                        self.assertIsNotNone(out, "the scene did not render")
                        img = Image.open(out).convert("RGB")
                        a, b = halves(img, scale, left, width)
                        diff = max(max(px) for px in ImageChops.difference(a, b).getdata())
                        worst = max(worst, diff)
                        if self.keep:
                            case = "s%s-x%.2f-w%.1f" % (scale, left, width)
                            z = 8
                            ca, cb = (c.crop((0, 0, c.width, c.height)).resize((c.width * z, c.height * z), Image.NEAREST)
                                      for c in (a, b))
                            both = Image.new("RGB", (ca.width * 2 + 8, ca.height), "#ff00ff")
                            both.paste(ca, (0, 0)); both.paste(cb, (ca.width + 8, 0))
                            both.save(os.path.join(self.keep, "join3-%s.png" % case))
                        self.assertLessEqual(diff, MAX_DIFF, "left and mirrored right differ by %d/255" % diff)
        print("JOIN max diff %d/255" % worst)


if __name__ == "__main__":
    unittest.main()
