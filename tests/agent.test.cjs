// Page agent tests: the agent runs in a node vm against a fake YouTube Music
// page (player, app store, InnerTube) shaped after the live one.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const { webcrypto } = require("node:crypto")

const ROOT = path.join(__dirname, "..")
const PARSE = fs.readFileSync(path.join(ROOT, "engine", "parse.js"), "utf8")
const AGENT = fs.readFileSync(path.join(ROOT, "engine", "agent.js"), "utf8")
const F = (name) => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "innertube", name + ".json"), "utf8"))
const ENTRIES = F("queue").queueDatas.map((d) => d.content)

function entry(videoId, title) {
  const e = JSON.parse(JSON.stringify(ENTRIES[0]))
  e.playlistPanelVideoRenderer.videoId = videoId
  e.playlistPanelVideoRenderer.title = { runs: [{ text: title }] }
  e.playlistPanelVideoRenderer.navigationEndpoint.watchEndpoint.videoId = videoId
  return e
}

function makeStore(queue) {
  let state = {
    player: { adPlaying: false, volume: 100, muted: false },
    queue: Object.assign({ items: [], automixItems: [], selectedItemIndex: 0, nextQueueItemId: 10, repeatMode: "NONE", shuffleEnabled: false }, queue),
    likeStatus: { videos: {}, playlists: {} }
  }
  const subs = new Set()
  const log = []
  function reduce(s, a) {
    const q = Object.assign({}, s.queue)
    switch (a.type) {
      case "ADD_ITEMS": q.items = q.items.slice(0, a.payload.index).concat(a.payload.items, q.items.slice(a.payload.index)); q.nextQueueItemId += a.payload.items.length; break
      case "MOVE_ITEM": { const it = q.items.slice(); const [m] = it.splice(a.payload.fromIndex, 1); it.splice(a.payload.toIndex, 0, m); q.items = it; break }
      case "REMOVE_ITEM": q.items = q.items.filter((_, i) => i !== a.payload); break
      case "REMOVE_AUTOMIX_ITEM": q.automixItems = q.automixItems.filter((_, i) => i !== a.payload); break
      case "SET_INDEX": q.selectedItemIndex = a.payload; break
      case "SET_REPEAT": q.repeatMode = a.payload; break
      case "SET_PLAYBACK_CONTENT_MODE": if (a.payload === "MODE_THE_APP_REFUSES") throw new TypeError("undefined is not iterable"); q.playbackContentMode = a.payload; break
      case "SET_SHUFFLE_ENABLED": q.shuffleEnabled = a.payload; break
      case "SET_AD_PLAYING": return Object.assign({}, s, { player: Object.assign({}, s.player, { adPlaying: a.payload }) })
      case "CLEAR": q.items = []; q.automixItems = []; q.nextQueueItemId = a.payload ? Math.max(...a.payload) + 1 : 0; break
      case "RESET_ITEMS": q.items = a.payload || []; break
      case "REPLACE_AUTOMIX_ITEMS": q.automixItems = a.payload.automixItems; break
      case "SET_VOLUME": return Object.assign({}, s, { player: Object.assign({}, s.player, { volume: a.payload }) })
      case "SET_MUTED": return Object.assign({}, s, { player: Object.assign({}, s.player, { muted: a.payload }) })
      case "SET_VIDEO_LIKE_STATUS": return Object.assign({}, s, { likeStatus: { videos: Object.assign({}, s.likeStatus.videos, { [a.payload.id]: a.payload.status }), playlists: {} } })
      default: return s
    }
    return Object.assign({}, s, { queue: q })
  }
  return {
    log,
    getState: () => state,
    dispatch(a) { log.push(a); state = reduce(state, a); subs.forEach((f) => f()); return a },
    subscribe(f) { subs.add(f); return () => subs.delete(f) },
    subscribers: () => subs.size
  }
}

// A fake WebAudio graph: nodes just record what they were asked to do, so a
// test can look at the shape of the chain the agent built.
class FakeAudioNode {
  constructor(kind) { this.kind = kind; this.connections = [] }
  connect(dst) { this.connections.push(dst); return dst }
  disconnect() { this.connections = [] }
}
class FakeGain extends FakeAudioNode {
  constructor() { super("gain"); this.gain = { value: 1 } }
}
class FakeBiquad extends FakeAudioNode {
  constructor() { super("biquad"); this.type = ""; this.frequency = { value: 0 }; this.Q = { value: 1 }; this.gain = { value: 0 } }
}
class FakeCompressor extends FakeAudioNode {
  constructor() { super("compressor") }
}
class FakeSource extends FakeAudioNode {
  constructor(el) { super("source"); this.mediaElement = el }
}
function makeAudioContext(list, opts = {}) {
  return class FakeAudioContext {
    constructor() {
      this.destination = new FakeAudioNode("destination")
      this.calls = []
      this.closed = false
      list.push(this)
    }
    createMediaElementSource(el) {
      // Like the real one: an element gets one source node for life.
      if (opts.sourceThrows || el.__wrapped) throw new Error("InvalidStateError: already connected")
      el.__wrapped = true
      const n = new FakeSource(el); this.calls.push(["source", n]); return n
    }
    createGain() { const n = new FakeGain(); this.calls.push(["gain", n]); return n }
    createBiquadFilter() { const n = new FakeBiquad(); this.calls.push(["biquad", n]); return n }
    createDynamicsCompressor() { const n = new FakeCompressor(); this.calls.push(["compressor", n]); return n }
    close() { this.closed = true }
  }
}

function makePage(opts = {}) {
  opts = Object.assign({ host: "music.youtube.com", signedIn: false, lands: true }, opts)
  const items = opts.items || [entry("AAAAAAAAAAA", "First Light"), entry("BBBBBBBBBBB", "Second Wind"), entry("CCCCCCCCCCC", "Third Rail")]
  const store = makeStore({ items, automixItems: [entry("DDDDDDDDDDD", "Drift")], selectedItemIndex: 0 })
  const listeners = {}
  const videoEl = {
    paused: false,
    addEventListener(n, f) { (listeners[n] = listeners[n] || []).push(f) },
    removeEventListener(n, f) { listeners[n] = (listeners[n] || []).filter((x) => x !== f) },
    fire(n) { (listeners[n] || []).forEach((f) => f({ type: n })) },
    count: () => Object.values(listeners).reduce((a, l) => a + l.length, 0)
  }
  const sel = () => store.getState().queue
  const vidAt = (i) => sel().items[i].playlistPanelVideoRenderer.videoId
  const player = {
    st: 1, time: 42, dur: 200, vol: 100, isMute: false, current: vidAt(0),
    getPlayerState() { return this.st },
    getCurrentTime() { return this.time },
    getDuration() { return this.dur },
    getVideoData() { return { video_id: this.current, title: "from player", author: "Player Author" } },
    getVolume() { return this.vol },
    setVolume(v) { this.vol = v },
    isMuted() { return this.isMute },
    mute() { this.isMute = true },
    unMute() { this.isMute = false },
    playVideo() { this.st = 1; videoEl.paused = false },
    pauseVideo() { this.st = 2; videoEl.paused = true },
    nextVideo() { store.dispatch({ type: "SET_INDEX", payload: sel().selectedItemIndex + 1 }); this.current = vidAt(sel().selectedItemIndex); this.time = 0 },
    previousVideo() { this.previousCalled = true },
    seekTo(t) { this.time = t },
    querySelector() { return videoEl }
  }
  const navigations = []
  const app = {
    queue: {
      store,
      selectQueueItem(item) { this.selected = item; player.current = item.playlistPanelVideoRenderer.videoId },
      shuffle() { this.shuffled = true }
    },
    dispatchEvent(ev) {
      navigations.push(ev.detail.endpoint)
      const w = ev.detail.endpoint.watchEndpoint
      if (opts.lands && w) player.current = w.videoId
      return true
    }
  }
  const requests = []
  const assigned = []
  const emitted = []
  const audioContexts = []
  const cfgValues = {
    INNERTUBE_CONTEXT: { client: { clientName: "WEB_REMIX", clientVersion: "1.2", hl: "es", gl: "ES" }, user: {} },
    INNERTUBE_API_KEY: "fixture-key", INNERTUBE_CLIENT_VERSION: "1.2", INNERTUBE_CONTEXT_CLIENT_NAME: 67,
    LOGGED_IN: opts.signedIn, SESSION_INDEX: 0,
    ...(opts.subscriber === undefined ? {} : { IS_SUBSCRIBER: opts.subscriber })
  }
  let now = 1_700_000_000_000
  // The engine's window sits on a hidden workspace: the real compositor
  // never calls back a native requestAnimationFrame. This stub matches
  // that — it remembers callbacks (so a test can tell whether the native
  // path was ever asked) but never runs them, the way the hidden window
  // never does either.
  let nativeRafId = 1
  const nativeRafStore = {}
  let nativeRafCalls = 0
  const ctx = {
    console,
    JSON, Math, Object, Array, String, Number, Promise, Error, RegExp, Uint8Array, TextEncoder, encodeURIComponent, decodeURIComponent, isFinite, parseInt,
    Date: class extends Date { static now() { return (now += 50) } },
    setTimeout: (fn) => setImmediate(fn),
    clearTimeout: () => {},
    requestAnimationFrame: (cb) => { nativeRafCalls++; const id = nativeRafId++; nativeRafStore[id] = cb; return id },
    cancelAnimationFrame: (id) => { delete nativeRafStore[id] },
    performance,
    AbortController,
    crypto: webcrypto,
    CustomEvent: class { constructor(type, init) { this.type = type; this.detail = init.detail } },
    location: { hostname: opts.host, origin: "https://" + opts.host, pathname: "/", href: "https://" + opts.host + "/", assign(u) { assigned.push(u) } },
    document: {
      readyState: "complete",
      cookie: opts.signedIn ? "PREF=x; SAPISID=fixture-sapisid; OTHER=1" : "PREF=x",
      querySelector(sel) { return sel === "ytmusic-app" ? app : sel === "video" ? videoEl : null },
      querySelectorAll(sel) { return /skip/.test(sel) ? (opts.skipButtons || []) : [] },
      getElementById(id) { return id === "movie_player" ? player : null },
      addEventListener() {}
    },
    ytcfg: { get: (k) => cfgValues[k] },
    AudioContext: makeAudioContext(audioContexts, opts),
    fetch: async (url, init) => {
      const endpoint = url.split("?")[0].replace("/youtubei/v1/", "")
      const body = JSON.parse(init.body)
      requests.push({ endpoint, body, init })
      const reply = opts.replies && opts.replies[endpoint] ? opts.replies[endpoint](body, init) : {}
      return { ok: true, status: 200, json: async () => reply }
    },
    __solfaEmit: (payload) => emitted.push(JSON.parse(payload))
  }
  ctx.window = ctx
  ctx.top = opts.frame ? {} : ctx
  vm.createContext(ctx)
  const load = (version) => vm.runInContext(PARSE + "\n;\n" + AGENT.replace("%%SOLFA_VERSION%%", version || "test-1"), ctx)
  load()
  const settle = () => new Promise((r) => setTimeout(r, 5))
  return { ctx, app, store, player, videoEl, requests, assigned, emitted, navigations, audioContexts, load, settle, call: (op, args) => ctx.__solfa.call(op, args), nativeRafCalls: () => nativeRafCalls }
}

test("starts, says hello and pushes the first state", async () => {
  const p = makePage()
  await p.settle()
  const kinds = p.emitted.map((e) => e.t)
  assert.ok(kinds.includes("hello"))
  assert.ok(kinds.includes("player"))
  assert.ok(kinds.includes("queue"))
  const player = p.emitted.find((e) => e.t === "player").data
  assert.equal(player.videoId, "AAAAAAAAAAA")
  assert.equal(player.title, "First Light", "the queue entry wins over the player's bare title")
  assert.ok(player.artists.length && player.album)
  assert.equal(player.playing, true)
})

test("a song outside the queue gets YouTube's 16:9 picture, not the letterboxed 4:3 one", async () => {
  const p = makePage()
  await p.settle()
  p.player.current = "ZZZZZZZZZZZ"
  p.videoEl.fire("seeked")
  await p.settle()
  const player = p.emitted.filter((e) => e.t === "player").pop().data
  assert.equal(player.videoId, "ZZZZZZZZZZZ")
  // hqdefault is 4:3 with black bars above and below a 16:9 video; cut
  // to a circle, the bars show. mqdefault is the same frame without them.
  assert.equal(player.thumb, "https://i.ytimg.com/vi/ZZZZZZZZZZZ/mqdefault.jpg")
})

test("pushes only on change, and a seek always", async () => {
  const p = makePage()
  await p.settle()
  const before = p.emitted.length
  p.videoEl.fire("timeupdate")
  p.store.dispatch({ type: "UNRELATED" })
  await p.settle()
  assert.equal(p.emitted.filter((e) => e.t === "player").length, p.emitted.slice(0, before).filter((e) => e.t === "player").length)
  p.player.time = 120
  p.videoEl.fire("seeked")
  await p.settle()
  assert.equal(p.emitted[p.emitted.length - 1].data.position, 120)
})

test("transport: toggle, and previous restarts a song that is well under way", async () => {
  const p = makePage()
  await p.settle()
  await p.call("transport", { action: "toggle" })
  assert.equal(p.player.st, 2)
  await p.call("transport", { action: "toggle" })
  assert.equal(p.player.st, 1)
  p.player.time = 30
  await p.call("transport", { action: "previous" })
  assert.equal(p.player.time, 0)
  assert.equal(p.player.previousCalled, undefined)
  p.player.time = 2
  await p.call("transport", { action: "previous" })
  assert.equal(p.player.previousCalled, true)
  await assert.rejects(p.call("transport", { action: "dance" }), /bad-args/)
})

test("volume goes to the player and to the app, and unmutes", async () => {
  const p = makePage()
  await p.settle()
  p.player.isMute = true
  const r = await p.call("volume", { level: 30 })
  assert.equal(r.volume, 30)
  assert.equal(p.player.vol, 30)
  assert.equal(p.player.isMute, false)
  assert.ok(p.store.log.some((a) => a.type === "SET_VOLUME" && a.payload === 30))
  assert.ok(p.store.log.some((a) => a.type === "SET_MUTED" && a.payload === false))
})

test("likes need sign-in, are signed, and update the app's store", async () => {
  const out = makePage()
  await out.settle()
  await assert.rejects(out.call("like", { videoId: "AAAAAAAAAAA", status: "LIKE" }), /signin-required/)
  const p = makePage({ signedIn: true, replies: { "like/like": () => ({}) } })
  await p.settle()
  await p.call("like", { videoId: "AAAAAAAAAAA", status: "LIKE" })
  const req = p.requests.find((r) => r.endpoint === "like/like")
  assert.equal(req.body.target.videoId, "AAAAAAAAAAA")
  assert.match(req.init.headers.Authorization, /^SAPISIDHASH \d+_[0-9a-f]{40}$/)
  assert.equal(req.init.credentials, "include")
  assert.equal(p.store.getState().likeStatus.videos.AAAAAAAAAAA, "LIKE")
  await p.settle()
  const last = p.emitted.filter((e) => e.t === "player").pop()
  assert.equal(last.data.like, "LIKE")
})

test("queue: add next, move and remove keep the playing track selected", async () => {
  const p = makePage({ replies: { "music/get_queue": () => ({ queueDatas: [{ content: entry("EEEEEEEEEEE", "Echo") }] }) } })
  await p.settle()
  p.store.dispatch({ type: "SET_INDEX", payload: 1 })
  p.player.current = "BBBBBBBBBBB"
  const added = await p.call("queue.add", { videoIds: ["EEEEEEEEEEE"], next: true })
  assert.equal(added.index, 2)
  let q = p.store.getState().queue
  assert.equal(q.items[2].playlistPanelVideoRenderer.videoId, "EEEEEEEEEEE")
  await p.call("queue.move", { from: 1, to: 3 })
  q = p.store.getState().queue
  assert.equal(q.items[q.selectedItemIndex].playlistPanelVideoRenderer.videoId, "BBBBBBBBBBB")
  await assert.rejects(p.call("queue.remove", { index: q.selectedItemIndex }), /playing/)
  await p.call("queue.remove", { index: 0 })
  q = p.store.getState().queue
  assert.equal(q.items[q.selectedItemIndex].playlistPanelVideoRenderer.videoId, "BBBBBBBBBBB")
  await assert.rejects(p.call("queue.move", { from: 0, to: 99 }), /out-of-range/)
  const model = await p.call("queue")
  assert.equal(model.items.length, 3)
  assert.equal(model.automix.length, 1)
})

test("session: saved on one page, given back on a fresh one", async () => {
  const old = makePage()
  await old.settle()
  old.store.dispatch({ type: "SET_INDEX", payload: 1 })
  old.store.dispatch({ type: "SET_REPEAT", payload: "ALL" })
  old.player.current = "BBBBBBBBBBB"
  await old.call("volume", { level: 30 })
  old.player.pauseVideo()
  const saved = JSON.parse(JSON.stringify(await old.call("session.save")))
  assert.equal(saved.videoId, "BBBBBBBBBBB")
  assert.equal(saved.playing, false)

  const fresh = makePage({ items: [entry("ZZZZZZZZZZZ", "Zero")] })
  await fresh.settle()
  fresh.store.dispatch({ type: "REPLACE_AUTOMIX_ITEMS", payload: { automixItems: [entry("YYYYYYYYYYY", "Other")] } })
  const res = await fresh.call("session.restore", saved)
  assert.equal(res.restored, "song")
  const q = fresh.store.getState().queue
  const ids = (list) => list.map((e) => e.playlistPanelVideoRenderer.videoId)
  assert.deepEqual(ids(q.items), ids(old.store.getState().queue.items))
  assert.deepEqual(ids(q.automixItems), ["DDDDDDDDDDD"])
  assert.equal(q.selectedItemIndex, 1)
  assert.equal(q.repeatMode, "ALL")
  assert.equal(q.nextQueueItemId, old.store.getState().queue.nextQueueItemId)
  assert.equal(fresh.player.current, "BBBBBBBBBBB")
  assert.equal(fresh.player.time, 42)
  assert.equal(fresh.player.getPlayerState(), 2, "stays paused")
  assert.equal(fresh.player.isMuted(), false, "loaded muted, then sound back")
  assert.equal(fresh.player.getVolume(), 30)
})

test("session: a song the app loads but leaves cued is started, muted, then paused again", async () => {
  const old = makePage()
  await old.settle()
  old.store.dispatch({ type: "SET_INDEX", payload: 1 })
  old.player.current = "BBBBBBBBBBB"
  old.player.pauseVideo()
  const saved = JSON.parse(JSON.stringify(await old.call("session.save")))

  const fresh = makePage({ items: [entry("ZZZZZZZZZZZ", "Zero")] })
  await fresh.settle()
  fresh.app.queue.selectQueueItem = function (item) {
    fresh.player.current = item.playlistPanelVideoRenderer.videoId
    fresh.player.st = -1   // loaded, never started
  }
  const res = await fresh.call("session.restore", saved)
  assert.equal(res.restored, "song")
  assert.equal(fresh.player.current, "BBBBBBBBBBB")
  assert.equal(fresh.player.getPlayerState(), 2, "stays paused")
  assert.equal(fresh.player.isMuted(), false, "sound back")
})

test("session: a setting the app refuses does not cost the rest of the session", async () => {
  const old = makePage()
  await old.settle()
  old.store.dispatch({ type: "SET_INDEX", payload: 1 })
  old.store.dispatch({ type: "SET_REPEAT", payload: "ALL" })
  old.player.current = "BBBBBBBBBBB"
  const saved = JSON.parse(JSON.stringify(await old.call("session.save")))
  saved.playbackContentMode = "MODE_THE_APP_REFUSES"

  const fresh = makePage({ items: [entry("ZZZZZZZZZZZ", "Zero")] })
  await fresh.settle()
  const res = await fresh.call("session.restore", saved)
  assert.equal(res.restored, "song")
  const q = fresh.store.getState().queue
  assert.equal(q.repeatMode, "ALL", "settings after the refused one still applied")
  assert.equal(q.selectedItemIndex, 1)
  assert.equal(fresh.player.current, "BBBBBBBBBBB")
})

test("session: the continuation the song's load appends is not kept, so the automix list does not grow at every recycle", async () => {
  const old = makePage()
  await old.settle()
  old.store.dispatch({ type: "SET_INDEX", payload: 1 })
  old.player.current = "BBBBBBBBBBB"
  const saved = JSON.parse(JSON.stringify(await old.call("session.save")))

  const fresh = makePage({ items: [entry("ZZZZZZZZZZZ", "Zero")] })
  await fresh.settle()
  const select = fresh.app.queue.selectQueueItem
  fresh.app.queue.selectQueueItem = function (item) {
    select.call(this, item)
    const q = fresh.store.getState().queue
    fresh.store.dispatch({ type: "REPLACE_AUTOMIX_ITEMS", payload: { automixItems: q.automixItems.concat([entry("NNNNNNNNNNN", "Fresh page")]) } })
  }
  const res = await fresh.call("session.restore", saved)
  assert.equal(res.restored, "song")
  const ids = (list) => list.map((e) => e.playlistPanelVideoRenderer.videoId)
  assert.deepEqual(ids(fresh.store.getState().queue.automixItems), ids(old.store.getState().queue.automixItems))
})

test("session: a song still buffering after 15 s is waited for, then seeked and paused as saved", async () => {
  const old = makePage()
  await old.settle()
  old.store.dispatch({ type: "SET_INDEX", payload: 1 })
  old.player.current = "BBBBBBBBBBB"
  old.player.pauseVideo()
  const saved = JSON.parse(JSON.stringify(await old.call("session.save")))
  saved.position = 42

  const fresh = makePage({ items: [entry("ZZZZZZZZZZZ", "Zero")] })
  await fresh.settle()
  fresh.app.queue.selectQueueItem = function (item) {
    fresh.player.current = item.playlistPanelVideoRenderer.videoId
    fresh.player.st = 3
    let looks = 0   // the wait looks a few times per 250 ms: 400 looks are well past the 15 s
    fresh.player.getPlayerState = function () { return this.st === 2 ? 2 : ++looks > 400 ? 1 : 3 }
  }
  fresh.player.time = 0
  const res = await fresh.call("session.restore", saved)
  assert.equal(res.restored, "song")
  assert.equal(fresh.player.time, 42, "seeked")
  assert.equal(fresh.player.getPlayerState(), 2, "paused")
})

test("armed: the next song is paused the moment it is selected, a queue edit is not a new song", async () => {
  const p = makePage()
  await p.settle()
  p.store.dispatch({ type: "SET_INDEX", payload: 1 })
  p.player.current = "BBBBBBBBBBB"
  assert.equal((await p.call("session.arm", { armed: true })).armed, true)
  await p.call("queue.remove", { index: 0 })   // the same song moves to index 0
  assert.equal(p.emitted.filter((e) => e.t === "recycle").length, 0)
  assert.equal(p.player.getPlayerState(), 1)
  p.player.nextVideo()
  assert.equal(p.player.getPlayerState(), 2)
  assert.deepEqual(p.emitted.filter((e) => e.t === "recycle").map((e) => e.data.videoId), ["CCCCCCCCCCC"])
  p.player.playVideo()
  p.store.dispatch({ type: "SET_INDEX", payload: 0 })
  assert.equal(p.emitted.filter((e) => e.t === "recycle").length, 1, "disarmed after one")
})

test("an arm that is not renewed runs out: no bridge, no pause", async () => {
  const p = makePage()
  await p.settle()
  await p.call("session.arm", { armed: true, ttl: 0.01 })
  p.player.nextVideo()
  assert.equal(p.player.getPlayerState(), 1)
  assert.equal(p.emitted.filter((e) => e.t === "recycle").length, 0)
})

test("queue jump uses the app's own selection", async () => {
  const p = makePage()
  await p.settle()
  await p.call("queue.jump", { index: 2 })
  assert.equal(p.player.current, "CCCCCCCCCCC")
  await p.call("queue.jump", { index: 0, automix: true })
  assert.equal(p.player.current, "DDDDDDDDDDD")
})

test("play changes the song inside the app, with a page load only as a fallback", async () => {
  const p = makePage()
  await p.settle()
  const r = await p.call("play", { videoId: "ZZZZZZZZZZZ", playlistId: "RDAMVMZZZZZZZZZZZ", params: "wAEB" })
  assert.equal(r.landed, "app")
  // (objects from the vm realm: compare as JSON)
  assert.equal(JSON.stringify(p.navigations[0]), JSON.stringify({ watchEndpoint: { videoId: "ZZZZZZZZZZZ", playlistId: "RDAMVMZZZZZZZZZZZ", params: "wAEB" } }))
  assert.equal(p.assigned.length, 0)
  const stuck = makePage({ lands: false })
  await stuck.settle()
  const r2 = await stuck.call("play", { videoId: "ZZZZZZZZZZZ", playlistId: "PLfixture" })
  assert.equal(r2.landed, "reload")
  assert.deepEqual(stuck.assigned, ["/watch?v=ZZZZZZZZZZZ&list=PLfixture"])
})

test("skip an advert: press its own visible Skip button, or say it cannot be skipped yet", async () => {
  const hidden = { offsetParent: null, clicked: 0, click() { this.clicked++ } }
  const shown = { offsetParent: {}, clicked: 0, click() { this.clicked++ } }
  const early = makePage({ skipButtons: [hidden] })
  await early.settle()
  await assert.rejects(early.call("ad.skip", {}), /not-skippable/)
  assert.equal(hidden.clicked, 0)
  const later = makePage({ skipButtons: [hidden, shown] })
  await later.settle()
  const r = await later.call("ad.skip", {})
  assert.equal(r.skipped, true)
  assert.equal(shown.clicked, 1)
})

test("radio from a song builds the radio list", async () => {
  const p = makePage()
  await p.settle()
  await p.call("radio", { videoId: "ZZZZZZZZZZZ" })
  assert.equal(p.navigations[0].watchEndpoint.playlistId, "RDAMVMZZZZZZZZZZZ")
})

test("search sends the filter's params and returns parsed groups", async () => {
  const p = makePage({ replies: { search: () => F("search-songs") } })
  await p.settle()
  const r = await p.call("search", { q: "harbour", filter: "songs" })
  const req = p.requests.find((x) => x.endpoint === "search")
  assert.equal(req.body.query, "harbour")
  assert.equal(req.body.params, "EgWKAQIIAWoSEAUQCRAOEAMQBBAKEBAQFRAR")
  assert.equal(req.body.context.client.clientName, "WEB_REMIX")
  assert.ok(r.songs.length >= 5)
})

test("lyrics: timed from the mobile client, asked anonymously", async () => {
  const p = makePage({ replies: { next: () => F("next-lyrics"), browse: (body, init) => (init.credentials === "omit" ? F("lyrics-timed") : F("lyrics-plain")) } })
  await p.settle()
  const r = await p.call("lyrics", { videoId: "AAAAAAAAAAA" })
  assert.equal(r.kind, "timed")
  const mobile = p.requests.find((x) => x.endpoint === "browse" && x.init.credentials === "omit")
  assert.equal(mobile.body.context.client.clientName, "ANDROID_MUSIC")
  assert.equal(mobile.init.headers.Authorization, undefined)
})

test("EQ: flat, off, no loudness never touches WebAudio", async () => {
  const p = makePage()
  await p.settle()
  const r = await p.call("eq.set", { bands: new Array(10).fill(0), preamp: 0, loudness: false })
  assert.equal(r.built, false)
  assert.equal(p.audioContexts.length, 0)
})

test("EQ: a non-flat preset builds the chain with the right filter types and frequencies", async () => {
  const p = makePage()
  await p.settle()
  const bass = [6, 5, 3, 1, 0, 0, 0, 0, 0, 0]
  const r = await p.call("eq.set", { bands: bass, preamp: -3, loudness: false })
  assert.equal(r.built, true)
  assert.equal(p.audioContexts.length, 1)
  const ctx = p.audioContexts[0]
  const biquads = ctx.calls.filter((c) => c[0] === "biquad").map((c) => c[1])
  assert.deepEqual(biquads.map((b) => b.type),
    ["lowshelf", "peaking", "peaking", "peaking", "peaking", "peaking", "peaking", "peaking", "peaking", "highshelf"])
  assert.deepEqual(biquads.map((b) => b.frequency.value), [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
  assert.deepEqual(biquads.map((b) => b.gain.value), bass)
  const preamp = ctx.calls.find((c) => c[0] === "gain")[1]
  assert.ok(Math.abs(preamp.gain.value - Math.pow(10, -3 / 20)) < 1e-9)
  // no compressor: loudness is off
  const tail = biquads[biquads.length - 1]
  assert.deepEqual(tail.connections, [ctx.destination])
})

test("EQ: eq.set with loudness on wires the compressor before the destination", async () => {
  const p = makePage()
  await p.settle()
  await p.call("eq.set", { bands: new Array(10).fill(0), preamp: 0, loudness: true })
  const ctx = p.audioContexts[0]
  const compressor = ctx.calls.find((c) => c[0] === "compressor")[1]
  const tail = ctx.calls.filter((c) => c[0] === "biquad").pop()[1]
  assert.deepEqual(tail.connections, [compressor])
  assert.deepEqual(compressor.connections, [ctx.destination])
})

test("EQ: once built, going back to flat sends flat gains through the same graph, not a teardown", async () => {
  const p = makePage()
  await p.settle()
  await p.call("eq.set", { bands: [4, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: -2, loudness: true })
  assert.equal(p.audioContexts.length, 1)
  const ctx = p.audioContexts[0]
  const r = await p.call("eq.set", { bands: new Array(10).fill(0), preamp: 0, loudness: false })
  assert.equal(r.built, true, "the graph is still there")
  assert.equal(p.audioContexts.length, 1, "no second context")
  const biquads = ctx.calls.filter((c) => c[0] === "biquad").map((c) => c[1])
  assert.ok(biquads.every((b) => b.gain.value === 0))
  const preamp = ctx.calls.find((c) => c[0] === "gain")[1]
  assert.equal(preamp.gain.value, 1, "0 dB preamp is unity gain")
  const tail = biquads[biquads.length - 1]
  assert.deepEqual(tail.connections, [ctx.destination], "the compressor is out of the chain again")
})

test("EQ: swapping the <video> element wraps the new one and leaves the old one routed, not silenced", async () => {
  const p = makePage()
  await p.settle()
  await p.call("eq.set", { bands: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0, loudness: false })
  const ctx = p.audioContexts[0]
  const firstSource = ctx.calls.find((c) => c[0] === "source")[1]
  const preamp = ctx.calls.find((c) => c[0] === "gain")[1]
  assert.equal(firstSource.mediaElement, p.videoEl)
  assert.deepEqual(firstSource.connections, [preamp], "connected onward")
  const newVideo = { addEventListener() {}, removeEventListener() {}, paused: false }
  p.player.querySelector = () => newVideo
  p.store.dispatch({ type: "SET_REPEAT", payload: "ALL" })   // any dispatch runs bindVideo() through flush()
  await p.settle()
  const sources = ctx.calls.filter((c) => c[0] === "source").map((c) => c[1])
  assert.equal(sources.length, 2, "a new source for the new element")
  assert.equal(sources[1].mediaElement, newVideo)
  assert.deepEqual(sources[1].connections, [preamp])
  // An element's audio only comes out through its source node: the old one
  // stays routed, or it would play silence if the page used it again.
  assert.deepEqual(firstSource.connections, [preamp])
  assert.equal(p.audioContexts.length, 1, "the same context, not a second one")
})

test("EQ: a swap back to an element already wrapped reuses its source instead of throwing (A -> B -> A)", async () => {
  const p = makePage()
  await p.settle()
  await p.call("eq.set", { bands: [2, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0, loudness: false })
  const a = p.videoEl
  const b = { addEventListener() {}, removeEventListener() {}, paused: false }
  p.player.querySelector = () => b
  p.store.dispatch({ type: "SET_REPEAT", payload: "ALL" })
  await p.settle()
  p.player.querySelector = () => a
  p.store.dispatch({ type: "SET_REPEAT", payload: "ONE" })
  await p.settle()
  const r = await p.call("eq.set", { bands: [3, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0, loudness: false })
  assert.equal(r.built, true)
  const ctx = p.audioContexts[0]
  const sources = ctx.calls.filter((c) => c[0] === "source").map((c) => c[1])
  assert.equal(sources.length, 2, "A kept its one source")
  const preamp = ctx.calls.find((c) => c[0] === "gain")[1]
  assert.deepEqual(sources[0].connections, [preamp], "A is routed, not silent")
  assert.equal(ctx.calls.filter((c) => c[0] === "biquad")[0][1].gain.value, 3)
})

test("EQ: an agent upgrade in the same document takes the graph over instead of silencing it", async () => {
  const p = makePage()
  await p.settle()
  await p.call("eq.set", { bands: [4, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: -2, loudness: false })
  const ctx = p.audioContexts[0]
  const source = ctx.calls.find((c) => c[0] === "source")[1]
  const preamp = ctx.calls.find((c) => c[0] === "gain")[1]
  p.load("test-2")
  await p.settle()
  assert.equal(p.ctx.__solfa.version, "test-2")
  assert.equal(ctx.closed, false, "the context the <video> plays through stays open")
  assert.deepEqual(source.connections, [preamp], "the source stays connected")
  // A flat EQ on the new agent goes through the same graph (not "no graph").
  let r = await p.call("eq.set", { bands: new Array(10).fill(0), preamp: 0, loudness: false })
  assert.equal(r.built, true)
  assert.equal(preamp.gain.value, 1)
  // A non-flat one reuses it: no second context, no second source (which would throw).
  r = await p.call("eq.set", { bands: [5, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0, loudness: true })
  assert.equal(r.built, true)
  assert.equal(p.audioContexts.length, 1)
  assert.equal(ctx.calls.filter((c) => c[0] === "source").length, 1)
  assert.equal(ctx.calls.filter((c) => c[0] === "biquad")[0][1].gain.value, 5)
})

test("EQ: replacing an agent that kept its graph to itself, on a wrapped <video>, asks for a fresh page", async () => {
  const p = makePage()
  await p.settle()
  // An agent from before window.__solfaEq: its stop() took the graph with it,
  // and the element stays bound to that dead source for life.
  p.ctx.__solfa = { version: "old", call() {}, stop() {} }
  p.ctx.__solfaEq = undefined
  p.videoEl.__wrapped = true
  p.emitted.length = 0
  p.load("test-2")
  await p.settle()
  assert.ok(p.emitted.some((e) => e.t === "eq-lost"), JSON.stringify(p.emitted.map((e) => e.t)))
})

test("EQ: replacing an older agent on a <video> never wrapped needs no fresh page", async () => {
  const p = makePage()
  await p.settle()
  p.ctx.__solfa = { version: "old", call() {}, stop() {} }
  p.emitted.length = 0
  p.load("test-2")
  await p.settle()
  assert.ok(!p.emitted.some((e) => e.t === "eq-lost"))
})

test("EQ: a source that cannot be made falls back to no EQ instead of failing the call", async () => {
  const p = makePage({ sourceThrows: true })
  await p.settle()
  const r = await p.call("eq.set", { bands: [6, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0, loudness: false })
  assert.equal(r.applied, true)
  assert.equal(r.built, false)
  // and the player keeps being watched (bindVideo does not throw either)
  p.store.dispatch({ type: "SET_REPEAT", payload: "ALL" })
  await p.settle()
  assert.equal((await p.call("state")).player.videoId, "AAAAAAAAAAA")
})

test("account.info needs sign-in and parses the account menu", async () => {
  const out = makePage()
  await out.settle()
  await assert.rejects(out.call("account.info"), /signin-required/)
  const p = makePage({ signedIn: true, replies: { "account/account_menu": () => F("account-menu") } })
  await p.settle()
  const r = await p.call("account.info")
  assert.equal(r.name, "Alex Example")
  assert.equal(r.email, "alex@example.com")
  assert.match(r.avatar, /=s64-c-mo$/)
})

test("the account event says Premium only for a signed-in subscriber", async () => {
  const account = async (opts) => {
    const p = makePage(opts)
    await p.settle()
    return p.emitted.filter((e) => e.t === "account").pop().data
  }
  assert.equal((await account({ signedIn: true, subscriber: true })).premium, true)
  assert.equal((await account({ signedIn: true, subscriber: false })).premium, false, "a free account")
  assert.equal((await account({ signedIn: true })).premium, false, "the page did not say")
  assert.equal((await account({ signedIn: false, subscriber: true })).premium, false, "signed out")
  assert.equal((await account({ signedIn: true, subscriber: "true" })).premium, false, "an odd value is not a yes")
})

test("in a child frame it stays silent and installs nothing", async () => {
  const p = makePage({ frame: true, host: "googleads.example" })
  await p.settle()
  assert.equal(p.emitted.length, 0)
  assert.equal(p.ctx.__solfa, undefined)
})

test("off the app (cookie page, sign-in page) it refuses and reports where it is", async () => {
  const p = makePage({ host: "consent.youtube.com" })
  await p.settle()
  await assert.rejects(p.call("state"), /not-on-app/)
  assert.equal(p.emitted[0].t, "account")
  assert.equal(p.emitted[0].data.host, "consent.youtube.com")
})

test("requestAnimationFrame runs via the setTimeout fallback, and cancelAnimationFrame stops a pending one", async () => {
  const p = makePage()
  await p.settle()
  let a = false, b = false
  const idA = p.ctx.window.requestAnimationFrame(() => { a = true })
  const idB = p.ctx.window.requestAnimationFrame(() => { b = true })
  p.ctx.window.cancelAnimationFrame(idB)
  await new Promise((r) => setTimeout(r, 80))
  assert.equal(a, true, "a callback the hidden compositor never runs still runs, via the timer fallback")
  assert.equal(b, false, "cancelAnimationFrame stops a pending fallback callback")
})

test("injecting the agent twice does not double-wrap requestAnimationFrame", async () => {
  const p = makePage()
  await p.settle()
  const wrapped = p.ctx.window.requestAnimationFrame
  p.load("test-2")
  await p.settle()
  assert.equal(p.ctx.window.requestAnimationFrame, wrapped, "wrapped once, kept across a re-injection")
  let calls = 0
  p.ctx.window.requestAnimationFrame(() => { calls++ })
  await new Promise((r) => setTimeout(r, 80))
  assert.equal(calls, 1, "a callback runs exactly once, not twice from nested fallback scheduling")
})

test("snapshot during an ad reports adPosition/adDuration, and zeroes the regular clock", async () => {
  const p = makePage()
  await p.settle()
  p.store.dispatch({ type: "SET_AD_PLAYING", payload: true })
  p.videoEl.currentTime = 7.5
  p.videoEl.duration = 30
  const s = (await p.call("state")).player
  assert.equal(s.ad, true)
  assert.equal(s.adPosition, 7.5)
  assert.equal(s.adDuration, 30)
  assert.equal(s.position, 0, "the song's own clock stays at 0 during an ad")
  assert.equal(s.duration, 0)
})

test("injecting again: same version is a no-op, a new version replaces the old", async () => {
  const p = makePage()
  await p.settle()
  assert.equal(p.store.subscribers(), 1)
  const listeners = p.videoEl.count()
  p.load("test-1")
  await p.settle()
  assert.equal(p.store.subscribers(), 1)
  p.load("test-2")
  await p.settle()
  assert.equal(p.store.subscribers(), 1)
  assert.equal(p.videoEl.count(), listeners)
  assert.equal(p.ctx.__solfa.version, "test-2")
})
