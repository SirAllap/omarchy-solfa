#!/usr/bin/env python3
"""Moving another widget in the bar never restarts the bridge.

Runs the real Service.qml and BarWidget.qml (tests/qml/ServiceLifecycleScene.qml)
in a private Quickshell, offscreen, against a fake bridge socket, and builds
and rebuilds the bar widget the way the Omarchy shell does when another
widget moves. The fake bridge records what it is asked; a `bridge.quit`
(which makes the song stop and come back) is the thing that must not
happen when the settings did not change. A real settings change must still
restart it. Skips when Quickshell or a desktop session is not available.
"""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import json
import os
import shutil
import socket
import stat
import subprocess
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHELL_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "shell")
QS = shutil.which(os.environ.get("QS_TOOL", "qs"))
PLUGIN_ID = "io.github.sirallap.solfa"
VERSION = json.load(open(os.path.join(ROOT, "manifest.json")))["version"]

# What the shell hands the widget: its shell.json entry, without the id.
ENTRY = {"barControls": True, "autostart": True, "browser": "/usr/bin/orbit-browser", "braveAdBlock": False}
KEY = "true|/usr/bin/orbit-browser|false"


class FakeBridge:
    """A bridge that answers `hello` with a launch key and a version, and
    records every request. `bridge.quit` closes every client and the socket
    for a moment, then listens again (the new unit)."""

    def __init__(self, path, key, version=VERSION, key_file=None):
        self.path, self.key, self.version, self.key_file = path, key, version, key_file
        self.ops, self.lock, self.stop = [], threading.Lock(), False
        self.clients, self.t0 = [], time.monotonic()
        self.server = None
        self.thread = threading.Thread(target=self.serve, daemon=True)

    def record(self, op, args):
        with self.lock:
            self.ops.append((round(time.monotonic() - self.t0, 2), op, args))

    def listen(self):
        server = socket.socket(socket.AF_UNIX)
        server.bind(self.path)
        server.listen()
        server.settimeout(0.1)
        self.server = server

    def serve(self):
        self.listen()
        while not self.stop:
            try:
                client, _ = self.server.accept()
            except socket.timeout:
                continue
            except OSError:
                time.sleep(0.05)  # closed for a restart (see `restart`)
                continue
            self.clients.append(client)
            threading.Thread(target=self.talk, args=(client,), daemon=True).start()

    def talk(self, client):
        buf = b""
        try:
            while True:
                chunk = client.recv(4096)
                if not chunk:
                    return
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line.strip():
                        self.answer(client, json.loads(line))
        except OSError:
            return

    def answer(self, client, req):
        op, args = req.get("op"), req.get("args") or {}
        self.record(op, args)
        data = {}
        if op == "hello":
            data = {"version": self.version, "launchKey": self.key, "engine": {"status": "ready"},
                    "account": {}, "player": {}, "queueVersion": 0, "shown": False, "browsers": []}
        client.sendall((json.dumps({"id": req["id"], "ok": True, "data": data}) + "\n").encode())
        if op == "bridge.quit":
            threading.Thread(target=self.restart, daemon=True).start()

    def restart(self):
        time.sleep(0.2)
        for c in self.clients:
            try:
                c.close()
            except OSError:
                pass
        self.clients = []
        self.server.close()
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass
        time.sleep(0.5)
        # The new unit runs the installed plugin, under the launch key the
        # service started it with.
        self.version = VERSION
        if self.key_file and os.path.exists(self.key_file):
            self.key = open(self.key_file).read().strip()
        if not self.stop:
            self.listen()

    def quits(self):
        return [o for o in self.ops if o[1] == "bridge.quit"]

    def hellos(self):
        return [o for o in self.ops if o[1] == "hello"]


def patched_service(dest, stubs):
    """Service.qml with every absolute path to a program that would reach the
    desktop (a unit, a key bind, a notification) pointed at a logging stub."""
    text = open(os.path.join(ROOT, "Service.qml")).read()
    for name in ("systemd-run", "hyprctl", "notify-send"):
        text = text.replace("/usr/bin/" + name, os.path.join(stubs, name))
    open(dest, "w").write(text)


def make_stubs(stubs, log, key_file):
    os.mkdir(stubs)
    for name in ("systemd-run", "hyprctl", "notify-send"):
        path = os.path.join(stubs, name)
        out = "echo '[]'" if name == "hyprctl" else ":"
        if name == "systemd-run":
            # Remember the launch key the unit was asked to start with.
            out = 'for a in "$@"; do case "$a" in --setenv=SOLFA_LAUNCH_KEY=*) echo "${a#--setenv=SOLFA_LAUNCH_KEY=}" > "%s";; esac; done' % key_file
        with open(path, "w") as f:
            f.write('#!/bin/sh\necho "%s $*" >> "%s"\n%s\n' % (name, log, out))
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


def run_scene(steps, key=KEY, version=VERSION, scene_ms=9000, bridge_delay=0.0):
    """Returns (bridge, stub_calls, log)."""
    work = tempfile.mkdtemp(prefix="solfa-wm-")
    # AF_UNIX paths are short (108 bytes): the runtime dir is a short one
    # under /tmp, never the (long) scratch dir.
    runtime = tempfile.mkdtemp(prefix="solfa-r-", dir="/tmp")
    try:
        cfg = os.path.join(work, "scene")
        os.mkdir(cfg)
        stubs, stublog = os.path.join(work, "stubs"), os.path.join(work, "stubs.log")
        key_file = os.path.join(work, "launch-key")
        make_stubs(stubs, stublog, key_file)
        patched_service(os.path.join(cfg, "Service.qml"), stubs)
        for name, target in (("Ui", os.path.join(SHELL_DIR, "Ui")), ("Commons", os.path.join(SHELL_DIR, "Commons")),
                             ("views", os.path.join(ROOT, "views")), ("lib", os.path.join(ROOT, "lib")),
                             ("BarWidget.qml", os.path.join(ROOT, "BarWidget.qml")),
                             ("Panel.qml", os.path.join(ROOT, "Panel.qml")),
                             ("manifest.json", os.path.join(ROOT, "manifest.json")),
                             ("shell.qml", os.path.join(HERE, "qml", "ServiceLifecycleScene.qml"))):
            os.symlink(target, os.path.join(cfg, name))
        os.makedirs(os.path.join(runtime, PLUGIN_ID))
        bridge = FakeBridge(os.path.join(runtime, PLUGIN_ID, "bridge.sock"), key, version, key_file)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=runtime,
                   SOLFA_SCENE_STEPS=json.dumps(steps + [{"at": scene_ms, "do": "quit"}]))
        for name in ("DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(name, None)
        live_runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        display = os.environ.get("WAYLAND_DISPLAY", "")
        if live_runtime and display and not os.path.isabs(display):
            env["WAYLAND_DISPLAY"] = os.path.join(live_runtime, display)
        threading.Timer(bridge_delay, bridge.thread.start).start() if bridge_delay else bridge.thread.start()
        run = subprocess.run([QS, "-p", os.path.join(cfg, "shell.qml"), "--no-color"], env=env,
                             capture_output=True, text=True, timeout=60)
        bridge.stop = True
        if bridge.thread.is_alive():
            bridge.thread.join(timeout=5)
        calls = open(stublog).read().splitlines() if os.path.exists(stublog) else []
        return bridge, calls, run.stdout + run.stderr
    finally:
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(runtime, ignore_errors=True)


def tail(log):
    return "\n".join(l for l in log.splitlines() if "STEP" in l or "WRITE" in l or "ERROR" in l or "Error" in l)[-2500:]


def started_with(calls):
    """The launch key of every unit the service asked systemd to start."""
    keys = []
    for call in calls:
        if call.startswith("systemd-run"):
            keys += [a.split("=", 2)[2] for a in call.split() if a.startswith("--setenv=SOLFA_LAUNCH_KEY=")]
    return keys


@unittest.skipUnless(QS and os.path.isdir(os.path.join(SHELL_DIR, "Ui")) and os.environ.get("WAYLAND_DISPLAY"),
                     "Quickshell, the Omarchy shell or a desktop session is missing")
class WidgetMove(unittest.TestCase):
    def test_a_new_service_keeps_a_bridge_that_runs_the_same_settings(self):
        # The shell builds a new Service (a scene reload, a bar rebuild after
        # a widget moved) while the bridge keeps running. The settings did
        # not change: the song must not stop.
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": ENTRY}]
        bridge, calls, log = run_scene(steps)
        self.assertTrue(bridge.hellos(), "the service never reached the bridge:\n" + tail(log))
        self.assertEqual(bridge.quits(), [], tail(log))
        self.assertEqual([k for k in started_with(calls) if k != KEY], [], "a unit started under settings the shell never handed over:\n" + tail(log))

    def test_the_equalizer_is_not_reset_while_the_settings_are_on_their_way(self):
        entry = dict(ENTRY, eqEnabled=True, eqPreset="bass", eqBands=json.dumps([6, 5, 4, 2, 0, 0, 0, 0, 0, 0]))
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": entry}]
        bridge, calls, log = run_scene(steps, scene_ms=3000)
        eq = [o[2]["preset"] for o in bridge.ops if o[1] == "eq.set"]
        self.assertTrue(eq and set(eq) == {"bass"}, str(eq) + "\n" + tail(log))

    def test_the_widget_rebuilt_over_and_over_keeps_the_bridge(self):
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": ENTRY},
                 {"at": 3000, "do": "destroy", "name": "w1"},
                 {"at": 3100, "do": "build", "name": "w2", "entry": ENTRY},
                 {"at": 4500, "do": "destroy", "name": "w2"},
                 {"at": 4600, "do": "build", "name": "w3", "entry": ENTRY}]
        bridge, calls, log = run_scene(steps)
        self.assertEqual(bridge.quits(), [], tail(log))

    def test_no_bridge_is_started_before_the_shell_hands_over_the_settings(self):
        # Nothing runs yet; the widget comes a moment after the service. The
        # first unit starts under the widget's settings, never the defaults.
        work_steps = [{"at": 0, "do": "service"},
                      {"at": 600, "do": "build", "name": "w1", "entry": ENTRY}]
        bridge, calls, log = run_scene(work_steps, bridge_delay=2.5, scene_ms=5000)
        self.assertEqual(started_with(calls)[:1], [KEY], "\n".join(calls) + "\n" + tail(log))

    def test_a_real_settings_change_restarts_the_bridge_once(self):
        # The service saves a setting; the shell hands the entry back a moment
        # later (the echo). One quit, then the new unit runs the new settings.
        changed = dict(ENTRY, braveAdBlock=True)
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": ENTRY},
                 {"at": 2000, "do": "save", "key": "braveAdBlock", "value": True},
                 {"at": 2150, "do": "inject", "name": "w1", "entry": changed},
                 {"at": 5500, "do": "inject", "name": "w1", "entry": changed}]
        bridge, calls, log = run_scene(steps, scene_ms=8000)
        self.assertEqual(len(bridge.quits()), 1, tail(log))
        self.assertEqual(bridge.quits()[0][2], {"keepSong": True})
        self.assertEqual(started_with(calls)[-1:], ["true|/usr/bin/orbit-browser|true"], "\n".join(calls))
        self.assertTrue(bridge.hellos()[-1:] and bridge.key == "true|/usr/bin/orbit-browser|true")

    def test_an_edit_of_the_entry_from_outside_restarts_the_bridge(self):
        # shell.json edited by hand (or by the shell's own settings form).
        changed = dict(ENTRY, browser="/usr/bin/other-browser")
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": ENTRY},
                 {"at": 2000, "do": "inject", "name": "w1", "entry": changed}]
        bridge, calls, log = run_scene(steps, scene_ms=6000)
        self.assertEqual(len(bridge.quits()), 1, tail(log))
        self.assertEqual(started_with(calls)[-1:], ["true|/usr/bin/other-browser|false"], "\n".join(calls))

    def test_a_bridge_from_an_older_plugin_version_restarts_once_under_the_real_settings(self):
        # The old bridge says hello before the widget hands the settings over:
        # the restart waits for them, so the new unit never runs the defaults.
        steps = [{"at": 0, "do": "service"},
                 {"at": 600, "do": "build", "name": "w1", "entry": ENTRY}]
        bridge, calls, log = run_scene(steps, version="0.0.1", scene_ms=8000)
        self.assertEqual(len(bridge.quits()), 1, tail(log))
        self.assertEqual(started_with(calls), [KEY], "\n".join(calls))
        self.assertEqual(bridge.version, VERSION)

    def test_a_bar_entry_with_nothing_but_its_id_still_follows_a_change(self):
        # An all-defaults user: the shell hands `{}`, which is no settings
        # entry. The user's own change is the settings from then on.
        steps = [{"at": 0, "do": "service"},
                 {"at": 300, "do": "build", "name": "w1", "entry": {}},
                 {"at": 2000, "do": "save", "key": "eqEnabled", "value": True},
                 {"at": 2500, "do": "save", "key": "braveAdBlock", "value": True}]
        bridge, calls, log = run_scene(steps, key="true||false", scene_ms=7000)
        self.assertEqual(len(bridge.quits()), 1, tail(log))
        self.assertEqual(started_with(calls)[-1:], ["true||true"], "\n".join(calls))


if __name__ == "__main__":
    unittest.main()
