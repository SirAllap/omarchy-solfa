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

test("search keeps the reply's own order, videos among the songs", () => {
  // Captured from a flat search whose top result is a video (see tests/make-fixtures.py).
  const s = P.search(F("search-mixed"))
  assert.equal(s.top.kind, "video")
  assert.match(s.top.videoId, ID)
  const kinds = s.all.map((x) => x.kind)
  assert.deepEqual(kinds, ["video", "video", "video", "song", "video", "song", "video", "artist", "episode", "podcast"])
  // Every item is in its group and in `all`, once: nothing falls out.
  const grouped = ["songs", "videos", "albums", "artists", "playlists", "other"].reduce((n, g) => n + s[g].length, 0)
  assert.equal(s.all.length, grouped)
  for (const it of s.all) if (it.videoId) assert.match(it.videoId, ID, "every playable result has a video id")
  assert.equal(s.other.length, 2)
  assert.deepEqual(s.other.map((x) => x.kind), ["episode", "podcast"])
})

test("search: a top result that is an album, then songs and videos as ranked", () => {
  const s = P.search(F("search-album-card"))
  assert.equal(s.top.kind, "album")
  assert.deepEqual(s.all.map((x) => x.kind), ["song", "song", "video", "video", "artist", "album", "playlist"])
  const v = P.search(F("search-videos-first"))
  assert.equal(v.top.kind, "video")
  assert.deepEqual(v.all.map((x) => x.kind), ["video", "video", "video", "artist", "song", "video", "video", "album"])
})

test("add to playlist: Recent first, then the rest, none twice, with their sizes", () => {
  // Captured from a signed-in reply (see tests/make-fixtures.py): four recent
  // playlists, Liked Music (id LM) among the others. The reply does not say
  // whether a playlist has the song, so the parser does not either.
  const a = P.addToPlaylist(F("add-to-playlist"))
  assert.equal(a.playlists.length, 5)
  assert.deepEqual(a.playlists.map((x) => x.recent), [true, true, true, true, false])
  assert.equal(a.playlists[4].id, "LM")
  assert.deepEqual(a.playlists.map((x) => x.count), ["889 tracks", "13 tracks", "6 tracks", "7 tracks", "206 songs"])
  assert.equal(new Set(a.playlists.map((x) => x.id)).size, 5)
  assert.ok(a.playlists.every((x) => x.title && !("has" in x) && !("contains" in x)))
  assert.deepEqual(P.addToPlaylist({}), { playlists: [] })
  // A recent card the list does not repeat is kept; no id, no entry.
  const card = (id) => ({ musicTwoRowItemRenderer: { title: { runs: [{ text: "T" + id }] }, subtitle: { runs: [{ text: "3 songs" }] }, navigationEndpoint: { playlistEditEndpoint: { playlistId: id } } } })
  const odd = P.addToPlaylist({ topShelf: { c: [card("PL1"), card("PL1"), { musicTwoRowItemRenderer: {} }] }, x: [{ playlistAddToOptionRenderer: { playlistId: "PL2", title: { runs: [{ text: "A" }, { text: "B" }] } } }, { playlistAddToOptionRenderer: { title: { simpleText: "no id" } } }] })
  assert.deepEqual(odd.playlists, [{ id: "PL1", title: "TPL1", count: "3 songs", recent: true }, { id: "PL2", title: "AB", count: "", recent: false }])
})

test("a playlist edit: added, a duplicate the check refused, or a failure", () => {
  assert.equal(P.playlistEditResult(F("playlist-edit-added")), "added")
  assert.equal(P.playlistEditResult(F("playlist-edit-duplicate")), "duplicate")
  assert.equal(P.playlistEditResult({ status: "STATUS_FAILED" }), "failed")
  assert.equal(P.playlistEditResult({ status: "STATUS_FAILED", playlistEditResults: [{}], actions: [{ addToToastAction: {} }] }), "failed")
  assert.equal(P.playlistEditResult(null), "failed")
})

test("a playlist of the user's own is editable; Liked songs, albums and other people's are not", () => {
  // No signed-in capture of a user's playlist exists, so this one is composed
  // of two real ones: the rows of playlist.json under the header that
  // playlist-edit-added.json returns as `newHeader` (the editable header).
  const compose = (swap) => {
    const page = JSON.parse(JSON.stringify(F("playlist")))
    const tab = page.contents.twoColumnBrowseResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer.contents
    tab[0] = JSON.parse(swap(JSON.stringify(F("playlist-edit-added").newHeader)))
    return page
  }
  const noPlayButton = (h) => h.replace(/"watch(Playlist)?Endpoint"/g, '"somethingElse"')
  const mine = P.playlist(compose((h) => h))
  const header = F("playlist-edit-added").newHeader.musicEditablePlaylistDetailHeaderRenderer
  assert.equal(mine.editable, true)
  assert.equal(mine.playlistId, header.playlistId)
  assert.equal(mine.tracks.length, P.playlist(F("playlist")).tracks.length)
  assert.ok(mine.tracks.every((t) => t.setVideoId))
  assert.equal(P.browse("VL" + header.playlistId, compose((h) => h)).editable, true)
  // Without a Play button the page's own id is used, else the header's.
  const noPlay = compose((h) => noPlayButton(h))
  assert.equal(P.playlist(noPlay).playlistId, F("playlist").contents.twoColumnBrowseResultsRenderer.secondaryContents.sectionListRenderer.contents[0].musicPlaylistShelfRenderer.playlistId)
  const bare = compose((h) => noPlayButton(h))
  delete bare.contents.twoColumnBrowseResultsRenderer.secondaryContents.sectionListRenderer.contents[0].musicPlaylistShelfRenderer.playlistId
  assert.equal(P.playlist(bare).playlistId, header.playlistId)
  assert.equal(P.playlist(bare).editable, true)
  // Liked songs (LM, with or without the VL prefix) never is.
  const liked = P.playlist(compose((h) => h.split(header.playlistId).join("LM")))
  assert.equal(liked.playlistId, "LM")
  assert.equal(liked.editable, false)
  assert.equal(P.playlist(compose((h) => h.split(header.playlistId).join("VLLM"))).editable, false)
  // Somebody else's playlist, an album, a continuation: not editable.
  assert.equal(P.playlist(F("playlist")).editable, false)
  assert.equal(P.playlist(F("album")).editable, false)
  assert.notEqual(P.browse("MPREb_x", F("album")).editable, true)
  assert.equal(P.playlist({ continuationContents: {} }).editable, false)
})

test("a playlist removal: only STATUS_SUCCEEDED is a removal", () => {
  assert.equal(P.playlistRemoveResult({ status: "STATUS_SUCCEEDED" }), true)
  assert.equal(P.playlistRemoveResult(F("playlist-edit-added")), true)
  assert.equal(P.playlistRemoveResult({ status: "STATUS_FAILED" }), false)
  assert.equal(P.playlistRemoveResult({}), false)
  assert.equal(P.playlistRemoveResult(null), false)
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

test("history: dated shelves in order, each row a playable song", () => {
  assert.equal(P.browseKind("FEmusic_history"), "sections")
  const h = P.browse("FEmusic_history", F("history"))
  assert.deepEqual(h.sections.map((s) => s.title), ["Today", "Yesterday", "This week"])
  assert.deepEqual(h.sections.map((s) => s.items.length), [2, 3, 1])
  for (const s of h.sections) for (const it of s.items) {
    assert.ok(["song", "video"].includes(it.kind), "a history row is a playable song or video")
    assert.match(it.videoId, ID)
  }
})

test("history: a reply with no shelves (signed out, or nothing played) parses to an empty page, never throws", () => {
  const h = P.browse("FEmusic_history", F("history-signed-out"))
  assert.deepEqual(h.sections, [])
  assert.deepEqual(P.browse("FEmusic_history", {}).sections, [])
  assert.deepEqual(P.browse("FEmusic_history", null).sections, [])
})

test("library playlists: the grid pages behind a continuation, and each page parses", () => {
  const page1 = P.browse("FEmusic_liked_playlists", F("library-playlists"))
  assert.equal(page1.kind, "page")
  assert.equal(page1.sections.length, 1)
  assert.equal(page1.sections[0].items.length, 2, "the continuation placeholder is not a row")
  assert.equal(page1.sections[0].items[0].playlistId, "LM")
  assert.equal(page1.sections[0].items[1].kind, "playlist")
  assert.equal(page1.sections[0].items[1].playlistId, "PLesJdD8psnow")
  // The token pages the grid's remainder; a grid's own continuations array
  // wins over a token inside a continuationItemRenderer row.
  assert.equal(P.gridToken(F("library-playlists")), "tok-page-2")
  const page2 = P.gridPage(F("library-playlists-cont"), { thumbPx: 240 })
  assert.equal(page2.items.length, 2)
  assert.equal(page2.items[0].kind, "playlist")
  assert.equal(page2.items[0].playlistId, "PLRbIJbyS1SB4")
  assert.equal(page2.items[0].artists[0].name, "WolfSparc")
  assert.equal(page2.continuation, "tok-page-3")
  const last = P.gridPage(F("library-playlists-cont2"), { thumbPx: 240 })
  assert.equal(last.items.length, 1)
  assert.equal(last.continuation, "", "the last page carries no token")
})
