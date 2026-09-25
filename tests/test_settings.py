#!/usr/bin/env python3
"""Settings: the gear reaches it, and the keyboard walk works end to end.

Renders tests/qml/SettingsScene.qml (a real BrandCorner with the gear, and
the real SettingsView driven by move()/change()/act()/switchColumn() against
a fake service that records every call) offscreen, like
tests/test_hit_targets.py, and reads its "STATE {...}"/"CLICKS {...}" lines.
Skips when Quickshell, the Omarchy shell or a desktop session is missing.
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


def render(workdir):
    cfg = os.path.join(workdir, "scene")
    os.mkdir(cfg)
    for name, target in (("Ui", os.path.join(SHELL_DIR, "Ui")), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("shell.qml", os.path.join(HERE, "qml", "SettingsScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    out1 = os.path.join(workdir, "settings-sound.png")
    out2 = os.path.join(workdir, "settings-advanced.png")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", SOLFA_SCENE_OUT=out1, SOLFA_SCENE_OUT2=out2,
               XDG_RUNTIME_DIR=workdir)
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=60)
    found = {}
    for key in ("STATE", "CLICKS", "MOUSE"):
        m = re.search(key + r" (\{.*\})", run.stdout + run.stderr)
        found[key] = json.loads(m.group(1)) if m else None
    found["out1"] = out1 if os.path.exists(out1) else None
    found["out2"] = out2 if os.path.exists(out2) else None
    found["log"] = run.stdout + run.stderr
    return found


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class SettingsKeyboard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp(prefix="solfa-settings-")
        cls.found = render(cls.workdir)
        cls.state, cls.clicks, cls.mouse = cls.found["STATE"], cls.found["CLICKS"], cls.found["MOUSE"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def setUp(self):
        self.assertIsNotNone(self.state, "the scene did not render: " + self.found["log"][-800:])

    def test_the_gear_is_a_real_hit_target_next_to_power(self):
        gear = self.state["gear"]
        self.assertIsNotNone(gear)
        self.assertGreaterEqual(min(gear["w"], gear["h"]), 28)
        self.assertEqual(gear["tooltip"], "Settings")

    def test_clicking_the_gear_and_the_back_label_both_fire(self):
        self.assertEqual(self.clicks["gearClicked"], 1)
        self.assertEqual(self.clicks["backRequested"], 1)
        self.assertTrue(self.state["backHitOk"])

    def test_tab_and_up_down_move_the_nav_cursor_across_sections(self):
        self.assertEqual(self.state["initial"], {"section": "account", "column": "content", "cursor": 0})
        self.assertEqual(self.state["navSection"], "bar")
        self.assertEqual(self.state["soundSection"], "sound")
        self.assertEqual(self.state["aboutSection"], "about")

    def test_left_right_toggles_a_bool_row_and_saves_it(self):
        self.assertEqual(self.state["barToggleSaved"], ["barControls", False])

    def test_equalizer_master_toggle_saves_before_the_preset_row(self):
        self.assertEqual(self.state["eqEnabledAfterToggle"], True)

    def test_equalizer_preset_cycles_then_editing_a_band_goes_custom(self):
        self.assertEqual(self.state["presetAfterCycle"], "bass")
        self.assertEqual(self.state["bandsAfterEdit"][0], 6 + 1, "bass's own band 0, nudged once")
        self.assertEqual(self.state["bandsAfterEdit"][1:], [5, 3, 1, 0, 0, 0, 0, 0, 0], "the rest of the bass preset, untouched")
        self.assertEqual(self.state["presetAfterEdit"], "custom")

    def test_sleep_timer_steps_through_service_not_a_local_fake(self):
        self.assertEqual(self.state["sleepCalls"], [1])
        self.assertEqual(self.state["sleepAfter"], "15")

    def test_keys_section_all_keys_button_asks_the_panel_for_the_overlay(self):
        self.assertEqual(self.state["showAllKeysCount"], 1)

    def test_advanced_clear_cache_calls_the_bridge_op_and_shows_the_result(self):
        self.assertEqual(self.state["clearCacheCalls"], 1)
        self.assertEqual(self.state["cacheNoteAfter"], "Cleared")

    def test_erase_needs_two_enters_and_calls_the_op_only_on_the_second(self):
        self.assertTrue(self.state["armedAfterFirst"])
        self.assertFalse(self.state["armedAfterSecond"])
        self.assertEqual(self.state["eraseCallsBeforeConfirm"], 0)
        self.assertEqual(self.state["eraseCalls"], 1)

    def test_an_armed_confirm_runs_out_on_a_move_a_close_or_after_5_seconds(self):
        self.assertTrue(self.state["eraseArmTimerRunning"])
        self.assertEqual(self.state["armTimeoutMs"], 5000)
        self.assertFalse(self.state["eraseArmedAfterMove"])
        self.assertFalse(self.state["eraseArmedAfterHide"])

    def test_entering_account_fetches_and_shows_the_real_parsed_account(self):
        # Once on the initial section (account is the first one) and again
        # on navigating back to it.
        self.assertGreaterEqual(self.state["accountInfoCallsAfterEnter"], 1)
        self.assertEqual(self.state["accountNameShown"], "Alex Example")
        self.assertEqual(self.state["accountEmailShown"], "alex@example.com")

    def test_the_avatar_is_whole_and_the_help_line_names_the_service(self):
        # Negative y: the avatar starts above its row and the clip cuts it flat.
        self.assertIsNotNone(self.state["avatarY"])
        self.assertGreaterEqual(self.state["avatarY"], 0)
        self.assertEqual(self.state["accountHelpShown"], "Signed in to YouTube Music")

    def test_switch_account_needs_two_enters_and_calls_the_real_op(self):
        self.assertTrue(self.state["switchArmedAfterFirst"])
        self.assertEqual(self.state["switchCallsAfterFirst"], 0)
        self.assertEqual(self.state["accountSwitchCalls"], 1)
        self.assertEqual(self.state["accountSwitchNoteAfter"], "")

    def test_sign_out_needs_two_enters_and_calls_the_op_only_on_the_second(self):
        self.assertTrue(self.state["signOutArmedAfterFirst"])
        self.assertEqual(self.state["signOutCallsAfterFirst"], 0)
        self.assertFalse(self.state["signOutArmedAfterSecond"])
        self.assertEqual(self.state["accountSignOutCalls"], 1)

    def test_about_shows_the_manifest_version_and_fetches_the_engine_once(self):
        self.assertEqual(self.state["solfaVersionShown"], "0.1.0-fixture")
        self.assertEqual(self.state["engineVersionCalls"], 1)
        self.assertIn("FakeChrome", self.state["engineVersionAfter"])

    # ---- the mouse: the right-hand body once took no clicks at all ----

    def test_mouse_walk_ran_and_found_every_control(self):
        self.assertIsNotNone(self.mouse, "no MOUSE line: " + self.found["log"][-800:])
        self.assertEqual([k for k in self.mouse if k.endswith("Missing")], [])

    def test_clicking_switch_account_arms_then_runs_it(self):
        self.assertTrue(self.mouse["switchArmedAfterClick"])
        self.assertEqual(self.mouse["switchCallsAfterOneClick"], 0)
        self.assertEqual(self.mouse["switchCallsAfterTwoClicks"], 1)

    def test_clicking_sign_out_arms_then_runs_it(self):
        self.assertTrue(self.mouse["signOutArmedAfterClick"])
        self.assertEqual(self.mouse["signOutCallsAfterOneClick"], 0)
        self.assertEqual(self.mouse["signOutCallsAfterTwoClicks"], 1)

    def test_clicking_sound_controls_changes_them(self):
        self.assertTrue(self.mouse["eqToggledByClick"])
        self.assertEqual(self.mouse["presetAfterChip"], "treble")
        self.assertEqual(self.mouse["band3AfterClick"], 12)
        self.assertEqual(self.mouse["presetAfterBand"], "custom")
        self.assertEqual(self.mouse["cursorAfterBand"], 3 + 2, "the clicked band takes the keyboard cursor")
        self.assertEqual(self.mouse["preampDelta"], -1)

    def test_a_row_with_a_wrapped_help_line_holds_its_title(self):
        # The row was a fixed 46 px with its text centred on it: a two-line
        # help pushed the title above the row, under the content's clip.
        self.assertIsNotNone(self.mouse["keysRowTextTop"])
        self.assertGreaterEqual(self.mouse["keysRowTextTop"], 0)
        self.assertTrue(self.mouse["keysRowTextFits"])
        self.assertTrue(self.mouse["globalKeysToggledByClick"])

    def test_evidence_frames_were_saved(self):
        self.assertIsNotNone(self.found["out1"])
        self.assertIsNotNone(self.found["out2"])
        self.assertGreater(os.path.getsize(self.found["out1"]), 1000)
        self.assertGreater(os.path.getsize(self.found["out2"]), 1000)


class SettingsSource(unittest.TestCase):
    """Every row the keyboard reaches, the pointer reaches too.

    No renderer needed: a row added without its index is a row the mouse
    cannot click, and that is visible in the source.
    """

    SRC = open(os.path.join(ROOT, "views", "SettingsView.qml"), encoding="utf-8").read()

    def component(self, name):
        start = self.SRC.index("component " + name + ":")
        nxt = self.SRC.find("\n  component ", start + 1)
        return self.SRC[start:nxt if nxt != -1 else len(self.SRC)]

    def rows(self):
        # Each "RowShell {" up to the next one, cut at its first control:
        # its own properties (row among them) always come before it.
        starts = [m.start() for m in re.finditer(r"(?<!component )\bRowShell \{", self.SRC)]
        out = []
        for i, start in enumerate(starts):
            seg = self.SRC[start:starts[i + 1] if i + 1 < len(starts) else len(self.SRC)]
            out.append(re.split(r"\b(?:MiniToggle|StepValue|QuietButton) \{", seg)[0])
        return out

    def steppers(self):
        return [line for line in self.SRC.splitlines() if re.search(r"(?<!component )\bStepValue \{", line)]

    def test_every_clickable_component_has_a_mouse_area(self):
        for name in ("RowShell", "QuietButton", "StepValue", "Chip"):
            self.assertIn("MouseArea", self.component(name), name)

    def test_every_row_and_stepper_says_which_row_it_is(self):
        rows, steps = self.rows(), self.steppers()
        self.assertGreaterEqual(len(rows), 20)
        self.assertEqual(len(steps), 8)
        for use in rows + steps:
            self.assertRegex(use, r"\brow: \d+", use[:80])

    def test_a_row_grows_with_its_text(self):
        self.assertNotRegex(self.component("RowShell"), r"\n    height: Style\.space\(46\)\n")


if __name__ == "__main__":
    unittest.main()
