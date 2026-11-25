#!/usr/bin/env python3
"""barFlat: at rest the bar widget is bar text, like the shell's own widgets.

Renders tests/qml/BarStatesScene.qml (the real BarWidget.qml, through
tests/test_bar_states.py's harness) on a transparent and an opaque bar, at
rest, hovered and open, with barFlat on (the setting in the widget's entry),
with it set to false, and with the entry saying nothing (the default). At rest with
barFlat: no fill and no outline, the bar's font and text colour. Hovered and
open: the same pill as without barFlat. The widget keeps one width in every
state. By default, and with barFlat false, nothing changes: the rest look is
upstream's, state by state the same as with the setting false (and
test_bar_states.py, which does not set it, holds for it). Set SOLFA_BAR_FLAT_OUT to keep the pictures.
Skips when Quickshell, the Omarchy shell or a desktop session is missing.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import os
import shutil
import tempfile
import unittest

import test_bar_states as bs

MODES = ("none", "opaque")
NAMES = {"1": "flat", "0": "pill", "": "default"}


def close(a, b):
    return all(abs(x - y) < 0.004 for x, y in zip(a, b))


@unittest.skipUnless(bs.QS and os.path.isdir(os.path.join(bs.SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class BarFlat(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-barflat-")
        keep = os.environ.get("SOLFA_BAR_FLAT_OUT")
        cls.results, cls.logs = {}, {}
        for flat in ("1", "0", ""):
            # One scene dir per look: the harness names its dirs by theme and bar look only.
            work = os.path.join(cls.workdir, NAMES[flat])
            os.makedirs(work)
            bs.cover(os.path.join(work, "cover.png"))
            for mode in MODES:
                out = os.path.join(keep, NAMES[flat]) if keep else os.path.join(work, "out-" + mode)
                os.makedirs(out, exist_ok=True)
                if flat:
                    os.environ["SOLFA_BAR_FLAT"] = flat
                try:
                    cls.results[(flat, mode)], cls.logs[(flat, mode)] = bs.render("dark", mode, out, work)
                finally:
                    os.environ.pop("SOLFA_BAR_FLAT", None)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def states(self, flat, mode):
        r = self.results[(flat, mode)]
        self.assertIsNotNone(r, "the scene did not render:\n" + self.logs[(flat, mode)])
        return r

    def test_at_rest_it_is_bar_text_no_pill(self):
        for mode in MODES:
            rest = self.states("1", mode)["rest"]
            self.assertTrue(rest["flat"])
            self.assertEqual(rest["fill"][3], 0, (mode, "no fill"))
            self.assertFalse(rest["outlined"], mode)
            self.assertTrue(close(rest["ink"], rest["barInk"]), (mode, "the bar's text colour", rest["ink"], rest["barInk"]))
            self.assertEqual(rest["family"], rest["barFamily"], (mode, "the bar's font"))

    def test_hover_and_open_keep_the_pill(self):
        for mode in MODES:
            flat, pill = self.states("1", mode), self.states("0", mode)
            for state in ("hover", "open"):
                self.assertTrue(close(flat[state]["fill"], pill[state]["fill"]), (mode, state, flat[state]["fill"], pill[state]["fill"]))
                self.assertTrue(close(flat[state]["ink"], pill[state]["ink"]), (mode, state))

    def test_one_width_in_every_state(self):
        for mode in MODES:
            s = self.states("1", mode)
            self.assertEqual(len({s[state]["width"] for state in ("rest", "hover", "open")}), 1, (mode, [s[x]["width"] for x in s]))

    def test_without_it_the_rest_look_is_upstreams(self):
        rest = self.states("0", "none")["rest"]
        self.assertFalse(rest["flat"])
        self.assertGreater(rest["fill"][3], 0, "the backdrop on a see-through bar")
        self.assertNotEqual(rest["family"], rest["barFamily"])

    def test_it_is_off_by_default(self):
        for mode in MODES:
            default, off = self.states("", mode), self.states("0", mode)
            for state in ("rest", "hover", "open"):
                self.assertFalse(default[state]["flat"], (mode, state))
                self.assertEqual(default[state], off[state], (mode, state))

    def test_the_width_is_the_same_with_the_setting_unset_in_every_state(self):
        # The pill's minimum width stays with the setting off: the widths are main's.
        for mode in MODES:
            s = self.states("", mode)
            self.assertEqual(len({s[state]["width"] for state in ("rest", "hover", "open")}), 1, (mode, [s[x]["width"] for x in s]))


if __name__ == "__main__":
    unittest.main()
