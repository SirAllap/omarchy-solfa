import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "lib/Model.js" as Model
import "lib"

// Service.qml — one per shell. It runs the bridge (bin/solfa-bridge), keeps
// the one copy of the state that every bar widget and the panel draw from,
// and holds the actions they call. Everything about the hidden engine and
// its window lives in the bridge; this side is the UI's model.
Item {
  id: root

  // Pushed by the bar widget: the shell's plugin API (settings writes go
  // through it) and this widget's entry in shell.json.
  property var shell: null
  property var settings: ({})
  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  // Settings store: one write path for every setting, real or bar-widget.
  // shell.json stays the only place settings live, so Omarchy's own plugin
  // settings UI (built from manifest.json's schema) edits the same values.
  function saveSetting(key, value) {
    var change = {}
    change[key] = value
    root.writeSettings(change)
  }
  // Defaults over the current entry (any other key in it is kept).
  function resetSettings() { root.writeSettings(Model.settingsAfterReset({})) }
  function writeSettings(changes) {
    root.pendingSettings = Object.assign({}, root.pendingSettings, changes)
    pendingSettingsTimer.restart()
    var next = Object.assign({}, root.settings, changes)
    root.settings = next
    if (root.shell && typeof root.shell.updateEntryInline === "function") root.shell.updateEntryInline(root.pluginId, next)
  }
  // The bar widget hands its shell.json entry over here (after every change
  // of it). Writes of ours it does not carry yet stay (a stale echo of an
  // earlier write must not undo a later one); after a few seconds whatever
  // shell.json says wins.
  property var pendingSettings: ({})
  // M5: bridgeEnvKey reads from `setting()`'s defaults until the bar widget
  // hands over the real shell.json values. Before that, a running bridge
  // under non-default settings looks stale by definition — this flag holds
  // the stale-key check off until there is something real to compare.
  property bool settingsLoaded: false
  function adoptSettings(incoming) {
    var r = Model.mergePendingSettings(incoming, root.pendingSettings)
    root.pendingSettings = r.pending
    root.settings = r.settings
    root.settingsLoaded = true
  }
  Timer { id: pendingSettingsTimer; interval: 5000; onTriggered: root.pendingSettings = ({}) }

  readonly property string pluginId: "io.github.sirallap.solfa"
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))) + "/" + pluginId
  readonly property string socketPath: runtimeDir + "/bridge.sock"

  // ------------------------------------------------------------------ state

  property var engine: ({ status: "starting", error: "", signedIn: false, host: "" })
  property var account: ({ signedIn: false, host: "" })
  property var player: ({})
  property int queueVersion: 0
  property string lastError: ""

  readonly property bool bridgeUp: sock.connected
  readonly property bool ready: bridgeUp && engine.status === "ready" && (!account.host || account.host === "music.youtube.com")
  readonly property bool signedIn: !!account.signedIn
  // Premium is only ever true when signed in and the page said so.
  readonly property bool premium: signedIn && account.premium === true
  // The sign-in window is open: YouTube Music is closed until it is done.
  readonly property bool signingIn: bridgeUp && !!engine.signingIn
  // A sign-in window closed and the page came back signed out: said once,
  // in the panel or as a notification, never a silent close.
  readonly property string signinError: bridgeUp ? (engine.signinError || "") : ""
  onSigninErrorChanged: if (signinError) root.report(signinError)
  readonly property bool gated: signingIn || (bridgeUp && engine.status === "ready" && !!account.host && account.host !== "music.youtube.com")
  readonly property string engineLine: bridgeUp ? Model.engineLine(engine, account) : Model.engineLineWhileDown(root.manifestVersion)
  // Closed: the engine is not running and nothing will start it by itself
  // (the user closed it, or it kept crashing). Nothing plays; play, the
  // power button or a click on the bar starts it again.
  readonly property bool closed: bridgeUp && engine.status === "stopped" && !engine.wantRunning && !signingIn
  readonly property bool hasTrack: ready && !!(player && player.videoId)
  readonly property bool isPlaying: hasTrack && !!player.playing
  readonly property bool isAd: hasTrack && !!player.ad
  readonly property string videoId: hasTrack ? player.videoId : ""
  readonly property string title: hasTrack ? (player.title || "") : ""
  readonly property string artist: hasTrack ? Model.artistsText(player.artists) : ""
  readonly property string album: hasTrack && player.album ? (player.album.name || "") : ""
  readonly property string thumb: hasTrack ? (player.thumb || "") : ""
  readonly property real duration: hasTrack ? (Number(player.duration) || 0) : 0
  readonly property int volume: player && player.volume !== undefined ? player.volume : 100
  readonly property bool muted: !!(player && player.muted)
  readonly property string repeatMode: player && player.repeat ? player.repeat : "NONE"
  readonly property string like: player && player.like ? player.like : "INDIFFERENT"

  // The clock that moves the progress between pushes. It only ticks while
  // a song plays; views that need finer time (lyrics) ask for a fast tick.
  property real now: Date.now()
  property int fastClockUsers: 0
  readonly property real position: Model.positionAt(player, now)
  readonly property real progress: duration > 0 ? Math.max(0, Math.min(1, position / duration)) : 0
  // An advert's own clock, moved between pushes like the song's.
  readonly property real adDuration: isAd ? (Number(player.adDuration) || 0) : 0
  readonly property real adPosition: {
    if (!isAd) return 0
    var pos = Number(player.adPosition) || 0
    if (player.playing && !player.buffering && player.at) pos += Math.max(0, (now - player.at) / 1000)
    return adDuration > 0 ? Math.min(pos, adDuration) : pos
  }
  readonly property real adLeft: Math.max(0, adDuration - adPosition)

  Timer {
    interval: root.fastClockUsers > 0 ? 250 : 1000
    repeat: true
    running: root.isPlaying
    onTriggered: { root.now = Date.now(); if (!root.isAd) root.checkSleepEnd() }
  }

  // The panel sets this so a track toast does not repeat what is on screen.
  property bool panelOpen: false

  signal trackChanged(string videoId)
  signal queueChanged()

  // ------------------------------------------------------------------ bridge lifetime
  //
  // The bridge is no longer a Quickshell child process: a dead DevTools TCP
  // port is not the only thing --remote-debugging-pipe removes, so does
  // "the shell runs the browser's parent". The bridge now runs as a
  // transient `systemd --user` unit, started detached (fire and forget: no
  // live Process wired to its stdout or lifetime), so it — and the engine,
  // its own child — survive a shell restart on their own. This side only
  // ever talks to it over the socket; Socket's own retry loop below
  // reconnects after either one restarts.

  readonly property string manifestVersion: {
    try { return JSON.parse(manifestFile.text()).version || "" } catch (e) { return "" }
  }
  FileView {
    id: manifestFile
    path: root.pluginDir + "/manifest.json"
    blockLoading: true
    printErrors: false
  }

  // The bridge reads `autostart` and `browser` once, from its environment
  // (a launch key it echoes back in `hello`): so it starts when this
  // service has its settings (the bar widget pushes them just after the
  // shell creates the service), or after 2 s with no widget at all, and it
  // is asked to quit and restart when one of those two settings changes
  // (or the plugin itself was updated under it).
  readonly property string bridgeEnvKey: String(root.setting("autostart", true)) + "|" + root.setting("browser", "")
  property string runningEnvKey: ""
  property string runningVersion: ""
  property bool bridgeUnitStarted: false
  property int restartDelay: 1000
  // H2: at most one quit/restart per (launch key, manifest version) pair,
  // so a bridge that keeps reporting a mismatch (a forgotten VERSION bump,
  // for instance) is asked to restart once, not in a loop.
  property string lastRestartTag: ""

  onSettingsChanged: { root.maybeRestartBridge(); root.sendEq(); root.sendStart() }
  onReadyChanged: if (root.ready) root.sendEq()

  function envForBridge() {
    var vars = {
      SOLFA_LAUNCH_KEY: root.bridgeEnvKey,
      // The shell's own idle lease: no UI connection (this Service) for
      // this long closes the bridge, the engine and the socket — off (0)
      // for anything that starts the bridge by hand (tests included).
      SOLFA_ORPHAN_SECONDS: "30",
      // Advanced > memory: read once when the bridge starts (the help text
      // says so); changing them does not itself restart the bridge.
      SOLFA_RECYCLE_HEAP_MB: String(Model.recycleHeapMbFor(root.setting("recycleHeapMb", 400))),
      SOLFA_RECYCLE_HOURS: String(Model.recycleHoursFor(root.setting("recycleHours", 12))),
      // Playback > "When Solfa starts" / "Volume at start": the bridge
      // applies them itself, once, to an engine it launches as a start of
      // Solfa (never to one already playing, a restart or a recycle). Given
      // here so it has them before the engine is up; start.set keeps them
      // current afterwards.
      SOLFA_START_PAUSED: root.setting("startPaused", false) ? "1" : "0"
    }
    var browser = root.setting("browser", "")
    if (browser !== "") vars.SOLFA_BROWSER = browser
    if (!root.setting("autostart", true)) vars.SOLFA_NO_LAUNCH = "1"
    var vol = root.startVolumeArg()
    if (vol !== null) vars.SOLFA_START_VOLUME = String(vol)
    // Everything else the engine's Chromium (and hyprctl) needs to reach
    // this session, passed through as it is now (never PATH, never "").
    var passthrough = ["WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE",
      "DBUS_SESSION_BUS_ADDRESS", "XDG_CURRENT_DESKTOP", "LANG"]
    for (var i = 0; i < passthrough.length; i++) {
      var v = Quickshell.env(passthrough[i])
      if (v) vars[passthrough[i]] = v
    }
    return vars
  }

  function startBridgeUnit() {
    var vars = root.envForBridge()
    // L1: systemd-run (261+) expands ${VAR} in command arguments by default;
    // a pluginDir containing "$" would otherwise be rewritten.
    var argv = ["/usr/bin/systemd-run", "--user", "--unit=io.github.sirallap.solfa-bridge", "--collect", "--quiet",
      "--expand-environment=no"]
    for (var k in vars) argv.push("--setenv=" + k + "=" + vars[k])
    argv.push("--")
    argv.push("/usr/bin/python3", root.pluginDir + "/bin/solfa-bridge")
    // Fire and forget: "unit already exists" (a bridge is already running)
    // is not an error here, it is the common case — the socket below is
    // what actually says whether one answers.
    Quickshell.execDetached(argv)
  }

  function startBridge() {
    if (root.bridgeUnitStarted) return
    root.bridgeUnitStarted = true
    root.runningEnvKey = root.bridgeEnvKey
    root.startBridgeUnit()
    bridgeRetryTimer.interval = Model.retryTimerInterval(root.restartDelay)
    bridgeRetryTimer.restart()
  }

  // Settings changed under a running bridge, or `hello` said it is not the
  // one this key/version wants: close it (engine included) and start a
  // fresh unit, rather than restarting a Quickshell child.
  function quitAndRestartBridge() {
    if (!root.bridgeUnitStarted && !sock.connected) { root.startBridge(); return }
    root.bridgeUnitStarted = false
    root.restartDelay = 300
    if (sock.connected) {
      root.request("bridge.quit", {}, function () { root.startBridge() })
    } else {
      root.startBridge()
    }
  }

  function maybeRestartBridge() {
    if (root.runningEnvKey !== "" && root.runningEnvKey !== root.bridgeEnvKey) {
      root.quitAndRestartBridge()
    } else {
      root.startBridge()
    }
  }

  Timer {
    // Not yet connected a while after asking for a unit: try again (the
    // unit may have failed to start, or systemd-run itself may not have
    // been reachable yet right after login).
    id: bridgeRetryTimer
    repeat: false
    onTriggered: {
      if (!sock.connected) {
        root.bridgeUnitStarted = false
        root.restartDelay = Model.nextRetryDelay(root.restartDelay)
        root.startBridge()
      }
    }
  }

  Timer {
    interval: 2000
    running: true
    onTriggered: root.startBridge()
  }

  // ------------------------------------------------------------------ socket

  property int nextId: 1
  property var pending: ({})

  // A fresh Quickshell Socket on every try (see lib/BridgeSocket.qml): one
  // that once found no socket file never connects again.
  BridgeSocket {
    id: sock
    path: root.socketPath
    onRead: data => root.onLine(data)
    onConnectedChanged: {
      if (sock.connected) {
        root.restartDelay = 1000
        root.bridgeUnitStarted = true  // something answered: no unit to start
        root.request("hello", {}, function (r) { if (r.ok) root.applyHello(r.data) })
        root.request("ui.attach", {})
        root.sendEq()
        root.sendStart()
      } else {
        root.failAll("bridge-down")
        // H1: the bridge was running and dropped (crash, OOM kill, a unit
        // stop from outside us) — nothing else will restart it. Back off
        // like the "never connected" path does, then try again: never a
        // tight loop, never silence forever.
        if (root.bridgeUnitStarted) {
          root.bridgeUnitStarted = false
          root.restartDelay = Model.nextRetryDelay(root.restartDelay)
          bridgeRetryTimer.interval = Model.retryTimerInterval(root.restartDelay)
          bridgeRetryTimer.restart()
        }
      }
    }
  }

  // Replies that never come: give up on them so views do not wait forever.
  Timer {
    id: sweeper
    interval: 1000
    repeat: true
    running: Object.keys(root.pending).length > 0
    onTriggered: {
      var dead = Model.expired(root.pending, Date.now())
      for (var i = 0; i < dead.length; i++) root.finish(dead[i], { ok: false, error: "timeout" })
    }
  }

  function request(op, args, cb, timeoutMs) {
    if (!sock.connected) {
      if (cb) Qt.callLater(function () { cb({ ok: false, error: "bridge-down" }) })
      return 0
    }
    var id = root.nextId++
    // A new object each time: assigning the same one back emits no change,
    // and the sweeper below would never start.
    var p = Object.assign({}, root.pending)
    p[id] = { cb: cb || null, deadline: Date.now() + (timeoutMs || 25000) }
    root.pending = p
    sock.write(JSON.stringify({ id: id, op: op, args: args || {} }) + "\n")
    sock.flush()
    return id
  }

  function finish(id, reply) {
    var entry = root.pending[id]
    if (!entry) return
    var p = Object.assign({}, root.pending)
    delete p[id]
    root.pending = p
    // Without a callback nobody else will say it failed; with the panel
    // closed it stays unsaid (report() covers the user's own actions).
    if (!reply.ok && reply.error && !entry.cb && root.panelOpen) root.lastError = Model.errorText(reply.error)
    if (entry.cb) {
      try { entry.cb(reply) } catch (e) { console.warn("[solfa] callback: " + e) }
    }
  }

  function failAll(code) {
    var ids = Object.keys(root.pending)
    for (var i = 0; i < ids.length; i++) root.finish(Number(ids[i]), { ok: false, error: code })
  }

  function onLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.id !== undefined && msg.id !== null) { root.finish(msg.id, msg); return }
    switch (msg.event) {
      case "player": root.applyPlayer(msg.data || {}); break
      case "engine": root.engine = msg.data || root.engine; break
      case "account": root.account = msg.data || root.account; break
      case "queue":
        root.queueVersion = (msg.data && msg.data.version) || 0
        root.queueChanged()
        break
    }
  }

  function applyHello(data) {
    root.engine = data.engine || root.engine
    root.account = data.account || root.account
    root.queueVersion = data.queueVersion || 0
    root.solfaVersion = data.version || root.solfaVersion
    root.applyPlayer(data.player || {})
    root.runningEnvKey = data.launchKey !== undefined ? data.launchKey : root.runningEnvKey
    root.runningVersion = data.version || root.runningVersion
    // A bridge started under old settings, or a plugin update under a
    // bridge that has not picked it up yet: close it and start a fresh one.
    var staleKey = root.settingsLoaded && data.launchKey !== undefined && data.launchKey !== root.bridgeEnvKey
    var staleVersion = root.manifestVersion !== "" && data.version !== undefined && data.version !== root.manifestVersion
    var tag = Model.restartTag(root.bridgeEnvKey, root.manifestVersion)
    if (Model.shouldRestartForStale(staleKey, staleVersion, root.lastRestartTag, tag)) {
      root.lastRestartTag = tag
      root.quitAndRestartBridge()
    }
  }

  // The bridge's own version, from `hello` (About).
  property string solfaVersion: ""

  property string lastVideo: ""
  property bool firstPlayer: true

  function applyPlayer(p) {
    var before = root.lastVideo
    root.player = p
    root.now = Date.now()
    if (p.videoId && p.videoId !== before) {
      root.lastVideo = p.videoId
      root.trackChanged(p.videoId)
      if (!root.firstPlayer) { root.pendingToast = p.videoId; toastTimer.restart() }
    } else if (root.pendingToast !== "" && root.pendingToast === p.videoId && !toastTimer.running) {
      // The title or the end of an advert came with a later push.
      root.toast()
    }
    root.firstPlayer = false
  }

  // Playback > "When Solfa starts" / "Volume at start" live in the bridge
  // (see SOLFA_START_* above): it knows whether an engine is a new start.
  function startVolumeArg() { return Model.startVolumeFor(root.setting("startVolume", "last")) }
  function sendStart() {
    if (sock.connected) root.request("start.set", { paused: !!root.setting("startPaused", false), volume: root.startVolumeArg() })
  }

  // ------------------------------------------------------------------ actions

  function call(op, args, cb) { return root.request(op, args, cb) }

  // An error from something the user did: in the open panel's footer, or,
  // with the panel closed (global keys, the bar), as a small notification.
  function report(code) {
    var text = Model.errorText(code)
    if (root.panelOpen) { root.lastError = text; return }
    Quickshell.execDetached(["/usr/bin/notify-send", "--app-name=Solfa", "--urgency=low", "--expire-time=4000", "--", "Solfa", text])
  }
  function reportFailure(r) { if (r && !r.ok && r.error !== "bridge-down") root.report(r.error) }

  function togglePlaying() {
    if (root.closed) root.startEngine()
    else root.request("transport", { action: "toggle" }, root.reportFailure)
  }
  function play() {
    if (root.closed) root.startEngine()
    else root.request("transport", { action: "play" }, root.reportFailure)
  }
  function pause() { root.request("transport", { action: "pause" }, root.reportFailure) }
  function next() { root.request("transport", { action: "next" }, root.reportFailure) }
  function previous() { root.request("transport", { action: "previous" }, root.reportFailure) }
  function seek(seconds) {
    if (!root.hasTrack) return
    var s = Math.max(0, Math.min(root.duration || seconds, seconds))
    // Show it at once; the page confirms with a push.
    var p = Object.assign({}, root.player, { position: s, at: Date.now() })
    root.player = p
    root.request("seek", { seconds: s })
  }
  function seekBy(delta) { root.seek(root.position + delta) }

  // Volume: at most one request in flight per 80 ms; the last value wins.
  property int wantVolume: -1
  function setVolume(level) {
    root.wantVolume = Math.max(0, Math.min(100, Math.round(level)))
    var p = Object.assign({}, root.player, { volume: root.wantVolume, muted: root.wantVolume > 0 ? false : root.muted })
    root.player = p
    if (!volumeTimer.running) { root.sendVolume(); volumeTimer.start() }
  }
  function sendVolume() {
    if (root.wantVolume < 0) return
    var v = root.wantVolume
    root.wantVolume = -1
    root.request("volume", { level: v })
  }
  Timer { id: volumeTimer; interval: 80; onTriggered: root.sendVolume() }
  function nudgeVolume(steps) { root.setVolume(Model.volumeAfter(root.volume, steps)) }
  function toggleMute() { root.request("mute", { muted: !root.muted }) }

  function skipAd() {
    root.request("ad.skip", {}, function (r) {
      if (!r.ok) root.lastError = r.error === "not-skippable" ? "This advert cannot be skipped yet" : Model.errorText(r.error)
    })
  }

  function cycleRepeat() { root.request("repeat", { mode: Model.nextRepeat(root.repeatMode) }) }
  function shuffle() { root.request("shuffle", {}) }
  function toggleLike() {
    if (!root.hasTrack) return
    if (!root.signedIn) { root.report("signin-required"); return }
    root.request("like", { videoId: root.videoId, status: Model.nextLike(root.like) }, root.reportFailure)
  }
  function dislike() {
    if (!root.hasTrack || !root.signedIn) return
    root.request("like", { videoId: root.videoId, status: root.like === "DISLIKE" ? "INDIFFERENT" : "DISLIKE" })
  }

  // Play whatever a row is: a track, an album, a playlist, an artist's shuffle.
  function playItem(item, cb) {
    if (!item) return
    if (item.videoId) {
      var a = { videoId: item.videoId }
      if (item.playlistId) a.playlistId = item.playlistId
      root.request("play", a, cb)
    } else if (item.playlistId) {
      root.request("play", { playlistId: item.playlistId }, cb)
    } else if (item.kind === "artist" && item.browseId) {
      root.request("browse", { id: item.browseId }, function (r) {
        if (r.ok && r.data && (r.data.shuffle || r.data.radio)) {
          var s = r.data.shuffle || r.data.radio
          var args = { playlistId: s.playlistId }
          if (s.videoId) args.videoId = s.videoId
          if (s.params) args.params = s.params
          root.request("play", args, cb)
        } else if (cb) cb({ ok: false, error: r.error || "not-found" })
      })
    }
  }

  function radioFor(item) {
    if (!item || !item.videoId) return
    if (item.radio && item.radio.playlistId) {
      var a = { videoId: item.videoId, playlistId: item.radio.playlistId }
      if (item.radio.params) a.params = item.radio.params
      root.request("radio", a)
    } else {
      root.request("radio", { videoId: item.videoId })
    }
  }

  function enqueue(item, next, cb) {
    if (!item || !item.videoId) { if (cb) cb({ ok: false, error: "not-found" }); return }
    root.request("queue.add", { videoIds: [item.videoId], next: !!next }, cb)
  }

  // ------------------------------------------------------------------ engine and window

  function startEngine() { root.request("engine.start", {}) }
  function restartEngine() { root.request("engine.restart", {}) }
  function stopEngine() { root.request("engine.stop", {}) }
  function toggleEngine() { if (root.closed) root.startEngine(); else root.stopEngine() }
  function signIn() { root.request("signin.begin", {}) }
  // "Use my browser's sign-in" was removed before the marketplace release;
  // importedSession stays read-only, for a profile from before this build.
  readonly property bool importedSession: bridgeUp && !!engine.importedSession
  function showWindow() { root.request("window.show", {}) }
  // Google's cookie question, answered with the user's choice from the panel.
  function answerCookies(accept) {
    root.request("consent.answer", { accept: accept }, function (r) {
      if (!r.ok) root.lastError = r.error === "no-consent" ? "Google's cookie question was not found; open the window instead" : Model.errorText(r.error)
    })
  }
  function hideWindow() { root.request("window.hide", {}) }

  // ------------------------------------------------------------------ Settings: Sound (EQ / loudness)

  // Assembled here (not in agent.js): off means flat/bypass is what actually
  // reaches the page, whatever preset or custom bands are stored — they are
  // untouched, so turning it back on returns exactly what was there.
  function eqPayload() {
    return Model.eqPayload(
      root.setting("eqEnabled", false),
      root.setting("eqPreset", "flat"),
      Model.parseEqBands(root.setting("eqBands", Model.SETTINGS_DEFAULTS.eqBands)),
      root.setting("eqPreamp", 0),
      root.setting("eqLoudness", false))
  }
  // Sent once the bridge is up (it may have just (re)started, forgetting
  // what it knew) and again whenever a setting changes; the bridge itself
  // resends the last one it was given after every page load and recycle.
  function sendEq() { root.request("eq.set", root.eqPayload()) }

  // ------------------------------------------------------------------ Settings: Account

  property var accountDetails: ({ name: "", email: "", avatar: "" })
  function accountInfo(cb) {
    root.request("account.info", {}, function (r) {
      if (r.ok) root.accountDetails = r.data
      if (cb) cb(r)
    })
  }
  // signout answers once Google's logout has landed back on the app
  // (up to ~20 s), so a sign-in after it never cuts the redirects short.
  function accountSignOut(cb) {
    root.request("signout", {}, function (r) {
      if (r.ok) root.accountDetails = { name: "", email: "", avatar: "" }
      if (cb) cb(r)
    }, 30000)
  }
  // Switch: sign out, then Google's account chooser (not a silent sign-in
  // back into the same account).
  function accountSwitch(cb) {
    root.accountSignOut(function (r) {
      if (!r.ok) { if (cb) cb(r); return }
      root.request("signin.begin", { chooser: true }, cb)
    })
  }

  // ------------------------------------------------------------------ Settings: Advanced

  function engineVersion(cb) { root.request("engine.version", {}, cb) }
  function clearCache(cb) { root.request("cache.clear", {}, cb) }
  // confirm: the view's two-step confirm, which the bridge requires. It
  // waits for the engine to close (up to ~20 s), then for the delete.
  function eraseProfile(cb) { root.request("profile.erase", { confirm: true }, cb, 120000) }

  // ------------------------------------------------------------------ Settings: Playback sleep timer (not persisted)

  property string sleepMode: "off"       // one of Model.SLEEP_OPTIONS
  property int sleepFadeVolume: -1       // >= 0 while fading: the volume to restore after pausing
  property string sleepArmedVideo: ""    // "end of song": the song playing when the timer was set

  function setSleepMode(mode) {
    // Cut short mid-fade (or while waiting for its pause): the volume the
    // fade started from comes back.
    var back = Model.sleepVolumeToRestore(root.sleepFadeVolume)
    if (back !== null) root.restoreSleepVolume(back, 0)
    root.sleepMode = mode
    sleepCountdown.stop()
    fadeTimer.stop()
    pauseCheck.stop()
    root.sleepFadeVolume = -1
    root.sleepArmedVideo = mode === "end" ? root.videoId : ""
    var delay = Model.sleepFadeDelayMs(mode)
    if (delay >= 0) { sleepCountdown.interval = Math.max(1, delay); sleepCountdown.start() }
  }
  function nudgeSleepMode(dir) { root.setSleepMode(Model.nextSleepOption(root.sleepMode, dir)) }

  function startSleepFade() {
    if (root.sleepFadeVolume >= 0) return
    // Nothing playing when it fires: nothing to fade; the timer is done.
    if (!root.hasTrack) { root.sleepMode = "off"; root.sleepArmedVideo = ""; return }
    root.sleepFadeVolume = root.volume
    fadeTimer.step = 0
    fadeTimer.start()
  }

  Timer {
    id: sleepCountdown
    repeat: false
    onTriggered: root.startSleepFade()
  }

  // 20 steps over 10 s: fade the volume out, pause, and put the volume back
  // once the song really is paused (pauseCheck).
  Timer {
    id: fadeTimer
    interval: 500
    repeat: true
    property int step: 0
    onTriggered: {
      fadeTimer.step++
      var steps = Model.fadeVolumeSteps(root.sleepFadeVolume, 20)
      root.setVolume(steps[Math.min(fadeTimer.step - 1, steps.length - 1)])
      if (fadeTimer.step >= steps.length) {
        fadeTimer.stop()
        root.pause()
        pauseCheck.tries = 0
        pauseCheck.start()
      }
    }
  }

  Timer {
    id: pauseCheck
    interval: 1500
    property int tries: 0
    onTriggered: {
      var next = Model.sleepAfterPause(root.isPlaying, pauseCheck.tries)
      if (next === "retry") { pauseCheck.tries++; root.pause(); pauseCheck.start(); return }
      if (next === "restore") root.restoreSleepVolume(root.sleepFadeVolume, 0)
      else root.report("sleep-pause-failed")
      root.sleepFadeVolume = -1
      root.sleepMode = "off"
      root.sleepArmedVideo = ""
    }
  }

  // Straight to the bridge (not the throttled setVolume) so a failure is
  // seen: tried once more, or the next song would start silent.
  function restoreSleepVolume(level, tries) {
    volumeTimer.stop()
    root.wantVolume = -1
    root.player = Object.assign({}, root.player, { volume: level })
    root.request("volume", { level: level }, function (r) {
      if (!r.ok && tries < 1) root.restoreSleepVolume(level, tries + 1)
    })
  }

  // "End of song": watches the armed song's own position/duration (the same
  // clock the progress ring uses) and starts the fade 10 s before it ends,
  // so it pauses at the end of that song, not after the next one has
  // already begun. If the armed song is left before then (skipped, or the
  // sleep mode changed), nothing fires for whatever plays after it.
  function checkSleepEnd() {
    if (Model.shouldStartSleepFade(root.sleepMode, root.sleepArmedVideo, root.videoId, root.duration, root.position, root.sleepFadeVolume >= 0))
      root.startSleepFade()
  }

  // ------------------------------------------------------------------ track toast

  property int toastId: 0

  Timer {
    id: toastTimer
    // Wait a moment: a quick run of skips shows one toast, not five.
    interval: 900
    onTriggered: root.toast()
  }

  // The song a toast is owed for. The first push of a new song often has
  // no title yet, and signed out an advert may come first: the toast waits
  // for a later push (applyPlayer calls again) rather than giving up.
  property string pendingToast: ""

  function toast() {
    if (root.pendingToast === "" || root.pendingToast !== root.videoId) return
    if (!root.setting("notify", true) || root.panelOpen) { root.pendingToast = ""; return }
    if (root.isAd || !root.title) return
    root.pendingToast = ""
    var text = Model.notifyText(root.player)
    if (!text) return
    var vid = root.videoId
    root.request("art", { videoId: vid, url: root.thumb }, function (r) {
      if (vid !== root.videoId) return
      var icon = r.ok && r.data ? r.data.path : "audio-x-generic"
      var esc = function (s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
      var argv = ["/usr/bin/notify-send", "--app-name=Solfa", "--icon=" + icon, "--print-id", "--urgency=low",
        "--hint=string:x-canonical-private-synchronous:" + root.pluginId]
      if (root.toastId > 0) argv.push("--replace-id=" + root.toastId)
      argv.push("--", esc(text.summary), esc(text.body))
      toastProc.command = argv
      toastProc.running = true
    }, 10000)
  }

  Process {
    id: toastProc
    stdout: StdioCollector {
      onStreamFinished: {
        var id = parseInt(String(text).trim(), 10)
        if (id > 0) root.toastId = id
      }
    }
  }

  // ------------------------------------------------------------------ global keys

  // Solfa's own shortcuts, registered at runtime and only where the key is
  // free; a Hyprland config reload wipes them, so they come back after one.
  // M3: the last bare program name run through Hyprland's exec (a PATH
  // lookup, sh -c). Resolved once, with an absolute fallback so a session
  // without OMARCHY_PATH set still gets an absolute path, never a name.
  readonly property string omarchyShellBin: {
    var p = Quickshell.env("OMARCHY_PATH")
    return p ? (p + "/bin/omarchy-shell") : "/usr/share/omarchy/bin/omarchy-shell"
  }
  readonly property bool wantKeys: root.setting("globalKeys", true)
  property bool keysRegistered: false
  property string lastBindsJson: ""
  onWantKeysChanged: root.syncKeys()

  // The plugin can be removed or disabled without warning (Omarchy just
  // destroys this Item): unbind Solfa's own keys so they are not left
  // dangling in Hyprland's config. This is the only cleanup done here — the
  // engine and the bridge itself outlive a shell restart on purpose; the
  // bridge's own orphan lease is what closes them once nothing reconnects.
  Component.onDestruction: {
    if (root.keysRegistered && root.lastBindsJson) {
      var off = Model.unbindLua(root.lastBindsJson)
      if (off) Quickshell.execDetached(["/usr/bin/hyprctl", "eval", off])
    }
  }

  Process {
    id: bindsProc
    command: ["/usr/bin/hyprctl", "-j", "binds"]
    property bool registering: true
    stdout: StdioCollector {
      onStreamFinished: {
        root.lastBindsJson = text
        if (bindsProc.registering) {
          var lua = Model.bindLua(Model.freeKeys(text), root.omarchyShellBin)
          if (lua) Quickshell.execDetached(["/usr/bin/hyprctl", "eval", lua])
          root.keysRegistered = true
        } else {
          var off = Model.unbindLua(text)
          if (off) Quickshell.execDetached(["/usr/bin/hyprctl", "eval", off])
          root.keysRegistered = false
        }
      }
    }
  }

  function syncKeys() {
    if (bindsProc.running) return
    bindsProc.registering = root.wantKeys
    if (root.wantKeys || root.keysRegistered) bindsProc.running = true
  }

  Timer {
    id: keysTimer
    interval: 400
    onTriggered: root.syncKeys()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") { root.keysRegistered = false; keysTimer.restart() }
    }
  }

  Timer {
    // After the settings arrive from the bar widget.
    interval: 1500
    running: true
    onTriggered: root.syncKeys()
  }

  // ------------------------------------------------------------------ IPC

  IpcHandler {
    target: "io.github.sirallap.solfa"

    function toggle(): void { if (root.shell) root.shell.toggle(root.pluginId, "{}") }
    function open(): void { if (root.shell) root.shell.summon(root.pluginId, "{}") }
    function close(): void { if (root.shell) root.shell.hide(root.pluginId) }
    function playPause(): void { root.togglePlaying() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function like(): void { root.toggleLike() }
    function volumeUp(): void { root.nudgeVolume(1) }
    function volumeDown(): void { root.nudgeVolume(-1) }
    function status(): string { return root.hasTrack ? (root.title + " — " + root.artist) : root.engineLine }
  }
}
