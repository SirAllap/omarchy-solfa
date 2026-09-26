#!/usr/bin/env python3
"""Bridge tests: the real bridge process against the fake engine (tests/fake_engine.py),
a fake hyprctl that logs its calls, and a fake Hyprland event socket."""
import testenv  # noqa: F401 - isolates HOME/XDG_*/SOLFA_* before anything else runs
import asyncio
import contextlib
import json
import os
import pathlib
import pwd
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bin" / "solfa-bridge"
FAKE = ROOT / "tests" / "fake_engine.py"


class Client:
    def __init__(self, path, timeout=10):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(str(path))
        self.buf = b""
        self.events = []
        self.next_id = 0

    def read(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def call(self, op, args=None, timeout=10):
        self.next_id += 1
        rid = self.next_id
        self.sock.settimeout(timeout)
        self.sock.sendall((json.dumps({"id": rid, "op": op, "args": args or {}}) + "\n").encode())
        while True:
            msg = self.read()
            if msg.get("id") == rid:
                return msg
            if "event" in msg:
                self.events.append(msg)

    def wait_event(self, pred, timeout=10):
        end = time.time() + timeout
        for e in self.events:
            if pred(e):
                return e
        while time.time() < end:
            self.sock.settimeout(max(0.1, end - time.time()))
            try:
                msg = self.read()
            except socket.timeout:
                break
            if "event" in msg:
                self.events.append(msg)
                if pred(msg):
                    return msg
        raise AssertionError("no matching event; got: " + json.dumps([e["event"] for e in self.events][-20:]))

    def close(self):
        self.sock.close()


class FakeHyprEvents:
    """A Hyprland socket2 stand-in: the test pushes event lines to the bridge."""

    def __init__(self, path):
        self.path = str(path)
        self.srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.srv.bind(self.path)
        self.srv.listen(1)
        self.conn = None
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        self.conn, _ = self.srv.accept()

    def send(self, line):
        end = time.time() + 5
        while self.conn is None and time.time() < end:
            time.sleep(0.05)
        self.conn.sendall((line + "\n").encode())

    def close(self):
        if self.conn:
            self.conn.close()
        self.srv.close()


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-test-"))
        # unix socket paths must stay short: use the runtime dir
        base = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR") or self.tmp)
        self.rt = pathlib.Path(tempfile.mkdtemp(prefix="solfa-t", dir=base))
        self.profile = self.tmp / "engine"
        self.hyprlog = self.tmp / "hyprctl.log"
        fake_ctl = self.tmp / "hyprctl"
        # `hyprctl -j clients` answers clients.json, `-j monitors` monitors.json.
        fake_ctl.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> " + str(self.hyprlog) + "\n"
                            "case \"$1\" in -j) printf '%s' \"$(cat " + str(self.tmp) + "/\"$2\".json 2>/dev/null || echo '[]')\";; esac\n")
        fake_ctl.chmod(0o755)
        self.events = FakeHyprEvents(self.rt / "hypr.sock")
        self.env = dict(os.environ,
                        SOLFA_RUNTIME_DIR=str(self.rt / "solfa"), SOLFA_PROFILE_DIR=str(self.profile),
                        SOLFA_STATE_DIR=str(self.tmp / "state"), SOLFA_CACHE_DIR=str(self.tmp / "cache"),
                        SOLFA_BROWSER=str(FAKE), SOLFA_HYPRCTL=str(fake_ctl), SOLFA_HYPR_EVENTS=str(self.rt / "hypr.sock"),
                        SOLFA_CHECK_EVERY="2", SOLFA_SIGNIN_COOLDOWN="0")
        self.env.pop("SOLFA_NO_LAUNCH", None)
        self.proc = None
        self.clients = []

    def tearDown(self):
        for c in self.clients:
            c.close()
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                # SIGTERM now closes the engine first: up to ~11 s worst case
                # (Browser.close's wait, then a pidfd SIGTERM's) when a test
                # left it refusing to close (FAKE_WONT_CLOSE).
                self.proc.wait(15)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(5)
        pid = self.engine_pid()
        if pid and pathlib.Path(f"/proc/{pid}").exists():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.events.close()
        shutil.rmtree(self.tmp, ignore_errors=True)
        shutil.rmtree(self.rt, ignore_errors=True)

    # ---- helpers

    def start(self, **env):
        e = dict(self.env, **env)
        with open(self.tmp / "bridge.err", "a") as err:
            self.proc = subprocess.Popen([sys.executable, str(BRIDGE)], env=e, stdout=subprocess.DEVNULL, stderr=err)
        sock = self.rt / "solfa" / "bridge.sock"
        for _ in range(100):
            if sock.exists():
                break
            time.sleep(0.05)
        c = Client(sock)
        self.clients.append(c)
        return c

    def engine_pid(self):
        try:
            return int(os.readlink(self.profile / "SingletonLock").rsplit("-", 1)[1])
        except (OSError, ValueError):
            return 0

    def wait_ready(self, c, timeout=15):
        end = time.time() + timeout
        while time.time() < end:
            if c.call("hello")["data"]["engine"]["status"] == "ready":
                return
            time.sleep(0.1)
        self.fail("engine never ready: " + (self.tmp / "bridge.err").read_text()[-600:])

    def page_log(self):
        try:
            return [json.loads(l) for l in (self.profile / "fake-log").read_text().splitlines()]
        except OSError:
            return []

    def hypr_calls(self):
        try:
            return self.hyprlog.read_text().splitlines()
        except OSError:
            return []

    # ---- tests

    def test_launches_engine_and_answers(self):
        c = self.start()
        self.wait_ready(c)
        self.assertTrue(self.engine_pid() > 0)
        calls = self.hypr_calls()
        self.assertTrue(any(l.startswith("eval ") and "special:solfa silent" in l and "no_initial_focus = true" in l for l in calls), calls)
        r = c.call("search", {"q": "harbour lights"})
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["data"]["songs"][0]["title"], "Result for harbour lights")

    def test_socket_is_private(self):
        c = self.start()
        self.wait_ready(c)
        self.assertEqual(stat.S_IMODE((self.rt / "solfa").stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.rt / "solfa" / "bridge.sock").stat().st_mode), 0o600)

    def test_refuses_bad_requests_before_the_page(self):
        c = self.start()
        self.wait_ready(c)
        before = len(self.page_log())
        bad = [("volume", {"level": 101}), ("volume", {"level": True}), ("seek", {"seconds": -1}),
               ("play", {"videoId": "x"}), ("play", {}), ("search", {"q": ""}), ("search", {"q": "a\nb"}),
               ("search", {"q": "ok", "extra": 1}), ("queue.add", {"videoIds": []}), ("repeat", {"mode": "SOMETIMES"}),
               ("like", {"videoId": "AAAAAAAAAAA", "status": "LOVE"}), ("browse", {"id": "../etc"}),
               ("radio", {"playlistId": "PLnotaradio"}), ("nonsense", {}), (7, {})]
        for op, args in bad:
            r = c.call(op, args)
            self.assertFalse(r["ok"], (op, args))
            self.assertEqual(r["error"], "bad-args", (op, args, r))
        self.assertEqual(len(self.page_log()), before, "nothing reached the page")
        # not JSON at all: an error reply, and the connection lives on
        c.sock.sendall(b"not json\n")
        self.assertEqual(c.read()["error"], "bad-json")
        self.assertTrue(c.call("state")["ok"])

    def test_page_errors_come_back_as_codes(self):
        c = self.start()
        self.wait_ready(c)
        r = c.call("like", {"videoId": "AAAAAAAAAAA", "status": "LIKE"})
        self.assertEqual(r["error"], "signin-required")

    def test_pushes_reach_every_client(self):
        a = self.start()
        self.wait_ready(a)
        b = Client(self.rt / "solfa" / "bridge.sock")
        self.clients.append(b)
        a.call("volume", {"level": 40})
        for c in (a, b):
            e = c.wait_event(lambda m: m["event"] == "player" and m["data"]["volume"] == 40)
            self.assertEqual(e["data"]["videoId"], "AAAAAAAAAAA")

    def test_a_client_that_stops_reading_is_dropped_not_waited_for(self):
        c = self.start()
        self.wait_ready(c)
        lazy = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        lazy.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        lazy.connect(str(self.rt / "solfa" / "bridge.sock"))
        t0 = time.time()
        for i in range(400):
            self.assertTrue(c.call("seek", {"seconds": i})["ok"])
        self.assertLess(time.time() - t0, 20)
        lazy.close()

    def test_restarts_a_killed_engine_and_restores_the_song(self):
        c = self.start()
        self.wait_ready(c)
        c.call("play", {"videoId": "CCCCCCCCCCC"})
        c.call("volume", {"level": 40})
        c.call("seek", {"seconds": 83})
        c.wait_event(lambda m: m["event"] == "player" and m["data"]["position"] == 83)
        time.sleep(2)  # it keeps playing: the restore must come back later than 83
        logged = len(self.page_log())
        old = self.engine_pid()
        c.events.clear()
        os.kill(old, signal.SIGKILL)
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "crashed")
        c.events.clear()
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "ready", timeout=20)
        new = self.engine_pid()
        self.assertNotEqual(new, old)
        end = time.time() + 10
        seeks = []
        while time.time() < end:
            ops = [(e["op"], e["args"]) for e in self.page_log()[logged:]]
            seeks = [a["seconds"] for op, a in ops if op == "seek"]
            if seeks:
                break
            time.sleep(0.2)
        ops = [(e["op"], e["args"]) for e in self.page_log()[logged:]]
        self.assertIn(("play", {"videoId": "CCCCCCCCCCC"}), ops)
        self.assertIn(("volume", {"level": 40}), ops)
        self.assertTrue(seeks, ops[-8:])
        # where it was when it died (83 plus the 2 s it kept playing), not
        # where the last push said, and not later by the restart time
        self.assertTrue(84.5 <= seeks[-1] <= 88, seeks)

    def _kill_and_wait_ready(self, c):
        old = self.engine_pid()
        c.events.clear()
        os.kill(old, signal.SIGKILL)
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "crashed")
        c.events.clear()
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "ready", timeout=20)

    def test_restore_waits_for_a_player_that_comes_late(self):
        # The bridge attaches while the app is still loading; the restore
        # must wait for the player instead of failing once and giving up.
        c = self.start(FAKE_LATE_PLAYER="3")
        self.wait_ready(c)
        time.sleep(3.2)  # this engine's player is up now
        c.call("play", {"videoId": "CCCCCCCCCCC"})
        c.call("seek", {"seconds": 40})
        c.wait_event(lambda m: m["event"] == "player" and m["data"]["position"] == 40)
        logged = len(self.page_log())
        self._kill_and_wait_ready(c)  # the new engine's player comes 3 s late again
        end = time.time() + 15
        while time.time() < end:
            ops = [(e["op"], e["args"]) for e in self.page_log()[logged:]]
            if any(op == "seek" for op, _ in ops):
                break
            time.sleep(0.2)
        ops = [(e["op"], e["args"]) for e in self.page_log()[logged:]]
        self.assertIn(("play", {"videoId": "CCCCCCCCCCC"}), ops)
        self.assertTrue(any(op == "seek" and a["seconds"] >= 40 for op, a in ops), ops)

    def test_restore_gives_way_to_the_user(self):
        # An advert holds the restored song; the user plays something else:
        # the restore must not seek or pause the user's song.
        c = self.start(FAKE_AD_SECONDS="3")
        self.wait_ready(c)
        c.call("play", {"videoId": "CCCCCCCCCCC"})
        time.sleep(3.3)
        c.call("seek", {"seconds": 70})
        c.wait_event(lambda m: m["event"] == "player" and m["data"]["position"] == 70)
        logged = len(self.page_log())
        self._kill_and_wait_ready(c)
        end = time.time() + 10
        while time.time() < end and not any(e["op"] == "play" for e in self.page_log()[logged:]):
            time.sleep(0.1)
        c.call("play", {"videoId": "DDDDDDDDDDD"})  # the user's own choice, during the advert
        time.sleep(4)
        after_user = [e for e in self.page_log()[logged:]]
        i = max(k for k, e in enumerate(after_user) if e["op"] == "play" and e["args"].get("videoId") == "DDDDDDDDDDD")
        later = [e["op"] for e in after_user[i + 1:]]
        self.assertNotIn("seek", later)
        self.assertNotIn("transport", later)
        # and it stood down at once rather than waiting its time out
        self.assertIn("restore: the user took over", (self.tmp / "bridge.err").read_text())

    def test_no_browser_says_so_and_stops_trying(self):
        c = self.start(SOLFA_BROWSER=str(self.tmp / "no-such-browser"))
        end = time.time() + 5
        eng = {}
        while time.time() < end:
            eng = c.call("hello")["data"]["engine"]
            # (Before its first try the engine is "stopped" with no error.)
            if eng["status"] == "stopped" and eng["error"]:
                break
            time.sleep(0.2)
        self.assertEqual(eng["status"], "stopped")
        self.assertIn("no Chromium-family browser", eng["error"])
        self.assertIs(eng.get("wantRunning"), False, "waits for the user instead of retrying the same failure")
        time.sleep(3)
        eng = c.call("hello")["data"]["engine"]
        self.assertIn("no Chromium-family browser", eng["error"], "not replaced by a crash-loop message")

    def test_relative_browser_setting_is_refused(self):
        c = self.start(SOLFA_BROWSER="chromium")
        end = time.time() + 5
        eng = {}
        while time.time() < end:
            eng = c.call("hello")["data"]["engine"]
            if eng["status"] == "stopped" and eng["error"]:
                break
            time.sleep(0.2)
        self.assertEqual(eng["status"], "stopped")
        self.assertIn("absolute path", eng["error"])

    def test_resume_point(self):
        b = PureTest.load()
        self.assertEqual(b.Bridge.resume_point({"position": 30, "playing": False, "at": 100}, now=160), 30)
        self.assertEqual(b.Bridge.resume_point({"position": 30, "playing": True, "at": 100}, now=160), 90)
        self.assertEqual(b.Bridge.resume_point({"position": 30, "playing": True, "at": 100, "died_at": 110}, now=160), 40)

    RECYCLE = dict(SOLFA_RECYCLE_HEAP_MB="100", SOLFA_RECYCLE_IDLE="1", SOLFA_RECYCLE_CHECK="1", SOLFA_RECYCLE_MIN_AGE="0.01")

    def wait_op(self, op, since=0, timeout=15):
        end = time.time() + timeout
        while time.time() < end:
            found = [e["args"] for e in self.page_log()[since:] if e["op"] == op]
            if found:
                return found[-1]
            time.sleep(0.2)
        self.fail(op + " never came: " + str([e["op"] for e in self.page_log()[since:]][-10:]))

    def test_a_grown_page_that_is_paused_is_swapped_for_a_fresh_one(self):
        c = self.start(**self.RECYCLE)
        self.wait_ready(c)
        c.call("volume", {"level": 30})
        c.call("seek", {"seconds": 42})
        c.call("transport", {"action": "pause"})
        c.events.clear()
        (self.profile / "fake-heap-mb").write_text("500")
        saved = self.wait_op("session.restore")
        self.assertEqual((saved["position"], saved["playing"], saved["volume"]), (42, False, 30))
        steps = [e["args"].get("url", e["op"]) for e in self.page_log() if e["op"] in ("navigate", "ServiceWorker.stopAllWorkers")]
        # the worker would keep the old renderer alive and get the app back
        self.assertEqual(steps[-3:], ["about:blank", "ServiceWorker.stopAllWorkers", "https://music.youtube.com/"])
        # The blank page in between is never shown as signed out.
        time.sleep(0.5)
        self.assertFalse([m for m in c.events if m["event"] == "account" and not m["data"].get("signedIn")], c.events)

    def test_a_grown_page_that_is_playing_waits_for_the_next_song(self):
        c = self.start(**self.RECYCLE)
        self.wait_ready(c)
        (self.profile / "fake-heap-mb").write_text("500")
        self.wait_op("session.arm")
        time.sleep(2)
        self.assertFalse([e for e in self.page_log() if e["op"] == "navigate"], "recycled mid-song")
        mark = len(self.page_log())
        c.call("transport", {"action": "next"})
        saved = self.wait_op("session.restore", since=mark)
        self.assertEqual((saved["videoId"], saved["position"], saved["playing"]), ("NNNNNNNNNNN", 0, True))

    def test_a_song_stopped_for_a_recycle_that_fails_plays_on(self):
        c = self.start(**self.RECYCLE)
        self.wait_ready(c)
        (self.profile / "fake-save-fails").write_text("")
        (self.profile / "fake-heap-mb").write_text("500")
        self.wait_op("session.arm")
        mark = len(self.page_log())
        c.call("transport", {"action": "next"})
        self.assertEqual(self.wait_op("transport", since=mark + 1)["action"], "play")
        self.assertNotIn("navigate", [e["op"] for e in self.page_log()[mark:]])

    def test_a_page_just_loaded_is_left_alone(self):
        c = self.start(**dict(self.RECYCLE, SOLFA_RECYCLE_MIN_AGE="600"))
        self.wait_ready(c)
        c.call("transport", {"action": "pause"})
        (self.profile / "fake-heap-mb").write_text("500")
        time.sleep(4)
        self.assertNotIn("session.save", [e["op"] for e in self.page_log()])

    def test_a_closed_engine_forgets_its_song(self):
        c = self.start()
        self.wait_ready(c)
        self.assertTrue(c.call("hello")["data"]["player"].get("videoId"))
        c.call("engine.stop")
        hello = c.call("hello")["data"]
        self.assertEqual(hello["engine"]["status"], "stopped")
        self.assertEqual(hello["player"], {}, "no stale song on a closed Solfa")

    def test_a_small_page_is_left_alone(self):
        c = self.start(**self.RECYCLE)
        self.wait_ready(c)
        c.call("transport", {"action": "pause"})
        time.sleep(4)
        ops = [e["op"] for e in self.page_log()]
        self.assertNotIn("session.save", ops)
        self.assertNotIn("session.arm", ops)

    def fake_renderer(self, mb, other_profile=False):
        d = self.tmp / "proc" / "4242"
        d.mkdir(parents=True, exist_ok=True)
        profile = "/somewhere/else" if other_profile else str(self.profile)
        (d / "cmdline").write_bytes(b"chromium\0--type=renderer\0--user-data-dir=" + profile.encode() + b"\0")
        (d / "status").write_text("Name:\tchromium\nVmRSS:\t%d kB\nVmSwap:\t0 kB\n" % (mb * 1024))

    def test_a_page_whose_process_grew_is_swapped_at_a_quiet_moment(self):
        # a small JS heap, a big process: the growth of skipping songs
        env = dict(self.RECYCLE, SOLFA_RECYCLE_HEAP_MB="100000", SOLFA_RECYCLE_RSS_MB="800", SOLFA_PROC_ROOT=str(self.tmp / "proc"))
        self.fake_renderer(500)
        c = self.start(**env)
        self.wait_ready(c)
        c.call("transport", {"action": "pause"})
        time.sleep(4)
        self.assertNotIn("session.save", [e["op"] for e in self.page_log()], "under the limit")
        self.fake_renderer(900)
        self.wait_op("session.restore")

    def test_a_big_process_of_another_browser_does_not_count(self):
        env = dict(self.RECYCLE, SOLFA_RECYCLE_HEAP_MB="100000", SOLFA_RECYCLE_RSS_MB="800", SOLFA_PROC_ROOT=str(self.tmp / "proc"))
        self.fake_renderer(2000, other_profile=True)
        c = self.start(**env)
        self.wait_ready(c)
        c.call("transport", {"action": "pause"})
        time.sleep(4)
        self.assertNotIn("session.save", [e["op"] for e in self.page_log()])

    def test_renderer_mb_is_the_biggest_renderer_of_this_engine(self):
        b = PureTest.load()
        proc = self.tmp / "proc"
        for pid, kind, mb, swap in (("10", "renderer", 300, 50), ("11", "renderer", 700, 0), ("12", "gpu-process", 900, 0)):
            d = proc / pid
            d.mkdir(parents=True)
            (d / "cmdline").write_bytes(("chromium\0--type=%s\0--user-data-dir=/p/engine\0" % kind).encode())
            (d / "status").write_text("VmRSS:\t%d kB\nVmSwap:\t%d kB\n" % (mb * 1024, swap * 1024))
        (proc / "self").mkdir()
        self.assertEqual(b.renderer_mb(proc, "/p/engine"), 700)
        self.assertEqual(b.renderer_mb(proc, "/p/other"), 0)
        self.assertEqual(b.renderer_mb(self.tmp / "no-such-dir", "/p/engine"), 0)

    def test_a_page_left_blank_by_a_recycle_cut_short_gets_the_app_back(self):
        c = self.start(FAKE_START_BLANK="1")
        self.wait_ready(c)
        self.assertIn("https://music.youtube.com/", [e["args"].get("url") for e in self.page_log() if e["op"] == "navigate"])

    def test_a_stuck_page_is_reloaded(self):
        c = self.start()
        self.wait_ready(c)
        c.events.clear()
        (self.profile / "fake-hang").touch()
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "stuck", timeout=70)
        c.events.clear()
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "ready", timeout=30)
        self.assertIn("reload", [e["op"] for e in self.page_log()])
        self.assertTrue(c.call("state")["ok"])

    def test_guard_puts_the_engine_away_unless_asked(self):
        c = self.start()
        self.wait_ready(c)
        (self.tmp / "clients.json").write_text(json.dumps([{"address": "0xabc", "class": "chrome-music.youtube.com__-Solfa", "pid": self.engine_pid(), "workspace": {"name": "special:solfa"}}]))
        (self.tmp / "monitors.json").write_text(json.dumps([{"name": "HDMI-A-1", "specialWorkspace": {"name": "special:solfa"}}, {"name": "DP-3", "specialWorkspace": {"name": ""}}]))
        self.events.send("activewindowv2>>1234")
        self.events.send("activespecial>>special:solfa,HDMI-A-1")
        deadline = time.time() + 5
        while time.time() < deadline and not any("toggle_special" in l for l in self.hypr_calls()):
            time.sleep(0.05)
        calls = self.hypr_calls()
        self.assertTrue(any("focus({ monitor = [[HDMI-A-1]] })" in l for l in calls), calls)
        self.assertTrue(any("toggle_special([[solfa]])" in l for l in calls), calls)
        self.assertFalse(any("[[DP-3]]" in l for l in calls), "only the monitor that shows it")
        self.assertTrue(any("focus({ window = [[address:0x1234]] })" in l for l in calls), calls)
        # asked for: no hiding
        (self.tmp / "monitors.json").write_text(json.dumps([{"name": "HDMI-A-1", "specialWorkspace": {"name": ""}}]))
        self.events.send("activespecial>>,HDMI-A-1")
        time.sleep(0.2)
        c.call("window.show")
        before = len(self.hypr_calls())
        self.events.send("activespecial>>special:solfa,HDMI-A-1")
        time.sleep(0.5)
        self.assertFalse(any("window.move" in l for l in self.hypr_calls()[before:]))
        # a config reload wipes runtime rules: they come back
        n = sum(1 for l in self.hypr_calls() if l.startswith("eval "))
        self.events.send("configreloaded>>")
        deadline = time.time() + 5
        while time.time() < deadline and sum(1 for l in self.hypr_calls() if l.startswith("eval ")) == n:
            time.sleep(0.05)
        self.assertEqual(sum(1 for l in self.hypr_calls() if l.startswith("eval ")), n + 1)

    def test_engine_window_mapping_in_the_open_is_put_away(self):
        c = self.start()
        self.wait_ready(c)
        (self.tmp / "clients.json").write_text(json.dumps([{"address": "0xdef", "class": "chrome-music.youtube.com__-Solfa", "pid": self.engine_pid(), "workspace": {"name": "1"}}]))
        self.events.send("openwindow>>def,1,chrome-music.youtube.com__-Solfa,YouTube Music")
        deadline = time.time() + 5
        while time.time() < deadline and not any("window.move" in l for l in self.hypr_calls()):
            time.sleep(0.05)
        self.assertTrue(any("window.move({ window = [[address:0xdef]], workspace = [[special:solfa]], follow = false })" in l for l in self.hypr_calls()), self.hypr_calls())

    def test_hide_asks_hyprland_what_is_open(self):
        # After a bridge restart the bridge has seen no event, yet the
        # window may be on screen: hide must still close it.
        c = self.start()
        self.wait_ready(c)
        (self.tmp / "clients.json").write_text(json.dumps([{"address": "0xabc", "class": "chrome-music.youtube.com__-Solfa", "pid": self.engine_pid(), "workspace": {"name": "special:solfa"}}]))
        (self.tmp / "monitors.json").write_text(json.dumps([{"name": "DP-3", "specialWorkspace": {"name": "special:solfa"}}]))
        before = len(self.hypr_calls())
        c.call("window.hide")
        calls = self.hypr_calls()[before:]
        self.assertTrue(any("focus({ monitor = [[DP-3]] })" in l for l in calls), calls)
        self.assertTrue(any("toggle_special([[solfa]])" in l for l in calls), calls)
        # and show must not toggle it shut when it is already open
        before = len(self.hypr_calls())
        c.call("window.show")
        self.assertFalse(any("toggle_special" in l for l in self.hypr_calls()[before:]))

    # ---- sign-in: a plain window Google accepts, no DevTools

    def signin_argv(self, timeout=10):
        f = self.profile / "fake-signin-argv"
        end = time.time() + timeout
        while time.time() < end:
            if f.exists() and f.read_text():
                return json.loads(f.read_text())
            time.sleep(0.05)
        self.fail("no sign-in window: " + (self.tmp / "bridge.err").read_text()[-600:])

    def wait_engine(self, c, pred, timeout=20):
        end = time.time() + timeout
        eng = {}
        while time.time() < end:
            eng = c.call("hello")["data"]["engine"]
            if pred(eng):
                return eng
            time.sleep(0.1)
        self.fail("engine never got there: " + json.dumps(eng) + (self.tmp / "bridge.err").read_text()[-600:])

    def alive(self, pid):
        return pid and pathlib.Path(f"/proc/{pid}").exists() and b"fake_engine" in pathlib.Path(f"/proc/{pid}/cmdline").read_bytes()

    def test_sign_in_opens_a_plain_window_without_devtools(self):
        c = self.start()
        self.wait_ready(c)
        engine = self.engine_pid()
        r = c.call("signin.begin")
        self.assertTrue(r["ok"], r)
        argv = self.signin_argv()
        self.assertFalse([a for a in argv if a.startswith("--remote-debugging") or "automation" in a], argv)
        self.assertIn("--user-data-dir=" + str(self.profile), argv)
        self.assertIn("--profile-directory=Solfa", argv)
        self.assertTrue(any(a.startswith("--app=https://accounts.google.com/") for a in argv), argv)
        self.assertFalse([a for a in argv if a.startswith(("--autoplay", "--disable-"))], "only what sign-in needs")
        self.assertFalse(self.alive(engine), "the engine is closed first: one browser per profile")
        eng = self.wait_engine(c, lambda e: e["status"] == "signing-in")
        self.assertTrue(eng["signingIn"])
        # The bridge does not attach to the sign-in window, and does not start
        # a second engine on its profile while it is open.
        time.sleep(2)
        self.assertEqual(c.call("hello")["data"]["engine"]["status"], "signing-in")
        self.assertFalse((self.profile / "DevToolsActivePort").exists())

    def test_sign_in_cookie_closes_the_window_and_the_engine_comes_back_signed_in(self):
        c = self.start(FAKE_SIGNIN_AFTER="0.5")
        self.wait_ready(c)
        self.assertFalse(c.call("hello")["data"]["account"]["signedIn"])
        c.call("signin.begin")
        self.signin_argv()
        window = self.engine_pid()
        eng = self.wait_engine(c, lambda e: e["status"] == "ready" and e["signedIn"] and not e["signinCheck"])
        self.assertFalse(eng["signingIn"])
        self.assertEqual(eng["signinError"], "")
        self.assertFalse(self.alive(window), "the sign-in window was closed")
        self.assertNotEqual(self.engine_pid(), window)

    # ---- an imported session (from before "Use my browser's sign-in" was
    # removed): the signout safety it left behind is still worth testing —
    # an existing profile may still carry the marker.

    def mark_imported(self):
        (self.profile / "solfa-imported-session").write_text("1\n")

    def google_left(self):
        """Google cookie names in the fake engine's jar now, the consent answer aside."""
        jars = [e["args"]["names"] for e in self.page_log() if e["op"] == "jar"]
        return set(jars[-1] if jars else []) - {"SOCS"}

    def test_new_document_on_the_same_url_gets_the_binding_back(self):
        c = self.start(FAKE_SWAP_AFTER_ATTACH="1.5")
        self.wait_ready(c)
        self.assertFalse(c.call("hello")["data"]["account"]["signedIn"])
        deadline = time.time() + 5
        while time.time() < deadline and not c.call("hello")["data"]["account"]["signedIn"]:
            time.sleep(0.2)
        self.assertTrue(c.call("hello")["data"]["account"]["signedIn"], "the bridge still hears the new page")

    def test_liveness_check_adds_a_lost_binding_back(self):
        # No navigation event at all: the quiet-page check still sees it.
        c = self.start(FAKE_SWAP_AFTER_ATTACH="1", FAKE_SWAP_SILENT="1", SOLFA_CHECK_EVERY="1")
        self.wait_ready(c)
        deadline = time.time() + 8
        while time.time() < deadline and not c.call("hello")["data"]["account"]["signedIn"]:
            time.sleep(0.2)
        self.assertTrue(c.call("hello")["data"]["account"]["signedIn"])
        self.assertIn("the page lost its binding", (self.tmp / "bridge.err").read_text())

    def test_sign_out_of_an_imported_session_never_calls_google_logout(self):
        c = self.start(FAKE_SIGNED_IN="1", FAKE_JAR="SID,LOGIN_INFO")
        self.wait_ready(c)
        self.mark_imported()
        r = c.call("signout", timeout=30)
        self.assertTrue(r["ok"], r)
        navs = [e["args"]["url"] for e in self.page_log() if e["op"] == "navigate"]
        self.assertFalse([u for u in navs if "accounts.google.com" in u], navs)
        self.assertEqual(self.google_left(), set())
        deleted = {e["args"]["name"] for e in self.page_log() if e["op"] == "cookies.delete"}
        self.assertNotIn("SOCS", deleted, "the cookie-consent answer stays")
        d = c.call("hello")["data"]
        self.assertFalse(d["account"]["signedIn"])
        self.assertFalse(d["engine"]["importedSession"])

    def test_sign_out_of_an_imported_session_deletes_a_cookie_set_back_late(self):
        c = self.start(FAKE_SIGNED_IN="1", FAKE_JAR="SID,LOGIN_INFO", FAKE_COOKIE_COMES_BACK="1")
        self.wait_ready(c)
        self.mark_imported()
        self.assertTrue(c.call("signout", timeout=30)["ok"])
        jars = [e["args"]["names"] for e in self.page_log() if e["op"] == "jar"]
        self.assertTrue(any("LOGIN_INFO" in j for j in jars[-3:]), "the fake did set one back")
        self.assertEqual(self.google_left(), set())

    def test_sign_out_without_the_marker_still_uses_google_logout(self):
        c = self.start(FAKE_SIGNED_IN="1")
        self.wait_ready(c)
        self.assertTrue(c.call("signout", timeout=30)["ok"])
        navs = [e["args"]["url"] for e in self.page_log() if e["op"] == "navigate"]
        self.assertTrue([u for u in navs if u.startswith("https://accounts.google.com/Logout")], navs)

    def test_sign_in_window_over_an_imported_session_forgets_it_first(self):
        c = self.start(FAKE_SIGNED_IN="1", FAKE_JAR="SID,LOGIN_INFO")
        self.wait_ready(c)
        self.mark_imported()
        self.assertTrue(c.call("signin.begin")["ok"])
        self.signin_argv()
        self.assertEqual(self.google_left(), set())
        navs = [e["args"]["url"] for e in self.page_log() if e["op"] == "navigate"]
        self.assertFalse([u for u in navs if "Logout" in u], navs)
        self.assertFalse(c.call("hello")["data"]["engine"]["importedSession"])

    def signin_window_titled(self, window, title):
        (self.tmp / "clients.json").write_text(json.dumps([
            {"address": "0xabc", "pid": window, "class": "chrome-accounts.google.com__-Solfa", "title": title,
             "workspace": {"name": "1"}}]))

    def test_sign_in_window_hides_when_it_reaches_the_app_and_closes_once_the_cookie_is_saved(self):
        # Chromium writes a new cookie to disk on a timer (about 30 s), and
        # SIGTERM does not write it first: a window closed on its title threw
        # the sign-in away. It hides at once and closes on the saved cookie.
        c = self.start(FAKE_SIGNIN_AFTER="3")
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        window = self.engine_pid()
        self.wait_engine(c, lambda e: e["status"] == "signing-in")
        self.signin_window_titled(window, "Sign in - Google Accounts")
        time.sleep(1.0)
        self.assertTrue(self.alive(window), "Google's own pages are not the end of the flow")
        self.signin_window_titled(window, "YouTube Music")
        eng = self.wait_engine(c, lambda e: e["signinSaving"], timeout=3)
        self.assertTrue(eng["signingIn"])
        self.assertTrue(any("address:0xabc" in l and "special:solfa" in l for l in self.hypr_calls()), "hidden at once")
        self.assertTrue(self.alive(window), "not closed before Google's cookie is on disk")
        eng = self.wait_engine(c, lambda e: e["status"] == "ready" and e["signedIn"] and not e["signinCheck"])
        self.assertFalse(self.alive(window), "the sign-in window was closed")
        self.assertFalse(eng["signingIn"])
        self.assertFalse(eng["signinSaving"])
        self.assertEqual(eng["signinError"], "")
        self.assertIn("cookie is saved; closing", (self.tmp / "bridge.err").read_text())

    def test_a_window_that_reaches_the_app_signed_out_is_a_failed_sign_in_not_a_silent_close(self):
        # Google's passive sign-in bounces straight back to the app when its
        # own session is alive but YouTube's step failed: the window reaches
        # the app, signed out, in a second. The title says the flow ended,
        # never that it worked: the player's own page decides.
        c = self.start(SOLFA_SIGNIN_SAVE_WAIT="1")
        self.wait_ready(c)
        c.call("signin.begin")
        first = self.signin_argv()
        window = self.engine_pid()
        self.wait_engine(c, lambda e: e["status"] == "signing-in")
        self.signin_window_titled(window, "YouTube Music")
        eng = self.wait_engine(c, lambda e: e["status"] == "ready" and not e["signingIn"] and not e["signinCheck"])
        self.assertFalse(eng["signedIn"])
        self.assertEqual(eng["signinError"], "signin-failed")
        self.assertIn("still signed out", (self.tmp / "bridge.err").read_text())
        # The next try must not bounce the same way: Google shows the account.
        (self.profile / "fake-signin-argv").unlink()
        c.call("signin.begin")
        again = self.signin_argv()
        eng = self.wait_engine(c, lambda e: e["status"] == "signing-in")
        self.assertEqual(eng["signinError"], "", "a new try starts clean")
        self.assertTrue(any("ServiceLogin" in a and "passive=true" in a for a in first), first)
        self.assertTrue(any("AccountChooser" in a for a in again), again)
        self.assertFalse(any("passive=true" in a for a in again), again)

    def test_a_window_that_reaches_the_app_signed_in_is_a_sign_in(self):
        c = self.start(FAKE_SIGNIN_AFTER="0.3")
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        window = self.engine_pid()
        self.wait_engine(c, lambda e: e["status"] == "signing-in")
        time.sleep(0.4)  # Google's cookie is in the profile, not yet on disk for the bridge to matter
        self.signin_window_titled(window, "YouTube Music")
        eng = self.wait_engine(c, lambda e: e["status"] == "ready" and e["signedIn"] and not e["signinCheck"])
        self.assertEqual(eng["signinError"], "")
        self.assertFalse(self.alive(window))

    def test_closing_the_sign_in_window_brings_the_engine_back(self):
        c = self.start(FAKE_SIGNIN_CLOSE_AFTER="0.5")
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        eng = self.wait_engine(c, lambda e: e["status"] == "ready" and not e["signinCheck"])
        self.assertFalse(eng["signedIn"])
        self.assertFalse(eng["signingIn"])
        self.assertEqual(eng["signinError"], "signin-failed", "a window closed before the account was in says so")

    def test_a_sign_in_window_that_closes_by_itself_says_how_and_when(self):
        # A window that is gone 2 s after it opened was not closed by a
        # person signing in: the log must say how long it lived and how its
        # browser ended, so the next time it happens the cause is visible.
        c = self.start(FAKE_SIGNIN_CLOSE_AFTER="0.5")
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        self.wait_engine(c, lambda e: e["status"] == "ready" and not e["signinCheck"])
        log = (self.tmp / "bridge.err").read_text()
        self.assertRegex(log, r"sign-in window closed after \d+\.\d s \(its browser exited with code 0\)")

    def test_cancel_closes_the_sign_in_window(self):
        c = self.start()
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        window = self.engine_pid()
        self.wait_engine(c, lambda e: e["status"] == "signing-in")
        self.assertTrue(c.call("window.hide")["ok"])
        eng = self.wait_engine(c, lambda e: e["status"] == "ready" and not e["signingIn"])
        self.assertFalse(self.alive(window))
        self.assertEqual(eng["signinError"], "", "Cancel is the user's choice, not a failure")

    def test_hide_while_the_sign_in_is_being_saved_keeps_the_window_until_the_cookie(self):
        # Once the window has reached the app, Google's cookie is in memory
        # only: closing it then throws the sign-in away. A stray "hide" (a key
        # the panel still had) must not end the wait.
        c = self.start(FAKE_SIGNIN_AFTER="3")
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        window = self.engine_pid()
        self.wait_engine(c, lambda e: e["status"] == "signing-in")
        self.signin_window_titled(window, "YouTube Music")
        self.wait_engine(c, lambda e: e["signinSaving"], timeout=3)
        self.assertTrue(c.call("window.hide")["ok"])
        time.sleep(0.8)
        self.assertTrue(self.alive(window), "still saving: not closed")
        eng = self.wait_engine(c, lambda e: e["status"] == "ready" and e["signedIn"] and not e["signinCheck"])
        self.assertEqual(eng["signinError"], "")
        self.assertFalse(self.alive(window))

    def test_sign_in_asked_again_right_after_one_ended_opens_no_window(self):
        # One click, one window: a request that lands just after a sign-in
        # ended (a key repeat, a second click) does not start another.
        c = self.start(SOLFA_SIGNIN_COOLDOWN="3")
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        self.wait_engine(c, lambda e: e["status"] == "signing-in")
        c.call("window.hide")
        self.wait_engine(c, lambda e: not e["signingIn"])
        (self.profile / "fake-signin-argv").unlink()
        r = c.call("signin.begin")
        self.assertFalse(r["ok"], r)
        self.assertEqual(r["error"], "signin-busy")
        time.sleep(1)
        self.assertFalse((self.profile / "fake-signin-argv").exists(), "no second window")
        self.assertIn("sign-in cancelled", (self.tmp / "bridge.err").read_text())
        time.sleep(2.5)
        self.assertTrue(c.call("signin.begin")["ok"])
        self.signin_argv()

    def test_a_sign_in_window_left_open_ends_with_an_error(self):
        # The wait always ends: a window that never reaches the app is closed
        # in the end, and the panel says the sign-in did not finish.
        c = self.start(SOLFA_SIGNIN_MAX="2")
        self.wait_ready(c)
        c.call("signin.begin")
        window = (self.signin_argv(), self.engine_pid())[1]
        eng = self.wait_engine(c, lambda e: e["status"] == "ready" and not e["signingIn"] and not e["signinCheck"], timeout=15)
        self.assertFalse(self.alive(window))
        self.assertEqual(eng["signinError"], "signin-failed")
        self.assertIn("open too long", (self.tmp / "bridge.err").read_text())

    def test_sign_in_twice_opens_one_window(self):
        c = self.start()
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        window = self.engine_pid()
        self.assertTrue(c.call("signin.begin")["ok"])
        time.sleep(1)
        self.assertEqual(self.engine_pid(), window)
        self.assertTrue(self.alive(window))

    def test_the_song_comes_back_after_sign_in(self):
        c = self.start(FAKE_SIGNIN_AFTER="3")
        self.wait_ready(c)
        c.call("play", {"videoId": "EEEEEEEEEEE"})
        c.call("seek", {"seconds": 30})
        c.wait_event(lambda m: m["event"] == "player" and m["data"]["position"] == 30)
        logged = len(self.page_log())
        c.call("signin.begin")  # closes the engine: the song stops
        end = time.time() + 20
        ops = []
        while time.time() < end:
            ops = [(e["op"], e["args"]) for e in self.page_log()[logged:]]
            if any(op == "seek" for op, _ in ops):
                break
            time.sleep(0.2)
        self.assertIn(("play", {"videoId": "EEEEEEEEEEE"}), ops)
        seeks = [a["seconds"] for op, a in ops if op == "seek"]
        # Where it stopped, not ahead by the time spent signing in (3 s here).
        self.assertTrue(seeks and 30 <= seeks[0] < 32, seeks)

    def test_stop_during_sign_in_closes_the_window(self):
        c = self.start()
        self.wait_ready(c)
        c.call("signin.begin")
        self.signin_argv()
        window = self.engine_pid()
        self.assertEqual(c.call("engine.stop")["data"]["status"], "stopped")
        self.assertFalse(self.alive(window))
        time.sleep(1.5)
        eng = c.call("hello")["data"]["engine"]
        self.assertEqual(eng["status"], "stopped")
        self.assertFalse(eng["signingIn"])

    def test_stop_during_a_slow_closing_sign_in_stays_stopped(self):
        # Chromium takes a moment to close: the closing window must not be
        # taken for a new sign-in, whose end would start the engine again.
        c = self.start(FAKE_EXIT_DELAY="2")
        self.wait_ready(c)
        c.call("play", {"videoId": "EEEEEEEEEEE"})
        c.call("signin.begin")
        self.signin_argv()
        logged = len(self.page_log())
        self.assertEqual(c.call("engine.stop")["data"]["status"], "stopped")
        time.sleep(4)
        eng = c.call("hello")["data"]["engine"]
        self.assertEqual((eng["status"], eng["signingIn"], eng["wantRunning"]), ("stopped", False, False))
        self.assertNotIn("found an open sign-in window", (self.tmp / "bridge.err").read_text())
        # A later start is a fresh start: the song is not replayed.
        c.call("engine.start")
        self.wait_ready(c)
        time.sleep(1)
        self.assertNotIn("play", [e["op"] for e in self.page_log()[logged:]])

    def test_two_sign_in_requests_at_once_open_one_window(self):
        a, b = self.start(), None
        self.wait_ready(a)
        b = Client(self.rt / "solfa" / "bridge.sock")
        self.clients.append(b)
        replies = []
        t = threading.Thread(target=lambda: replies.append(b.call("signin.begin")))
        t.start()
        replies.append(a.call("signin.begin"))
        t.join(20)
        self.assertTrue(all(r["ok"] for r in replies), replies)
        self.signin_argv()
        self.wait_engine(a, lambda e: e["status"] == "signing-in")
        time.sleep(1.5)
        self.assertEqual((self.tmp / "bridge.err").read_text().count("launching the sign-in window"), 1)
        self.assertEqual(a.call("hello")["data"]["engine"]["status"], "signing-in")

    def test_sign_in_while_the_engine_starts_keeps_the_window(self):
        c = self.start()
        c.call("signin.begin")  # the engine is still starting
        argv = self.signin_argv()
        window = self.engine_pid()
        time.sleep(3)
        self.assertTrue(self.alive(window), "the supervisor did not close the sign-in window")
        eng = c.call("hello")["data"]["engine"]
        self.assertEqual((eng["status"], eng["signingIn"]), ("signing-in", True))
        self.assertTrue(any(a.startswith("--app=https://accounts.google.com/") for a in argv))

    def test_leaving_a_google_page_takes_the_engine_back_to_the_app(self):
        # An engine left on a Google page (by an older Solfa, or a link):
        # "Back to YouTube Music" takes it home.
        c = self.start(FAKE_START_HOST="accounts.google.com")
        self.wait_engine(c, lambda e: e["status"] == "ready")
        c.call("window.hide")
        c.wait_event(lambda m: m["event"] == "account" and m["data"]["host"] == "music.youtube.com", timeout=5)
        nav = [e["args"]["url"] for e in self.page_log() if e["op"] == "navigate"]
        self.assertEqual(nav[-1], "https://music.youtube.com/")

    def test_a_navigation_that_drops_the_binding_is_noticed(self):
        # Chromium loses the page binding when a navigation changes process
        # (a Google page to YouTube Music): the bridge must add it again and
        # read the state, or it never hears the page again.
        c = self.start(FAKE_DROP_BINDING="1", FAKE_START_HOST="accounts.google.com")
        self.wait_engine(c, lambda e: e["status"] == "ready")
        c.events.clear()
        c.call("window.hide")
        c.wait_event(lambda m: m["event"] == "account" and m["data"]["host"] == "music.youtube.com", timeout=5)
        c.events.clear()
        c.call("volume", {"level": 33})
        c.wait_event(lambda m: m["event"] == "player" and m["data"]["volume"] == 33, timeout=5)

    def test_stop_closes_the_engine_and_leaves_it_closed(self):
        c = self.start()
        self.wait_ready(c)
        pid = self.engine_pid()
        self.assertEqual(c.call("engine.stop")["data"]["status"], "stopped")
        time.sleep(1.5)
        self.assertFalse(pathlib.Path(f"/proc/{pid}").exists() and b"fake_engine" in pathlib.Path(f"/proc/{pid}/cmdline").read_bytes())
        self.assertEqual(c.call("hello")["data"]["engine"]["status"], "stopped")
        r = c.call("state")
        self.assertEqual(r["error"], "engine-stopped")
        c.call("engine.start")
        self.wait_ready(c)

    def test_a_stale_engine_from_before_this_bridge_is_closed_never_adopted(self):
        # A live Chromium already holding the profile lock when the bridge
        # starts (left by an older Solfa run, or a crashed bridge): checked
        # by its pid, closed, and a fresh engine launched. Never attached to.
        stale = subprocess.Popen([str(FAKE), "--user-data-dir=" + str(self.profile), "--profile-directory=Solfa"], env=self.env)
        try:
            for _ in range(50):
                if self.engine_pid() == stale.pid:
                    break
                time.sleep(0.05)
            self.assertEqual(self.engine_pid(), stale.pid)
            c = self.start()
            self.wait_ready(c)
            self.assertNotEqual(self.engine_pid(), stale.pid, "never adopted: a fresh engine is launched instead")
            for _ in range(50):
                # poll(), not a /proc check: stale is our own child (Popen),
                # so a killed-but-unreaped process is still a zombie in /proc.
                if stale.poll() is not None:
                    break
                time.sleep(0.1)
            self.assertIsNotNone(stale.poll(), "the stale one is closed, not left running")
        finally:
            try:
                stale.kill()
            except ProcessLookupError:
                pass
            stale.wait()

    def test_the_engine_is_the_bridges_own_child(self):
        # posix_spawn, no uwsm-app/setsid: the engine lives in the bridge's
        # own process tree now, since the bridge itself (not the engine) is
        # what stays up across a shell restart.
        c = self.start()
        self.wait_ready(c)
        pid = self.engine_pid()
        ppid = int(pathlib.Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[1])
        self.assertEqual(ppid, self.proc.pid)

    def test_bridge_exit_closes_the_engine_first(self):
        # SIGTERM (systemctl --user stop, included) now stops the engine
        # before the bridge process goes away: nothing is left playing.
        c = self.start()
        self.wait_ready(c)
        pid = self.engine_pid()
        c.close()
        self.proc.send_signal(signal.SIGTERM)
        self.proc.wait(10)
        for _ in range(50):
            if not pathlib.Path(f"/proc/{pid}").exists():
                break
            time.sleep(0.1)
        self.assertFalse(pathlib.Path(f"/proc/{pid}").exists())

    def test_bridge_quit_op_stops_the_engine_and_the_bridge_exits(self):
        c = self.start()
        self.wait_ready(c)
        pid = self.engine_pid()
        r = c.call("bridge.quit")
        self.assertTrue(r["ok"], r)
        self.proc.wait(10)
        for _ in range(50):
            if not pathlib.Path(f"/proc/{pid}").exists():
                break
            time.sleep(0.1)
        self.assertFalse(pathlib.Path(f"/proc/{pid}").exists())
        self.assertFalse((self.rt / "solfa" / "bridge.sock").exists())

    def test_orphan_lease_closes_everything_with_no_ui_attach(self):
        c = self.start(SOLFA_ORPHAN_SECONDS="1")
        self.wait_ready(c)  # hello only: never ui.attach
        pid = self.engine_pid()
        self.proc.wait(10)
        for _ in range(50):
            if not pathlib.Path(f"/proc/{pid}").exists():
                break
            time.sleep(0.1)
        self.assertFalse(pathlib.Path(f"/proc/{pid}").exists())

    def test_ui_attach_holds_the_orphan_lease_off_while_connected(self):
        c = self.start(SOLFA_ORPHAN_SECONDS="1")
        self.wait_ready(c)
        self.assertTrue(c.call("ui.attach")["ok"])
        time.sleep(2.5)  # past the lease, but still attached: nothing closes
        self.assertTrue(c.call("hello")["ok"])
        c.close()
        self.proc.wait(10)  # disconnected: the lease fires from here

    def test_art_only_from_image_hosts(self):
        c = self.start()
        self.wait_ready(c)
        for url in ("http://i.ytimg.com/vi/x/hq.jpg", "https://example.com/a.jpg", "file:///etc/passwd", 5):
            self.assertEqual(c.call("art", {"videoId": "AAAAAAAAAAA", "url": url})["error"], "bad-args", url)

    # ---- Advanced settings ops (About, cache, profile erase)

    def test_engine_version_reports_the_real_engine(self):
        c = self.start()
        self.wait_ready(c)
        r = c.call("engine.version")
        self.assertTrue(r["ok"], r)
        self.assertIn("FakeChrome", r["data"]["product"])

    def test_engine_version_before_attach_is_engine_down(self):
        c = self.start(SOLFA_NO_LAUNCH="1")
        time.sleep(0.5)
        r = c.call("engine.version")
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"], "engine-down")

    def test_cache_clear_hits_network_and_storage_keeps_cookies(self):
        c = self.start(FAKE_SIGNED_IN="1")
        self.wait_ready(c)
        before = len(self.page_log())
        r = c.call("cache.clear")
        self.assertTrue(r["ok"], r)
        self.assertTrue(r["data"]["cleared"])
        ops = [e["op"] for e in self.page_log()[before:]]
        self.assertIn("cache.clear", ops)
        self.assertIn("storage.clear", ops)
        storage_call = next(e for e in self.page_log()[before:] if e["op"] == "storage.clear")
        self.assertEqual(storage_call["args"]["storageTypes"], "cache_storage,service_workers")
        self.assertEqual(storage_call["args"]["origin"], "https://music.youtube.com")
        # Cookies untouched: still signed in after the clear.
        self.assertTrue(c.call("hello")["data"]["account"]["signedIn"])

    def test_profile_erase_stops_the_engine_deletes_its_profile_and_starts_it_clean(self):
        c = self.start(FAKE_SIGNED_IN="1")
        self.wait_ready(c)
        pid = self.engine_pid()
        self.assertTrue(self.profile.exists())
        (self.profile / "Solfa" / "Cookies-fixture").write_text("x")
        self.assertEqual(c.call("profile.erase")["error"], "bad-args", "needs the UI's confirm")
        r = c.call("profile.erase", {"confirm": True})
        self.assertTrue(r["ok"], r)
        self.assertTrue(r["data"]["erased"])
        self.assertFalse(pathlib.Path(f"/proc/{pid}").exists() and b"fake_engine" in pathlib.Path(f"/proc/{pid}/cmdline").read_bytes())
        self.assertFalse((self.profile / "Solfa" / "Cookies-fixture").exists())
        # The engine comes back by itself, on a clean profile, signed out.
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "ready", timeout=20)
        self.assertNotEqual(self.engine_pid(), pid)
        self.assertFalse(c.call("hello")["data"]["account"]["signedIn"])

    def test_profile_erase_refuses_a_folder_that_is_not_an_engine_profile(self):
        other = self.tmp / "data"
        other.mkdir()
        (other / "precious.txt").write_text("keep me")
        c = self.start(SOLFA_NO_LAUNCH="1", SOLFA_PROFILE_DIR=str(other))
        time.sleep(0.5)
        r = c.call("profile.erase", {"confirm": True})
        self.assertFalse(r["ok"], r)
        self.assertEqual(r["error"], "erase-refused")
        self.assertEqual((other / "precious.txt").read_text(), "keep me")

    def test_profile_erase_waits_for_the_engine_and_refuses_while_it_holds_the_profile(self):
        c = self.start(FAKE_WONT_CLOSE="1")
        self.wait_ready(c)
        r = c.call("profile.erase", {"confirm": True}, timeout=40)
        self.assertFalse(r["ok"], r)
        self.assertEqual(r["error"], "engine-busy")
        self.assertTrue((self.profile / "Local State").exists(), "nothing deleted under a live browser")

    def test_profile_erase_reports_what_it_could_not_delete(self):
        c = self.start()
        self.wait_ready(c)
        locked = self.profile / "Solfa" / "locked"
        locked.mkdir(parents=True)
        (locked / "f").write_text("x")
        locked.chmod(0o500)
        try:
            r = c.call("profile.erase", {"confirm": True})
            self.assertFalse(r["ok"], r)
            self.assertEqual(r["error"], "erase-failed")
        finally:
            locked.chmod(0o700)

    # ---- EQ / loudness, account (Sound and Account settings)

    def test_eq_set_reaches_the_page(self):
        c = self.start()
        self.wait_ready(c)
        eq = {"bands": [6, 5, 3, 1, 0, 0, 0, 0, 0, 0], "preamp": -3, "loudness": False}
        r = c.call("eq.set", eq)
        self.assertTrue(r["ok"], r)
        sent = self.wait_op("eq.set")
        self.assertEqual(sent["bands"], eq["bands"])
        self.assertEqual(sent["preamp"], eq["preamp"])
        self.assertEqual(sent["loudness"], eq["loudness"])

    def test_eq_set_rejects_the_wrong_shape(self):
        c = self.start()
        self.wait_ready(c)
        self.assertEqual(c.call("eq.set", {"bands": [0, 0, 0], "preamp": 0, "loudness": False})["error"], "bad-args")
        self.assertEqual(c.call("eq.set", {"bands": [0] * 10, "preamp": 5, "loudness": False})["error"], "bad-args")

    def test_eq_set_is_resent_after_the_page_reloads(self):
        c = self.start()
        self.wait_ready(c)
        eq = {"bands": [0, 0, 0, 0, 0, 0, 0, 0, 0, 4], "preamp": 0, "loudness": True}
        self.assertTrue(c.call("eq.set", eq)["ok"])
        mark = len(self.page_log())
        c.call("engine.restart")
        self.wait_ready(c)
        sent = self.wait_op("eq.set", since=mark)
        self.assertEqual(sent["bands"], eq["bands"])
        self.assertEqual(sent["loudness"], eq["loudness"])

    def test_eq_set_is_resent_after_a_recycle(self):
        c = self.start(**self.RECYCLE)
        self.wait_ready(c)
        eq = {"bands": [3, 0, 0, 0, 0, 0, 0, 0, 0, -2], "preamp": -4, "loudness": True}
        self.assertTrue(c.call("eq.set", eq)["ok"])
        (self.profile / "fake-heap-mb").write_text("500")
        self.wait_op("session.arm")
        mark = len(self.page_log())
        c.call("transport", {"action": "next"})
        self.wait_op("session.restore", since=mark)
        sent = self.wait_op("eq.set", since=mark)
        self.assertEqual(sent["bands"], eq["bands"])
        self.assertEqual(sent["preamp"], eq["preamp"])
        self.assertEqual(sent["loudness"], eq["loudness"])

    def test_audio_lost_to_an_agent_update_swaps_the_page_keeping_the_song(self):
        c = self.start()
        self.wait_ready(c)
        (self.profile / "fake-eq-lost").touch()
        mark = len(self.page_log())
        c.call("eq.set", {"bands": [3] + [0] * 9, "preamp": 0, "loudness": False})
        restored = self.wait_op("session.restore", since=mark)
        self.assertEqual(restored["videoId"], "AAAAAAAAAAA")
        self.assertTrue(restored["playing"], "a song that was playing plays on")

    def test_account_info_needs_sign_in(self):
        c = self.start()
        self.wait_ready(c)
        r = c.call("account.info")
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"], "signin-required")

    def test_account_info_returns_the_parsed_account(self):
        c = self.start(FAKE_SIGNED_IN="1")
        self.wait_ready(c)
        r = c.call("account.info")
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["data"]["name"], "Alex Example")
        self.assertEqual(r["data"]["email"], "alex@example.com")

    def test_signout_navigates_to_googles_logout_and_the_page_reports_signed_out(self):
        c = self.start(FAKE_SIGNED_IN="1")
        self.wait_ready(c)
        self.assertTrue(c.call("hello")["data"]["account"]["signedIn"])
        r = c.call("signout")
        self.assertTrue(r["ok"], r)
        nav = [e for e in self.page_log() if e["op"] == "navigate"]
        self.assertTrue(nav, "no navigation")
        self.assertEqual(nav[0]["args"]["url"], "https://accounts.google.com/Logout?continue=https://music.youtube.com/")
        # Google's own redirect (continue=...) lands back on the app, signed out.
        time.sleep(0.4)
        hello = c.call("hello")["data"]
        self.assertFalse(hello["account"]["signedIn"])
        self.assertEqual(hello["account"]["host"], "music.youtube.com")

    def test_signout_resolves_from_the_pages_own_signal_when_the_navigate_reply_never_comes(self):
        # A CDP reply to Page.navigate can be outrun by Google's own redirect
        # chain (or simply never arrive): the bridge's 15 s wait for it times
        # out, but that is not a failed sign-out as long as the page itself
        # reports back on the app, signed out.
        c = self.start(FAKE_SIGNED_IN="1", FAKE_NAVIGATE_NO_REPLY="1", FAKE_LOGOUT_DELAY="0.2")
        self.wait_ready(c)
        r = c.call("signout", timeout=25)
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["data"], {"signedOut": True})
        hello = c.call("hello")["data"]
        self.assertFalse(hello["account"]["signedIn"])
        self.assertEqual(hello["account"]["host"], "music.youtube.com")

    # ---- Playback > "When Solfa starts" / "Volume at start"

    def ops_since(self, mark):
        return [(e["op"], e["args"]) for e in self.page_log()[mark:]]

    def test_start_state_applies_once_on_a_fresh_launch(self):
        c = self.start(SOLFA_START_PAUSED="1", SOLFA_START_VOLUME="30")
        self.wait_ready(c)
        self.assertEqual(self.wait_op("volume"), {"level": 30})
        self.assertEqual(self.wait_op("transport"), {"action": "pause"})
        # A restart of the running engine is not a start of Solfa: nothing
        # is paused or turned down again.
        c.call("transport", {"action": "play"})
        c.call("volume", {"level": 70})
        mark = len(self.page_log())
        c.call("engine.restart")
        self.wait_ready(c)
        time.sleep(2)
        ops = self.ops_since(mark)
        self.assertNotIn(("transport", {"action": "pause"}), ops)
        self.assertNotIn(("volume", {"level": 30}), ops)

    def test_start_state_set_over_the_socket_applies_on_the_next_start(self):
        c = self.start()
        self.wait_ready(c)
        time.sleep(1)
        self.assertNotIn("transport", [op for op, _ in self.ops_since(0)])
        self.assertTrue(c.call("start.set", {"paused": True, "volume": 25})["ok"])
        self.assertEqual(c.call("start.set", {"paused": "yes", "volume": None})["error"], "bad-args")
        self.assertEqual(c.call("start.set", {"paused": True, "volume": 150})["error"], "bad-args")
        c.call("engine.stop")
        mark = len(self.page_log())
        c.call("engine.start")
        self.wait_ready(c)
        self.assertEqual(self.wait_op("volume", since=mark), {"level": 25})
        self.assertEqual(self.wait_op("transport", since=mark), {"action": "pause"})

    def test_start_state_is_not_applied_to_the_engine_after_a_sign_in(self):
        # Autostart off: nothing launched yet, then a sign-in. The engine
        # that follows is the end of a sign-in, not a start of Solfa.
        c = self.start(SOLFA_NO_LAUNCH="1", SOLFA_START_PAUSED="1", SOLFA_START_VOLUME="30", FAKE_SIGNIN_AFTER="1")
        time.sleep(0.5)
        self.assertTrue(c.call("signin.begin")["ok"])
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "ready", timeout=20)
        time.sleep(2)
        ops = self.ops_since(0)
        self.assertNotIn(("transport", {"action": "pause"}), ops)
        self.assertNotIn(("volume", {"level": 30}), ops)

    def test_start_state_is_not_applied_to_an_engine_restarted_after_a_crash(self):
        # A crash mid-play, restarted by the same bridge: this is a restore
        # of what was playing, never a start of Solfa (start settings do
        # not apply to it, the same as the running engine a bridge used to
        # find already up before adoption was removed).
        c = self.start(SOLFA_START_PAUSED="1", SOLFA_START_VOLUME="30")
        self.wait_ready(c)
        # Let this first, genuine start of Solfa finish applying start state
        # before crashing it, or its own (correct) pause/volume ops race the
        # crash and land after `mark` below.
        self.wait_op("transport")
        old = self.engine_pid()
        c.events.clear()
        os.kill(old, signal.SIGKILL)
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "crashed")
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "ready", timeout=20)
        mark = len(self.page_log())
        time.sleep(2)
        ops = self.ops_since(mark)
        self.assertNotIn(("transport", {"action": "pause"}), ops)
        self.assertNotIn(("volume", {"level": 30}), ops)

    def test_signout_returns_only_once_the_page_is_back_on_the_app_signed_out(self):
        # Google's redirect chain takes its time: a sign-in started right
        # after signout must not cut it short.
        c = self.start(FAKE_SIGNED_IN="1", FAKE_LOGOUT_DELAY="1.5")
        self.wait_ready(c)
        r = c.call("signout")
        self.assertTrue(r["ok"], r)
        account = c.call("hello")["data"]["account"]
        self.assertEqual(account["host"], "music.youtube.com")
        self.assertFalse(account["signedIn"])

    def test_signout_with_no_engine_is_engine_down(self):
        c = self.start(SOLFA_NO_LAUNCH="1")
        time.sleep(0.5)
        r = c.call("signout")
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"], "engine-down")

    def test_switch_account_opens_googles_account_chooser_and_replays_nothing(self):
        c = self.start(FAKE_SIGNED_IN="1", FAKE_SIGNIN_AFTER="1")
        self.wait_ready(c)
        c.call("play", {"videoId": "EEEEEEEEEEE"})
        c.call("seek", {"seconds": 30})
        c.wait_event(lambda m: m["event"] == "player" and m["data"]["position"] == 30)
        self.assertTrue(c.call("signout")["ok"])
        mark = len(self.page_log())
        self.assertTrue(c.call("signin.begin", {"chooser": True})["ok"])
        for _ in range(50):
            if (self.profile / "fake-signin-argv").exists():
                break
            time.sleep(0.1)
        url = next(a for a in json.loads((self.profile / "fake-signin-argv").read_text()) if a.startswith("--app="))
        self.assertIn("accounts.google.com/AccountChooser", url)
        self.assertNotIn("passive=true", url)
        self.assertEqual(c.call("signin.begin", {"chooser": "yes"})["error"], "bad-args")
        # The old account's song does not come back under the new one.
        c.wait_event(lambda m: m["event"] == "engine" and m["data"]["status"] == "ready", timeout=20)
        time.sleep(2)
        self.assertNotIn(("play", {"videoId": "EEEEEEEEEEE"}), self.ops_since(mark))

class PureTest(unittest.TestCase):
    """Functions of the bridge that need no process."""

    @staticmethod
    def load():
        import importlib.machinery
        import importlib.util
        loader = importlib.machinery.SourceFileLoader("solfa_bridge", str(BRIDGE))
        spec = importlib.util.spec_from_loader("solfa_bridge", loader)
        mod = importlib.util.module_from_spec(spec)
        loader.exec_module(mod)
        return mod

    @staticmethod
    def load_with_env(extra_env):
        """A fresh module import under a patched environment: for the module-
        level path constants (RUNTIME_DIR, PROFILE_DIR, ...) that are only
        ever read once, at import time. Never touches the real environment
        of this test process for longer than the import itself."""
        import importlib.machinery
        import importlib.util
        old = dict(os.environ)
        os.environ.update(extra_env)
        try:
            loader = importlib.machinery.SourceFileLoader("solfa_bridge_env", str(BRIDGE))
            spec = importlib.util.spec_from_loader("solfa_bridge_env", loader)
            mod = importlib.util.module_from_spec(spec)
            loader.exec_module(mod)
            return mod
        finally:
            os.environ.clear()
            os.environ.update(old)

    @classmethod
    def setUpClass(cls):
        cls.b = cls.load()

    def test_is_signin_window_is_bridge_tracked_not_cmdline(self):
        # No more /proc/cmdline sniffing for a DevTools flag (there is none,
        # on either window any more): a lookup against what launch() itself
        # tracked.
        eng = self.b.Engine(bridge=None)
        self.assertFalse(eng.is_signin_window(4242), "nothing spawned yet")
        eng.pid, eng.is_signin = 4242, True
        self.assertTrue(eng.is_signin_window(4242))
        self.assertFalse(eng.is_signin_window(1), "a different pid")
        eng.is_signin = False
        self.assertFalse(eng.is_signin_window(4242), "tracked, but as the engine, not the sign-in window")

    def test_first_run_of_this_install_is_always_false_under_SOLFA_TEST(self):
        # The whole suite runs with SOLFA_TEST=1 (see testenv.py): a fresh
        # install must never hold up a test's own engine launch.
        self.assertFalse(self.b.first_run_of_this_install())

    def test_first_run_of_this_install_and_mark_install(self):
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-install-"))
        old = dict(os.environ)
        try:
            os.environ["SOLFA_TEST"] = ""   # falsy: exercise the real logic, not the test shortcut
            os.environ["SOLFA_STATE_DIR"] = str(tmp / "state")
            mod = self.load()
            self.assertTrue(mod.first_run_of_this_install(), "nothing marked yet")
            mod.mark_install()
            self.assertFalse(mod.first_run_of_this_install(), "marked by this install")
            # A mark from a different install (a different inode: a reinstall,
            # or another copy of the plugin) looks like a fresh install again.
            mod.INSTALL_MARK.write_text("not-this-install\n", encoding="utf-8")
            self.assertTrue(mod.first_run_of_this_install())
        finally:
            os.environ.clear()
            os.environ.update(old)
            shutil.rmtree(tmp, ignore_errors=True)

    def test_pidfd_send_signal_on_a_process_we_spawned_ourselves(self):
        # The bridge signals every engine/sign-in child this way; this test
        # exercises the exact primitive on a short-lived process of its own
        # (never a pid this test did not itself just spawn).
        pid = os.posix_spawn("/usr/bin/sleep", ["/usr/bin/sleep", "20"], dict(os.environ))
        pidfd = os.pidfd_open(pid)
        try:
            import signal as _signal
            _signal.pidfd_send_signal(pidfd, _signal.SIGTERM)
            _, status = os.waitpid(pid, 0)
            self.assertTrue(os.WIFSIGNALED(status))
            self.assertEqual(os.WTERMSIG(status), _signal.SIGTERM)
        finally:
            os.close(pidfd)

    def test_orphan_wipe_removes_only_a_path_shaped_like_plugin_id(self):
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-wipe-"))
        try:
            data_home = tmp / "data"
            data_dir = data_home / "io.github.sirallap.solfa"
            data_dir.mkdir(parents=True)
            (data_dir / "marker.txt").write_text("x")
            runtime_dir = tmp / "runtime" / "io.github.sirallap.solfa"
            runtime_dir.mkdir(parents=True)
            # M2 added CACHE_DIR/STATE_DIR and the old id's cache/runtime dirs
            # to the wipe list: isolate every one of them, or this test would
            # reach into the real machine's home (never acceptable, even for
            # a cache dir).
            mod = self.load_with_env({
                "XDG_DATA_HOME": str(data_home), "SOLFA_RUNTIME_DIR": str(runtime_dir),
                "XDG_CACHE_HOME": str(tmp / "cache"), "XDG_STATE_HOME": str(tmp / "state"),
            })
            self.assertTrue(str(mod.RUNTIME_DIR).endswith("/io.github.sirallap.solfa"))
            mod.wipe_solfa_data()
            self.assertFalse(data_dir.exists())
            self.assertFalse(runtime_dir.exists())
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_orphan_wipe_refuses_a_path_not_shaped_like_plugin_id(self):
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-wipe-"))
        try:
            runtime_dir = tmp / "runtime-not-shaped"
            runtime_dir.mkdir(parents=True)
            (runtime_dir / "marker.txt").write_text("x")
            mod = self.load_with_env({
                "XDG_DATA_HOME": str(tmp / "data-unused"), "SOLFA_RUNTIME_DIR": str(runtime_dir),
                "XDG_CACHE_HOME": str(tmp / "cache"), "XDG_STATE_HOME": str(tmp / "state"),
            })
            mod.wipe_solfa_data()
            self.assertTrue(runtime_dir.exists(), "refused: does not end in /io.github.sirallap.solfa")
            self.assertTrue((runtime_dir / "marker.txt").exists())
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_orphan_wipe_also_removes_cache_state_and_old_id_leftovers_M2(self):
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-wipe-"))
        try:
            data_home = tmp / "data"
            data_dir = data_home / "io.github.sirallap.solfa"
            data_dir.mkdir(parents=True)
            cache_home = tmp / "cache"
            cache_dir = cache_home / "io.github.sirallap.solfa"
            cache_dir.mkdir(parents=True)
            (cache_dir / "cover.jpg").write_text("x")
            state_home = tmp / "state"
            state_dir = state_home / "io.github.sirallap.solfa"
            state_dir.mkdir(parents=True)
            runtime_dir = tmp / "runtime" / "io.github.sirallap.solfa"
            runtime_dir.mkdir(parents=True)
            old_cache_dir = cache_home / "serallap.solfa"
            old_cache_dir.mkdir(parents=True)
            old_runtime_dir = tmp / "runtime" / "serallap.solfa"
            old_runtime_dir.mkdir(parents=True)
            mod = self.load_with_env({
                "XDG_DATA_HOME": str(data_home), "XDG_CACHE_HOME": str(cache_home),
                "XDG_STATE_HOME": str(state_home), "SOLFA_RUNTIME_DIR": str(runtime_dir),
            })
            mod.wipe_solfa_data()
            for gone in (data_dir, cache_dir, state_dir, runtime_dir, old_cache_dir, old_runtime_dir):
                self.assertFalse(gone.exists(), gone)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_quit_stops_the_engine_before_wiping_M1(self):
        # The old order (wipe, then stop) could lose the race against
        # Chromium still writing into the profile. Prove the new order
        # directly: engine.stop() must finish before wipe_solfa_data() runs.
        mod = self.load()
        order = []
        bridge = mod.Bridge()

        async def fake_stop():
            order.append("engine.stop")
        bridge.engine.stop = fake_stop

        def fake_wipe():
            order.append("wipe")
        real_wipe = mod.wipe_solfa_data
        mod.wipe_solfa_data = fake_wipe
        try:
            asyncio.run(bridge.quit(wipe=True))
        finally:
            mod.wipe_solfa_data = real_wipe
        self.assertEqual(order, ["engine.stop", "wipe"])

    def test_migration_closes_the_old_engine_before_renaming_M2_dir_H3(self):
        # Both the old and new plugin id's data dirs would exist for an
        # upgrader with Solfa already running: the old engine's SingletonLock
        # is checked pid-alive, closed, and only then is the dir renamed.
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-migrate-"))
        try:
            data_home = tmp / "data"
            old_dir = data_home / "serallap.solfa"
            old_engine_dir = old_dir / "engine"
            old_engine_dir.mkdir(parents=True)
            (old_dir / "shell.json").write_text("{}")  # partial state alongside the profile
            (old_engine_dir / "Preferences").write_text("{}")

            pid = os.posix_spawn(sys.executable, [sys.executable, "-c", "import time; time.sleep(30)",
                                                   "--user-data-dir=" + str(old_engine_dir)], dict(os.environ))
            try:
                (old_engine_dir / "SingletonLock").symlink_to(f"{socket.gethostname()}-{pid}")
                new_dir = data_home / "io.github.sirallap.solfa"
                self.assertFalse(new_dir.exists())

                mod = self.load_with_env({"XDG_DATA_HOME": str(data_home)})
                # migrate_old_data_dir reads SOLFA_PROFILE_DIR live, at call time (its own
                # guard against ever running when a test - or a deliberate override -
                # pointed it elsewhere), not only at import time like load_with_env's
                # module-level constants. tests/testenv.py sets it ambiently for the whole
                # suite, so it must be cleared here too, for the call itself, exactly like
                # a real, non-test process would see it unset.
                had = os.environ.pop("SOLFA_PROFILE_DIR", None)
                try:
                    mod.migrate_old_data_dir()
                finally:
                    if had is not None:
                        os.environ["SOLFA_PROFILE_DIR"] = had

                # We spawned pid ourselves, so it is our job to reap it: a
                # SIGTERM'd child is a zombie (still visible to os.kill)
                # until we do, which is not what "closed" means here.
                reaped = None
                for _ in range(50):
                    r_pid, status = os.waitpid(pid, os.WNOHANG)
                    if r_pid == pid:
                        reaped = status
                        break
                    time.sleep(0.1)
                if reaped is None:
                    self.fail("old engine was not closed before the migration")
                self.assertTrue(os.WIFSIGNALED(reaped) and os.WTERMSIG(reaped) == signal.SIGTERM)

                self.assertFalse(old_dir.exists(), "renamed away")
                self.assertTrue(new_dir.exists())
                self.assertEqual((new_dir / "shell.json").read_text(), "{}")
                self.assertTrue((new_dir / "engine" / "Preferences").exists(), "the profile inside survived")
            finally:
                with contextlib.suppress(ProcessLookupError):
                    os.kill(pid, signal.SIGKILL)
                with contextlib.suppress(ChildProcessError):
                    os.waitpid(pid, 0)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_orphan_wipe_refuses_the_real_dirs_when_SOLFA_TEST_is_set(self):
        # The exact incident, reproduced on purpose: point every path the
        # wipe would use at the owner's REAL dirs, with the test marker set,
        # and prove the wipe never gets as far as calling rmtree - not just
        # that the dirs survive, but that the delete call itself never
        # happens. shutil.rmtree is replaced with a tripwire first, so even
        # a regression in the guard fails loudly here instead of deleting
        # anything real.
        real_home = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)
        mod = self.load_with_env({
            "XDG_DATA_HOME": str(real_home / ".local" / "share"),
            "XDG_CACHE_HOME": str(real_home / ".cache"),
            "XDG_STATE_HOME": str(real_home / ".local" / "state"),
            "SOLFA_RUNTIME_DIR": str(pathlib.Path(f"/run/user/{os.getuid()}") / "io.github.sirallap.solfa"),
            "SOLFA_TEST": "1",
        })
        real_data_dir = real_home / ".local" / "share" / "io.github.sirallap.solfa"
        existed_before = real_data_dir.exists()

        # mod.shutil is the SAME shutil module object as this test's own
        # (module caching): patch and restore it, so a regression here fails
        # loudly instead of deleting anything real, without leaving other
        # tests with a broken shutil.rmtree.
        real_rmtree = shutil.rmtree

        def tripwire(*a, **k):
            raise AssertionError("rmtree called on a real path: " + repr(a))
        shutil.rmtree = tripwire
        try:
            mod.wipe_solfa_data()  # must not raise: the guard refuses before rmtree
        finally:
            shutil.rmtree = real_rmtree

        if existed_before:  # this machine may or may not have Solfa installed
            self.assertTrue(real_data_dir.exists(), "the real data dir must still be exactly where it was")

    def test_close_engine_at_falls_back_to_proc_scan_without_a_SingletonLock(self):
        # H3's second bug: the profile dir had already been wiped (so its
        # SingletonLock is gone too), yet a live Chromium still had that
        # --user-data-dir open. close_engine_at must still find and close it
        # by scanning /proc for the exact cmdline argument, never adopting
        # one of its --type= children.
        mod = self.load()
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-procscan-"))
        try:
            profile = tmp / "engine"  # never created: proves no SingletonLock is needed
            pid = os.posix_spawn(sys.executable,
                                  [sys.executable, "-c", "import time; time.sleep(30)",
                                   "--user-data-dir=" + str(profile)], dict(os.environ))
            try:
                for _ in range(50):
                    if mod.pid_from_proc_scan(profile) == pid:
                        break
                    time.sleep(0.1)
                self.assertEqual(mod.pid_from_proc_scan(profile), pid)
                self.assertTrue(mod.close_engine_at(profile))
                r_pid, status = os.waitpid(pid, 0)
                self.assertEqual(r_pid, pid)
                self.assertTrue(os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGTERM)
            finally:
                with contextlib.suppress(ProcessLookupError):
                    os.kill(pid, signal.SIGKILL)
                with contextlib.suppress(ChildProcessError):
                    os.waitpid(pid, 0)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_close_engine_at_never_adopts_a_type_child_as_the_browser(self):
        # A renderer/GPU/utility child has the same --user-data-dir but also
        # a --type= argument: the proc scan must skip it, never mistake it
        # for the main browser process.
        mod = self.load()
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-procscan-"))
        try:
            profile = tmp / "engine"
            pid = os.posix_spawn(sys.executable,
                                  [sys.executable, "-c", "import time; time.sleep(30)",
                                   "--user-data-dir=" + str(profile), "--type=renderer"], dict(os.environ))
            try:
                time.sleep(0.3)
                self.assertEqual(mod.pid_from_proc_scan(profile), 0)
            finally:
                with contextlib.suppress(ProcessLookupError):
                    os.kill(pid, signal.SIGKILL)
                with contextlib.suppress(ChildProcessError):
                    os.waitpid(pid, 0)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_watch_connection_kills_the_child_if_the_pipe_drops_but_it_lives_M4(self):
        mod = self.load()
        bridge = mod.Bridge()
        eng = bridge.engine

        pid = os.posix_spawn(sys.executable, [sys.executable, "-c", "import time; time.sleep(30)"], dict(os.environ))
        try:
            eng.pid = pid
            eng.pidfd = os.pidfd_open(pid)
            eng.is_signin = False

            class FakeCdp:
                async def run(self):
                    return  # the pipe is already closed when this returns

                def close(self):
                    pass

            eng.cdp = FakeCdp()
            asyncio.run(eng.watch_connection(eng.cdp))

            reaped = None
            for _ in range(50):
                r_pid, status = os.waitpid(pid, os.WNOHANG)
                if r_pid == pid:
                    reaped = status
                    break
                time.sleep(0.1)
            if reaped is None:
                self.fail("watch_connection did not close the child left behind by the lost pipe")
            self.assertTrue(os.WIFSIGNALED(reaped))
        finally:
            with contextlib.suppress(ProcessLookupError):
                os.kill(pid, signal.SIGKILL)
            with contextlib.suppress(ChildProcessError):
                os.waitpid(pid, 0)

    def test_recycle_knobs_from_the_environment_are_clamped(self):
        env = os.environ.copy()
        try:
            for value, want in (("-5", 200), ("5000", 700), ("450", 450), ("junk", 400), ("nan", 400), ("", 400)):
                os.environ["SOLFA_TEST_KNOB"] = value
                self.assertEqual(self.b.env_number("SOLFA_TEST_KNOB", 400, 200, 700), want, value)
        finally:
            os.environ.clear()
            os.environ.update(env)

    def test_only_an_engine_profile_may_be_erased(self):
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="solfa-erase-"))
        try:
            plain = tmp / "plain"
            plain.mkdir()
            self.assertTrue(self.b.erasable_profile(plain))
            chromium = tmp / "chromium"
            (chromium / "Default").mkdir(parents=True)
            (chromium / "Local State").touch()
            self.assertTrue(self.b.erasable_profile(chromium), "an everyday browser profile is not ours")
            ours = tmp / "engine"
            (ours / "Solfa").mkdir(parents=True)
            (ours / "Local State").touch()
            self.assertEqual(self.b.erasable_profile(ours), "")
            (ours / "Default").mkdir()
            self.assertTrue(self.b.erasable_profile(ours), "a browser's own profiles live here too")
            (ours / "Default").rmdir()
            (ours / "Profile 2").mkdir()
            self.assertTrue(self.b.erasable_profile(ours))
            (ours / "Profile 2").rmdir()
            link = tmp / "link"
            link.symlink_to(ours)
            self.assertTrue(self.b.erasable_profile(link))
            self.assertTrue(self.b.erasable_profile(pathlib.Path.home()))
            self.assertTrue(self.b.erasable_profile(pathlib.Path("/")))
            self.assertTrue(self.b.erasable_profile(pathlib.Path("relative/engine")))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_profile_in_split_and_joined_command_lines(self):
        p = "/home/someone/.local/share/io.github.sirallap.solfa/engine"
        split = b"/usr/lib/chromium/chromium\0--user-data-dir=" + p.encode() + b"\0--app=https://music.youtube.com/\0"
        joined = b"/usr/lib/chromium/chromium --ozone-platform=wayland --user-data-dir=" + p.encode() + b" --profile-directory=Solfa\0"
        self.assertTrue(self.b.uses_profile(split, p))
        self.assertTrue(self.b.uses_profile(joined, p))
        self.assertFalse(self.b.uses_profile(joined, p + "-other"))
        self.assertFalse(self.b.uses_profile(b"chromium --user-data-dir=" + p.encode() + b"x\0", p))

    def test_sign_in_cookie_is_found_by_name_and_time_only(self):
        import sqlite3
        d = pathlib.Path(tempfile.mkdtemp(prefix="solfa-ck-"))
        try:
            self.assertFalse(self.b.signed_in_since(d, 0))
            (d / "Network").mkdir()
            con = sqlite3.connect(d / "Network" / "Cookies")
            con.execute("CREATE TABLE cookies (creation_utc INTEGER, host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB)")
            at = lambda t: int((t + 11644473600) * 1_000_000)
            con.execute("INSERT INTO cookies VALUES (?, '.google.com', 'NID', '', X'00')", (at(2000),))
            con.execute("INSERT INTO cookies VALUES (?, '.example.com', 'SAPISID', '', X'00')", (at(2000),))
            con.execute("INSERT INTO cookies VALUES (?, '.youtube.com', 'SAPISID', '', X'00')", (at(1000),))
            con.commit()
            self.assertFalse(self.b.signed_in_since(d, 1500), "only YouTube's sign-in cookie, only a new one")
            self.assertTrue(self.b.signed_in_since(d, 500))
            con.execute("INSERT INTO cookies VALUES (?, '.google.com', '__Secure-3PAPISID', '', X'00')", (at(2000),))
            con.commit()
            self.assertFalse(self.b.signed_in_since(d, 1500), "Google's copy comes before YouTube's")
            con.execute("INSERT INTO cookies VALUES (?, '.youtube.com', '__Secure-3PAPISID', '', X'00')", (at(2000),))
            con.commit()
            con.close()
            self.assertTrue(self.b.signed_in_since(d, 1500))
            (d / "Network" / "Cookies").write_bytes(b"not a database")
            self.assertFalse(self.b.signed_in_since(d, 0))
        finally:
            shutil.rmtree(d)

    def test_guard_decisions(self):
        h = self.b.Hypr(bridge=None)
        h.engine_address = "0xabc"
        self.assertTrue(h.guard_decision("activewindowv2", "abc"))
        self.assertFalse(h.guard_decision("activewindowv2", "def"))
        self.assertEqual(h.last_other, "0xdef")
        self.assertTrue(h.guard_decision("activespecial", "special:solfa,DP-3"))
        self.assertFalse(h.guard_decision("activespecial", "special:scratchpad,DP-3"))
        self.assertTrue(h.guard_decision("openwindow", "abc,1,chrome-music.youtube.com__-Solfa,YouTube Music"))
        self.assertFalse(h.guard_decision("openwindow", "abc,special:solfa,chrome-music.youtube.com__-Solfa,YouTube Music"))
        self.assertFalse(h.guard_decision("openwindow", "abc,1,chrome-music.youtube.com__-Default,YouTube Music"))
        h.shown = True
        self.assertFalse(h.guard_decision("activewindowv2", "abc"))

    def test_pipe_round_trip(self):
        import asyncio as _asyncio

        async def go():
            to_r, to_w = os.pipe()      # bridge -> browser
            from_r, from_w = os.pipe()  # browser -> bridge
            bridge_side = await self.b.Pipe.open(to_w, from_r)
            browser_side = await self.b.Pipe.open(from_w, to_r)
            try:
                await bridge_side.send('{"id":1}')
                self.assertEqual(await browser_side.recv(), '{"id":1}')
                await browser_side.send('{"result":true}')
                self.assertEqual(await bridge_side.recv(), '{"result":true}')
            finally:
                bridge_side.close()
                browser_side.close()
        _asyncio.run(go())

    def test_pipe_fails_closed_over_the_cap(self):
        import asyncio as _asyncio

        async def go():
            old = self.b.MAX_CDP_MESSAGE
            self.b.MAX_CDP_MESSAGE = 16  # small on purpose: no 32 MiB write in a unit test
            try:
                to_r, to_w = os.pipe()
                from_r, from_w = os.pipe()
                bridge_side = await self.b.Pipe.open(to_w, from_r)
                browser_side = await self.b.Pipe.open(from_w, to_r)
                try:
                    await browser_side.send("x" * 100)  # over the cap, no NUL within it
                    self.assertIsNone(await bridge_side.recv(), "fails closed on an oversized message")
                    self.assertTrue(bridge_side.closed)
                finally:
                    bridge_side.close()
                    browser_side.close()
            finally:
                self.b.MAX_CDP_MESSAGE = old
        _asyncio.run(go())

    def test_every_request_gets_an_answer(self):
        import asyncio as _asyncio
        sent = []

        class W:
            transport = type("T", (), {"get_write_buffer_size": lambda self: 0})()
            def write(self, b): sent.append(json.loads(b))

        async def go():
            br = self.b.Bridge()

            async def boom(op, args):
                raise RuntimeError("unexpected")
            br.dispatch = boom
            await br.handle(W(), b'{"id": 9, "op": "state", "args": {}}\n')
        _asyncio.run(go())
        self.assertEqual(sent[0]["id"], 9)
        self.assertEqual(sent[0]["error"], "internal-error")

    def test_page_junk_does_not_replace_the_account(self):
        import asyncio as _asyncio

        async def go():
            br = self.b.Bridge()
            br.engine.account = {"signedIn": True, "host": "music.youtube.com"}
            payload = json.dumps({"t": "account", "data": "x"})
            br.engine.on_event({"method": "Runtime.bindingCalled", "params": {"name": "__solfaEmit", "payload": payload}})
            payload = json.dumps({"t": "hello", "data": {"account": "x"}})
            br.engine.on_event({"method": "Runtime.bindingCalled", "params": {"name": "__solfaEmit", "payload": payload}})
            return br.engine.account, br.engine.describe()
        account, desc = _asyncio.run(go())
        self.assertEqual(account["host"], "music.youtube.com")
        self.assertTrue(desc["signedIn"])

    def test_rule_matches_only_our_engine(self):
        import re as _re
        rx = self.b.WINDOW_CLASS_RE
        self.assertTrue(_re.fullmatch(rx, "chrome-music.youtube.com__-Solfa"))
        self.assertTrue(_re.fullmatch(rx, "brave-music.youtube.com__-Solfa"))
        self.assertFalse(_re.fullmatch(rx, "chrome-music.youtube.com__-Default"))
        self.assertFalse(_re.fullmatch(rx, "chrome-music.youtube.com__explore-Default"))
        lua = self.b.Hypr.rule_lua()
        self.assertIn("special:solfa silent", lua)
        self.assertIn("focus_on_activate = false", lua)
        self.assertIn("suppress_event = [[activate activatefocus]]", lua)


class ImportPureTest(unittest.TestCase):
    """The signout safety left behind by "Use my browser's sign-in" (removed),
    and the child-process/absolute-path helpers (B3), that need no process."""

    @classmethod
    def setUpClass(cls):
        cls.b = PureTest.load()

    def test_sign_out_covers_google_country_domains(self):
        fam = self.b.google_family
        for d in (".google.com", ".google.es", "accounts.google.co.uk", ".google.com.br", ".youtube.com", "music.youtube.com", ".youtube.de"):
            self.assertTrue(fam(d), d)
        for d in ("evilgoogle.com", ".google.com.evil.test", "googleusercontent.com", ".example.com", "", "google.example.org"):
            self.assertFalse(fam(d), d)

    @staticmethod
    @contextlib.contextmanager
    def _patched_env(extra):
        """find_browser() and child_env() read os.environ at CALL time (not
        import time, unlike the module-level path constants), so testing them
        needs the patch held across the call, not just across the import that
        PureTest.load_with_env() covers."""
        old = dict(os.environ)
        os.environ.update(extra)
        try:
            yield
        finally:
            os.environ.clear()
            os.environ.update(old)

    def test_find_browser_refuses_a_relative_setting(self):
        with self._patched_env({"SOLFA_BROWSER": "chromium"}):
            path, error = self.b.find_browser()
        self.assertEqual(path, "")
        self.assertEqual(error, "browser must be an absolute path")

    def test_find_browser_refuses_a_nonexistent_absolute_path(self):
        with self._patched_env({"SOLFA_BROWSER": "/no/such/browser-anywhere"}):
            path, error = self.b.find_browser()
        self.assertEqual(path, "")
        self.assertIn("no Chromium-family browser", error)

    def test_find_browser_accepts_an_absolute_executable_path(self):
        with self._patched_env({"SOLFA_BROWSER": str(FAKE)}):
            path, error = self.b.find_browser()
        self.assertEqual(path, str(FAKE))
        self.assertEqual(error, "")

    def test_child_env_path_is_always_fixed(self):
        with self._patched_env({"PATH": "/some/attacker/controlled/path:/usr/bin"}):
            env = self.b.child_env()
        self.assertEqual(env["PATH"], "/usr/bin:/bin")

    def test_child_env_drops_anything_not_on_the_allow_list(self):
        with self._patched_env({"SOLFA_TEST_SHOULD_NOT_LEAK": "1", "LC_TIME": "C", "XDG_DATA_HOME": "/x"}):
            env = self.b.child_env()
        self.assertNotIn("SOLFA_TEST_SHOULD_NOT_LEAK", env)
        self.assertEqual(env.get("LC_TIME"), "C")
        self.assertEqual(env.get("XDG_DATA_HOME"), "/x")

    def test_child_env_extra_overrides(self):
        env = self.b.child_env({"TMPDIR": "/tmp/solfa-import-xyz"})
        self.assertEqual(env["TMPDIR"], "/tmp/solfa-import-xyz")
        self.assertEqual(env["PATH"], "/usr/bin:/bin")


class SpawnFdTest(unittest.TestCase):
    """The engine's pipe must reach it on fds 3 and 4 even when 3 and 4 are
    free in the bridge (a bridge started by systemd has only 0-2 open, and
    an engine restart frees the old pipe's numbers)."""

    CHILD = r"""
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("solfa_bridge", sys.argv[1])
spec = importlib.util.spec_from_loader("solfa_bridge", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
probe = [sys.executable, "-c",
         "import os; os.write(4, os.read(3, 4) + b'\\0')"]
for n in range(3):
    for fd in (3, 4):
        try:
            os.close(fd)
        except OSError:
            pass
    pid, pidfd, to_fd, from_fd = mod.Engine._spawn(None, probe, True)
    os.write(to_fd, b"ping")
    os.close(to_fd)
    got = os.read(from_fd, 16)
    os.close(from_fd)
    os.waitpid(pid, 0)
    os.close(pidfd)
    if got != b"ping\0":
        sys.exit("round %d: got %r" % (n, got))
"""

    def test_pipe_reaches_fds_3_and_4_when_they_are_free(self):
        r = subprocess.run([sys.executable, "-c", self.CHILD, str(BRIDGE)], capture_output=True, text=True,
                           timeout=30, close_fds=True)
        self.assertEqual(r.returncode, 0, r.stderr[-800:])


if __name__ == "__main__":
    unittest.main(verbosity=1)
