#!/usr/bin/env python3
"""The panel views build with svc null (shell start): no binding may read a
property of it. Renders tests/qml/NullSvcScene.qml (the real NowPlaying and
QueueView, svc null, then a starting fake, then null again) in a private
Quickshell, offscreen, and fails on any TypeError or ReferenceError in its log. Skips when
Quickshell, the Omarchy shell or a desktop session is not available.
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
    os.makedirs(cfg)
    for name, target in (("Ui", os.path.join(SHELL_DIR, "Ui")), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                         ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                         ("shell.qml", os.path.join(HERE, "qml", "NullSvcScene.qml"))):
        os.symlink(target, os.path.join(cfg, name))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir)
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if runtime and display and not os.path.isabs(display):
        env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
    run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                         capture_output=True, text=True, timeout=60)
    return run.stdout + run.stderr


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class NullSvc(unittest.TestCase):
    def test_no_warning_with_svc_null(self):
        workdir = tempfile.mkdtemp(prefix="solfa-nullsvc-")
        try:
            log = render(workdir)
        finally:
            shutil.rmtree(workdir, ignore_errors=True)
        m = re.search(r"STATE (\{.*\})", log)
        self.assertIsNotNone(m, "the scene did not render:\n" + log[-3000:])
        bad = [l for l in log.splitlines() if re.search(r"TypeError|ReferenceError|Cannot read property", l)]
        self.assertEqual(bad, [], "warnings with svc null:\n" + "\n".join(bad))
        s = json.loads(m.group(1))
        self.assertTrue(s["startFull"] is not None)


if __name__ == "__main__":
    unittest.main()
