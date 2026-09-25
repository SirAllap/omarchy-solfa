#!/usr/bin/env python3
"""Structural guard against B3 regressions: no bare-name program spawn, no
PATH-dependent lookup, anywhere in the Python bridge or the QML shell code.

This is a grep over the actual source, not a manual check, so a future PR
that reintroduces `["hyprctl", ...]` or `shutil.which(...)` fails here.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
PY_FILES = [ROOT / "bin" / "solfa", ROOT / "bin" / "solfa-bridge"]
QML_FILES = [ROOT / "Service.qml"] + sorted((ROOT / "views").glob("*.qml"))

# A literal bare program name as the first element of the argv passed to a
# spawn call: `subprocess.run(["hyprctl", ...])`, `os.posix_spawn("chromium", ...)`.
# Absolute paths ("/usr/bin/...") and identifiers (variables, attributes) are
# fine and do not match this.
PY_SPAWN_BARE = re.compile(
    r'(?:subprocess\.run|subprocess\.Popen|asyncio\.create_subprocess_exec|os\.posix_spawn|os\.spawnv[ep]?|os\.execvp?e?)'
    r'\(\s*\[?\s*"([a-zA-Z][\w.-]*)"')

# The same, for a QML command array or Quickshell.execDetached call:
# `execDetached(["notify-send", ...])`, `command: ["hyprctl", ...]`.
QML_SPAWN_BARE = re.compile(r'(?:execDetached|command\s*[:=])\s*\(?\s*\[\s*"([a-zA-Z][\w.-]*)"')


class NoBareProgramNamesTest(unittest.TestCase):
    def test_python_spawn_sites_are_never_a_literal_bare_name(self):
        for path in PY_FILES:
            text = path.read_text()
            hits = PY_SPAWN_BARE.findall(text)
            self.assertEqual(hits, [], f"{path}: bare-name spawn(s): {hits}")

    def test_qml_command_arrays_are_never_a_literal_bare_name(self):
        for path in QML_FILES:
            text = path.read_text()
            hits = QML_SPAWN_BARE.findall(text)
            self.assertEqual(hits, [], f"{path}: bare-name command array(s): {hits}")

    def test_no_shutil_which_in_the_python_bridge(self):
        for path in PY_FILES:
            text = path.read_text()
            self.assertNotIn("shutil.which", text, str(path))
            self.assertNotRegex(text, r"(?<!\w)which\(", str(path))

    def test_shebangs_do_not_go_through_env(self):
        for path in PY_FILES + [ROOT / "tests" / "fake_engine.py"]:
            first_line = path.read_text().splitlines()[0]
            self.assertEqual(first_line, "#!/usr/bin/python3", str(path))
            self.assertNotIn("/usr/bin/env", first_line, str(path))

    def test_hyprctl_and_notify_send_are_absolute_in_service_qml(self):
        # A direct read of what's actually there, in addition to the regex
        # sweep above: every known spawn spot uses an absolute path.
        text = (ROOT / "Service.qml").read_text()
        for needle in ('"/usr/bin/notify-send"', '"/usr/bin/hyprctl"', '"/usr/bin/python3"', '"/usr/bin/systemd-run"'):
            self.assertIn(needle, text)


if __name__ == "__main__":
    unittest.main(verbosity=1)
