// Tests for lib/Model.js (the QML's logic), loaded as QML would load it.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const src = fs.readFileSync(path.join(__dirname, "..", "lib", "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const M = {}
vm.createContext(M)
vm.runInContext(src, M)
// Objects made in the vm realm: compare them as JSON.
const deep = (a, b) => assert.equal(JSON.stringify(a), JSON.stringify(b))

test("position runs on while playing and stops at the end", () => {
  const p = { videoId: "AAAAAAAAAAA", position: 10, at: 1000, playing: true, duration: 30 }
  assert.equal(M.positionAt(p, 6000), 15)
  assert.equal(M.positionAt(p, 100000), 30)
  assert.equal(M.positionAt(Object.assign({}, p, { playing: false }), 6000), 10)
  assert.equal(M.positionAt(Object.assign({}, p, { buffering: true }), 6000), 10)
  assert.equal(M.positionAt(Object.assign({}, p, { ad: true }), 6000), 10)
  assert.equal(M.positionAt({}, 6000), 0)
})

test("times", () => {
  assert.equal(M.fmtTime(0), "0:00")
  assert.equal(M.fmtTime(65.9), "1:05")
  assert.equal(M.fmtTime(3723), "1:02:03")
  assert.equal(M.fmtTime(-3), "0:00")
})

test("artists and row subtitles", () => {
  assert.equal(M.artistsText([{ name: "Mira" }, { name: "Tor" }, null]), "Mira, Tor")
  assert.equal(M.rowSubtitle({ videoId: "x", artists: [], album: { name: "Harbour" } }), "Harbour")
  assert.equal(M.rowSubtitle({ browseId: "MPRE", subtitle: "Album · Mira · 2019" }), "Album · Mira · 2019")
})

test("repeat and like cycle", () => {
  assert.equal(M.nextRepeat("NONE"), "ALL")
  assert.equal(M.nextRepeat("ALL"), "ONE")
  assert.equal(M.nextRepeat("ONE"), "NONE")
  assert.equal(M.nextLike("LIKE"), "INDIFFERENT")
  assert.equal(M.nextLike("DISLIKE"), "LIKE")
  assert.equal(M.volumeAfter(98, 1), 100)
  assert.equal(M.volumeAfter(3, -1), 0)
  assert.equal(M.volumeAfter(50, -2), 40)
})

test("search rows: groups with headers, capped, and a filter shows one group whole", () => {
  const song = (i) => ({ kind: "song", videoId: "S" + i })
  const r = { top: { kind: "artist", browseId: "UC1" }, songs: [1, 2, 3, 4, 5, 6, 7, 8].map(song), albums: [{ browseId: "MPRE1" }], artists: [], playlists: [], videos: [] }
  const rows = M.searchRows(r, "")
  deep(rows.filter((x) => x.header).map((x) => x.header), ["Top result", "Songs", "Albums"])
  assert.equal(rows.filter((x) => x.item && x.item.videoId).length, 6)
  assert.equal(rows.find((x) => x.header === "Songs").more, "songs")
  const only = M.searchRows(r, "songs")
  assert.equal(only.length, 8)
  assert.ok(only.every((x) => x.item))
})

test("search rows with no filter follow the reply's order and drop nothing", () => {
  const P = require("../engine/parse.js")
  const fixture = (n) => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "innertube", n + ".json"), "utf8"))
  const r = P.search(fixture("search-mixed"))
  const rows = M.searchRows(r, "")
  deep(rows.filter((x) => x.header).map((x) => x.header), ["Top result", "More results"])
  const items = rows.filter((x) => x.item)
  assert.equal(items.length, 1 + r.all.length)
  assert.equal(items[0].item, r.top)
  // Songs and videos side by side, in the reply's order; episodes and
  // podcasts are there too.
  deep(items.slice(1).map((x) => x.item.kind), r.all.map((x) => x.kind))
  deep(items.slice(1).map((x) => x.label), ["Video", "Video", "Video", "Song", "Video", "Song", "Video", "", "Episode", ""])
  assert.equal(M.labelled("Video", "Some Artist"), "Video · Some Artist")
  assert.equal(M.labelled("Episode", ""), "Episode")
  assert.equal(M.labelled("", "Album"), "Album")
  // A filter still shows its own group whole.
  const only = M.searchRows(r, "videos")
  assert.ok(only.every((x) => x.item && x.item.kind === "video"))
  assert.equal(only.length, r.videos.length)
})

test("save picker rows: New playlist, then Recent and All playlists, the filter matches both", () => {
  const pl = (id, title, recent) => ({ id, title, count: "3 songs", recent })
  const pls = [pl("PL1", "Road trip", true), pl("PL3", "Studio Ghibli", true), pl("LM", "Liked Music", false), pl("PL2", "Study", false)]
  const shape = (rows) => rows.map((r) => (r.create ? "+" : r.header ? "#" + r.header : r.playlist.title))
  deep(shape(M.saveRows(pls, "")), ["+", "#Recent", "Road trip", "Studio Ghibli", "#All playlists", "Liked Music", "Study"])
  deep(shape(M.saveRows(pls, "  STUD ")), ["+", "#Recent", "Studio Ghibli", "#All playlists", "Study"])
  deep(shape(M.saveRows(pls, "liked")), ["+", "#All playlists", "Liked Music"])
  deep(shape(M.saveRows(pls, "zzz")), ["+"])
  deep(shape(M.saveRows(null, "")), ["+"])
  const rows = M.saveRows(pls, "")
  assert.equal(M.firstPlaylistRow(rows), 2)
  assert.equal(M.firstPlaylistRow(M.saveRows(null, "")), 0)
  assert.equal(M.moveCursor(rows, 0, 1), 2, "the cursor skips the headers")
  assert.equal(M.moveCursor(rows, 3, 1), 5)
  assert.equal(M.savedMessage("Study", false), "Saved to Study")
  assert.equal(M.savedMessage("Study", true), "Already in Study · ↵ again to add anyway")
  assert.equal(M.errorText("failed"), "YouTube Music did not save it")
  assert.ok(M.ALL_KEY_HINTS.some((h) => h[0] === "S"))
})

test("find in a playlist: every word, any order, any field, no case, no accents", () => {
  const t = (title, artists, album) => ({ title, artists: artists.map((name) => ({ name })), album: album ? { name: album } : undefined })
  const tracks = [
    t("Crème Brûlée", ["Zoë Example"], "Été Sessions"),
    t("Sunrise", ["Zoë Example", "The Samples"]),
    t("Zebra Crossing", ["Mia Fixture"], "Stripes"),
    { title: "No Artist" },
  ]
  const names = (q) => M.filterTracks(tracks, q).map((x) => x.title)
  deep(names(""), ["Crème Brûlée", "Sunrise", "Zebra Crossing", "No Artist"])
  deep(names("   "), ["Crème Brûlée", "Sunrise", "Zebra Crossing", "No Artist"], "blanks are no query")
  deep(names("creme"), ["Crème Brûlée"], "accents do not matter")
  deep(names("CRÈME brulee"), ["Crème Brûlée"], "nor case, in either direction")
  deep(names("zoe"), ["Crème Brûlée", "Sunrise"], "the artist")
  deep(names("sessions"), ["Crème Brûlée"], "the album")
  deep(names("zoe brulee"), ["Crème Brûlée"], "all words must match")
  deep(names("brulee   zoe"), ["Crème Brûlée"], "in any order, any spacing")
  deep(names("samples sunrise"), ["Sunrise"], "title and a second artist")
  deep(names("zoe stripes"), [], "words from different songs do not add up")
  deep(names("ZEBRA"), ["Zebra Crossing"])
  deep(names("artist"), ["No Artist"], "a song with no artists or album still matches its title")
  assert.equal(M.filterTracks(tracks, "").length, 4)
  assert.equal(M.filterTracks(null, "x").length, 0)
  assert.equal(M.foldText("Ångström Ñandú"), "angstrom nandu")
  assert.equal(M.foldText(null), "")
})

test("find in a playlist: the status line and the cursor's place in the full list", () => {
  assert.equal(M.findStatus("", 890, 890, false, false), "890 songs")
  assert.equal(M.findStatus("", 300, 300, true, false), "Loading 300 songs")
  assert.equal(M.findStatus("", 1, 1, false, false), "1 song")
  assert.equal(M.findStatus("", 200, 200, false, true), "200 songs · not all loaded")
  assert.equal(M.findStatus("zoe", 12, 890, false, false), "12 of 890")
  assert.equal(M.findStatus("zoe", 2, 300, true, false), "2 of 300 · loading")
  assert.equal(M.findStatus("zoe", 0, 200, false, true), "0 of 200 · not all loaded")
  const rows = M.trackRows([{ videoId: "A", setVideoId: "1" }, { videoId: "B", setVideoId: "2" }, { videoId: "A", setVideoId: "3" }])
  assert.equal(M.rowIndex(rows, { item: { videoId: "A", setVideoId: "3" } }), 2, "a song twice in the list is told apart by its own id")
  assert.equal(M.rowIndex(rows, { item: { videoId: "B", setVideoId: "2" } }), 1)
  assert.equal(M.rowIndex(rows, { item: { videoId: "Z" } }), -1)
  assert.equal(M.rowIndex(rows, null), -1)
  assert.equal(M.rowIndex(rows, { header: "x" }), -1)
  assert.ok(M.ALL_KEY_HINTS.some((h) => h[0] === "F"))
})

test("footer hints: a pinned hint stays after the first", () => {
  const page = [["↵", "play or open"], ["F", "find", true], ["e", "play next"], ["esc", "back"]]
  deep(M.footerHints(page, true), [["↵", "play or open"], ["F", "find", true], ["space", "play/pause"], ["n p", "next/previous"]])
  deep(M.footerHints(page, false), [["↵", "play or open"], ["F", "find", true], ["space", "play/pause"], ["n p", "next/previous"]])
})

test("queue rows: queued, then autoplay under its own header", () => {
  const rows = M.queueRows({ items: [{ videoId: "A" }, { videoId: "B" }], automix: [{ videoId: "C" }], index: 1 })
  assert.equal(rows.length, 4)
  assert.equal(rows[1].current, true)
  assert.equal(rows[2].header, "Autoplay")
  assert.equal(rows[3].automix, true)
  assert.equal(rows[3].queueIndex, 0)
})

test("the cursor skips headers and stays inside the list", () => {
  const rows = [{ header: "A" }, { item: 1 }, { item: 2 }, { header: "B" }, { item: 3 }]
  assert.equal(M.firstRow(rows), 1)
  assert.equal(M.moveCursor(rows, 1, 1), 2)
  assert.equal(M.moveCursor(rows, 2, 1), 4)
  assert.equal(M.moveCursor(rows, 4, 1), 4)
  assert.equal(M.moveCursor(rows, 4, -1), 2)
  assert.equal(M.moveCursor(rows, 1, -1), 1)
  assert.equal(M.moveCursor(rows, -1, 1), 1)
  assert.equal(M.moveCursor([], 0, 1), -1)
})

test("the lyric line being sung", () => {
  const lines = [{ t: 0 }, { t: 1000 }, { t: 5000 }]
  assert.equal(M.lyricIndex(lines, -5), -1)
  assert.equal(M.lyricIndex(lines, 0), 0)
  assert.equal(M.lyricIndex(lines, 4999), 1)
  assert.equal(M.lyricIndex(lines, 99999), 2)
  assert.equal(M.lyricIndex([], 10), -1)
})

test("expired requests", () => {
  deep(M.expired({ 1: { deadline: 5 }, 2: { deadline: 50 } }, 10), [1])
})

test("global keys: only the free ones, ours do not count as taken", () => {
  const binds = JSON.stringify([
    { modmask: 72, key: "m", description: "Someone else's" },
    { modmask: 72, key: "N", description: "Solfa: next song" }
  ])
  const free = M.freeKeys(binds).map((k) => k.keys)
  assert.ok(!free.includes("SUPER + ALT + M"))
  assert.ok(free.includes("SUPER + ALT + N"))
  assert.equal(M.freeKeys("not json").length, 0)
})

test("panel key: Super+Alt+M when free, else the first free fallback, never another app's key", () => {
  const free = "[]"
  assert.equal(M.panelKeyFor(free, "").keys, "SUPER + ALT + M")
  const taken = JSON.stringify([{ modmask: 72, key: "M", description: "Someone else's" }])
  assert.equal(M.panelKeyFor(taken, "").keys, "SUPER + SHIFT + M")
  const more = JSON.stringify([{ modmask: 72, key: "M", description: "x" }, { modmask: 65, key: "m", description: "y" }])
  assert.equal(M.panelKeyFor(more, "").keys, "SUPER + CTRL + M")
  const all = JSON.stringify([{ modmask: 72, key: "M" }, { modmask: 65, key: "M" }, { modmask: 68, key: "M" }])
  assert.equal(M.panelKeyFor(all, ""), null)
  assert.ok(!M.freeKeys(all, "").some((k) => k.command === "toggle"))
  // Omarchy's Super+M (minimize) is not ours and does not matter
  const minimize = JSON.stringify([{ modmask: 64, key: "M", description: "Minimize window to the dock" }])
  assert.equal(M.panelKeyFor(minimize, "").keys, "SUPER + ALT + M")
  // a pick is honoured when free, ignored when taken
  assert.equal(M.panelKeyFor(free, "SUPER + CTRL + M").keys, "SUPER + CTRL + M")
  assert.equal(M.panelKeyFor(taken, "SUPER + ALT + M").keys, "SUPER + SHIFT + M")
  assert.equal(M.panelKeyOptions(taken).join("|"), "|SUPER + SHIFT + M|SUPER + CTRL + M")
  assert.equal(M.keyLabel("SUPER + SHIFT + M"), "Super+Shift+M")
  // Solfa's own binds do not count as taken
  const ours = JSON.stringify([{ modmask: 65, key: "M", description: "Solfa: open or close" }])
  assert.equal(M.panelKeyFor(ours, "").keys, "SUPER + ALT + M")
})

test("play/pause key: Super+Alt+P, then the same fallbacks; next, previous and like keep theirs", () => {
  const key = (binds) => M.freeKeys(JSON.stringify(binds), "").find((k) => k.command === "playPause")
  assert.equal(key([]).keys, "SUPER + ALT + P")
  assert.equal(key([{ modmask: 72, key: "P", description: "Other" }]).keys, "SUPER + SHIFT + P")
  assert.equal(key([{ modmask: 72, key: "P" }, { modmask: 65, key: "P" }]).keys, "SUPER + CTRL + P")
  assert.equal(key([{ modmask: 72, key: "P" }, { modmask: 65, key: "P" }, { modmask: 68, key: "P" }]), undefined)
  const all = M.freeKeys("[]", "").map((k) => k.command + "=" + k.keys).sort().join(",")
  assert.equal(all, "like=SUPER + ALT + L,next=SUPER + ALT + N,playPause=SUPER + ALT + P,previous=SUPER + ALT + B,toggle=SUPER + ALT + M")
})

test("unbind: only our own binds, by their own key", () => {
  const binds = JSON.stringify([
    { modmask: 64, key: "M", description: "Minimize window to the dock" },
    { modmask: 65, key: "M", description: "Solfa: open or close" },
    { modmask: 72, key: "N", description: "Solfa: next song" }
  ])
  const lua = M.unbindLua(binds)
  assert.match(lua, /SUPER \+ SHIFT \+ M/)
  assert.match(lua, /SUPER \+ ALT \+ N/)
  assert.ok(!/\[\[SUPER \+ M\]\]/.test(lua))
})

test("bind Lua unbinds first and calls the service over the shell's IPC", () => {
  const lua = M.bindLua(M.GLOBAL_KEYS.slice(0, 2))
  assert.match(lua, /pcall\(hl\.unbind, \[\[SUPER \+ ALT \+ M\]\]\); hl\.bind\(\[\[SUPER \+ ALT \+ M\]\], hl\.dsp\.exec_cmd\(\[\[\/usr\/share\/omarchy\/bin\/omarchy-shell shell toggle io\.github\.sirallap\.solfa '\{\}'\]\]\)/)
  assert.match(lua, /exec_cmd\(\[\[\/usr\/share\/omarchy\/bin\/omarchy-shell io\.github\.sirallap\.solfa playPause\]\]\)/)
  // every IPC method a key calls exists on the service's handler
  const svc = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  for (const k of M.GLOBAL_KEYS) if (k.command !== "toggle") assert.match(svc, new RegExp("function " + k.command + "\\(\\): void"))
  assert.equal(M.unbindLua(JSON.stringify([{ description: "Solfa: like", modmask: 72, key: "l" }])), "pcall(hl.unbind, [[SUPER + ALT + L]]); ")
})

// M3: no bare program name goes through Hyprland's exec (a PATH lookup, sh -c).
test("bind Lua always runs an absolute omarchy-shell, never a bare name", () => {
  const withCustomBin = M.bindLua(M.GLOBAL_KEYS.slice(0, 1), "/opt/omarchy/bin/omarchy-shell")
  assert.match(withCustomBin, /exec_cmd\(\[\[\/opt\/omarchy\/bin\/omarchy-shell /)
  const withDefault = M.bindLua(M.GLOBAL_KEYS.slice(0, 1))
  assert.match(withDefault, /exec_cmd\(\[\[\/usr\/share\/omarchy\/bin\/omarchy-shell /)
  assert.doesNotMatch(withDefault, /exec_cmd\(\[\[omarchy-shell /, "never a bare name")
})

test("engine words and error words", () => {
  assert.equal(M.engineLine({ status: "ready" }, { host: "music.youtube.com" }), "")
  assert.equal(M.engineLine({ status: "ready" }, { host: "consent.youtube.com" }), "Waiting for sign-in")
  assert.match(M.engineLine({ status: "stuck" }, {}), /stopped answering/)
  assert.equal(M.engineLine({ status: "signing-in" }, {}), "Signing in, in the Google window")
  assert.equal(M.errorText("engine-signing-in"), "Finish signing in first")
  assert.equal(M.errorText("signin-required"), "Sign in to do that")
  assert.match(M.errorText("http-429"), /429/)
  assert.match(M.errorText("engine-starting"), /not ready/)
  assert.match(M.errorText("engine-busy"), /did not close/)
  assert.match(M.errorText("signin-failed"), /still signed out/)
  assert.match(M.errorText("erase-refused"), /nothing was deleted/)
  assert.match(M.errorText("erase-failed"), /could not be deleted/)
  assert.match(M.errorText("sleep-pause-failed"), /could not pause/)
})

test("notification text", () => {
  deep(M.notifyText({ title: "Harbour", artists: [{ name: "Mira" }], album: { name: "Lights" } }), { summary: "Harbour", body: "Mira — Lights" })
  assert.equal(M.notifyText({}), null)
})

test("footer hints: the view's main key, then play, next and like; never more than four", () => {
  const queue = [["↵", "play"], ["x", "remove"], ["J K", "move"]]
  deep(M.footerHints(queue, true), [["↵", "play"], ["space", "play/pause"], ["n p", "next/previous"], ["f", "like"]])
  deep(M.footerHints(queue, false), [["↵", "play"], ["space", "play/pause"], ["n p", "next/previous"]], "no like without a song to like")
  deep(M.footerHints([], true), [["space", "play/pause"], ["n p", "next/previous"], ["f", "like"]])
  deep(M.footerHints(null, true), [["space", "play/pause"], ["n p", "next/previous"], ["f", "like"]])
  deep(M.footerHints([["space", "pause"]], true), [["space", "play/pause"], ["n p", "next/previous"], ["f", "like"]], "a key is shown once")
})

test("the full key list names the like key", () => {
  assert.ok(M.ALL_KEY_HINTS.some((h) => /(^|\s)f(\s|$)/.test(h[0]) && /like/.test(h[1])))
  assert.ok(M.ALL_KEY_HINTS.some((h) => h[0] === "?"), "and how to close it again")
})

test("footer hints: while typing in a field, only the field's own keys", () => {
  const field = [["↵", "search"], ["↓", "results"], ["esc", "clear"]]
  deep(M.footerHints(field, true, true), field, "space, n, p and f would type into the field")
})

// ------------------------------------------------------------------ settings

test("CODE_VERSION matches manifest.json's version", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
  assert.equal(M.CODE_VERSION, manifest.version)
})

test("engineLineWhileDown asks for a shell restart only when the code on disk is newer", () => {
  assert.equal(M.engineLineWhileDown(M.CODE_VERSION), "Starting Solfa")
  assert.equal(M.engineLineWhileDown(""), "Starting Solfa")
  assert.equal(M.engineLineWhileDown("9.9.9"), "Solfa was updated. Restart the shell to finish")
})

test("SETTINGS_DEFAULTS matches manifest.json's barWidget.defaults exactly", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
  deep(M.SETTINGS_DEFAULTS, manifest.barWidget.defaults)
  // Every default also has a schema row with a label (Omarchy's own settings UI).
  const keys = manifest.barWidget.schema.map((s) => s.key)
  for (const k of Object.keys(M.SETTINGS_DEFAULTS)) {
    assert.ok(keys.includes(k), k + " has no schema row")
    const row = manifest.barWidget.schema.find((s) => s.key === k)
    assert.ok(row.label && row.label.length > 0, k + " has no label")
  }
})

test("equalizer presets: 10 bands, custom keeps what was there", () => {
  for (const name of ["flat", "bass", "treble", "vocal", "loudness"]) {
    assert.equal(M.eqBandsFor(name, null).length, 10, name)
  }
  deep(M.eqBandsFor("flat", null), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  deep(M.eqBandsFor("custom", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  deep(M.eqBandsFor("custom", null), M.EQ_PRESETS.flat, "no custom bands yet: flat")
  assert.equal(M.EQ_BAND_HZ.length, 10)
})

test("eqBands settings value round-trips through JSON and clamps to +/-12 dB", () => {
  deep(M.parseEqBands("[1,2,3,4,5,6,7,8,9,10]"), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  deep(M.parseEqBands("[99,-99,0,0,0,0,0,0,0,0]"), [12, -12, 0, 0, 0, 0, 0, 0, 0, 0], "clamped to the pedal's range")
  deep(M.parseEqBands("not json"), M.EQ_PRESETS.flat, "garbage falls back to flat")
  deep(M.parseEqBands("[1,2,3]"), M.EQ_PRESETS.flat, "wrong length falls back to flat")
  assert.equal(M.eqBandDb([1, 2], 0), 1)
  assert.equal(M.eqBandDb([1, 2], 5), 0, "missing band reads as 0 dB")
})

test("eqPayload: off is always flat, whatever preset or custom bands are stored", () => {
  const custom = [7, 0, 0, 0, 0, 0, 0, 0, 0, -3]
  deep(M.eqPayload(false, "bass", custom, -6, true), { preset: "flat", bands: M.EQ_PRESETS.flat, preamp: 0, loudness: false })
  deep(M.eqPayload(true, "bass", custom, -6, true), { preset: "bass", bands: M.EQ_PRESETS.bass, preamp: -6, loudness: true })
  deep(M.eqPayload(true, "custom", custom, -3, false), { preset: "custom", bands: custom, preamp: -3, loudness: false })
  // preamp is always <= 0 (the design's own range), even if asked for more
  assert.equal(M.eqPayload(true, "flat", null, 5, false).preamp, 0)
})

test("settings writes: a stale echo from the shell never undoes a write it has not caught up with", () => {
  // Two quick writes; the shell's echo of the first arrives after both.
  let pending = { eqBands: "[1,0,0,0,0,0,0,0,0,0]", eqPreset: "custom" }
  let r = M.mergePendingSettings({ id: "io.github.sirallap.solfa", eqBands: "[1,0,0,0,0,0,0,0,0,0]", eqPreset: "flat" }, pending)
  assert.equal(r.settings.eqPreset, "custom", "write #2 is kept over the stale echo")
  assert.equal(r.settings.eqBands, "[1,0,0,0,0,0,0,0,0,0]")
  assert.deepEqual(Object.keys(r.pending), ["eqPreset"], "write #1 is confirmed by its echo")
  r = M.mergePendingSettings({ id: "io.github.sirallap.solfa", eqBands: "[1,0,0,0,0,0,0,0,0,0]", eqPreset: "custom" }, r.pending)
  assert.equal(Object.keys(r.pending).length, 0, "all confirmed")
  assert.equal(r.settings.id, "io.github.sirallap.solfa", "other keys of the entry are kept")
})

test("launch key: one string from one settings snapshot, as the bridge parses it", () => {
  assert.equal(M.launchKey({}), "true||false", "defaults")
  assert.equal(M.launchKey({ autostart: false, browser: "/usr/bin/brave", braveAdBlock: true }), "false|/usr/bin/brave|true")
  assert.equal(M.launchKey({ browser: "/opt/my|browser/brave" }), "true|/opt/my|browser/brave|false", "a path with | goes in whole")
  // A hand-edited shell.json can hold the string "false": the shell treats
  // any non-empty string as on, so the key says on as well.
  assert.equal(M.launchKey({ autostart: "false", braveAdBlock: "false" }), "true||true")
  assert.equal(M.launchKey(null), "true||false")
})

test("settings pushed before the shell has handed over the entry are not real", () => {
  assert.equal(M.hasSettings({}), false, "the widget's default, before the shell assigns its entry")
  assert.equal(M.hasSettings(null), false)
  assert.equal(M.hasSettings(undefined), false)
  assert.equal(M.hasSettings({ id: "io.github.sirallap.solfa" }), true, "an entry with only its id is real")
  assert.equal(M.hasSettings({ browser: "/usr/bin/brave" }), true)
})

test("settings reset: defaults over the current entry, other keys kept", () => {
  const next = M.settingsAfterReset({ id: "io.github.sirallap.solfa", eqEnabled: true, recycleHours: 30, somethingElse: 7 })
  assert.equal(next.eqEnabled, false)
  assert.equal(next.recycleHours, 12)
  assert.equal(next.somethingElse, 7)
  assert.equal(next.id, "io.github.sirallap.solfa")
})

test("recycle knobs are clamped to a range the page can live with", () => {
  assert.equal(M.recycleHeapMbFor(undefined), 400)
  assert.equal(M.recycleHeapMbFor("abc"), 400)
  assert.equal(M.recycleHeapMbFor(-5), 200)
  assert.equal(M.recycleHeapMbFor(5000), 700)
  assert.equal(M.recycleHeapMbFor(450), 450)
  assert.equal(M.recycleHoursFor(0.001), 1)
  assert.equal(M.recycleHoursFor(500), 72)
  assert.equal(M.recycleHoursFor(null), 12)
  assert.equal(M.recycleHoursFor(24), 24)
})

test("sleep timer: a fade cut short gives the volume back", () => {
  assert.equal(M.sleepVolumeToRestore(-1), null, "no fade running: nothing to give back")
  assert.equal(M.sleepVolumeToRestore(0), 0)
  assert.equal(M.sleepVolumeToRestore(64), 64)
})

test("sleep timer: after the fade, the volume comes back only once the song is paused", () => {
  assert.equal(M.sleepAfterPause(false, 0), "restore")
  assert.equal(M.sleepAfterPause(true, 0), "retry", "the pause did not land: ask once more")
  assert.equal(M.sleepAfterPause(true, 1), "give-up", "still playing: stay faded down rather than blast a sleeper")
  assert.equal(M.sleepAfterPause(false, 1), "restore")
})

test("sleep timer options cycle and label", () => {
  assert.equal(M.sleepLabel("off"), "Off")
  assert.equal(M.sleepLabel("30"), "30 min")
  assert.equal(M.sleepLabel("end"), "End of song")
  assert.equal(M.nextSleepOption("off", 1), "15")
  assert.equal(M.nextSleepOption("end", 1), "off", "wraps around")
  assert.equal(M.nextSleepOption("off", -1), "end", "wraps the other way")
  assert.equal(M.sleepFadeDelayMs("15"), 15 * 60000 - 10000)
  assert.equal(M.sleepFadeDelayMs("off"), -1)
  assert.equal(M.sleepFadeDelayMs("end"), -1)
})

test("sleep timer 'end of song': fires only for the armed song, in its last 10 s, once", () => {
  assert.equal(M.shouldStartSleepFade("end", "A", "A", 200, 190, false), true, "exactly 10 s left")
  assert.equal(M.shouldStartSleepFade("end", "A", "A", 200, 189, false), false, "11 s left: not yet")
  assert.equal(M.shouldStartSleepFade("end", "A", "A", 200, 200, false), true, "at the very end")
  assert.equal(M.shouldStartSleepFade("end", "A", "B", 200, 199, false), false, "a different song is playing: never fires for it")
  assert.equal(M.shouldStartSleepFade("end", "A", "A", 200, 195, true), false, "already fading: one-shot")
  assert.equal(M.shouldStartSleepFade("15", "A", "A", 200, 195, false), false, "not the end-of-song mode")
  assert.equal(M.shouldStartSleepFade("end", "", "A", 200, 195, false), false, "not armed")
  assert.equal(M.shouldStartSleepFade("end", "A", "A", 0, 0, false), false, "no duration yet: never fires early")
})

test("sleep timer fade: even steps down to zero, never negative", () => {
  const steps = M.fadeVolumeSteps(100, 10)
  assert.equal(steps.length, 10)
  assert.equal(steps[9], 0)
  assert.ok(steps.every((v) => v >= 0 && v <= 100))
  deep(M.fadeVolumeSteps(0, 5), [0, 0, 0, 0, 0])
})

test("start volume: \"last\" changes nothing, a percent is clamped", () => {
  assert.equal(M.startVolumeFor("last"), null)
  assert.equal(M.startVolumeFor(undefined), null)
  assert.equal(M.startVolumeFor(""), null)
  assert.equal(M.startVolumeFor("80"), 80)
  assert.equal(M.startVolumeFor(150), 100)
  assert.equal(M.startVolumeFor(-5), 0)
  assert.equal(M.startVolumeFor("not a number"), null)
})

test("stepNumber clamps; cycleList wraps both ways", () => {
  assert.equal(M.stepNumber(10, 5, 0, 100), 15)
  assert.equal(M.stepNumber(98, 5, 0, 100), 100)
  assert.equal(M.stepNumber(2, -5, 0, 100), 0)
  const list = ["a", "b", "c"]
  assert.equal(M.cycleList(list, "a", 1), "b")
  assert.equal(M.cycleList(list, "c", 1), "a")
  assert.equal(M.cycleList(list, "a", -1), "c")
  assert.equal(M.cycleList(list, "?", 1), "b", "unknown current starts from the top")
})

// H1: the shell must keep retrying the bridge, with backoff, never a tight loop.
test("bridge retry backoff doubles and caps; never a zero-delay retry", () => {
  let d = 1000
  const seen = []
  for (let i = 0; i < 8; i++) { d = M.nextRetryDelay(d); seen.push(d) }
  assert.deepEqual(seen, [2000, 4000, 8000, 16000, 30000, 30000, 30000, 30000], "doubles, then caps at 30s")
  assert.equal(M.retryTimerInterval(1000), 3000, "never less than 3s even right after a reset")
  assert.equal(M.retryTimerInterval(30000), 30000)
})

// H2: a mismatch is fixed at most once per (launch key, version) — never a loop.
test("stale-key/version restart fires once per tag, then holds off on the same tag", () => {
  const tag1 = M.restartTag("true|/usr/bin/brave", "0.2.0")
  assert.equal(M.shouldRestartForStale(true, false, "", tag1), true, "first mismatch: restart")
  assert.equal(M.shouldRestartForStale(true, false, tag1, tag1), false, "same tag again: no loop")
  assert.equal(M.shouldRestartForStale(false, true, tag1, tag1), false, "still the same tag: no loop")
  const tag2 = M.restartTag("true|/usr/bin/brave", "0.2.1")
  assert.equal(M.shouldRestartForStale(false, true, tag1, tag2), true, "a genuinely new version: restart once")
  assert.equal(M.shouldRestartForStale(false, false, tag1, tag2), false, "nothing stale: never restart")
})

test("history rows: one header per dated shelf, its songs under it, newest shelf first", () => {
  const song = (id) => ({ kind: "song", videoId: id, title: id })
  const rows = M.sectionRows([
    { title: "Today", items: [song("a"), song("b")] },
    { title: "Yesterday", items: [song("c")] },
    { title: "Empty", items: [] }
  ])
  deep(rows.map((r) => r.header || r.item.videoId), ["Today", "a", "b", "Yesterday", "c"])
  deep(M.sectionRows(undefined), [])
})

test("Settings names the engine browser with a capital", () => {
  assert.equal(M.browserLabel(""), "Auto")
  assert.equal(M.browserLabel(undefined), "Auto")
  assert.equal(M.browserLabel("/usr/bin/chromium"), "Chromium")
  assert.equal(M.browserLabel("/usr/bin/brave"), "Brave")
  assert.equal(M.browserLabel("/usr/bin/brave-browser"), "Brave")
  assert.equal(M.browserLabel("/usr/bin/google-chrome-stable"), "Google Chrome")
  assert.equal(M.browserLabel("/opt/acme/browser"), "Browser")
})

test("only a Brave engine shows the ad-blocker row", () => {
  assert.equal(M.isBraveBrowser("/usr/bin/brave"), true)
  assert.equal(M.isBraveBrowser("/usr/bin/brave-browser"), true)
  assert.equal(M.isBraveBrowser("/usr/bin/chromium"), false)
  assert.equal(M.isBraveBrowser(""), false)
  assert.equal(M.isBraveBrowser(undefined), false)
})

test("the engine's browser choices are Auto and what is installed", () => {
  // Settings once cycled through Chrome, Brave and Vivaldi on a machine with
  // only Chromium: each step restarted the engine on a missing file and left
  // Solfa off.
  deep(M.browserChoices(["/usr/bin/chromium"], ""), ["", "/usr/bin/chromium"])
  deep(M.browserChoices(["/usr/bin/chromium", "/usr/bin/brave"], "/usr/bin/brave"), ["", "/usr/bin/chromium", "/usr/bin/brave"])
  // A path set by hand (or one uninstalled since) stays reachable, so the
  // cycle can leave it, and is not lost from the list it is shown in.
  deep(M.browserChoices(["/usr/bin/chromium"], "/opt/acme/browser"), ["", "/usr/bin/chromium", "/opt/acme/browser"])
  // Before the bridge has said (or an older bridge that never does): Auto only.
  deep(M.browserChoices(undefined, ""), [""])
  assert.equal(M.cycleList(M.browserChoices(["/usr/bin/chromium"], ""), "", 1), "/usr/bin/chromium")
  assert.equal(M.cycleList(M.browserChoices(["/usr/bin/chromium"], ""), "/usr/bin/chromium", 1), "")
})

test("Settings cycles the engine's browser over what the bridge found installed", () => {
  const view = fs.readFileSync(path.join(__dirname, "..", "views", "SettingsView.qml"), "utf8")
  const line = view.split("\n").find(l => l.includes('saveSetting("browser"'))
  assert.ok(line, "the browser row's change handler")
  assert.match(line, /Model\.browserChoices\(svc\.browsers,/)
  assert.doesNotMatch(line, /\/usr\/bin\//, "no fixed list of paths that may not exist here")
  const service = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  assert.match(service, /root\.browsers = data\.browsers/)
})

test("share link: the plain link, and a reply is trusted only when it is exactly that", () => {
  const url = "https://music.youtube.com/watch?v=AAAAAAAAAAA"
  assert.equal(M.shareUrl("AAAAAAAAAAA"), url)
  assert.equal(M.shareUrl("AAAAAAAAAAA&si=x"), "")
  assert.equal(M.shareUrl(""), "")
  assert.equal(M.shareUrl(undefined), "")
  deep(M.shareLinkFrom({ ok: true, data: { url: url, source: "share-panel" } }, "AAAAAAAAAAA"), { url: url, source: "share-panel" })
  deep(M.shareLinkFrom({ ok: true, data: { url: url, source: "fallback" } }, "AAAAAAAAAAA"), { url: url, source: "fallback" })
  deep(M.shareLinkFrom({ ok: true, data: { url: url + "&si=abc", source: "share-panel" } }, "AAAAAAAAAAA"), { url: url, source: "fallback" }, "a link with `si` is replaced")
  deep(M.shareLinkFrom({ ok: true, data: { url: "https://music.youtube.com/watch?v=BBBBBBBBBBB", source: "share-panel" } }, "AAAAAAAAAAA"), { url: url, source: "fallback" }, "another song's link too")
  deep(M.shareLinkFrom({ ok: false, error: "timeout" }, "AAAAAAAAAAA"), { url: url, source: "fallback" })
  deep(M.shareLinkFrom({ ok: false, error: "bridge-down" }, "AAAAAAAAAAA"), { url: url, source: "fallback" })
  deep(M.shareLinkFrom(null, "AAAAAAAAAAA"), { url: url, source: "fallback" })
  deep(M.shareLinkFrom({ ok: true, data: {} }, "AAAAAAAAAAA"), { url: url, source: "fallback" })
  assert.ok(M.ALL_KEY_HINTS.some((h) => h[0] === "c" && /link/.test(h[1])))
})

test("removing a song from a playlist: only a user's own, never Liked songs, one row at a time", () => {
  const row = { item: { videoId: "AAAAAAAAAAA", setVideoId: "S1" } }
  const mine = { kind: "playlist", editable: true, playlistId: "PLmine", title: "Road trip", tracks: [row.item, { videoId: "BBBBBBBBBBB", setVideoId: "S2" }, { videoId: "AAAAAAAAAAA", setVideoId: "S3" }] }
  assert.equal(M.removable(mine, row), true)
  assert.equal(M.removable(Object.assign({}, mine, { playlistId: "VLPLmine" }), row), true)
  assert.equal(M.removable(Object.assign({}, mine, { editable: false }), row), false)
  assert.equal(M.removable(Object.assign({}, mine, { editable: undefined }), row), false)
  assert.equal(M.removable(Object.assign({}, mine, { kind: "album" }), row), false, "an album's tracks have a setVideoId too")
  assert.equal(M.removable(Object.assign({}, mine, { playlistId: "LM" }), row), false)
  assert.equal(M.removable(Object.assign({}, mine, { playlistId: "VLLM" }), row), false)
  assert.equal(M.removable(Object.assign({}, mine, { playlistId: "" }), row), false)
  assert.equal(M.removable(mine, { item: { videoId: "AAAAAAAAAAA" } }), false)
  assert.equal(M.removable(mine, { item: { setVideoId: "S1" } }), false)
  assert.equal(M.removable(mine, { header: "Songs" }), false)
  assert.equal(M.removable(mine, null), false)
  assert.equal(M.removable(null, row), false)
  // The copy lacks that row only: the same song's other row stays.
  const rest = M.withoutTrack(mine, "S1")
  deep(rest.tracks.map((t) => t.setVideoId), ["S2", "S3"])
  assert.equal(rest.title, "Road trip")
  assert.equal(rest.editable, true)
  assert.equal(mine.tracks.length, 3, "the original is left alone")
  assert.equal(M.withoutTrack(mine, "nope"), mine)
  assert.equal(M.withoutTrack(null, "S1"), null)
  assert.equal(M.cursorAfterRemoval(1, 2), 1)
  assert.equal(M.cursorAfterRemoval(2, 2), 1)
  assert.equal(M.cursorAfterRemoval(0, 0), -1)
  assert.equal(M.removedMessage("Road trip"), "Removed from Road trip")
  assert.equal(M.removedMessage(""), "Removed from the playlist")
  const x = M.ALL_KEY_HINTS.filter((h) => h[0] === "x")
  assert.equal(x.length, 1)
  assert.match(x[0][1], /queue/)
  assert.match(x[0][1], /playlist/)
  assert.ok(M.ALL_KEY_HINTS.some((h) => h[0] === "J / K" && /queue/.test(h[1])))
})

test("Now Playing's remove: only the song playing from a playlist of the user's, by its own row, once", () => {
  const playing = { videoId: "AAAAAAAAAAA", playlistId: "PLmine", setVideoId: "S3", ad: false }
  const mine = { kind: "playlist", editable: true, playlistId: "PLmine", title: "Road trip",
    tracks: [{ videoId: "AAAAAAAAAAA", setVideoId: "S1" }, { videoId: "BBBBBBBBBBB", setVideoId: "S2" }, { videoId: "AAAAAAAAAAA", setVideoId: "S3" }] }
  const but = (o, extra) => Object.assign({}, o, extra)
  // The playlist worth a look: a "PL" list with the entry's row, nothing else.
  assert.equal(M.playingListId(playing), "PLmine")
  assert.equal(M.playingListId(but(playing, { playlistId: "VLPLmine" })), "PLmine")
  assert.equal(M.playingListId(but(playing, { setVideoId: "" })), "", "no row: nothing to remove, nothing asked")
  assert.equal(M.playingListId(but(playing, { playlistId: "" })), "")
  assert.equal(M.playingListId(but(playing, { playlistId: "LM" })), "", "Liked songs")
  assert.equal(M.playingListId(but(playing, { playlistId: "RDAMPLPLmine" })), "", "the radio after a playlist")
  assert.equal(M.playingListId(but(playing, { playlistId: "RDAMVMAAAAAAAAAAA" })), "", "a song's radio")
  assert.equal(M.playingListId(but(playing, { playlistId: "OLAK5uy_album" })), "", "an album")
  assert.equal(M.playingListId(but(playing, { ad: true })), "", "an advert")
  assert.equal(M.playingListId(but(playing, { videoId: "" })), "")
  assert.equal(M.playingListId(null), "")

  deep(M.playingRemoval(playing, mine, {}), { playlistId: "PLmine", videoId: "AAAAAAAAAAA", setVideoId: "S3", title: "Road trip" })
  deep(M.playingRemoval(playing, but(mine, { playlistId: "VLPLmine" }), null), { playlistId: "PLmine", videoId: "AAAAAAAAAAA", setVideoId: "S3", title: "Road trip" })
  // A row the page has not loaded (a long playlist): the queue's word is enough.
  deep(M.playingRemoval(but(playing, { setVideoId: "S999" }), mine, {}).setVideoId, "S999")
  // Every one of these must keep the button away.
  assert.equal(M.playingRemoval(but(playing, { setVideoId: "" }), mine, {}), null, "no setVideoId")
  assert.equal(M.playingRemoval(playing, but(mine, { editable: false }), {}), null, "someone else's playlist")
  assert.equal(M.playingRemoval(playing, but(mine, { editable: undefined }), {}), null, "not known to be editable")
  assert.equal(M.playingRemoval(playing, null, {}), null, "not looked up yet")
  assert.equal(M.playingRemoval(but(playing, { playlistId: "LM" }), but(mine, { playlistId: "LM" }), {}), null, "Liked songs")
  assert.equal(M.playingRemoval(but(playing, { playlistId: "RDAMPLPLmine" }), mine, {}), null, "the radio after the playlist")
  assert.equal(M.playingRemoval(but(playing, { playlistId: "OLAK5uy_album" }), but(mine, { playlistId: "OLAK5uy_album" }), {}), null, "an album")
  assert.equal(M.playingRemoval(but(playing, { playlistId: "OLAK5uy_album" }), but(mine, { kind: "album", playlistId: "OLAK5uy_album" }), {}), null, "an album page")
  assert.equal(M.playingRemoval(playing, but(mine, { kind: "album" }), {}), null, "a page that is not a playlist")
  assert.equal(M.playingRemoval(playing, but(mine, { playlistId: "PLother" }), {}), null, "the page of another playlist")
  assert.equal(M.playingRemoval(but(playing, { playlistId: "PLother" }), mine, {}), null, "a song playing from another list")
  assert.equal(M.playingRemoval(but(playing, { ad: true }), mine, {}), null, "an advert")
  assert.equal(M.playingRemoval(but(playing, { setVideoId: "S2" }), mine, {}), null, "the page gives that row to another song")
  assert.equal(M.playingRemoval(playing, mine, { "PLmine/S3": true }), null, "taken out already")
  assert.notEqual(M.playingRemoval(playing, mine, { "PLmine/S1": true, "PLother/S3": true }), null, "another row, or the same setVideoId in another list")
  // A song and its music video share one queue entry: the twin playing is
  // still the entry's row, and the removal names the row's own video.
  const twin = but(playing, { videoId: "TTTTTTTTTTT", entryVideoIds: ["AAAAAAAAAAA", "TTTTTTTTTTT"] })
  deep(M.playingRemoval(twin, mine, {}), { playlistId: "PLmine", videoId: "AAAAAAAAAAA", setVideoId: "S3", title: "Road trip" })
  const notLoaded = but(twin, { setVideoId: "S999" })
  assert.equal(M.playingRemoval(notLoaded, mine, {}).videoId, "AAAAAAAAAAA", "a row the page has not loaded: the entry's own video")
  assert.equal(M.playingRemoval(but(twin, { entryVideoIds: ["UUUUUUUUUUU", "TTTTTTTTTTT"] }), mine, {}), null, "an entry whose videos are not the row's")
  assert.equal(M.rowKey("VLPLmine", "S3"), "PLmine/S3")
  assert.equal(M.bareListId("VLPLmine"), "PLmine")
  assert.equal(M.bareListId(undefined), "")
})
