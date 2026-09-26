#!/usr/bin/python3
"""A stand-in for Chromium, for the bridge tests.

The bridge posix_spawns it exactly as it would spawn the real browser (it is
given as SOLFA_BROWSER), dup'ing a pipe onto its fd 3 (reads bridge -> browser
commands there) and fd 4 (writes browser -> bridge events/replies there) —
the same convention --remote-debugging-pipe uses. It writes SingletonLock
into the --user-data-dir, speaks a small part of the DevTools protocol over
that pipe, and plays the page agent: operations get canned answers, and the
agent's pushes arrive as Runtime.bindingCalled events.

Launched without --remote-debugging-pipe it is the sign-in window instead:
no DevTools, only the profile lock. It writes its argv to fake-signin-argv,
then (FAKE_SIGNIN_AFTER seconds) Google's sign-in cookie into the profile's
cookie database, and (FAKE_SIGNIN_CLOSE_AFTER seconds) closes by itself, as
a user closing the window. A later engine on that profile is signed in.

Control files in the profile dir let a test change its behaviour:
  fake-hang        stop answering Runtime.evaluate (a stuck renderer)
  fake-stuck-hard  Page.reload does not help while this exists
  fake-log         one JSON line per page operation it received (written by it)
  fake-eq-lost     the next eq.set reports the audio graph lost (an agent update)

FAKE_WONT_CLOSE=1 makes it ignore Browser.close and SIGTERM (only SIGKILL ends it).
"""
import asyncio
import json
import os
import pathlib
import re
import signal
import socket
import sqlite3
import sys
import time

args = {a.split("=", 1)[0]: (a.split("=", 1)[1] if "=" in a else "") for a in sys.argv[1:]}
PROFILE = pathlib.Path(args["--user-data-dir"])

COOKIES = PROFILE / "Solfa" / "Network" / "Cookies"


def has_signin_cookie():
    try:
        con = sqlite3.connect(COOKIES)
        try:
            return bool(con.execute("SELECT 1 FROM cookies WHERE name = 'SAPISID'").fetchone())
        finally:
            con.close()
    except sqlite3.Error:
        return False


state = {
    "host": "" if os.environ.get("FAKE_START_BLANK") == "1" else (os.environ.get("FAKE_START_HOST") or "music.youtube.com"),
    "signedIn": os.environ.get("FAKE_SIGNED_IN") == "1" or has_signin_cookie(),
    "player": {"videoId": "AAAAAAAAAAA", "title": "First Light", "artists": [{"name": "Mira Solvent", "id": "UCfixture"}],
               "album": None, "thumb": "", "kind": "song", "duration": 200, "position": 12, "at": 0, "playing": True,
               "buffering": False, "ended": False, "ad": False, "volume": 100, "muted": False, "repeat": "NONE",
               "shuffle": False, "like": "INDIFFERENT", "index": 0, "canNext": True, "canPrev": True},
    "queueVersion": 1,
    "navigations": [],
    # Google cookies in the jar: (name, domain, path). A consent answer is
    # there from the start, as in a real profile; FAKE_JAR (comma-separated
    # names) seeds more, for tests of a session already signed in when the
    # engine starts (a profile carrying the old browser-import marker, say).
    "jar": {("SOCS", ".youtube.com", "/")} | {
        (name, ".google.com", "/") for name in filter(None, os.environ.get("FAKE_JAR", "").split(","))},
}
# The bridge's own end of the pipe: exactly one at a time (a pipe is not a
# listening socket), set once run_pipe() has the transport up.
conn = None


def hang():
    return (PROFILE / "fake-hang").exists()


def record(op, a):
    with open(PROFILE / "fake-log", "a") as f:
        f.write(json.dumps({"op": op, "args": a}) + "\n")


def send_to_bridge(msg):
    if conn is not None:
        asyncio.get_running_loop().create_task(conn.send(json.dumps(msg)))


def emit_event(kind, data):
    # Like Chromium after a cross-site navigation: the page's binding is gone
    # until the bridge adds it again, and pushes fall on the floor.
    if state.get("binding_lost"):
        return
    if kind == "player":
        data["at"] = int(time.time() * 1000)  # the page's clock, as the agent stamps it
    payload = json.dumps({"t": kind, "v": "fake", "data": data})
    msg = {"method": "Runtime.bindingCalled", "params": {"name": "__solfaEmit", "payload": payload, "executionContextId": 1},
           "sessionId": "S1"}
    send_to_bridge(msg)


def swap_renderer():
    """Like Chromium committing a slow first load after the bridge attached:
    a new document in a new renderer, the same URL, no binding; the app
    comes up signed in and says hello (which falls on the floor)."""
    state["binding_lost"] = True
    state["signedIn"] = True
    url = "https://" + state["host"] + "/"
    msg = {"method": "Page.frameNavigated", "params": {"frame": {"id": "F1", "url": url}}, "sessionId": "S1"}
    if os.environ.get("FAKE_SWAP_SILENT") != "1":
        send_to_bridge(msg)
    account = {"signedIn": True, "host": state["host"], "path": "/"}
    asyncio.get_running_loop().call_later(0.1, lambda: emit_event("hello", {"version": "fake", "account": account}))


STARTED = time.monotonic()
LATE_PLAYER = float(os.environ.get("FAKE_LATE_PLAYER") or 0)   # seconds before the app has a player
AD_SECONDS = float(os.environ.get("FAKE_AD_SECONDS") or 0)     # an advert before each played song


def page_op(op, a):
    """The agent's side, canned. Returns (value, error-code)."""
    record(op, a)
    p = state["player"]
    if state["host"] != "music.youtube.com":
        return None, "not-on-app"
    if op in ("volume", "play", "seek", "transport", "mute") and time.monotonic() - STARTED < LATE_PLAYER:
        return None, "no-player"
    if op == "state":
        return {"player": p, "account": {"signedIn": state["signedIn"], "host": state["host"], "path": "/"}, "queueVersion": state["queueVersion"]}, None
    if op == "transport":
        if a["action"] == "next":
            p["videoId"], p["position"] = "NNNNNNNNNNN", 0
            if state.get("armed"):
                # The agent stops the new song at once and says so.
                state["armed"] = False
                p["playing"] = False
                emit_event("player", p)
                emit_event("recycle", {"videoId": p["videoId"]})
                return {"done": True}, None
        if a["action"] == "toggle":
            p["playing"] = not p["playing"]
        elif a["action"] in ("play", "pause"):
            p["playing"] = a["action"] == "play"
        emit_event("player", p)
        return {"done": True}, None
    if op == "seek":
        p["position"] = a["seconds"]
        emit_event("player", p)
        return {"position": a["seconds"]}, None
    if op == "volume":
        p["volume"] = a["level"]
        emit_event("player", p)
        return {"volume": a["level"]}, None
    if op == "play":
        p["videoId"] = a.get("videoId") or p["videoId"]
        p["position"] = 0
        p["playing"] = True
        if AD_SECONDS:
            p["ad"] = True
            played = p["videoId"]

            def ad_over():
                if p["videoId"] == played:
                    p["ad"] = False
                    emit_event("player", p)
            asyncio.get_running_loop().call_later(AD_SECONDS, ad_over)
        emit_event("player", p)
        return {"landed": "app"}, None
    if op == "eq.set" and (PROFILE / "fake-eq-lost").exists():
        # An older agent took the audio graph with it (see agent.js).
        (PROFILE / "fake-eq-lost").unlink()
        emit_event("eq-lost", {})
        return {"applied": True, "built": False}, None
    if op == "session.arm":
        state["armed"] = bool(a.get("armed"))
        return {"armed": state["armed"]}, None
    if op == "session.save":
        if (PROFILE / "fake-save-fails").exists():
            return None, "no-queue"
        return {"items": [{"id": 1}], "selectedItemIndex": 0, "nextQueueItemId": 1, "videoId": p["videoId"],
                "position": p["position"], "playing": p["playing"], "volume": p["volume"], "muted": p["muted"],
                "repeatMode": p["repeat"]}, None
    if op == "session.restore":
        p.update(videoId=a["videoId"], position=a["position"], playing=a["playing"], volume=a["volume"])
        emit_event("player", p)
        return {"restored": "song"}, None
    if op == "search":
        return {"top": None, "songs": [{"kind": "song", "videoId": "BBBBBBBBBBB", "title": "Result for " + a["q"]}],
                "videos": [], "albums": [], "artists": [], "playlists": [], "other": [], "continuation": ""}, None
    if op in ("like", "library", "account.info") and not state["signedIn"]:
        return None, "signin-required"
    if op == "account.info":
        # An invented account (never a real one): Alex Example, alex@example.com.
        return {"name": "Alex Example", "email": "alex@example.com",
                "avatar": "https://lh3.googleusercontent.com/a/fixture=s64-c-mo"}, None
    if op == "queue":
        return {"items": [], "automix": [], "index": 0, "version": state["queueVersion"]}, None
    return {"ok": True}, None


class Pipe:
    """The bridge-side transport's mirror image: NUL-terminated JSON, one
    message per direction, on the fds the bridge dup'd for us (fd 3 to read
    its commands, fd 4 to write our events and replies)."""

    def __init__(self, reader, writer):
        self.reader, self.writer = reader, writer

    async def send(self, text):
        try:
            self.writer.write(text.encode("utf-8") + b"\0")
            await self.writer.drain()
        except (ConnectionError, OSError):
            pass

    async def recv(self):
        try:
            data = await self.reader.readuntil(b"\0")
        except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, ConnectionError, OSError):
            return None
        return data[:-1].decode("utf-8", "replace")


def redirect_after_logout():
    """Google's Logout URL (continue=...) lands back on the app, signed out:
    the same one navigation a real browser would end up doing by itself."""
    state["host"] = "music.youtube.com"
    record("navigate", {"url": "https://music.youtube.com/"})
    info = {"method": "Target.targetInfoChanged", "params": {"targetInfo": {"targetId": "T1", "type": "page", "url": "https://music.youtube.com/"}}}
    send_to_bridge(info)
    emit_event("hello", {"version": "fake", "account": {"signedIn": state["signedIn"], "host": state["host"], "path": "/"}})


OP_RE = re.compile(r'^window\.__solfa \? window\.__solfa\.call\((".*?"), (.*)\) : Promise\.reject', re.S)


async def handle(ws, msg):
    mid, method, params = msg.get("id"), msg.get("method"), msg.get("params") or {}
    result, error = {}, None
    if method == "Target.getTargets":
        result = {"targetInfos": [{"targetId": "T1", "type": "page", "url": ("https://" + state["host"] + "/") if state["host"] else "about:blank", "attached": False}]}
    elif method == "Target.attachToTarget":
        result = {"sessionId": "S1"}
        # Chromium reports the page (title, url) as changed around an attach.
        info = {"method": "Target.targetInfoChanged", "params": {"targetInfo": {"targetId": "T1", "type": "page", "url": "https://" + state["host"] + "/"}}}
        asyncio.get_running_loop().call_later(0.05, lambda: asyncio.get_running_loop().create_task(ws.send(json.dumps(info))))
        swap = float(os.environ.get("FAKE_SWAP_AFTER_ATTACH") or 0)
        if swap and not state.get("swapped"):
            state["swapped"] = True
            asyncio.get_running_loop().call_later(swap, swap_renderer)
    elif method == "Runtime.evaluate":
        expr = params.get("expression", "")
        if hang():
            return  # never answer
        if "SolfaParse" in expr and "__solfaEmit" in expr:
            asyncio.get_running_loop().call_later(0.05, lambda: emit_event("hello", {"version": "fake", "account": {"signedIn": state["signedIn"], "host": state["host"], "path": "/"}}))
            result = {"result": {"type": "undefined"}}
        elif expr == "location.hostname":
            result = {"result": {"type": "string", "value": state["host"]}}
        elif expr == "1":
            result = {"result": {"type": "number", "value": 1}}
        elif expr == "typeof __solfaEmit":
            result = {"result": {"type": "string", "value": "undefined" if state.get("binding_lost") else "function"}}
        elif "ListAccounts" in expr:
            record("listaccounts", {})
            result = {"result": {"type": "number", "value": int(os.environ.get("FAKE_ACCOUNTS") or 2)}}
        else:
            m = OP_RE.match(expr)
            if not m:
                result = {"exceptionDetails": {"text": "Uncaught", "exception": {"description": "Error: unknown-expression"}}}
            else:
                value, err = page_op(json.loads(m.group(1)), json.loads(m.group(2)))
                if err:
                    result = {"exceptionDetails": {"text": "Uncaught", "exception": {"description": "Error: " + err + "\n    at call"}}}
                else:
                    result = {"result": {"type": "object", "value": value}}
    elif method.startswith("ServiceWorker."):
        record(method, {})
    elif method == "Runtime.getHeapUsage":
        try:
            mb = float((PROFILE / "fake-heap-mb").read_text())
        except (OSError, ValueError):
            mb = 50
        result = {"usedSize": mb * (1 << 20), "totalSize": mb * (1 << 20)}
    elif method == "Runtime.addBinding":
        state["binding_lost"] = False
    elif method == "Page.navigate":
        url = params.get("url", "")
        state["navigations"].append(url)
        record("navigate", {"url": url})
        old = state["host"]
        is_logout = url.startswith("https://accounts.google.com/Logout")
        if is_logout:
            state["signedIn"] = False
        m = re.match(r"https://([^/?]+)", url)
        state["host"] = m.group(1) if m else ""
        # "always": Chromium can swap the page's renderer on a same-URL
        # reload too, when the Google session changed under it.
        drop = os.environ.get("FAKE_DROP_BINDING")
        if drop == "always" or (drop == "1" and old != state["host"]):
            state["binding_lost"] = True
        info = {"method": "Target.targetInfoChanged", "params": {"targetInfo": {"targetId": "T1", "type": "page", "url": url}}}
        send_to_bridge(info)
        if (os.environ.get("FAKE_COOKIE_COMES_BACK") == "1" and state["host"] == "music.youtube.com"
                and not state["signedIn"] and not state.get("came_back") and state["jar"] - {("SOCS", ".youtube.com", "/")} == set()
                and any(e for e in state["navigations"] if e == "about:blank")):
            # A request in flight from before the sign-out sets one back.
            state["came_back"] = True
            state["jar"].add(("LOGIN_INFO", ".youtube.com", "/"))
            record("jar", {"names": sorted({n for n, _, _ in state["jar"]})})
        account = {"signedIn": state["signedIn"], "host": state["host"], "path": "/"}
        if state["host"] == "music.youtube.com":
            asyncio.get_running_loop().call_later(0.05, lambda: emit_event("hello", {"version": "fake", "account": account}))
        else:
            asyncio.get_running_loop().call_later(0.05, lambda: emit_event("account", account))
            if is_logout:
                # Google's own redirect (continue=...): back to the app, signed out.
                asyncio.get_running_loop().call_later(float(os.environ.get("FAKE_LOGOUT_DELAY") or 0.15), redirect_after_logout)
        if is_logout and os.environ.get("FAKE_NAVIGATE_NO_REPLY") == "1":
            # Like a CDP reply that never lands (the tab is mid-navigation):
            # everything above still happens, only this call's own reply
            # does not. The bridge must fall back to the page's own signal.
            return
    elif method == "Page.reload":
        record("reload", {})
        if not (PROFILE / "fake-stuck-hard").exists():
            (PROFILE / "fake-hang").unlink(missing_ok=True)
            asyncio.get_running_loop().call_later(0.1, lambda: emit_event("hello", {"version": "fake", "account": {"signedIn": state["signedIn"], "host": state["host"], "path": "/"}}))
    elif method == "Browser.close":
        await ws.send(json.dumps({"id": mid, "result": {}}))
        if os.environ.get("FAKE_WONT_CLOSE") != "1":
            os._exit(0)
    elif method == "Browser.getVersion":
        result = {"product": "FakeChrome/999.0.0.0", "userAgent": "Mozilla/5.0 (Fake)"}
    elif method == "Network.clearBrowserCache":
        # A page-target domain, as in Chromium: the browser target has no Network.
        if not msg.get("sessionId"):
            error = "'Network.clearBrowserCache' wasn't found"
        else:
            record("cache.clear", {})
    elif method == "Storage.clearDataForOrigin":
        record("storage.clear", params)
    elif method == "Storage.setCookies":
        # Names and domains only in the log: a test checks no value leaks
        # anywhere, this log included.
        cookies = params.get("cookies") or []
        record("cookies.set", {"cookies": [{"name": c.get("name"), "where": c.get("domain") or c.get("url")} for c in cookies]})
        broken = os.environ.get("FAKE_SETCOOKIES_BREAKS") == "1"
        for c in cookies[:1] if broken else cookies:
            where = c.get("domain") or re.sub(r"^https://([^/]+).*", r"\1", c.get("url") or "")
            state["jar"].add((c.get("name"), where, c.get("path") or "/"))
        record("jar", {"names": sorted({n for n, _, _ in state["jar"]})})
        if broken:
            error = "Invalid cookie fields"
        elif os.environ.get("FAKE_IMPORT_REJECTED") != "1" and any(c.get("name") == "SID" for c in cookies):
            state["signedIn"] = True
            # As Google does: the session is copied to a country domain.
            state["jar"].add(("SID", ".google.es", "/"))
            record("jar", {"names": sorted({n for n, _, _ in state["jar"]})})
    elif method == "Storage.getCookies":
        result = {"cookies": [{"name": n, "domain": d, "path": p, "value": "x"} for n, d, p in sorted(state["jar"])]}
    elif method == "Network.deleteCookies":
        key = (params.get("name"), params.get("domain"), params.get("path") or "/")
        record("cookies.delete", {"name": key[0], "domain": key[1]})
        state["jar"].discard(key)
        record("jar", {"names": sorted({n for n, _, _ in state["jar"]})})
        if key[0] == "SID" and not any(n == "SID" for n, _, _ in state["jar"]):
            state["signedIn"] = False
    out = {"id": mid, "result": result} if error is None else {"id": mid, "error": {"message": error}}
    if msg.get("sessionId"):
        out["sessionId"] = msg["sessionId"]
    await ws.send(json.dumps(out))


async def run_pipe():
    """Read commands off fd 3 (dup'd there by the bridge's posix_spawn),
    write events and replies to fd 4, exactly as a real --remote-debugging-
    pipe browser would. Runs until the bridge closes its end."""
    global conn
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader(limit=1 << 25)
    read_file = os.fdopen(3, "rb", buffering=0)
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), read_file)
    write_file = os.fdopen(4, "wb", buffering=0)
    write_transport, write_protocol = await loop.connect_write_pipe(asyncio.streams.FlowControlMixin, write_file)
    writer = asyncio.StreamWriter(write_transport, write_protocol, reader, loop)
    conn = Pipe(reader, writer)
    try:
        while True:
            text = await conn.recv()
            if text is None:
                break
            asyncio.get_running_loop().create_task(handle(conn, json.loads(text)))
    except (asyncio.IncompleteReadError, ConnectionError):
        pass


def take_lock():
    lock = PROFILE / "SingletonLock"
    lock.unlink(missing_ok=True)
    os.symlink(f"{socket.gethostname()}-{os.getpid()}", lock)


def write_signin_cookie():
    """Google's sign-in cookie, as Chromium stores it (the value is a dummy)."""
    COOKIES.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(COOKIES)
    con.execute("CREATE TABLE IF NOT EXISTS cookies (creation_utc INTEGER, host_key TEXT, name TEXT, value TEXT, "
                "encrypted_value BLOB)")
    created = int((time.time() + 11644473600) * 1_000_000)
    con.execute("INSERT INTO cookies VALUES (?, '.google.com', 'SAPISID', '', X'763130')", (created,))
    con.execute("INSERT INTO cookies VALUES (?, '.youtube.com', 'SAPISID', '', X'763130')", (created,))
    con.commit()
    con.close()


async def signin_window():
    (PROFILE / "fake-signin-argv").write_text(json.dumps(sys.argv[1:]))
    take_lock()

    def close(*_):
        # Chromium removes its lock on a clean exit.
        (PROFILE / "SingletonLock").unlink(missing_ok=True)
        os._exit(0)

    def slow_close(*_):
        # A clean exit takes a while (Chromium writes its cookies first).
        time.sleep(float(os.environ.get("FAKE_EXIT_DELAY") or 0))
        close()

    signal.signal(signal.SIGTERM, slow_close)
    after = os.environ.get("FAKE_SIGNIN_AFTER")
    close_after = os.environ.get("FAKE_SIGNIN_CLOSE_AFTER")
    start = time.monotonic()
    while True:
        await asyncio.sleep(0.05)
        if after is not None and time.monotonic() - start >= float(after):
            write_signin_cookie()
            after = None
        if close_after is not None and time.monotonic() - start >= float(close_after):
            close()


async def main():
    PROFILE.mkdir(parents=True, exist_ok=True)
    # What Chromium lays out on its first start: its Local State file and
    # the profile directory it was given.
    (PROFILE / "Local State").touch()
    (PROFILE / args.get("--profile-directory", "Default")).mkdir(exist_ok=True)
    if "--remote-debugging-pipe" not in args:
        await signin_window()
    take_lock()
    if os.environ.get("FAKE_WONT_CLOSE") == "1":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)  # a browser that will not go
    await run_pipe()
    # A real browser keeps running once its DevTools pipe closes (it does
    # not mean "exit"); stay alive until SIGTERM/SIGKILL, same as before.
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
