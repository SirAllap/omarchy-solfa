// agent.js — the page side of Solfa.
//
// The bridge injects parse.js and this file into the hidden YouTube Music
// page (the engine), on every new document and once into the current one.
// It drives the web app through the app's own pieces: its player, its queue
// store and its InnerTube API, with the page's own sign-in. Cookies never
// leave the page.
//
// Changes are pushed, not polled: the bridge adds a DevTools binding
// (window.__solfaEmit) and the agent calls it when the player, the queue or
// the account changes. Nothing here runs on a timer once the page is up.

;(function () {
  "use strict"

  var VERSION = "%%SOLFA_VERSION%%"
  var EMIT = "__solfaEmit"
  var HOST = "music.youtube.com"
  var P = typeof SolfaParse !== "undefined" ? SolfaParse : null

  // The bridge's script runs in every frame of the page; only the top one
  // is the app. A frame (an advert's, say) must not speak for it.
  try { if (window.top !== window) return } catch (e) { return }

  var previous = window.__solfa
  if (previous && previous.version === VERSION) return
  // An agent from before the EQ graph was shared (window.__solfaEq): its
  // stop() closes the graph, and a <video> it wrapped stays bound to that
  // dead source for life, silent. Checked once the app is up (start()).
  var fromUnsharedAgent = !!(previous && !previous.sharesEq)
  if (previous && typeof previous.stop === "function") { try { previous.stop() } catch (e) { /* old agent is gone anyway */ } }

  // ---------------------------------------------------------------- emit

  function emit(type, data) {
    try {
      if (typeof window[EMIT] === "function") window[EMIT](JSON.stringify({ t: type, v: VERSION, data: data }))
    } catch (e) { /* the bridge is not listening; nothing to do */ }
  }

  function fail(code) { var e = new Error(code); e.code = code; throw e }

  // ---------------------------------------------------------------- page access

  function app() { return document.querySelector("ytmusic-app") }

  function store() {
    var a = app()
    var s = a && a.queue && a.queue.store
    return s && typeof s.getState === "function" && typeof s.dispatch === "function" ? s : null
  }

  function appState() {
    var s = store()
    try { return s ? s.getState() : null } catch (e) { return null }
  }

  function player() {
    var p = document.getElementById("movie_player")
    return p && typeof p.getPlayerState === "function" ? p : null
  }

  function video() {
    var p = document.getElementById("movie_player")
    return (p && p.querySelector("video")) || document.querySelector("video")
  }

  function cfg(key) {
    try { return window.ytcfg && typeof window.ytcfg.get === "function" ? window.ytcfg.get(key) : undefined } catch (e) { return undefined }
  }

  function signedIn() { return cfg("LOGGED_IN") === true }
  // The page's own config says whether the account has Premium. Strictly
  // true or nothing: a missing or odd value never shows a badge.
  function premium() { return signedIn() && cfg("IS_SUBSCRIBER") === true }

  function needStore() { var s = store(); if (!s) fail("no-queue"); return s }
  function needPlayer() { var p = player(); if (!p) fail("no-player"); return p }
  function needSignIn() { if (!signedIn()) fail("signin-required") }

  // ---------------------------------------------------------------- InnerTube

  function cookie(name) {
    var parts = document.cookie ? document.cookie.split("; ") : []
    for (var i = 0; i < parts.length; i++) {
      var eq = parts[i].indexOf("=")
      if (eq > 0 && parts[i].slice(0, eq) === name) return decodeURIComponent(parts[i].slice(eq + 1))
    }
    return ""
  }

  async function sha1hex(s) {
    var buf = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(s))
    return Array.prototype.map.call(new Uint8Array(buf), function (b) { return (b < 16 ? "0" : "") + b.toString(16) }).join("")
  }

  // POST /youtubei/v1/<endpoint>, as the web app does it. `mobile` asks as
  // the Android app, anonymously: timed lyrics are only served to it.
  async function innertube(endpoint, body, opts) {
    opts = opts || {}
    var ctx = cfg("INNERTUBE_CONTEXT")
    if (!ctx) fail("not-ready")
    var headers = { "Content-Type": "application/json" }
    var credentials = "include"
    if (opts.mobile) {
      var client = ctx.client || {}
      ctx = { client: { clientName: "ANDROID_MUSIC", clientVersion: "7.21.50", hl: client.hl || "en", gl: client.gl || "US" }, user: {} }
      credentials = "omit"
    } else {
      ctx = JSON.parse(JSON.stringify(ctx))
      headers["X-Youtube-Client-Name"] = String(cfg("INNERTUBE_CONTEXT_CLIENT_NAME") || 67)
      headers["X-Youtube-Client-Version"] = String(cfg("INNERTUBE_CLIENT_VERSION") || "")
      headers["X-Origin"] = location.origin
      var visitor = cfg("VISITOR_DATA")
      if (visitor) headers["X-Goog-Visitor-Id"] = String(visitor)
      var sid = cookie("SAPISID") || cookie("__Secure-3PAPISID")
      if (sid && signedIn()) {
        var ts = Math.floor(Date.now() / 1000)
        headers["Authorization"] = "SAPISIDHASH " + ts + "_" + (await sha1hex(ts + " " + sid + " " + location.origin))
        headers["X-Goog-AuthUser"] = String(cfg("SESSION_INDEX") || 0)
      }
    }
    var key = cfg("INNERTUBE_API_KEY")
    var url = "/youtubei/v1/" + endpoint + "?prettyPrint=false" + (key ? "&key=" + encodeURIComponent(key) : "")
    var ctrl = typeof AbortController === "function" ? new AbortController() : null
    var timer = ctrl ? setTimeout(function () { ctrl.abort() }, opts.timeout || 12000) : null
    try {
      var res = await fetch(url, {
        method: "POST", credentials: credentials, headers: headers,
        body: JSON.stringify(Object.assign({ context: ctx }, body || {})),
        signal: ctrl ? ctrl.signal : undefined
      })
      if (!res.ok) fail("http-" + res.status)
      return await res.json()
    } catch (e) {
      if (e && e.name === "AbortError") fail("timeout")
      throw e
    } finally {
      if (timer) clearTimeout(timer)
    }
  }

  // ---------------------------------------------------------------- player model

  // The current queue entry, parsed (artists, album, cover).
  function currentEntry(q) {
    if (!q || !Array.isArray(q.items)) return null
    var i = q.selectedItemIndex
    var raw = i >= 0 && i < q.items.length ? q.items[i] : null
    return raw && P ? P.panelVideo(raw, { thumbPx: 544 }) : null
  }

  var likeCache = {}   // videoId → status set by us this session

  function likeOf(st, videoId) {
    if (!videoId) return "INDIFFERENT"
    var fromStore = st && st.likeStatus && st.likeStatus.videos ? st.likeStatus.videos[videoId] : undefined
    return String(fromStore || likeCache[videoId] || "INDIFFERENT")
  }

  function snapshot() {
    var p = player()
    var v = video()
    var st = appState() || {}
    var ps = st.player || {}
    var q = st.queue || {}
    var data = p && typeof p.getVideoData === "function" ? (p.getVideoData() || {}) : {}
    var cur = currentEntry(q)
    var videoId = String(data.video_id || (cur && cur.videoId) || "")
    var state = p ? p.getPlayerState() : -1
    var ad = !!ps.adPlaying
    var playing = ad ? !!(v && !v.paused) : state === 1
    var matches = cur && cur.videoId === videoId
    var items = Array.isArray(q.items) ? q.items.length : 0
    var automix = Array.isArray(q.automixItems) ? q.automixItems.length : 0
    return {
      videoId: videoId,
      title: String((matches && cur.title) || data.title || ""),
      artists: matches ? cur.artists : (data.author ? [{ name: String(data.author), id: "" }] : []),
      album: matches ? cur.album : null,
      thumb: matches && cur.thumb ? cur.thumb : (videoId ? "https://i.ytimg.com/vi/" + videoId + "/mqdefault.jpg" : ""),
      kind: matches ? cur.kind : "song",
      duration: p && !ad ? Math.max(0, Number(p.getDuration()) || 0) : 0,
      position: p && !ad ? Math.max(0, Number(p.getCurrentTime()) || 0) : 0,
      at: Date.now(),
      playing: playing,
      buffering: state === 3,
      ended: state === 0,
      ad: ad,
      volume: p && typeof p.getVolume === "function" ? Math.round(Number(p.getVolume()) || 0) : 100,
      muted: p && typeof p.isMuted === "function" ? !!p.isMuted() : false,
      repeat: String(q.repeatMode || "NONE"),
      shuffle: !!q.shuffleEnabled,
      like: likeOf(st, videoId),
      index: typeof q.selectedItemIndex === "number" ? q.selectedItemIndex : -1,
      canNext: (q.selectedItemIndex || 0) < items - 1 || automix > 0,
      canPrev: videoId !== ""
    }
  }

  function account() {
    return { signedIn: signedIn(), premium: premium(), host: location.hostname, path: location.pathname }
  }

  // ---------------------------------------------------------------- EQ / loudness

  // <video> -> preamp Gain -> 10 BiquadFilters (Settings > Sound's bands,
  // same order as lib/Model.js's EQ_BAND_HZ: a 32 Hz lowshelf, eight peaking
  // bands 64 Hz-8 kHz at Q~1.0, a 16 kHz highshelf) -> an optional
  // DynamicsCompressor ("Even out loudness") -> destination.
  //
  // Built only once a setting actually needs it: flat gains, preamp 0 and
  // loudness off never touch WebAudio at all (the cheapest path is no graph).
  // Once built it stays built; "off"/flat from then on is just flat gains
  // and no compressor sent through the same graph.
  //
  // The graph belongs to the document, not to this agent: once a <video>
  // is wrapped in a MediaElementAudioSourceNode its audio only comes out
  // through that node, and an element gets one for life. So the graph
  // lives on window.__solfaEq, a newer agent injected into the same
  // document (a Solfa update) takes it over, and stop() leaves it alone.
  // Every element ever wrapped keeps its source connected to the preamp
  // (a page that swaps its <video>, or goes back to an earlier one, is
  // still heard, through the EQ); sources are found again through a
  // WeakMap rather than made twice.
  var EQ_FILTERS = [
    { type: "lowshelf", freq: 32 },
    { type: "peaking", freq: 64, q: 1.0 },
    { type: "peaking", freq: 125, q: 1.0 },
    { type: "peaking", freq: 250, q: 1.0 },
    { type: "peaking", freq: 500, q: 1.0 },
    { type: "peaking", freq: 1000, q: 1.0 },
    { type: "peaking", freq: 2000, q: 1.0 },
    { type: "peaking", freq: 4000, q: 1.0 },
    { type: "peaking", freq: 8000, q: 1.0 },
    { type: "highshelf", freq: 16000 }
  ]

  // { ctx, preamp, biquads, compressor, tail, sources: WeakMap<el, node> }
  var eqGraph = window.__solfaEq && window.__solfaEq.ctx ? window.__solfaEq : null
  var eqEl = null        // the element whose source is known to be in the graph
  var eqApplied = null   // the last settings asked for: { bands, preamp, loudness }

  function dbToGain(db) { return Math.pow(10, (Number(db) || 0) / 20) }

  function isFlatEq(s) {
    if (!s) return true
    if (s.loudness) return false
    if ((Number(s.preamp) || 0) !== 0) return false
    var bands = s.bands || []
    for (var i = 0; i < bands.length; i++) if ((Number(bands[i]) || 0) !== 0) return false
    return true
  }

  // Connects (or reconnects) the tail of the filter chain to the
  // compressor and destination, or straight to destination without it.
  function wireOutput(loudness) {
    var g = eqGraph
    if (!g) return
    try { g.tail.disconnect() } catch (e) { /* nothing connected yet */ }
    try { g.compressor.disconnect() } catch (e) { /* nothing connected yet */ }
    if (loudness) {
      g.tail.connect(g.compressor)
      g.compressor.connect(g.ctx.destination)
    } else {
      g.tail.connect(g.ctx.destination)
    }
  }

  function buildGraph() {
    var AC = window.AudioContext || window.webkitAudioContext
    if (!AC) return null
    var ctx = new AC()
    var g = { ctx: ctx, preamp: ctx.createGain(), sources: new WeakMap() }
    g.biquads = EQ_FILTERS.map(function (f) {
      var b = ctx.createBiquadFilter()
      b.type = f.type
      b.frequency.value = f.freq
      if (f.q) b.Q.value = f.q
      return b
    })
    g.compressor = ctx.createDynamicsCompressor()
    var node = g.preamp
    g.biquads.forEach(function (b) { node.connect(b); node = b })
    g.tail = node
    window.__solfaEq = g
    return g
  }

  // True once `el` plays through the graph. False (no EQ, the audio left
  // as it is) when WebAudio is missing or the element cannot be wrapped.
  function ensureGraph(el) {
    if (eqEl === el && eqGraph) return true
    try {
      if (!eqGraph) {
        eqGraph = buildGraph()
        if (!eqGraph) return false
        wireOutput(!!(eqApplied && eqApplied.loudness))
      }
      if (!eqGraph.sources.has(el)) {
        var src = eqGraph.ctx.createMediaElementSource(el)
        src.connect(eqGraph.preamp)
        eqGraph.sources.set(el, src)
      }
      eqEl = el
      return true
    } catch (e) {
      return false
    }
  }

  // Applies `settings` to the graph, building it first if it is needed and
  // not there yet. With no <video> yet the settings are kept and applied
  // the moment bindVideo() sees one (start-up order: the agent can run
  // before the app's player exists).
  function applyEq(settings) {
    eqApplied = settings
    if (!eqGraph && isFlatEq(settings)) return false
    var el = video()
    if (!el) return false
    if (!ensureGraph(el)) return false
    var bands = settings.bands || []
    eqGraph.preamp.gain.value = dbToGain(settings.preamp)
    for (var i = 0; i < eqGraph.biquads.length; i++) eqGraph.biquads[i].gain.value = Number(bands[i]) || 0
    wireOutput(!!settings.loudness)
    return true
  }

  function parseEqArgs(args) {
    var bands = args.bands
    if (typeof bands === "string") { try { bands = JSON.parse(bands) } catch (e) { bands = [] } }
    if (!Array.isArray(bands)) bands = []
    return { bands: bands, preamp: Number(args.preamp) || 0, loudness: !!args.loudness }
  }

  // ---------------------------------------------------------------- push

  var queueVersion = 0
  var lastItems = null, lastAutomix = null, lastSelected = null
  var lastKey = ""
  var lastSignedIn = null
  var flushTimer = null
  var seekPending = false
  var unsubscribe = null
  var boundVideo = null
  var VIDEO_EVENTS = ["play", "pause", "playing", "waiting", "seeked", "durationchange", "volumechange", "ended", "emptied", "loadeddata", "ratechange"]

  // Everything but the clock: a change here is worth a push.
  function keyOf(s) {
    return [s.videoId, s.title, s.playing, s.buffering, s.ended, s.ad, s.volume, s.muted, s.repeat, s.shuffle, s.like,
      s.index, s.canNext, Math.round(s.duration), s.thumb].join("\u0001")
  }

  function schedule(isSeek) {
    if (isSeek) seekPending = true
    if (flushTimer) return
    flushTimer = setTimeout(flush, 60)
  }

  function flush() {
    flushTimer = null
    var s
    try { s = snapshot() } catch (e) { return }
    var key = keyOf(s)
    if (key !== lastKey || seekPending) {
      lastKey = key
      seekPending = false
      emit("player", s)
    }
    var st = appState()
    var q = st && st.queue
    if (q && (q.items !== lastItems || q.automixItems !== lastAutomix || q.selectedItemIndex !== lastSelected)) {
      lastItems = q.items
      lastAutomix = q.automixItems
      lastSelected = q.selectedItemIndex
      queueVersion++
      emit("queue", { version: queueVersion })
    }
    var si = signedIn() + ":" + premium()
    if (si !== lastSignedIn) {
      lastSignedIn = si
      emit("account", account())
    }
    bindVideo()
  }

  function onVideoEvent(ev) { schedule(ev && ev.type === "seeked") }

  function bindVideo() {
    var v = video()
    if (v === boundVideo) return
    if (boundVideo) VIDEO_EVENTS.forEach(function (n) { boundVideo.removeEventListener(n, onVideoEvent) })
    boundVideo = v || null
    if (boundVideo) VIDEO_EVENTS.forEach(function (n) { boundVideo.addEventListener(n, onVideoEvent) })
    // The page swapped its <video> (a real navigation): follow it, so a
    // graph already built (or settings waiting for one) end up on the one
    // actually playing.
    if (boundVideo && eqApplied) applyEq(eqApplied)
    else if (boundVideo && eqGraph) ensureGraph(boundVideo)   // taken over, no settings yet: keep the gains it has
  }

  // ---------------------------------------------------------------- navigation

  // Change what plays the way the app's own links do: a `yt-navigate` event
  // on the app. Same document, no page load, no window activation. A page
  // load is the fallback only when the app did not react at all.
  function navigate(endpoint) {
    var a = app()
    if (!a) fail("no-app")
    a.dispatchEvent(new CustomEvent("yt-navigate", { bubbles: true, composed: true, detail: { endpoint: endpoint } }))
  }

  function watchUrl(w) {
    var qs = []
    if (w.videoId) qs.push("v=" + encodeURIComponent(w.videoId))
    if (w.playlistId) qs.push("list=" + encodeURIComponent(w.playlistId))
    return "/watch?" + qs.join("&")
  }

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms) }) }

  // Resolves once the player or queue shows the request landed.
  async function landed(before, wanted, waitMs) {
    var end = Date.now() + waitMs
    while (Date.now() < end) {
      await sleep(100)
      var p = player()
      var st = appState()
      var vid = p && p.getVideoData ? (p.getVideoData() || {}).video_id : ""
      if (wanted && vid === wanted) return true
      if (!wanted && st && st.queue && st.queue.items !== before.items) return true
      if (location.href !== before.href && !wanted) return true
    }
    return false
  }

  async function play(args) {
    var endpoint, wanted = args.videoId || ""
    if (args.videoId) {
      endpoint = { watchEndpoint: { videoId: args.videoId } }
      if (args.playlistId) endpoint.watchEndpoint.playlistId = args.playlistId
      if (args.params) endpoint.watchEndpoint.params = args.params
      if (typeof args.index === "number") endpoint.watchEndpoint.index = args.index
    } else if (args.playlistId) {
      endpoint = { watchPlaylistEndpoint: { playlistId: args.playlistId } }
      if (args.params) endpoint.watchPlaylistEndpoint.params = args.params
    } else {
      fail("bad-args")
    }
    var st = appState()
    var before = { items: st && st.queue ? st.queue.items : null, href: location.href }
    navigate(endpoint)
    if (await landed(before, wanted, wanted ? 4000 : 10000)) return { landed: "app" }
    location.assign(watchUrl(args))
    return { landed: "reload" }
  }

  // ---------------------------------------------------------------- queue

  function queueModel() {
    var st = appState()
    var q = st && st.queue
    if (!q) return { items: [], automix: [], index: -1, version: queueVersion }
    var map = function (list, offset) {
      var out = []
      for (var i = 0; i < (list || []).length; i++) {
        var t = P ? P.panelVideo(list[i], { thumbPx: 120 }) : null
        if (t) { t.queueIndex = offset + i; out.push(t) }
      }
      return out
    }
    return { items: map(q.items, 0), automix: map(q.automixItems, 0), index: q.selectedItemIndex, version: queueVersion }
  }

  // After MOVE_ITEM or REMOVE_ITEM the selection index points at whatever
  // now sits there; point it back at the track that is playing.
  function keepSelection(s, videoId) {
    var q = s.getState().queue
    for (var i = 0; i < q.items.length; i++) {
      var t = P ? P.panelVideo(q.items[i]) : null
      if (t && t.videoId === videoId) {
        if (i !== q.selectedItemIndex) s.dispatch({ type: "SET_INDEX", payload: i })
        return
      }
    }
  }

  // A queue edit, then the selection put back on the playing song: one
  // step, so an armed recycle never mistakes the moment between for a new song.
  var editing = false

  function editQueue(s, action, playing) {
    editing = true
    try {
      s.dispatch(action)
      keepSelection(s, playing)
    } finally {
      editing = false
    }
    checkArmed()
  }

  function playingId() {
    var p = player()
    return p && p.getVideoData ? String((p.getVideoData() || {}).video_id || "") : ""
  }

  async function queueAdd(args) {
    var s = needStore()
    var res = await innertube("music/get_queue", { videoIds: args.videoIds })
    var entries = P ? P.queueEntries(res) : []
    if (!entries.length) fail("not-found")
    var q = s.getState().queue
    var before = q.items.length
    var index = args.next ? Math.min(before, (q.selectedItemIndex || 0) + 1) : before
    var playing = playingId()
    editQueue(s, { type: "ADD_ITEMS", payload: { items: entries, index: index, nextQueueItemId: q.nextQueueItemId, shouldAssignIds: true } }, playing)
    if (s.getState().queue.items.length !== before + entries.length) fail("unchanged")
    return { added: entries.length, index: index }
  }

  function queueMove(args) {
    var s = needStore()
    var q = s.getState().queue
    var n = q.items.length
    if (args.from < 0 || args.from >= n || args.to < 0 || args.to >= n) fail("out-of-range")
    if (args.from === args.to) return { moved: false }
    var playing = playingId()
    editQueue(s, { type: "MOVE_ITEM", payload: { fromIndex: args.from, toIndex: args.to } }, playing)
    return { moved: true }
  }

  function queueRemove(args) {
    var s = needStore()
    var q = s.getState().queue
    if (args.automix) {
      if (args.index < 0 || args.index >= q.automixItems.length) fail("out-of-range")
      s.dispatch({ type: "REMOVE_AUTOMIX_ITEM", payload: args.index })
      return { removed: true }
    }
    if (args.index < 0 || args.index >= q.items.length) fail("out-of-range")
    if (args.index === q.selectedItemIndex) fail("playing")
    var playing = playingId()
    editQueue(s, { type: "REMOVE_ITEM", payload: args.index }, playing)
    return { removed: true }
  }

  async function queueJump(args) {
    var s = needStore()
    var a = app()
    var q = s.getState().queue
    var list = args.automix ? q.automixItems : q.items
    if (args.index < 0 || args.index >= list.length) fail("out-of-range")
    var entry = list[args.index]
    if (a && a.queue && typeof a.queue.selectQueueItem === "function") {
      a.queue.selectQueueItem(entry)
    } else {
      var t = P ? P.panelVideo(entry) : null
      if (!t) fail("not-found")
      navigate({ watchEndpoint: { videoId: t.videoId, playlistId: t.playlistId || undefined } })
    }
    return { jumped: true }
  }

  // ---------------------------------------------------------------- recycle

  // The page grows while it is open (the app's own heap, about 30 MB an
  // hour). The bridge swaps it for a fresh one at a quiet moment: it saves
  // the session here, loads the app again, and gives the session back.

  // The queue's plain fields and the store action that sets each one.
  var QUEUE_SETTERS = {
    autoplay: "SET_AUTOPLAY_ENABLED", header: "SET_HEADER", isInfinite: "SET_IS_INFINITE",
    playbackContentMode: "SET_PLAYBACK_CONTENT_MODE", queueContextParams: "SET_QUEUE_CONTEXT_PARAMS",
    repeatMode: "SET_REPEAT", shuffleEnabled: "SET_SHUFFLE_ENABLED", shuffleEndpoints: "SET_SHUFFLE_ENDPOINTS",
    watchNextType: "SET_WATCH_NEXT_TYPE"
  }

  // Armed, the next song is paused the moment it is selected, before it
  // makes a sound, and the bridge is told: that song boundary is the quiet
  // moment of a page that is playing.
  // (A queue edit moves the index too, but not to another song.) An arm
  // lasts a short while and the bridge renews it: a bridge that is gone
  // must not leave a trap that stops the music at the next song.
  var armedOn = null   // the song selected when armed
  var armedUntil = 0

  function selectedId() {
    var cur = currentEntry((appState() || {}).queue)
    return cur ? cur.videoId : ""
  }

  function checkArmed() {
    if (armedOn === null || editing) return
    if (Date.now() > armedUntil) { armedOn = null; return }
    var id = selectedId()
    if (!id || id === armedOn) return
    armedOn = null
    var p = player()
    if (p) p.pauseVideo()
    emit("recycle", { videoId: id })
  }

  function saveSession() {
    var q = needStore().getState().queue
    var p = needPlayer()
    var out = {
      items: q.items, automixItems: q.automixItems || [], selectedItemIndex: q.selectedItemIndex,
      nextQueueItemId: q.nextQueueItemId || 0,
      videoId: selectedId() || playingId(), position: Math.max(0, Number(p.getCurrentTime()) || 0),
      playing: p.getPlayerState() === 1,
      volume: Math.round(Number(p.getVolume()) || 0), muted: !!(p.isMuted && p.isMuted())
    }
    Object.keys(QUEUE_SETTERS).forEach(function (k) { if (k in q) out[k] = q[k] })
    return out
  }

  function sameItems(a, b) {
    if (!a || !b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) {
      var x = P ? P.panelVideo(a[i]) : null
      var y = P ? P.panelVideo(b[i]) : null
      if (!x || !y || x.videoId !== y.videoId) return false
    }
    return true
  }

  function putQueue(s, saved) {
    var next = Number(saved.nextQueueItemId) || 0
    // CLEAR is the one action that sets the next queue id: to one past the
    // largest index it keeps (none here: the fresh page's queue is empty).
    s.dispatch(next > 0 ? { type: "CLEAR", payload: [next - 1] } : { type: "CLEAR" })
    s.dispatch({ type: "RESET_ITEMS", payload: saved.items })
    s.dispatch({ type: "REPLACE_AUTOMIX_ITEMS", payload: { automixItems: saved.automixItems || [], shouldAssignIds: false } })
    // The app's reducers are picky about some values (a content mode it
    // does not know throws): one setting it refuses must not cost the rest
    // of the session, and the song's own load sets it again.
    Object.keys(QUEUE_SETTERS).forEach(function (k) {
      if (!(k in saved)) return
      try { s.dispatch({ type: QUEUE_SETTERS[k], payload: saved[k] }) } catch (e) { /* keep the rest */ }
    })
    s.dispatch({ type: "SET_INDEX", payload: saved.selectedItemIndex })
  }

  async function restoreSession(saved) {
    var s = needStore()
    var p = needPlayer()
    var a = app()
    if (!Array.isArray(saved.items)) fail("bad-args")
    putQueue(s, saved)
    var i = saved.selectedItemIndex
    if (typeof i !== "number" || i < 0 || i >= saved.items.length || !a || !a.queue ||
        typeof a.queue.selectQueueItem !== "function") return { restored: "queue" }
    // Load the song muted when it is to stay paused: selecting it plays it.
    p.setVolume(saved.volume)
    s.dispatch({ type: "SET_VOLUME", payload: saved.volume })
    var quiet = !saved.playing || saved.muted
    if (quiet) p.mute()
    a.queue.selectQueueItem(saved.items[i])
    var ok = false
    // Up to 15 s, and as long as the right song is still buffering (a slow
    // network is not a failed restore: giving up skips the seek and the pause).
    var limit = 60
    for (var n = 0; n < limit; n++) {
      await sleep(250)
      if (n === limit - 1 && limit < 240 && playingId() === saved.videoId && p.getPlayerState() === 3) limit++
      if (playingId() === saved.videoId && p.getPlayerState() === 1) { ok = true; break }
      // The app sometimes loads the song and leaves it cued (unstarted),
      // for ever: it only starts when told to (still muted when it is to stay paused).
      if (n >= 4 && playingId() === saved.videoId && (p.getPlayerState() === -1 || p.getPlayerState() === 5)) p.playVideo()
    }
    if (ok && saved.position > 1) p.seekTo(saved.position, true)
    if (!saved.playing) p.pauseVideo()
    if (!saved.muted) {
      if (!saved.playing) await sleep(300)
      p.unMute()
      s.dispatch({ type: "SET_MUTED", payload: false })
    } else {
      s.dispatch({ type: "SET_MUTED", payload: true })
    }
    // Selecting a song asks the server what comes next, which may rewrite
    // the rest of the queue: put the saved one back.
    await sleep(1500)
    if (!sameItems(s.getState().queue.items, saved.items)) {
      var keep = s.getState().queue.automixItems
      s.dispatch({ type: "RESET_ITEMS", payload: saved.items })
      s.dispatch({ type: "SET_INDEX", payload: i })
      if (!(keep && keep.length)) s.dispatch({ type: "REPLACE_AUTOMIX_ITEMS", payload: { automixItems: saved.automixItems || [], shouldAssignIds: false } })
    } else if ((s.getState().queue.automixItems || []).length > (saved.automixItems || []).length) {
      // The song's load appended a fresh continuation to the saved one: left
      // alone, the list grows by one page (50 songs) at every recycle.
      s.dispatch({ type: "REPLACE_AUTOMIX_ITEMS", payload: { automixItems: saved.automixItems || [], shouldAssignIds: false } })
    }
    schedule(false)
    return { restored: ok ? "song" : "queue" }
  }

  // ---------------------------------------------------------------- operations

  var FILTERS = P ? P.SEARCH_FILTERS : {}

  var LIBRARY = {
    playlists: "FEmusic_liked_playlists",
    songs: "VLLM",
    albums: "FEmusic_liked_albums",
    artists: "FEmusic_library_corpus_track_artists",
    history: "FEmusic_history"
  }

  var ops = {
    ping: function () { return { version: VERSION, host: location.hostname } },

    state: function () {
      return { player: snapshot(), account: account(), queueVersion: queueVersion }
    },

    transport: function (args) {
      var p = needPlayer()
      var v = video()
      switch (args.action) {
        case "play": p.playVideo(); break
        case "pause": p.pauseVideo(); break
        case "toggle":
          if (p.getPlayerState() === 1 || (v && !v.paused)) p.pauseVideo()
          else p.playVideo()
          break
        case "next": p.nextVideo(); break
        case "previous":
          // Like every player: restart the song unless it just started.
          if ((Number(p.getCurrentTime()) || 0) > 5) p.seekTo(0, true)
          else p.previousVideo()
          break
        default: fail("bad-args")
      }
      schedule(false)
      return { done: true }
    },

    seek: function (args) {
      var p = needPlayer()
      var d = Number(p.getDuration()) || 0
      var t = Math.max(0, Math.min(args.seconds, d > 1 ? d - 1 : args.seconds))
      p.seekTo(t, true)
      schedule(true)
      return { position: t }
    },

    volume: function (args) {
      var p = needPlayer()
      var s = store()
      p.setVolume(args.level)
      if (s) s.dispatch({ type: "SET_VOLUME", payload: args.level })
      if (args.level > 0 && p.isMuted && p.isMuted()) {
        p.unMute()
        if (s) s.dispatch({ type: "SET_MUTED", payload: false })
      }
      schedule(false)
      return { volume: Math.round(p.getVolume()) }
    },

    mute: function (args) {
      var p = needPlayer()
      var s = store()
      if (args.muted) p.mute(); else p.unMute()
      if (s) s.dispatch({ type: "SET_MUTED", payload: !!args.muted })
      schedule(false)
      return { muted: !!p.isMuted() }
    },

    repeat: function (args) {
      var s = needStore()
      s.dispatch({ type: "SET_REPEAT", payload: args.mode })
      schedule(false)
      return { repeat: String(s.getState().queue.repeatMode || "") }
    },

    // The advert's own Skip button, pressed when the user asks. Nothing
    // watches for it: the button in the panel shows for every advert and
    // says so when this one cannot be skipped yet.
    "ad.skip": function () {
      var buttons = document.querySelectorAll(".ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern")
      for (var i = 0; i < buttons.length; i++) {
        var b = buttons[i]
        if (b && b.offsetParent !== null && typeof b.click === "function") {
          b.click()
          schedule(false)
          return { skipped: true }
        }
      }
      fail("not-skippable")
    },

    shuffle: function () {
      var a = app()
      if (!a || !a.queue || typeof a.queue.shuffle !== "function") fail("no-queue")
      a.queue.shuffle()
      schedule(false)
      return { shuffled: true }
    },

    play: play,

    radio: function (args) {
      if (args.playlistId) return play({ videoId: args.videoId || "", playlistId: args.playlistId, params: args.params || "wAEB" })
      return play({ videoId: args.videoId, playlistId: "RDAMVM" + args.videoId, params: "wAEB" })
    },

    search: async function (args) {
      var body = { query: args.q }
      if (args.filter) body.params = decodeURIComponent(FILTERS[args.filter])
      if (args.continuation) body = { continuation: args.continuation }
      var data = await innertube("search", body, { timeout: 15000 })
      return P.search(data, { filter: args.filter || "" })
    },

    suggest: async function (args) {
      return { suggestions: P.suggestions(await innertube("music/get_search_suggestions", { input: args.q })) }
    },

    browse: async function (args) {
      var body = args.continuation ? { continuation: args.continuation } : { browseId: args.id }
      if (args.params && !args.continuation) body.params = args.params
      var data = await innertube("browse", body, { timeout: 15000 })
      return P.browse(args.id, data)
    },

    home: async function () {
      return P.browse("FEmusic_home", await innertube("browse", { browseId: "FEmusic_home" }, { timeout: 15000 }))
    },

    library: async function (args) {
      needSignIn()
      var id = LIBRARY[args.section]
      var data = await innertube("browse", { browseId: id }, { timeout: 15000 })
      return P.browse(id, data)
    },

    queue: function () { return queueModel() },
    "session.save": function () { return saveSession() },
    "session.restore": function (args) { return restoreSession(args) },
    "session.arm": function (args) {
      needStore()
      if (!args.armed) armedOn = null
      else if (armedOn === null) armedOn = selectedId()
      armedUntil = Date.now() + 1000 * (args.ttl || 90)
      return { armed: armedOn !== null }
    },
    "queue.add": queueAdd,
    "queue.move": queueMove,
    "queue.remove": queueRemove,
    "queue.jump": queueJump,

    like: async function (args) {
      needSignIn()
      var ep = args.status === "LIKE" ? "like/like" : args.status === "DISLIKE" ? "like/dislike" : "like/removelike"
      await innertube(ep, { target: { videoId: args.videoId } })
      likeCache[args.videoId] = args.status
      var s = store()
      if (s) s.dispatch({ type: "SET_VIDEO_LIKE_STATUS", payload: { id: args.videoId, status: args.status } })
      schedule(false)
      return { like: args.status }
    },

    lyrics: async function (args) {
      var info = P.watchInfo(await innertube("next", { videoId: args.videoId, isAudioOnly: true }))
      if (!info.lyricsId) return { kind: "none", lines: [], text: "", source: "" }
      var timed = null
      try { timed = await innertube("browse", { browseId: info.lyricsId }, { mobile: true }) } catch (e) { timed = null }
      var out = P.lyrics(timed, null)
      if (out.kind === "timed") return out
      return P.lyrics(null, await innertube("browse", { browseId: info.lyricsId }))
    },

    "playlist.create": async function (args) {
      needSignIn()
      var body = { title: args.title, privacyStatus: "PRIVATE" }
      if (args.videoIds && args.videoIds.length) body.videoIds = args.videoIds
      var res = await innertube("playlist/create", body)
      if (!res || !res.playlistId) fail("failed")
      return { playlistId: String(res.playlistId) }
    },

    "playlist.add": async function (args) {
      needSignIn()
      var res = await innertube("browse/edit_playlist", {
        playlistId: args.playlistId,
        actions: [{ action: "ACTION_ADD_VIDEO", addedVideoId: args.videoId, dedupeOption: "DEDUPE_OPTION_SKIP" }]
      })
      if (!res || res.status !== "STATUS_SUCCEEDED") fail("failed")
      return { added: true }
    },

    "eq.set": function (args) {
      var on = applyEq(parseEqArgs(args))
      return { applied: true, built: on }
    },

    "account.info": async function () {
      needSignIn()
      return P.accountInfo(await innertube("account/account_menu", {}))
    }
  }

  async function call(op, args) {
    if (location.hostname !== HOST) fail("not-on-app")
    var fn = Object.prototype.hasOwnProperty.call(ops, op) ? ops[op] : null
    if (!fn) fail("unknown-op")
    return await fn(args || {})
  }

  // ---------------------------------------------------------------- start

  var startTimer = null

  function stop() {
    if (startTimer) clearTimeout(startTimer)
    if (flushTimer) clearTimeout(flushTimer)
    if (unsubscribe) { try { unsubscribe() } catch (e) { /* store gone */ } }
    if (boundVideo) VIDEO_EVENTS.forEach(function (n) { boundVideo.removeEventListener(n, onVideoEvent) })
    boundVideo = null
    unsubscribe = null
    // The EQ graph stays: the <video> plays through it (see window.__solfaEq).
  }

  // On a new document the agent runs before the app exists: wait for it.
  // This is the only loop, and it ends when the app is up (or after 90 s).
  function start(tries) {
    if (location.hostname !== HOST) {
      emit("account", account())
      return
    }
    var s = store()
    if (!s || !player() || !cfg("INNERTUBE_CONTEXT")) {
      if (tries < 360) startTimer = setTimeout(function () { start(tries + 1) }, 250)
      else emit("error", { code: "app-not-found" })
      return
    }
    unsubscribe = s.subscribe(function () { checkArmed(); schedule(false) })
    bindVideo()
    if (fromUnsharedAgent && !eqGraph) {
      fromUnsharedAgent = false
      var el = video()
      // Wrapping it fails only if the old agent had: then only a fresh page
      // brings the sound back, and the bridge swaps it for one.
      if (el && !ensureGraph(el)) emit("eq-lost", {})
    }
    lastSignedIn = null
    emit("hello", { version: VERSION, account: account() })
    flush()
  }

  window.__solfa = { version: VERSION, call: call, stop: stop, sharesEq: true }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", function () { start(0) }, { once: true })
  else start(0)
})()
