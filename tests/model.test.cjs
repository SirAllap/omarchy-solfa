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
    { modmask: 64, key: "m", description: "Someone else's" },
    { modmask: 72, key: "N", description: "Solfa: next song" }
  ])
  const free = M.freeKeys(binds).map((k) => k.keys)
  assert.ok(!free.includes("SUPER + M"))
  assert.ok(free.includes("SUPER + ALT + N"))
  assert.equal(M.freeKeys("not json").length, 0)
})

test("bind Lua unbinds first and calls the service over the shell's IPC", () => {
  const lua = M.bindLua(M.GLOBAL_KEYS.slice(0, 2))
  assert.match(lua, /pcall\(hl\.unbind, \[\[SUPER \+ M\]\]\); hl\.bind\(\[\[SUPER \+ M\]\], hl\.dsp\.exec_cmd\(\[\[\/usr\/share\/omarchy\/bin\/omarchy-shell shell toggle io\.github\.sirallap\.solfa '\{\}'\]\]\)/)
  assert.match(lua, /exec_cmd\(\[\[\/usr\/share\/omarchy\/bin\/omarchy-shell io\.github\.sirallap\.solfa playPause\]\]\)/)
  // every IPC method a key calls exists on the service's handler
  const svc = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  for (const k of M.GLOBAL_KEYS) if (k.command !== "toggle") assert.match(svc, new RegExp("function " + k.command + "\\(\\): void"))
  assert.equal(M.unbindLua(JSON.stringify([{ description: "Solfa: like" }])), "pcall(hl.unbind, [[SUPER + ALT + L]]); ")
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
