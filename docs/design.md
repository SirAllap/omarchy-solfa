# Solfa — design

Solfa is a YouTube Music player for the Omarchy shell. Everything happens in
a bar widget and a keyboard panel. The web app that plays the audio is an
engine: it is never seen and never takes focus.

## Name

Three options were considered:

1. **Solfa** — from tonic sol-fa (do, re, mi). Short, musical, easy to type.
2. **Fermata** — the "hold" sign in music. Pretty, but longer and harder to spell.
3. **Refrain** — the part of a song that comes back. Also means "to hold back".

Picked **Solfa**, plugin id `io.github.sirallap.solfa`. No trademark in the name, and no
"YouTube" in it.

## Parts

```
 bar widget ─┐                      ┌─ hidden Chromium window (the engine)
 panel ──────┼─ Service.qml ── unix socket ── bin/solfa-bridge ── CDP (loopback)
 IPC/keys ───┘   (state, actions)    (JSON lines)  (Python, stdlib)   │
                                                          page agent ─┘
                                                     (engine/agent.js)
```

- **Engine.** Chromium with its own profile (`~/.local/share/io.github.sirallap.solfa/engine`)
  and its own profile directory name, so its Wayland app id is
  `chrome-music.youtube.com__-Solfa`. It never matches TekTube or a YouTube
  Music web app the user opens. A Hyprland rule (registered at runtime with
  `hyprctl eval`) maps it straight into `special:solfa`, silent, with no initial
  focus, no animation, `focus_on_activate = false` and `suppress_event =
  activate activatefocus`. It is the bridge's own child (`os.posix_spawn`,
  tracked and signalled by `pidfd`), never adopted from a previous run; a
  shell restart does not stop the music because the **bridge**, not the
  engine, is what stays up across one (see Bridge lifetime, below).
- **Bridge** (`bin/solfa-bridge`). Python, standard library only, asyncio. It
  spawns the engine itself and attaches over the Chrome DevTools protocol on
  a pipe (`--remote-debugging-pipe`, no TCP port anywhere), injects the page
  agent, and serves the shell on `$XDG_RUNTIME_DIR/io.github.sirallap.solfa/bridge.sock`
  (directory 0700, socket 0600). It has a fixed list of operations, and it
  checks every argument before anything reaches the page.
- **Page agent** (`engine/agent.js` + `engine/parse.js`). Runs inside the web
  app. It calls the app's own InnerTube API with the page's own sign-in, and it
  drives the app's own player and queue store. It never reads cookies out of the
  page. It **pushes** changes through a DevTools binding (`Runtime.addBinding`):
  play, pause, seek, track, volume, queue, likes, sign-in. The bridge does no
  polling for state.
- **Service** (`Service.qml`). Keeps one copy of the state for every bar and the
  panel. Position is computed locally from the last pushed position and a
  timestamp, so nothing ticks while nothing is visible.
- **Bar widget** and **panel** (`BarWidget.qml`, `Panel.qml`, `views/`).

## What is better than TekTube (on purpose)

| Topic | TekTube | Solfa |
|---|---|---|
| Song change | full page load (window can jump forward, audio gap, MPRIS flicker) | in-app navigation (`yt-navigate`), same document |
| State | MPRIS for transport + polling the page | pushed from the page through a binding; MPRIS is left to Chromium for media keys |
| Volume | MPRIS (ignored by Chromium) | the player (`setVolume`) plus the app's own `SET_VOLUME`, so the web app keeps it |
| Likes | read from a page button that API calls do not update | the app's store (`SET_VIDEO_LIKE_STATUS`) is updated with every like |
| Search | subtitle parts read by position (broke in Spanish) | every item classified by its endpoints (page type, video type), never by text |
| Window id | shared with any YouTube Music web app | own profile directory name, own app id |
| Engine crash or hang | manual reload | watchdog; restart and restore the track, position and play state |
| Idle cost | endless animations (record, equalizer) | no endless animations; a 1 Hz tick only while playing and visible |
| Bridge | threads and locks | one asyncio loop, bounded reads, slow clients dropped |

## Protocol (shell ↔ bridge)

One JSON object per line.

- Request: `{"id": 7, "op": "search", "args": {"q": "…"}}`
- Reply: `{"id": 7, "ok": true, "data": …}` or
  `{"id": 7, "ok": false, "error": "code", "message": "…"}`
- Event: `{"event": "player" | "engine" | "account" | "queue", "data": …}`

Operations are listed in `bin/solfa-bridge` (`OPS`), each with its argument
checks.

## Bridge lifetime

`Service.qml` no longer runs the bridge as a Quickshell child process: it
tries the socket first, and only if nothing answers starts the bridge
detached, as a transient `systemd --user` unit (`io.github.sirallap.solfa-bridge`).
The bridge (and the engine, its own child) then survive a shell restart on
their own; the socket's own retry loop reconnects. The bridge reports the
settings it was started under (`autostart`/`browser`) and its own version
back in `hello`; if either no longer matches, the shell asks it to quit
(`bridge.quit`, which stops the engine first) and starts a fresh unit.

An idle lease closes everything if nobody is left to use it: the shell
marks its connection as the UI (`ui.attach`) right after it connects, and
the bridge closes itself (`SOLFA_ORPHAN_SECONDS`, off by default, 30 s in
`Service.qml`) once no such connection has existed for that long — the
usual case being the plugin was disabled or removed. If, at that moment,
the plugin's own `manifest.json` is gone from disk too, the bridge also
erases Solfa's data dir (the signed-in profile included) and its runtime
dir, each guarded to only ever match a path that literally ends in
`/io.github.sirallap.solfa`.

## Sign-in

A fresh engine shows Google's cookie page (in the EU) and is signed out. Search
and play still work signed out (with ads). Library, likes and playlists need
sign-in.

Google refuses to sign in a browser it thinks is automated ("This browser or
app may not be secure"), and the engine talks DevTools at all. So sign-in
does not happen in the engine. "Sign in" closes the engine (remembering the
song) and opens a plain browser window on the same profile: only the
profile, the Google sign-in page as an app window, and no DevTools flag,
automation switch or `SOLFA_ENGINE_FLAGS`. The bridge spawns it (same as the
engine: `posix_spawn`, tracked by `pidfd`) but never talks CDP to it. It
watches two things: the profile's cookie database, for Google's sign-in
cookie (`SAPISID`) created after the window opened (name, host and time
only, never a value; read-only and immutable, as the browser holds the
file), and the window's own exit (its pidfd becoming readable). On the
cookie it closes the window with `pidfd_send_signal(SIGTERM)` (Chromium's
clean exit, which writes the cookies); if the user closes it, that is the
end too. Then the engine starts again, with its bridge, and the song comes
back. Cancel in the panel closes the window.

## Keys

Global (optional, `hypr/bindings.lua`): open the panel, play/pause, next,
previous, like. Media keys already work through Chromium's MPRIS player.

In the panel: see `docs/keys.md`.
