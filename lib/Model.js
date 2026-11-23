.pragma library

// Model.js — the logic behind Solfa's QML, kept free of Qt objects so node
// can test it (tests/model.test.cjs).

var PLUGIN_ID = "io.github.sirallap.solfa"

// The version this code is, kept equal to manifest.json's by a test. The
// shell's plugin reload reuses the QML it compiled before (it never clears
// its component cache), so a Service still running older code after an
// update sees a newer manifest on disk than this: it then asks for a shell
// restart instead of leaving the panel on "Starting Solfa".
var CODE_VERSION = "1.1.0"

function engineLineWhileDown(manifestVersion) {
  return manifestVersion !== "" && manifestVersion !== CODE_VERSION
    ? "Solfa was updated. Restart the shell to finish" : "Starting Solfa"
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// ---------------------------------------------------------------- bridge lifecycle (Service.qml)

// H1: the shell must keep trying to bring the bridge back — after it never
// answers, and after it answers, then drops — but never in a tight loop.
// Same backoff either way: double the delay (capped), and give the unit at
// least this long to show up on the socket before trying again.
function nextRetryDelay(current) { return Math.min(30000, (Number(current) || 1000) * 2) }
function retryTimerInterval(delay) { return Math.max(3000, Number(delay) || 0) }

// H2: a launch key + manifest version this session has already asked the
// bridge to restart for is never asked again — a bridge that keeps
// reporting a mismatch (a forgotten version bump, for instance) gets one
// restart, not a loop.
function restartTag(envKey, version) { return String(envKey) + "@" + String(version) }
function shouldRestartForStale(staleKey, staleVersion, lastTag, tag) {
  return (staleKey || staleVersion) && lastTag !== tag
}

// Where the song is now: the last pushed position plus the time since,
// while it plays. The page pushes on changes only; this fills the gaps.
function positionAt(player, nowMs) {
  if (!player || !player.videoId) return 0
  var pos = Number(player.position) || 0
  if (player.playing && !player.buffering && !player.ad && player.at) pos += Math.max(0, (nowMs - player.at) / 1000)
  var d = Number(player.duration) || 0
  return d > 0 ? clamp(pos, 0, d) : Math.max(0, pos)
}

function fmtTime(sec) {
  sec = Math.max(0, Math.floor(Number(sec) || 0))
  var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
  return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s
}

function artistsText(list) {
  var out = []
  for (var i = 0; i < (list || []).length; i++) if (list[i] && list[i].name) out.push(list[i].name)
  return out.join(", ")
}

// The second line of a row.
function rowSubtitle(item) {
  if (!item) return ""
  if (item.videoId) return artistsText(item.artists) || (item.album ? item.album.name : "")
  return item.subtitle || artistsText(item.artists)
}

// A row's second line with its type in front ("Video · Artist").
function labelled(label, subtitle) {
  return label ? (subtitle ? label + " · " + subtitle : label) : subtitle
}

function nextRepeat(mode) {
  return mode === "NONE" ? "ALL" : mode === "ALL" ? "ONE" : "NONE"
}

function repeatLabel(mode) {
  return mode === "ALL" ? "Repeat all" : mode === "ONE" ? "Repeat one" : "Repeat off"
}

function nextLike(status) { return status === "LIKE" ? "INDIFFERENT" : "LIKE" }

function volumeAfter(current, steps) { return clamp(Math.round((Number(current) || 0) + steps * 5), 0, 100) }

// ------------------------------------------------------------------ lists

var GROUPS = [
  { key: "top", label: "Top result", most: 1 },
  { key: "songs", label: "Songs", most: 6 },
  { key: "albums", label: "Albums", most: 4 },
  { key: "artists", label: "Artists", most: 3 },
  { key: "playlists", label: "Playlists", most: 4 },
  { key: "videos", label: "Videos", most: 3 }
]

// What a result's type is called in the unfiltered list (albums, playlists
// and artists carry theirs in the subtitle already).
var KIND_LABELS = { song: "Song", video: "Video", episode: "Episode" }

// A search result as one list: section headers and rows. With a filter,
// only that group, and all of it. Without one, YouTube Music's own order:
// the top result, then everything else as the reply ranked it, songs and
// videos side by side and nothing left out.
function searchRows(result, filter) {
  var rows = []
  if (!result) return rows
  if (!filter && Array.isArray(result.all)) {
    if (result.top) {
      rows.push({ header: "Top result" })
      rows.push({ item: result.top, label: KIND_LABELS[result.top.kind] || "" })
    }
    if (result.all.length) rows.push({ header: result.top ? "More results" : "Results" })
    for (var n = 0; n < result.all.length; n++) rows.push({ item: result.all[n], label: KIND_LABELS[result.all[n].kind] || "" })
    return rows
  }
  for (var g = 0; g < GROUPS.length; g++) {
    var group = GROUPS[g]
    if (filter && group.key !== filter) continue
    var items = group.key === "top" ? (result.top ? [result.top] : []) : (result[group.key] || [])
    if (!filter) items = items.slice(0, group.most)
    if (items.length === 0) continue
    if (!filter) rows.push({ header: group.label, more: group.key !== "top" && (result[group.key] || []).length > group.most ? group.key : "" })
    for (var i = 0; i < items.length; i++) rows.push({ item: items[i] })
  }
  return rows
}

// ------------------------------------------------------------------ save to a playlist

// The picker's rows: "New playlist" first, then the playlists whose title
// holds what was typed (case does not matter), under "Recent" and "All
// playlists" as YouTube Music lists them (a header only over a group that
// has rows).
function saveRows(playlists, query) {
  var rows = [{ create: true }]
  var q = String(query || "").trim().toLowerCase()
  var list = (playlists || []).filter(function (p) { return q === "" || String(p.title || "").toLowerCase().indexOf(q) !== -1 })
  var groups = [{ label: "Recent", recent: true }, { label: "All playlists", recent: false }]
  for (var g = 0; g < groups.length; g++) {
    var items = list.filter(function (p) { return !!p.recent === groups[g].recent })
    if (items.length === 0) continue
    rows.push({ header: groups[g].label })
    for (var i = 0; i < items.length; i++) rows.push({ playlist: items[i] })
  }
  return rows
}

// The row a fresh picker rests on: the first playlist, else "New playlist".
function firstPlaylistRow(rows) {
  for (var i = 0; i < (rows || []).length; i++) if (rows[i].playlist) return i
  return 0
}

// The footer's word after a save: where the song went.
function savedMessage(title, duplicate) {
  return duplicate ? "Already in " + title + " · ↵ again to add anyway" : "Saved to " + title
}

// x on an open page: a song can leave a playlist of the user's (`editable`
// comes from the page header), never Liked songs, and only by its own row
// (`setVideoId`: albums have one too, so it is not enough on its own).
function removable(info, row) {
  if (!info || info.kind !== "playlist" || info.editable !== true) return false
  var id = String(info.playlistId || "").replace(/^VL/, "")
  if (!id || id === "LM") return false
  var it = row && row.item
  return !!(it && it.videoId && it.setVideoId)
}

// The page's info without the row that was taken out. The same object when
// nothing matches.
function withoutTrack(info, setVideoId) {
  if (!info || !info.tracks || !setVideoId) return info
  var rest = info.tracks.filter(function (t) { return t.setVideoId !== setVideoId })
  if (rest.length === info.tracks.length) return info
  var out = Object.assign({}, info)
  out.tracks = rest
  return out
}

// Where the cursor rests after a row left the list: the same place, or the
// last row.
function cursorAfterRemoval(index, length) {
  return length > 0 ? clamp(index, 0, length - 1) : -1
}

function removedMessage(title) { return "Removed from " + (title || "the playlist") }

// What the undo of a removal needs, read from the page before the row goes:
// where it was (`index` in the page's tracks), the row itself, and the
// setVideoIds of up to three rows after it (`before`, nearest first: the
// restore moves the song back before the first of them still there).
// `last`: nothing follows it and the page has no more to load;
// `continuation`: the page's next page, which starts with the rows after
// the last one loaded. null when the page does not hold that row.
function removalRecord(info, setVideoId) {
  var tracks = info && info.tracks ? info.tracks : []
  for (var i = 0; i < tracks.length; i++) {
    if (!setVideoId || tracks[i].setVideoId !== setVideoId) continue
    var after = tracks.slice(i + 1, i + 4).map(function (t) { return t.setVideoId || "" }).filter(Boolean)
    var more = String(info.continuation || "")
    return { index: i, row: tracks[i], before: after, last: after.length === 0 && more === "", continuation: after.length ? "" : more }
  }
  return null
}

// The page's info with a row put back by an undo (`track`, carrying its new
// setVideoId): just before the first of `before` the page holds. When it
// was the last row (no `before`), or it came back at the end (`placed`
// false), at the end of a page that has everything; a page with more to
// load leaves it to the page that holds the end. The same object when
// nothing changes, or the row is there already.
function withTrackRestored(info, track, before, placed) {
  if (!info || !info.tracks || !track || !track.setVideoId) return info
  var tracks = info.tracks
  for (var i = 0; i < tracks.length; i++) if (tracks[i].setVideoId === track.setVideoId) return info
  var at = -1
  if (placed) {
    for (var b = 0; b < (before || []).length && at < 0; b++) {
      for (var j = 0; j < tracks.length; j++) if (tracks[j].setVideoId === before[b]) { at = j; break }
    }
  }
  if (at < 0 && (!placed || !(before || []).length) && !info.continuation) at = tracks.length
  if (at < 0) return info
  var out = Object.assign({}, info)
  out.tracks = tracks.slice(0, at).concat([track], tracks.slice(at))
  return out
}

function restoredMessage(title, placed) {
  return (placed ? "Restored to " : "Restored to the end of ") + (title || "the playlist")
}

// A playlist's id as the queue and edit_playlist use it: no "VL".
function bareListId(id) { return String(id || "").replace(/^VL/, "") }

// What a row taken out of a playlist is remembered by. setVideoIds repeat
// from one playlist to the next: one means something only with its list.
function rowKey(playlistId, setVideoId) { return bareListId(playlistId) + "/" + String(setVideoId || "") }

// The playlist the song playing comes from, worth asking about only when
// it could be one of the user's and the queue says which row of it plays:
// a "PL" list (not Liked songs, a radio or mix "RD...", an album
// "OLAK...") and the entry's setVideoId. "" otherwise, and during an advert.
function playingListId(player) {
  if (!player || !player.videoId || player.ad || !player.setVideoId) return ""
  var id = bareListId(player.playlistId)
  return /^PL[A-Za-z0-9_-]+$/.test(id) ? id : ""
}

// Now Playing's "Remove from queue", when the song playing is not a row of
// a playlist of the user's: the queue index of the entry playing, when it
// has one and something comes after it (the player moves on to that
// first). -1 otherwise, and during an advert.
function playingQueueIndex(player) {
  if (!player || !player.videoId || player.ad || !player.canNext) return -1
  return typeof player.index === "number" && player.index >= 0 ? player.index : -1
}

// Now Playing's remove button: the song playing as a row of its playlist,
// { playlistId, videoId, setVideoId, title }, or null. All of it or
// nothing: `info` (that playlist's page) says the playlist is the user's
// (removable), it is the very list the queue entry names, the entry has
// its setVideoId, the page does not give that setVideoId to another song,
// and the row was not taken out already (`removed`, by rowKey).
// A song and its music video share one queue entry (`entryVideoIds`: the
// entry's video, then its twin), and either may play: the row is the
// entry's whichever of the two it holds, and `videoId` is the row's.
// A row put back by an undo is a new row: `renames` (rowKey of the old
// setVideoId -> the new one) leads the queue entry, which still names the
// old row, to it.
function playingRemoval(player, info, removed, renames) {
  var id = playingListId(player)
  if (!id || !info || bareListId(info.playlistId) !== id) return null
  var set = (renames && renames[rowKey(id, player.setVideoId)]) || player.setVideoId
  if (!removable(info, { item: { videoId: player.videoId, setVideoId: set } })) return null
  var ids = (player.entryVideoIds || []).concat([player.videoId])
  var rowVideo = ""
  var tracks = info.tracks || []
  for (var i = 0; i < tracks.length; i++) {
    if (tracks[i].setVideoId !== set) continue
    if (ids.indexOf(tracks[i].videoId) < 0) return null
    rowVideo = tracks[i].videoId
  }
  if (removed && removed[rowKey(id, set)]) return null
  return { playlistId: id, videoId: rowVideo || ids[0], setVideoId: set, title: info.title || "" }
}

// ---------------------------------------------------- find in a playlist

// Text as the filter compares it: lower case, accents taken off.
function foldText(s) {
  return String(s === undefined || s === null ? "" : s).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
}

// The tracks that match what was typed: every word has to be in the title,
// the artists or the album, in any order (accents and case do not matter).
// Nothing typed: the same list. Order is kept.
function filterTracks(tracks, query) {
  var words = foldText(query).split(/\s+/).filter(Boolean)
  if (words.length === 0) return tracks || []
  return (tracks || []).filter(function (t) {
    var hay = foldText([t.title, artistsText(t.artists), t.album ? t.album.name : ""].join(" "))
    for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) === -1) return false
    return true
  })
}

// The line beside the find field: how many songs match, and whether the
// rest of the playlist is still on its way or did not come.
function findStatus(query, shown, total, loading, failed) {
  var all = total + (total === 1 ? " song" : " songs")
  if (String(query || "").trim() === "") return loading ? "Loading " + all : failed ? all + " · not all loaded" : all
  var n = shown + " of " + total
  return loading ? n + " · loading" : failed ? n + " · not all loaded" : n
}

// Where a row sits in another list of rows (the same song, not the same
// position), or -1: a cursor that survives the filter being closed.
function rowIndex(rows, row) {
  var it = row && row.item
  if (!it) return -1
  for (var i = 0; i < (rows || []).length; i++) {
    var c = rows[i].item
    if (c && c.videoId === it.videoId && c.setVideoId === it.setVideoId) return i
  }
  return -1
}

// Shelves of a page (artist, home, library) as one list.
function sectionRows(sections, mostPerSection) {
  var rows = []
  for (var s = 0; s < (sections || []).length; s++) {
    var sec = sections[s]
    if (!sec || !sec.items || sec.items.length === 0) continue
    if (sec.title) rows.push({ header: sec.title, more: sec.more ? sec.more.browseId : "", moreParams: sec.more ? sec.more.params : "" })
    var items = mostPerSection ? sec.items.slice(0, mostPerSection) : sec.items
    for (var i = 0; i < items.length; i++) rows.push({ item: items[i] })
  }
  return rows
}

function trackRows(tracks) {
  var rows = []
  for (var i = 0; i < (tracks || []).length; i++) rows.push({ item: tracks[i] })
  return rows
}

// The queue: what is queued, then what autoplay would pick.
function queueRows(queue) {
  var rows = []
  if (!queue) return rows
  var items = queue.items || []
  for (var i = 0; i < items.length; i++) rows.push({ item: items[i], queueIndex: i, current: i === queue.index })
  var auto = queue.automix || []
  if (auto.length) {
    rows.push({ header: "Autoplay" })
    for (var j = 0; j < auto.length; j++) rows.push({ item: auto[j], queueIndex: j, automix: true })
  }
  return rows
}

// Next row the cursor can stop on (headers are skipped).
function moveCursor(rows, index, delta) {
  if (!rows || rows.length === 0) return -1
  var i = index
  if (i < 0) i = delta > 0 ? -1 : rows.length
  for (var n = 0; n < rows.length; n++) {
    i += delta > 0 ? 1 : -1
    if (i < 0 || i >= rows.length) return index >= 0 && index < rows.length && !rows[index].header ? index : firstRow(rows)
    if (!rows[i].header) return i
  }
  return index
}

function firstRow(rows) {
  for (var i = 0; i < (rows || []).length; i++) if (!rows[i].header) return i
  return -1
}

// The line being sung (lines sorted by start, ms). -1 before the first.
function lyricIndex(lines, ms) {
  var lo = 0, hi = (lines || []).length - 1, ans = -1
  while (lo <= hi) {
    var mid = (lo + hi) >> 1
    if (lines[mid].t <= ms) { ans = mid; lo = mid + 1 } else hi = mid - 1
  }
  return ans
}

// ------------------------------------------------------------------ bridge

// Pending requests whose time is up.
function expired(pending, nowMs) {
  var out = []
  for (var id in pending) if (pending[id] && pending[id].deadline <= nowMs) out.push(Number(id))
  return out
}

// Words for the engine's state, for the one line that explains it.
function engineLine(engine, account) {
  var st = engine ? engine.status : ""
  if (st === "ready") {
    if (account && account.host && account.host !== "music.youtube.com") return "Waiting for sign-in"
    return ""
  }
  if (st === "starting") return "Starting YouTube Music"
  if (st === "attaching") return "Connecting"
  if (st === "stuck") return "YouTube Music stopped answering. Restarting it"
  if (st === "crashed") return "YouTube Music closed. Starting it again"
  if (st === "signing-in") return "Signing in, in the Google window"
  if (st === "stopped") return engine && engine.error ? engine.error : "Solfa is off"
  return "Starting"
}

function errorText(code) {
  switch (code) {
    case "signin-required": return "Sign in to do that"
    case "bad-args": return "That request was not valid"
    case "timeout": return "YouTube Music took too long to answer"
    case "bridge-down": return "Solfa's helper is restarting"
    case "not-on-app": return "Finish signing in first"
    case "engine-signing-in": return "Finish signing in first"
    case "playing": return "That song is playing; skip it first"
    case "moved": return "The queue changed; nothing was removed"
    case "last": return "Nothing comes after it in the queue"
    case "not-found": return "Nothing found"
    case "failed": return "YouTube Music did not save it"
    case "sleep-pause-failed": return "The sleep timer could not pause; the volume was left down"
    case "engine-busy": return "YouTube Music did not close; try again"
    case "signin-failed": return "Signing in did not finish; YouTube Music is still signed out"
    case "erase-refused": return "That folder is not Solfa's engine profile; nothing was deleted"
    case "erase-failed": return "Some engine data could not be deleted"
    default:
      if (/^engine-/.test(code || "")) return "YouTube Music is not ready yet"
      if (/^http-/.test(code || "")) return "YouTube Music refused the request (" + code.slice(5) + ")"
      return "Something went wrong (" + (code || "unknown") + ")"
  }
}

// ------------------------------------------------------------------ keys

// Each key calls the service over the shell's IPC (no process of ours to
// start per press), so a failure is reported like any other user action.
var GLOBAL_KEYS = [
  { keys: "SUPER + ALT + M", mods: 72, key: "M", command: "toggle", description: "Solfa: open or close" },
  { keys: "SUPER + ALT + P", mods: 72, key: "P", command: "playPause", description: "Solfa: play or pause" },
  { keys: "SUPER + ALT + N", mods: 72, key: "N", command: "next", description: "Solfa: next song" },
  { keys: "SUPER + ALT + B", mods: 72, key: "B", command: "previous", description: "Solfa: previous song" },
  { keys: "SUPER + ALT + L", mods: 72, key: "L", command: "like", description: "Solfa: like" }
]

// The panel key: Super+Alt+M when it is free, else the first free of these.
// A key another app holds is never taken (Super+M stays Omarchy's minimize).
var PANEL_KEY_CHOICES = [
  { keys: "SUPER + ALT + M", mods: 72, key: "M" },
  { keys: "SUPER + SHIFT + M", mods: 65, key: "M" },
  { keys: "SUPER + CTRL + M", mods: 68, key: "M" }
]
// Play/pause falls back the same way.
var PLAYPAUSE_KEY_CHOICES = [
  { keys: "SUPER + ALT + P", mods: 72, key: "P" },
  { keys: "SUPER + SHIFT + P", mods: 65, key: "P" },
  { keys: "SUPER + CTRL + P", mods: 68, key: "P" }
]

function takenKeys(binds) {
  var taken = {}
  for (var i = 0; i < binds.length; i++) {
    var b = binds[i]
    if (!b || String(b.description || "").indexOf("Solfa:") === 0) continue
    taken[(b.modmask | 0) + ":" + String(b.key || "").toUpperCase()] = true
  }
  return taken
}

// The panel key to register: the one picked in Settings (setting `panelKey`,
// "" = automatic) if it is free, else the first free choice, else null.
function panelKeyFor(bindsJson, picked) {
  var binds = []
  try { binds = JSON.parse(bindsJson || "[]") } catch (e) { return null }
  var taken = takenKeys(binds)
  var free = PANEL_KEY_CHOICES.filter(function (k) { return !taken[k.mods + ":" + k.key] })
  for (var i = 0; i < free.length; i++) if (free[i].keys === picked) return free[i]
  return free.length ? free[0] : null
}

// The play/pause key to register: Super+Alt+P, else the first free fallback.
function playPauseKeyFor(bindsJson) {
  var binds = []
  try { binds = JSON.parse(bindsJson || "[]") } catch (e) { return null }
  var taken = takenKeys(binds)
  return PLAYPAUSE_KEY_CHOICES.filter(function (k) { return !taken[k.mods + ":" + k.key] })[0] || null
}

// A key as the hint tables type it: "SUPER + SHIFT + M" -> "Super + Shift + M"
// (KeyHint draws each word as its own cap, "+" as plain text between them).
function keyChord(keys) { return keyLabel(keys).split("+").join(" + ") }

// "SUPER + SHIFT + M" -> "Super+Shift+M"
function keyLabel(keys) {
  return String(keys || "").split(" + ").map(function (p) { return p.length > 1 ? p.charAt(0) + p.slice(1).toLowerCase() : p }).join("+")
}

// The choices Settings cycles: automatic, then each key that is free (or ours).
function panelKeyOptions(bindsJson) {
  var binds = []
  try { binds = JSON.parse(bindsJson || "[]") } catch (e) { binds = [] }
  var taken = takenKeys(binds)
  return [""].concat(PANEL_KEY_CHOICES.filter(function (k) { return !taken[k.mods + ":" + k.key] }).map(function (k) { return k.keys }))
}

// Our keys that nobody else holds, from `hyprctl -j binds`.
function freeKeys(bindsJson, picked) {
  var binds = []
  try { binds = JSON.parse(bindsJson || "[]") } catch (e) { return [] }
  var taken = takenKeys(binds)
  var out = GLOBAL_KEYS.filter(function (k) { return k.command !== "toggle" && k.command !== "playPause" && !taken[k.mods + ":" + k.key] })
  var pp = playPauseKeyFor(bindsJson)
  if (pp) out.unshift({ keys: pp.keys, mods: pp.mods, key: pp.key, command: "playPause", description: GLOBAL_KEYS[1].description })
  var panel = panelKeyFor(bindsJson, picked)
  if (panel) out.unshift({ keys: panel.keys, mods: panel.mods, key: panel.key, command: "toggle", description: GLOBAL_KEYS[0].description })
  return out
}

// Lua for `hyprctl eval`: our binds, removed first so a reload or a second
// call never stacks them.
function bindLua(entries, shellBin) {
  var bin = shellBin || "/usr/share/omarchy/bin/omarchy-shell"
  var lua = ""
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    var cmd = e.command === "toggle"
      ? bin + " shell toggle " + PLUGIN_ID + " '{}'"
      : bin + " " + PLUGIN_ID + " " + e.command
    lua += "pcall(hl.unbind, [[" + e.keys + "]]); "
    lua += "hl.bind([[" + e.keys + "]], hl.dsp.exec_cmd([[" + cmd + "]]), { description = [[" + e.description + "]] }); "
  }
  return lua
}

// Only binds that carry one of our descriptions are removed, each by its own
// modifiers and key (the panel key moves), never another app's key.
function unbindLua(bindsJson) {
  var binds = []
  try { binds = JSON.parse(bindsJson || "[]") } catch (e) { return "" }
  var ours = {}
  for (var i = 0; i < GLOBAL_KEYS.length; i++) ours[GLOBAL_KEYS[i].description] = true
  var lua = ""
  for (var j = 0; j < binds.length; j++) {
    var b = binds[j]
    if (!b || !ours[String(b.description || "")]) continue
    var mods = b.modmask | 0
    var parts = []
    if (mods & 64) parts.push("SUPER")
    if (mods & 4) parts.push("CTRL")
    if (mods & 1) parts.push("SHIFT")
    if (mods & 8) parts.push("ALT")
    parts.push(String(b.key || "").toUpperCase())
    lua += "pcall(hl.unbind, [[" + parts.join(" + ") + "]]); "
  }
  return lua
}

// ------------------------------------------------------------------ notifications

function notifyText(player) {
  if (!player || !player.title) return null
  var body = artistsText(player.artists)
  if (player.album && player.album.name) body += (body ? " — " : "") + player.album.name
  return { summary: player.title, body: body }
}

// A value stepped by ←→ inside a fixed range (SettingsView's number rows).
function stepNumber(value, delta, lo, hi) { return clamp((Number(value) || 0) + delta, lo, hi) }

// The next (or previous) item of a fixed list, wrapping (SettingsView's
// preset/option rows: eqPreset, startVolume, browser...).
function cycleList(list, current, dir) {
  if (!list || list.length === 0) return current
  var i = list.indexOf(current)
  if (i < 0) i = 0
  i = (i + (dir > 0 ? 1 : -1) + list.length) % list.length
  return list[i]
}

// Settings > "Browser for the engine": Auto, then the browsers the bridge
// found installed (hello's `browsers`), then the current path when it is
// none of those (set by hand, or uninstalled since) so it stays shown and
// the cycle can leave it.
// Settings shows the Brave ad-blocker row only for a Brave engine: the same
// test the bridge uses (bin/solfa-bridge blocks_ads) on the browser's file name.
function isBraveBrowser(path) {
  return String(path || "").split("/").pop().toLowerCase().indexOf("brave") >= 0
}

// How Settings names an engine browser: "Auto" for none, the well-known
// ones by their product name, anything else by its file name, capitalized.
var BROWSER_NAMES = {
  "chromium": "Chromium", "google-chrome-stable": "Google Chrome", "brave": "Brave",
  "brave-browser": "Brave", "vivaldi-stable": "Vivaldi", "microsoft-edge-stable": "Microsoft Edge"
}
function browserLabel(path) {
  var name = String(path || "").split("/").pop()
  if (name === "") return "Auto"
  return BROWSER_NAMES[name] || name.charAt(0).toUpperCase() + name.slice(1)
}

function browserChoices(installed, current) {
  var list = [""].concat(installed || [])
  if (current && list.indexOf(current) < 0) list.push(current)
  return list
}

// ------------------------------------------------------------------ settings

// Mirrors manifest.json's barWidget.defaults exactly (model.test.cjs checks
// the two stay in step). Settings > Advanced > "Reset settings" writes them
// over the current entry (settingsAfterReset), in one write.
var SETTINGS_DEFAULTS = {
  barControls: true, showTitle: true, maxLabelWidth: 160, showWhenIdle: true, notify: true,
  globalKeys: true, panelKey: "", autostart: true, browser: "", braveAdBlock: false,
  eqEnabled: false, eqPreset: "flat", eqBands: "[0,0,0,0,0,0,0,0,0,0]", eqPreamp: 0, eqLoudness: false,
  startPaused: false, startVolume: "last", recycleHeapMb: 400, recycleHours: 12, reduceMotion: false
}

function settingsAfterReset(current) {
  return Object.assign({}, current || {}, SETTINGS_DEFAULTS)
}

// What the bridge is started under (SOLFA_LAUNCH_KEY): `autostart|browser|
// braveAdBlock`, from one settings snapshot. Truthiness is the one the
// SOLFA_NO_LAUNCH / SOLFA_BRAVE_ADBLOCK vars use (a hand-edited "false"
// string counts as on in both), so the key and the vars never disagree. The
// bridge parses it back from both ends, so a browser path may hold a "|".
function launchKey(settings) {
  var s = settings || {}
  var autostart = s.autostart === undefined || s.autostart === null ? true : s.autostart
  var browser = s.browser === undefined || s.browser === null ? "" : s.browser
  return (autostart ? "true" : "false") + "|" + String(browser) + "|" + (s.braveAdBlock ? "true" : "false")
}

// A bar widget starts with `{}` and gets its shell.json entry a moment
// later (the shell assigns the widget's `bar` before its `settings`). `{}`
// is not a settings entry: adopting it would start the engine under the
// defaults. A real entry always carries at least its id.
function hasSettings(incoming) {
  return !!incoming && typeof incoming === "object" && Object.keys(incoming).length > 0
}

// Settings writes go to shell.json through the shell, and come back to the
// service as the widget's whole entry, later. Writes not yet seen coming
// back (`pending`, key -> value) win over what an echo says, so a stale echo
// of an earlier write cannot undo a later one; an echo that carries a
// pending value confirms it.
function mergePendingSettings(incoming, pending) {
  var settings = Object.assign({}, incoming || {})
  var left = {}
  for (var k in pending) {
    if (JSON.stringify(settings[k]) === JSON.stringify(pending[k])) continue
    settings[k] = pending[k]
    left[k] = pending[k]
  }
  return { settings: settings, pending: left }
}

// Advanced > memory: SOLFA_RECYCLE_HEAP_MB / SOLFA_RECYCLE_HOURS. Too low
// and the page is swapped every hour; too high and V8's ceiling (768 MB)
// comes first.
var RECYCLE_HEAP_MB_RANGE = [200, 700]
var RECYCLE_HOURS_RANGE = [1, 72]
function recycleHeapMbFor(v) {
  var n = Number(v)
  return v === null || v === undefined || v === "" || !isFinite(n) ? 400 : clamp(Math.round(n), RECYCLE_HEAP_MB_RANGE[0], RECYCLE_HEAP_MB_RANGE[1])
}
function recycleHoursFor(v) {
  var n = Number(v)
  return v === null || v === undefined || v === "" || !isFinite(n) ? 12 : clamp(Math.round(n), RECYCLE_HOURS_RANGE[0], RECYCLE_HOURS_RANGE[1])
}

// ------------------------------------------------------------------ equalizer (Sound section; the graph itself is engine/agent.js)

var EQ_BAND_HZ = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
var EQ_PRESETS = {
  flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  bass: [6, 5, 3, 1, 0, 0, 0, 0, 0, 0],
  treble: [0, 0, 0, 0, 0, 1, 2, 3, 4, 5],
  vocal: [-2, -2, -1, 1, 3, 3, 2, 0, -1, -1],
  loudness: [4, 3, 1, 0, -1, -1, 0, 1, 3, 4]
}
var EQ_PRESET_ORDER = ["flat", "bass", "treble", "vocal", "loudness", "custom"]
var EQ_PRESET_LABELS = { flat: "Flat", bass: "Bass", treble: "Treble", vocal: "Vocal", loudness: "Loudness", custom: "Custom" }

// The bands to show for a preset: the preset's own numbers, or (for
// "custom") whatever the user last set.
function eqBandsFor(preset, customBands) {
  var p = EQ_PRESETS[preset]
  if (p) return p.slice()
  return Array.isArray(customBands) && customBands.length === 10 ? customBands.slice() : EQ_PRESETS.flat.slice()
}

// eqBands is stored as a JSON string (the manifest schema has no array
// type); this is always a 10-number array, whatever is in the setting.
function parseEqBands(json) {
  try {
    var v = JSON.parse(json)
    if (Array.isArray(v) && v.length === 10) return v.map(function (n) { return clamp(Number(n) || 0, -12, 12) })
  } catch (e) { /* fall through */ }
  return EQ_PRESETS.flat.slice()
}

function eqBandDb(bands, index) { return clamp(Number((bands || [])[index]) || 0, -12, 12) }

// The eq.set payload actually sent to the page. Off (eqEnabled false) always
// means flat gains, no preamp and no loudness, whatever preset or custom
// bands are stored — they stay untouched in settings, so turning it back on
// returns exactly what was there before.
function eqPayload(enabled, preset, customBands, preamp, loudness) {
  if (!enabled) return { preset: "flat", bands: EQ_PRESETS.flat.slice(), preamp: 0, loudness: false }
  return { preset: preset, bands: eqBandsFor(preset, customBands), preamp: clamp(Number(preamp) || 0, -12, 0), loudness: !!loudness }
}

// ------------------------------------------------------------------ sleep timer (Playback; not persisted)

var SLEEP_OPTIONS = ["off", "15", "30", "60", "end"]
function sleepLabel(mode) {
  switch (mode) {
    case "15": return "15 min"
    case "30": return "30 min"
    case "60": return "60 min"
    case "end": return "End of song"
    default: return "Off"
  }
}
function nextSleepOption(mode, dir) {
  var i = SLEEP_OPTIONS.indexOf(mode)
  if (i < 0) i = 0
  i = (i + (dir > 0 ? 1 : -1) + SLEEP_OPTIONS.length) % SLEEP_OPTIONS.length
  return SLEEP_OPTIONS[i]
}
// Milliseconds until the 10 s fade should start for a plain countdown
// timer, or -1 for "off" and "end" (which have no fixed delay).
function sleepFadeDelayMs(mode) {
  var minutes = { "15": 15, "30": 30, "60": 60 }[mode]
  return minutes ? Math.max(0, minutes * 60000 - 10000) : -1
}
// "End of song": true the instant the fade should start — the armed song is
// still the one playing and is within its last 10 s of its own duration.
// False once a fade is already running (one-shot) or a different song is
// playing (skipped away from, or it already changed): whatever comes after
// the armed song never fires a fade of its own.
function shouldStartSleepFade(mode, armedVideoId, videoId, duration, position, alreadyFading) {
  if (mode !== "end" || !armedVideoId || alreadyFading) return false
  if (videoId !== armedVideoId) return false
  return duration > 0 && (duration - position) <= 10
}

// The fade: `steps` volume levels from the current volume down to 0, evenly
// spaced (Service.qml calls setVolume with each, one per tick).
function fadeVolumeSteps(fromVolume, steps) {
  steps = Math.max(1, Math.floor(steps) || 1)
  var out = []
  for (var i = 1; i <= steps; i++) out.push(Math.max(0, Math.round(fromVolume * (1 - i / steps))))
  return out
}

// The volume a fade had started from, to give back when the fade is cut
// short (the timer turned off or changed mid-fade); null when none runs.
function sleepVolumeToRestore(fadeVolume) {
  return fadeVolume >= 0 ? fadeVolume : null
}
// After the fade's pause, looked at a moment later: "restore" the volume
// once the song really is paused; "retry" the pause once if it is still
// playing; then "give-up" and stay faded down (a sleeper is not woken by
// the song coming back at full volume).
function sleepAfterPause(playing, tries) {
  if (!playing) return "restore"
  return tries < 1 ? "retry" : "give-up"
}

// startVolume: "last" (do nothing) or a 0-100 percent to apply once, after
// the engine's own restore has run. null means "leave it".
function startVolumeFor(setting) {
  if (setting === undefined || setting === null || setting === "last" || setting === "") return null
  var n = Number(setting)
  return isFinite(n) ? clamp(Math.round(n), 0, 100) : null
}

// ------------------------------------------------------------------ share link

// The link Solfa copies for a song: its id on YouTube Music, nothing else.
// "" when `videoId` is not a video id.
function shareUrl(videoId) {
  return typeof videoId === "string" && /^[A-Za-z0-9_-]{11}$/.test(videoId) ? "https://music.youtube.com/watch?v=" + videoId : ""
}

// What to copy from the engine's reply to share.link: its link when it is
// exactly the canonical one for this song (the engine has cleaned it already;
// this is the second check, on the way out), otherwise the same link built
// here. { url, source } with source "share-panel" or "fallback".
function shareLinkFrom(reply, videoId) {
  var url = shareUrl(videoId)
  var d = reply && reply.ok ? reply.data : null
  if (url !== "" && d && d.url === url && d.source === "share-panel") return { url: url, source: "share-panel" }
  return { url: url, source: "fallback" }
}

// ------------------------------------------------------------------ key hints

// Every panel key, for the "?" list.
var ALL_KEY_HINTS = [
  ["space", "play or pause"], ["n / p", "next / previous"], [", / .", "back / forward 10 s"], ["- / =", "volume"],
  ["m", "mute"], ["f / d", "like / dislike"], ["r", "repeat"], ["s", "shuffle"], ["1-5 or ← →", "tabs"], ["/", "search"],
  ["↵", "play or open"], ["e / a", "play next / add to queue"], ["R", "radio"], ["S", "save to a playlist"], ["F", "find in a playlist or album"], ["g / o", "artist / album"],
  ["c", "copy the song's link"], ["x", "remove (queue, your playlists)"], ["u", "undo a removal from a playlist"], ["J / K", "move (queue)"], ["[ ]", "filter / section"], ["w", "show the YouTube window"], ["i", "sign in (signed out)"], ["esc", "back / close"],
  ["?", "show or hide this list"]
]

// The footer line: the view's main key, then play, next and like (when
// there is a song to like). Four at most; "?" sits apart, at the right.
// While a text field has the keys, letters and space type into it: only
// the field's own keys are shown.
function footerHints(viewHints, canLike, inField) {
  if (inField) return Array.isArray(viewHints) ? viewHints.slice(0, 4) : []
  var out = []
  var first = Array.isArray(viewHints) && viewHints.length ? viewHints[0] : null
  var common = [["space", "play/pause"], ["n p", "next/previous"]]
  if (canLike) common.push(["f", "like"])
  if (first && !common.some(function (h) { return h[0] === first[0] })) out.push(first)
  // A later hint marked `true` as its third item is kept too.
  for (var i = 1; Array.isArray(viewHints) && i < viewHints.length; i++) if (viewHints[i][2] === true) out.push(viewHints[i])
  return out.concat(common).slice(0, 4)
}
