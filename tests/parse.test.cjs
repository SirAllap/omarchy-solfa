// Parser tests against invented fixtures shaped like real replies.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const P = require("../engine/parse.js")

const F = (name) => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "innertube", name + ".json"), "utf8"))
const ID = /^[A-Za-z0-9_-]{11}$/

test("flat search: top artist card, grouped items, no type labels as artists", () => {
  const s = P.search(F("search"))
  assert.equal(s.top.kind, "artist")
  assert.match(s.top.browseId, /^UC/)
  assert.ok(s.songs.length >= 3)
  for (const song of s.songs) {
    assert.equal(song.kind, "song")
    assert.match(song.videoId, ID)
    assert.ok(song.artists.length >= 1, "every song has an artist")
    for (const a of song.artists) {
      assert.doesNotMatch(a.name, /^(Song|Canción)$/)
      assert.doesNotMatch(a.name, /^\d/, "a play count is not an artist")
    }
  }
  for (const album of s.albums) {
    assert.equal(album.kind, "album")
    assert.match(album.browseId, /^MPRE/)
    assert.ok(album.artists.length >= 1)
  }
  for (const pl of s.playlists) assert.equal(pl.kind, "playlist")
})

test("songs under the top artist card get that artist", () => {
  const s = P.search(F("search"))
  assert.equal(s.songs[0].artists[0].name, s.top.title)
  assert.equal(s.songs[0].artists[0].id, s.top.browseId)
})

test("a Spanish reply parses to the same items (only display text differs)", () => {
  const strip = (r) => JSON.stringify(r, (k, v) => (k === "subtitle" ? undefined : v))
  assert.equal(strip(P.search(F("search-es"))), strip(P.search(F("search"))))
})

test("filtered searches keep to their kind", () => {
  const songs = P.search(F("search-songs"), { filter: "songs" })
  assert.ok(songs.songs.length >= 5)
  assert.ok(songs.songs.every((x) => x.artists.length >= 1))
  assert.ok(songs.continuation.length > 10)
  assert.ok(P.search(F("search-albums"), { filter: "albums" }).albums.length >= 5)
  const artists = P.search(F("search-artists"), { filter: "artists" }).artists
  assert.ok(artists.length >= 5)
  assert.ok(artists.every((a) => /^UC/.test(a.browseId)))
  assert.ok(P.search(F("search-playlists"), { filter: "playlists" }).playlists.length >= 5)
})

test("filter params decode to the filter they name", () => {
  const field = (p) => Buffer.from(decodeURIComponent(p), "base64")
  assert.equal(field(P.SEARCH_FILTERS.songs)[5], 0x08)
  assert.equal(field(P.SEARCH_FILTERS.videos)[5], 0x10)
  assert.equal(field(P.SEARCH_FILTERS.albums)[5], 0x18)
  assert.equal(field(P.SEARCH_FILTERS.artists)[5], 0x20)
})

test("album page: header, play list id, tracks inherit the album artist", () => {
  const a = P.album(F("album"))
  assert.equal(a.kind, "album")
  assert.ok(a.title)
  assert.match(a.playlistId, /^OLAK5uy_/)
  assert.ok(a.tracks.length >= 1)
  for (const t of a.tracks) {
    assert.match(t.videoId, ID)
    assert.ok(t.duration > 0)
    assert.deepEqual(t.artists, a.artists)
    assert.equal(t.album.name, a.title)
  }
})

test("playlist page: title, author, tracks with their set ids", () => {
  const p = P.playlist(F("playlist"))
  assert.ok(p.title)
  assert.ok(p.author)
  assert.match(p.playlistId, /^PL/)
  assert.ok(p.tracks.length >= 5)
  assert.ok(p.tracks.every((t) => ID.test(t.videoId) && t.setVideoId))
})

test("artist page: shuffle, radio and shelves by kind", () => {
  const a = P.artist(F("artist"))
  assert.ok(a.title)
  assert.match(a.shuffle.playlistId, /^RD/)
  assert.match(a.radio.playlistId, /^RD/)
  const top = a.sections[0]
  assert.ok(top.items.every((x) => x.kind === "song"))
  assert.ok(top.more && /^VL/.test(top.more.browseId))
  assert.ok(a.sections.some((s) => s.items[0].kind === "album"))
  assert.ok(a.sections.some((s) => s.items[0].kind === "artist"))
})

test("browse picks the parser from the id", () => {
  assert.equal(P.browseKind("MPREb_x"), "album")
  assert.equal(P.browseKind("UCabc"), "artist")
  assert.equal(P.browseKind("VLPLabc"), "playlist")
  assert.equal(P.browseKind("FEmusic_home"), "sections")
  const home = P.browse("FEmusic_home", F("home"))
  assert.ok(home.sections.length >= 2)
  assert.ok(home.sections.every((s) => s.title && s.items.length))
})

test("watch info: lyrics tab id and like status", () => {
  const w = P.watchInfo(F("next-lyrics"))
  assert.match(w.lyricsId, /^MPLYt/)
  assert.equal(w.likeStatus, "INDIFFERENT")
  assert.equal(w.queue.length, 1)
})

test("lyrics: timed first, then plain, else none", () => {
  const timed = P.lyrics(F("lyrics-timed"), F("lyrics-plain"))
  assert.equal(timed.kind, "timed")
  assert.deepEqual(timed.lines.map((l) => l.t), [0, 12000, 15400, 19100, 21000])
  assert.match(timed.source, /Example Lyrics/)
  const plain = P.lyrics(null, F("lyrics-plain"))
  assert.equal(plain.kind, "plain")
  assert.match(plain.text, /harbour/)
  assert.deepEqual(P.lyrics(null, F("lyrics-none")), { kind: "none", lines: [], text: "", source: "" })
})

test("queue entries from get_queue parse as tracks", () => {
  const entries = P.queueEntries(F("queue"))
  assert.equal(entries.length, 2)
  const t = P.panelVideo(entries[0])
  assert.match(t.videoId, ID)
  assert.ok(t.artists.length && t.album && t.duration > 0)
})

test("a song/video twin in the queue plays its primary", () => {
  const inner = P.queueEntries(F("queue"))[0]
  const wrapped = { playlistPanelVideoWrapperRenderer: { primaryRenderer: inner, counterpart: [{ counterpartRenderer: P.queueEntries(F("queue"))[1] }] } }
  assert.equal(P.panelVideo(wrapped).videoId, P.panelVideo(inner).videoId)
})

test("suggestions are plain queries", () => {
  const s = P.suggestions(F("suggest"))
  assert.ok(s.length >= 3 && s.every((x) => typeof x === "string" && x.length))
})

test("thumbnails: smallest that is big enough, resized in the URL", () => {
  const thumbs = [
    { url: "https://lh3.googleusercontent.com/a=w60-h60-l90-rj", width: 60 },
    { url: "https://lh3.googleusercontent.com/a=w226-h226-l90-rj", width: 226 },
    { url: "https://lh3.googleusercontent.com/a=w544-h544-l90-rj", width: 544 }
  ]
  assert.equal(P.bestThumb(thumbs, 240), "https://lh3.googleusercontent.com/a=w240-h240-l90-rj")
  assert.equal(P.bestThumb(thumbs.slice(0, 1), 240), "https://lh3.googleusercontent.com/a=w240-h240-l90-rj")
  assert.equal(P.bestThumb([{ url: "https://i.ytimg.com/vi/x/hq.jpg", width: 480 }], 240), "https://i.ytimg.com/vi/x/hq.jpg")
  assert.equal(P.bestThumb([], 240), "")
})

test("durations", () => {
  assert.equal(P.seconds("3:45"), 225)
  assert.equal(P.seconds("1:02:03"), 3723)
  assert.equal(P.seconds("2013"), 0)
  assert.equal(P.seconds("12 songs"), 0)
})

test("account menu: name, email and a 64px avatar", () => {
  const a = P.accountInfo(F("account-menu"))
  assert.equal(a.name, "Alex Example")
  assert.equal(a.email, "alex@example.com")
  assert.match(a.avatar, /=s64-c-mo$/)
})

test("account menu with no header parses to empty, not a throw", () => {
  const a = P.accountInfo({ actions: [] })
  assert.deepEqual(a, { name: "", email: "", avatar: "" })
})

test("a row with no linked artist: skip the flat label, durations and counts", () => {
  const row = {
    flexColumns: [
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Harbour Lights" }] } } },
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Canción" }, { text: " • " }, { text: "Mira Solvent" }, { text: " • " }, { text: "3:12" }] } } },
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "1,2 M reproducciones" }] } } }
    ],
    playlistItemData: { videoId: "AbCdEfGhIjK" }
  }
  const t = P.listItem(row, { flat: true })
  assert.equal(t.artists[0].name, "Mira Solvent")
  assert.equal(t.duration, 192)
  const noArtist = JSON.parse(JSON.stringify(row))
  noArtist.flexColumns[1].musicResponsiveListItemFlexColumnRenderer.text.runs = [{ text: "Song" }, { text: " • " }, { text: "3:12" }]
  assert.deepEqual(P.listItem(noArtist, { flat: true }).artists, [])
})
