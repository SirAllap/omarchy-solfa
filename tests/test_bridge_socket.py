#!/usr/bin/env python3
"""The shell reconnects to the bridge, whatever went wrong before.

Runs tests/qml/SocketScene.qml (the real lib/BridgeSocket.qml) in a private
Quickshell, offscreen, against a fake bridge socket that is missing at
first, or that goes away and comes back. Quickshell's Socket never connects
again after one "server not found", which once left the panel on "Starting
Solfa" for good after a bridge restart. Skips when Quickshell or a desktop
session is not available.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))


class FakeBridge:
    """Listens on `path` for the given windows of time (seconds from start),
    answering one line per client and closing every client when a window
    ends. Between windows the socket file does not exist."""

    def __init__(self, path, windows):
        self.path, self.windows, self.accepted = path, windows, []
        self.thread = threading.Thread(target=self.run, daemon=True)

    def run(self):
        start = time.monotonic()
        for index, (opens, closes) in enumerate(self.windows):
            time.sleep(max(0, start + opens - time.monotonic()))
            server = socket.socket(socket.AF_UNIX)
            server.bind(self.path)
            server.listen()
            clients = []
            while time.monotonic() < start + closes:
                server.settimeout(max(0.05, start + closes - time.monotonic()))
                try:
                    client, _ = server.accept()
                except socket.timeout:
                    break
                self.accepted.append(index)
                client.sendall(b'{"window":%d}\n' % index)
                clients.append(client)
            for client in clients:
                client.close()
            server.close()
            os.unlink(self.path)


def run_scene(windows, scene_ms):
    workdir = tempfile.mkdtemp(prefix="solfa-sock-")
    # AF_UNIX paths are short (108 bytes): the socket lives in its own dir
    # under /tmp, never in the (long) scratch dir.
    sockdir = tempfile.mkdtemp(prefix="solfa-s-", dir="/tmp")
    try:
        cfg = os.path.join(workdir, "scene")
        os.mkdir(cfg)
        os.symlink(os.path.join(ROOT, "lib"), os.path.join(cfg, "lib"))
        os.symlink(os.path.join(HERE, "qml", "SocketScene.qml"), os.path.join(cfg, "shell.qml"))
        path = os.path.join(sockdir, "bridge.sock")
        bridge = FakeBridge(path, windows)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=workdir,
                   SOLFA_SOCKET_PATH=path, SOLFA_SCENE_MS=str(scene_ms))
        env.pop("DISPLAY", None)
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        display = os.environ.get("WAYLAND_DISPLAY", "")
        if runtime and display and not os.path.isabs(display):
            env["WAYLAND_DISPLAY"] = os.path.join(runtime, display)
        bridge.thread.start()
        run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                             capture_output=True, text=True, timeout=60)
        bridge.thread.join(timeout=10)
        log = run.stdout + run.stderr
        events = [line.split("qml: ", 1)[1] for line in log.splitlines() if "qml: LINK " in line or "qml: LINE " in line]
        return bridge.accepted, events, log[-3000:]
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
        shutil.rmtree(sockdir, ignore_errors=True)


@unittest.skipUnless(QS and os.environ.get("WAYLAND_DISPLAY"), "Quickshell or a desktop session is missing")
class Reconnect(unittest.TestCase):
    def test_cold_start_bridge_not_up_yet(self):
        # The shell starts before the bridge: the first tries find no socket.
        accepted, events, log = run_scene([(2.5, 6.0)], 5000)
        self.assertEqual(accepted[:1], [0], "never connected once the bridge came up:\n" + log)
        self.assertIn('LINE {"window":0}', events, log)

    def test_bridge_restart_with_a_gap(self):
        # Up, then down (socket gone for a while, as during a bridge.quit
        # and a new unit), then up again.
        accepted, events, log = run_scene([(0.0, 1.5), (3.5, 7.0)], 6500)
        self.assertEqual(accepted[:1], [0], log)
        self.assertIn(1, accepted, "never reconnected after the bridge came back:\n" + log)
        self.assertEqual(events[:3], ["LINK up", 'LINE {"window":0}', "LINK down"], log)
        self.assertIn('LINE {"window":1}', events, log)
        self.assertEqual(events[-2:], ["LINK up", 'LINE {"window":1}'], log)


if __name__ == "__main__":
    unittest.main()
