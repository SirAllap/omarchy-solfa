// parse.js — turns YouTube Music's InnerTube replies into small, flat models.
//
// Runs inside the engine page (bundled in front of agent.js by the bridge)
// and in node for the tests. No DOM, no network, no globals besides the one
// it defines.
//
// Rule of the house: an item's kind comes from its endpoints (page type,
// video type), never from its text. Text is localized ("Song", "Canción"),
// endpoints are not.

var SolfaParse = (function () {
  "use strict"

  // ------------------------------------------------------------------ helpers

  function text(t) {
    if (!t) return ""
    if (typeof t === "string") return t
    if (typeof t.simpleText === "string") return t.simpleText
    if (Array.isArray(t.runs)) return t.runs.map(function (r) { return r && r.text || "" }).join("")
    return ""
  }

  function runs(t) { return t && Array.isArray(t.runs) ? t.runs : [] }

  function dig(o, path) {
    for (var i = 0; i < path.length && o != null; i++) o = o[path[i]]
    return o
  }

  // Every object under `o` that has key `key`, depth first, in order.
  function collect(o, key, out, depth) {
    out = out || []
    depth = depth || 0
    if (!o || typeof o !== "object" || depth > 40) return out
    if (Array.isArray(o)) {
      for (var i = 0; i < o.length; i++) collect(o[i], key, out, depth + 1)
      return out
    }
    for (var k in o) {
      if (!Object.prototype.hasOwnProperty.call(o, k)) continue
      if (k === key) out.push(o[k])
      else collect(o[k], key, out, depth + 1)
    }
    return out
  }

  function pageType(browseEndpoint) {
    return dig(browseEndpoint, ["browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"]) || ""
  }

  function videoType(watchEndpoint) {
    return dig(watchEndpoint, ["watchEndpointMusicSupportedConfigs", "watchEndpointMusicConfig", "musicVideoType"]) || ""
  }

  function kindOfVideo(type) {
    if (type === "MUSIC_VIDEO_TYPE_OMV" || type === "MUSIC_VIDEO_TYPE_UGC" || type === "MUSIC_VIDEO_TYPE_OFFICIAL_SOURCE_MUSIC") return "video"
    if (type === "MUSIC_VIDEO_TYPE_PODCAST_EPISODE") return "episode"
    return "song"
  }

  function kindOfPage(type) {
    switch (type) {
      case "MUSIC_PAGE_TYPE_ALBUM":
      case "MUSIC_PAGE_TYPE_AUDIOBOOK":
        return "album"
      case "MUSIC_PAGE_TYPE_ARTIST":
      case "MUSIC_PAGE_TYPE_USER_CHANNEL":
      case "MUSIC_PAGE_TYPE_LIBRARY_ARTIST":
        return "artist"
      case "MUSIC_PAGE_TYPE_PLAYLIST":
        return "playlist"
      case "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE":
        return "podcast"
      case "MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE":
        return "episode"
      default:
        return ""
    }
  }

  // Google image URLs carry their size ("=w60-h60-l90-rj"); ask for the one
  // we draw at, so covers are sharp on HiDPI and small ones stay small.
  function sizedImage(url, px) {
    url = String(url || "")
    if (!url) return ""
    if (url.indexOf("//") === 0) url = "https:" + url
    if (/googleusercontent\.com|ggpht\.com/.test(url)) {
      if (/=w\d+-h\d+/.test(url)) return url.replace(/=w\d+-h\d+/, "=w" + px + "-h" + px)
      if (/=s\d+/.test(url)) return url.replace(/=s\d+/, "=s" + px)
    }
    return url
  }

  // The smallest picture at least `px` wide, else the biggest one.
  function bestThumb(thumbs, px) {
    px = px || 240
    if (!Array.isArray(thumbs) || thumbs.length === 0) return ""
    var sorted = thumbs.filter(function (t) { return t && t.url }).slice().sort(function (a, b) { return (a.width || 0) - (b.width || 0) })
    if (sorted.length === 0) return ""
    var pick = sorted[sorted.length - 1]
    for (var i = 0; i < sorted.length; i++) if ((sorted[i].width || 0) >= px) { pick = sorted[i]; break }
    return sizedImage(pick.url, px)
  }

  function thumbsOf(o) {
    var lists = collect(o, "thumbnails")
    for (var i = 0; i < lists.length; i++) if (Array.isArray(lists[i]) && lists[i].length) return lists[i]
    return []
  }

  var TIME = /^\s*(\d{1,2}:)?\d{1,2}:\d{2}\s*$/

  function seconds(s) {
    s = String(s || "").trim()
    if (!TIME.test(s)) return 0
    return s.split(":").reduce(function (acc, part) { return acc * 60 + parseInt(part, 10) }, 0)
  }

  // Runs split at the " • " separators into segments of runs.
  function segments(rs) {
    var out = [], cur = []
    for (var i = 0; i < rs.length; i++) {
      var t = rs[i] && rs[i].text
      if (typeof t === "string" && /^\s*[•·]\s*$/.test(t)) {
        if (cur.length) out.push(cur)
        cur = []
      } else {
        cur.push(rs[i])
      }
    }
    if (cur.length) out.push(cur)
    return out
  }

  function linked(rs, kind) {
    var out = []
    for (var i = 0; i < rs.length; i++) {
      var be = dig(rs[i], ["navigationEndpoint", "browseEndpoint"])
      if (be && kindOfPage(pageType(be)) === kind) out.push({ name: String(rs[i].text || ""), id: String(be.browseId || "") })
    }
    return out
  }

  function isLinked(seg) {
    for (var i = 0; i < seg.length; i++) if (seg[i] && seg[i].navigationEndpoint) return true
    return false
  }

  function segText(seg) { return seg.map(function (r) { return r.text || "" }).join("").trim() }

  function explicitOf(o) {
    var icons = collect(o && o.badges, "iconType")
    return icons.indexOf("MUSIC_EXPLICIT_BADGE") !== -1
  }

  function firstWatchEndpoint(o) {
    var eps = collect(o, "watchEndpoint")
    for (var i = 0; i < eps.length; i++) if (eps[i] && eps[i].videoId) return eps[i]
    return null
  }

  function firstPlaylistPlay(o) {
    var eps = collect(o, "watchPlaylistEndpoint")
    for (var i = 0; i < eps.length; i++) if (eps[i] && eps[i].playlistId) return eps[i]
    var w = collect(o, "watchEndpoint")
    for (var j = 0; j < w.length; j++) if (w[j] && w[j].playlistId) return w[j]
    return null
  }

  // "Add to queue" / "Play next" / "Start radio" live in an item's menu.
  function menuEndpoints(o) {
    var out = {}
    var radios = collect(dig(o, ["menu"]), "watchEndpoint")
    for (var i = 0; i < radios.length; i++) {
      if (radios[i] && radios[i].playlistId && /^RD/.test(radios[i].playlistId)) { out.radio = { videoId: radios[i].videoId || "", playlistId: radios[i].playlistId, params: radios[i].params || "" }; break }
    }
    var lists = collect(dig(o, ["menu"]), "watchPlaylistEndpoint")
    for (var j = 0; j < lists.length; j++) {
      if (lists[j] && /^RD/.test(lists[j].playlistId || "")) { out.radio = out.radio || { playlistId: lists[j].playlistId, params: lists[j].params || "" }; break }
    }
    return out
  }

  // ------------------------------------------------------------------ items

  // One track-shaped model for every kind of row that plays something.
  function track(fields) {
    return {
      kind: fields.kind || "song",
      videoId: fields.videoId || "",
      title: fields.title || "",
      artists: fields.artists || [],
      album: fields.album || null,
      duration: fields.duration || 0,
      thumb: fields.thumb || "",
      explicit: !!fields.explicit,
      playlistId: fields.playlistId || "",
      setVideoId: fields.setVideoId || "",
      radio: fields.radio || null
    }
  }

  // musicResponsiveListItemRenderer: search rows, album and playlist tracks,
  // quick picks, library rows.
  //
  // `flat`: the unfiltered search puts a type label first in the subtitle
  // ("Song • Artist • Album"). It is skipped by position only when nothing
  // in the row is linked, which is rare.
  function listItem(r, opts) {
    opts = opts || {}
    if (!r) return null
    var cols = (r.flexColumns || []).map(function (c) { return dig(c, ["musicResponsiveListItemFlexColumnRenderer", "text"]) })
    var fixed = (r.fixedColumns || []).map(function (c) { return dig(c, ["musicResponsiveListItemFixedColumnRenderer", "text"]) })
    var title = text(cols[0])
    var rest = []
    for (var i = 1; i < cols.length; i++) {
      if (rest.length && runs(cols[i]).length) rest.push({ text: " • " })
      rest = rest.concat(runs(cols[i]))
    }
    var thumbs = thumbsOf(r.thumbnail)
    var thumb = bestThumb(thumbs, opts.thumbPx || 240)
    var nav = r.navigationEndpoint || {}
    var be = nav.browseEndpoint
    if (be && be.browseId) {
      var kind = kindOfPage(pageType(be)) || "playlist"
      var segs = segments(rest)
      var play = firstPlaylistPlay(r.overlay) || firstPlaylistPlay(r.menu)
      var model = {
        kind: kind,
        browseId: String(be.browseId),
        title: title,
        subtitle: segs.map(segText).filter(Boolean).join(" · "),
        artists: linked(rest, "artist"),
        thumb: thumb,
        playlistId: play ? String(play.playlistId || "") : (kind === "playlist" ? String(be.browseId).replace(/^VL/, "") : "")
      }
      return model
    }
    var we = firstWatchEndpoint(cols[0]) || firstWatchEndpoint(r.overlay) || null
    var videoId = dig(r, ["playlistItemData", "videoId"]) || (we && we.videoId) || ""
    if (!videoId) return null
    var artists = linked(rest, "artist")
    var albums = linked(rest, "album")
    var dur = 0
    var fixedText = fixed.map(text).join(" ")
    if (seconds(fixedText)) dur = seconds(fixedText)
    var segs2 = segments(rest)
    for (var s = 0; s < segs2.length && !dur; s++) if (seconds(segText(segs2[s]))) dur = seconds(segText(segs2[s]))
    if (artists.length === 0) {
      // Nothing linked: take the first plain part of the subtitle line that is
      // not the type label (flat layout), a duration, a year or a count
      // ("1.2M plays", "280 M reproducciones").
      var line = segments(runs(cols[1]))
      var start = opts.flat && line.length > 1 ? 1 : 0
      for (var k = start; k < line.length; k++) {
        var t = segText(line[k])
        if (t && !seconds(t) && !/^\d/.test(t) && !isLinked(line[k])) { artists = [{ name: t, id: "" }]; break }
      }
    }
    return track({
      kind: kindOfVideo(videoType(we)),
      videoId: String(videoId),
      title: title,
      artists: artists,
      album: albums.length ? albums[0] : null,
      duration: dur,
      thumb: thumb,
      explicit: explicitOf(r),
      playlistId: we && we.playlistId ? String(we.playlistId) : "",
      setVideoId: dig(r, ["playlistItemData", "playlistSetVideoId"]) || "",
      radio: menuEndpoints(r).radio || null
    })
  }

  // musicTwoRowItemRenderer: the cards in carousels (home, artist pages).
  function twoRow(r, opts) {
    opts = opts || {}
    if (!r) return null
    var title = text(r.title)
    var subRuns = runs(r.subtitle)
    var thumb = bestThumb(thumbsOf(r.thumbnailRenderer), opts.thumbPx || 240)
    var nav = r.navigationEndpoint || {}
    if (nav.browseEndpoint && nav.browseEndpoint.browseId) {
      var kind = kindOfPage(pageType(nav.browseEndpoint)) || "playlist"
      var play = firstPlaylistPlay(r.thumbnailOverlay) || firstPlaylistPlay(r.menu)
      return {
        kind: kind,
        browseId: String(nav.browseEndpoint.browseId),
        title: title,
        subtitle: segments(subRuns).map(segText).filter(Boolean).join(" · "),
        artists: linked(subRuns, "artist"),
        thumb: thumb,
        playlistId: play ? String(play.playlistId || "") : (kind === "playlist" ? String(nav.browseEndpoint.browseId).replace(/^VL/, "") : "")
      }
    }
    var we = nav.watchEndpoint || firstWatchEndpoint(r.thumbnailOverlay)
    if (we && we.videoId) {
      return track({
        kind: kindOfVideo(videoType(we)),
        videoId: String(we.videoId),
        title: title,
        artists: linked(subRuns, "artist"),
        album: null,
        thumb: thumb,
        playlistId: we.playlistId || "",
        radio: menuEndpoints(r).radio || null
      })
    }
    var wpe = nav.watchPlaylistEndpoint
    if (wpe && wpe.playlistId) {
      return { kind: "playlist", browseId: "VL" + wpe.playlistId, title: title, subtitle: segments(subRuns).map(segText).filter(Boolean).join(" · "), artists: [], thumb: thumb, playlistId: String(wpe.playlistId) }
    }
    return null
  }

  // playlistPanelVideoRenderer (the queue), also inside a wrapper that pairs
  // a song with its music-video twin: the primary one is what plays. A song
  // queued from a playlist carries its row there (`playlistSetVideoId`, the
  // same value the playlist's page gives that row) next to the playlist's
  // id in its watch endpoint.
  function panelVideo(r, opts) {
    opts = opts || {}
    if (!r) return null
    if (r.playlistPanelVideoWrapperRenderer) r = dig(r, ["playlistPanelVideoWrapperRenderer", "primaryRenderer"])
    if (r && r.playlistPanelVideoRenderer) r = r.playlistPanelVideoRenderer
    if (!r || !r.videoId) return null
    var by = runs(r.longBylineText)
    var we = dig(r, ["navigationEndpoint", "watchEndpoint"]) || {}
    var artists = linked(by, "artist")
    if (artists.length === 0) {
      var segs = segments(by)
      if (segs.length) artists = [{ name: segText(segs[0]), id: "" }]
    }
    var albums = linked(by, "album")
    return track({
      kind: kindOfVideo(videoType(we)),
      videoId: String(r.videoId),
      title: text(r.title),
      artists: artists,
      album: albums.length ? albums[0] : null,
      duration: seconds(text(r.lengthText)),
      thumb: bestThumb(dig(r, ["thumbnail", "thumbnails"]) || [], opts.thumbPx || 120),
      playlistId: we.playlistId || "",
      setVideoId: r.playlistSetVideoId || "",
      radio: menuEndpoints(r).radio || null
    })
  }

  function anyItem(wrapper, opts) {
    if (!wrapper) return null
    if (wrapper.musicResponsiveListItemRenderer) return listItem(wrapper.musicResponsiveListItemRenderer, opts)
    if (wrapper.musicTwoRowItemRenderer) return twoRow(wrapper.musicTwoRowItemRenderer, opts)
    if (wrapper.playlistPanelVideoRenderer || wrapper.playlistPanelVideoWrapperRenderer) return panelVideo(wrapper, opts)
    return null
  }

  function items(list, opts) {
    var out = []
    for (var i = 0; i < (list || []).length; i++) {
      var it = anyItem(list[i], opts)
      if (it) out.push(it)
    }
    return out
  }

  // ------------------------------------------------------------------ search

  function continuationOf(o) {
    var next = collect(o, "nextContinuationData")
    if (next.length && next[0].continuation) return String(next[0].continuation)
    var cmds = collect(o, "continuationCommand")
    if (cmds.length && cmds[0].token) return String(cmds[0].token)
    return ""
  }

  // The token that pages a grid's remainder. The library pages (playlists,
  // albums, artists) ship only their first 25 rows; the rest come a page at
  // a time behind this token.
  function gridToken(data) {
    var grids = collect(data, "gridRenderer")
    for (var i = 0; i < grids.length; i++) {
      var t = continuationOf(grids[i])
      if (t) return t
    }
    return continuationOf(data)
  }

  // One page of that remainder: its rows, and the next page's token (""
  // on the last page).
  function gridPage(data, opts) {
    var g = dig(data, ["continuationContents", "gridContinuation"]) ||
      dig(data, ["continuationContents", "sectionListContinuation"]) || {}
    return { items: items(g.contents || g.items || [], opts), continuation: continuationOf(g || data) }
  }

  // The top result card: an artist, album, playlist or track, with its own
  // play buttons.
  function topCard(card) {
    if (!card) return null
    var titleRuns = runs(card.title)
    var nav = (titleRuns[0] && titleRuns[0].navigationEndpoint) || card.onTap || {}
    var thumb = bestThumb(thumbsOf(card.thumbnail), 240)
    var sub = runs(card.subtitle)
    if (nav.browseEndpoint && nav.browseEndpoint.browseId) {
      var kind = kindOfPage(pageType(nav.browseEndpoint)) || "playlist"
      var play = firstPlaylistPlay(card.buttons)
      return { kind: kind, browseId: String(nav.browseEndpoint.browseId), title: text(card.title), subtitle: segments(sub).map(segText).filter(Boolean).join(" · "), artists: linked(sub, "artist"), thumb: thumb, playlistId: play ? String(play.playlistId || "") : "" }
    }
    var we = nav.watchEndpoint || firstWatchEndpoint(card.buttons)
    if (we && we.videoId) {
      return track({ kind: kindOfVideo(videoType(we)), videoId: String(we.videoId), title: text(card.title), artists: linked(sub, "artist"), album: (linked(sub, "album")[0] || null), thumb: thumb, playlistId: we.playlistId || "" })
    }
    return null
  }

  var SEARCH_FILTERS = {
    songs: "EgWKAQIIAWoSEAUQCRAOEAMQBBAKEBAQFRAR",
    videos: "EgWKAQIQAWoSEAUQCRAOEAMQBBAKEBAQFRAR",
    albums: "EgWKAQIYAWoSEAUQCRAOEAMQBBAKEBAQFRAR",
    artists: "EgWKAQIgAWoSEAUQCRAOEAMQBBAKEBAQFRAR",
    playlists: "EgeKAQQoAEABahIQBRAJEA4QAxAEEAoQEBAVEBE%3D"
  }

  function groupOf(kind) {
    if (kind === "song") return "songs"
    if (kind === "video") return "videos"
    if (kind === "album") return "albums"
    if (kind === "artist") return "artists"
    if (kind === "playlist") return "playlists"
    return "other"
  }

  // Both layouts: the flat one (one item per section, type label first) and
  // the shelf one (a filtered search). Also a continuation page.
  //
  // Every item is in its group (songs, videos, ...) and, in the order the
  // reply listed it, in `all`: the unfiltered view follows YouTube Music's
  // own ranking, which mixes songs, videos, albums and the rest.
  function search(data, opts) {
    opts = opts || {}
    var out = { top: null, all: [], songs: [], videos: [], albums: [], artists: [], playlists: [], other: [], continuation: "" }
    var cards = collect(data, "musicCardShelfRenderer")
    if (cards.length) out.top = topCard(cards[0])
    var rows = collect(data, "musicResponsiveListItemRenderer")
    var seen = {}
    if (out.top) seen[out.top.videoId || out.top.browseId] = true
    for (var i = 0; i < rows.length; i++) {
      var it = listItem(rows[i], { flat: !opts.filter, thumbPx: 120 })
      if (!it) continue
      var key = it.videoId || it.browseId
      if (seen[key]) continue
      seen[key] = true
      out[groupOf(it.kind)].push(it)
      out.all.push(it)
    }
    // The flat layout lists the top artist's songs under its card with no
    // artist of their own.
    if (out.top && out.top.kind === "artist") {
      for (var j = 0; j < out.songs.length; j++) {
        if (out.songs[j].artists.length === 0) out.songs[j].artists = [{ name: out.top.title, id: out.top.browseId }]
      }
    }
    out.continuation = continuationOf(data)
    return out
  }

  function suggestions(data) {
    var out = []
    var rs = collect(data, "searchSuggestionRenderer")
    for (var i = 0; i < rs.length && out.length < 8; i++) {
      var q = dig(rs[i], ["navigationEndpoint", "searchEndpoint", "query"]) || text(rs[i].suggestion)
      if (q && out.indexOf(q) === -1) out.push(String(q))
    }
    return out
  }

  // ------------------------------------------------------------------ pages

  function shelfTitle(s) {
    return text(s.title) || text(dig(s, ["header", "musicCarouselShelfBasicHeaderRenderer", "title"])) || text(dig(s, ["header", "musicCarouselShelfBasicHeaderRenderer", "strapline"]))
  }

  function shelfMore(s) {
    var be = dig(s, ["bottomEndpoint", "browseEndpoint"]) ||
      dig(s, ["header", "musicCarouselShelfBasicHeaderRenderer", "moreContentButton", "buttonRenderer", "navigationEndpoint", "browseEndpoint"]) ||
      dig(s, ["title", "runs", 0, "navigationEndpoint", "browseEndpoint"]) ||
      dig(s, ["header", "musicCarouselShelfBasicHeaderRenderer", "title", "runs", 0, "navigationEndpoint", "browseEndpoint"])
    return be && be.browseId ? { browseId: String(be.browseId), params: String(be.params || "") } : null
  }

  // Every shelf and carousel on a page, in order: home, artist, "more".
  function sections(data, opts) {
    var out = []
    var lists = collect(data, "sectionListRenderer")
    for (var l = 0; l < lists.length; l++) {
      var contents = lists[l].contents || []
      for (var i = 0; i < contents.length; i++) {
        var c = contents[i]
        var s = c.musicShelfRenderer || c.musicCarouselShelfRenderer || c.musicPlaylistShelfRenderer || c.gridRenderer ||
          dig(c, ["itemSectionRenderer", "contents", 0, "gridRenderer"])
        if (!s) continue
        var its = items(s.contents || s.items || [], opts)
        if (its.length === 0) continue
        out.push({ title: shelfTitle(s), items: its, more: shelfMore(s) })
      }
    }
    return out
  }

  function responsiveHeader(data) {
    return collect(data, "musicResponsiveHeaderRenderer")[0] ||
      collect(data, "musicDetailHeaderRenderer")[0] ||
      collect(data, "musicEditablePlaylistDetailHeaderRenderer").map(function (e) { return dig(e, ["header", "musicResponsiveHeaderRenderer"]) || dig(e, ["header", "musicDetailHeaderRenderer"]) })[0] ||
      collect(data, "musicImmersiveHeaderRenderer")[0] ||
      collect(data, "musicVisualHeaderRenderer")[0] || null
  }

  // An album, single or EP.
  function album(data) {
    var h = responsiveHeader(data) || {}
    var strap = runs(h.straplineTextOne)
    var artists = linked(strap, "artist")
    if (artists.length === 0 && strap.length) artists = [{ name: text(h.straplineTextOne), id: "" }]
    var play = firstPlaylistPlay(h.buttons)
    var thumb = bestThumb(thumbsOf(h.thumbnail), 544)
    var shelf = collect(data, "musicShelfRenderer")[0] || collect(data, "musicPlaylistShelfRenderer")[0] || {}
    var tracks = items(shelf.contents || [], { thumbPx: 120 })
    var playlistId = play ? String(play.playlistId || "") : ""
    for (var i = 0; i < tracks.length; i++) {
      if (!tracks[i].artists.length) tracks[i].artists = artists
      if (!tracks[i].thumb) tracks[i].thumb = sizedImage(thumb, 120)
      if (!tracks[i].album) tracks[i].album = { name: text(h.title), id: "" }
      if (!playlistId && tracks[i].playlistId) playlistId = tracks[i].playlistId
    }
    return {
      kind: "album",
      title: text(h.title),
      subtitle: segments(runs(h.subtitle)).map(segText).filter(Boolean).join(" · "),
      artists: artists,
      thumb: thumb,
      playlistId: playlistId,
      tracks: tracks
    }
  }

  // A playlist page, or a continuation of one.
  function playlist(data) {
    var h = responsiveHeader(data) || {}
    var shelf = collect(data, "musicPlaylistShelfRenderer")[0] || collect(data, "musicShelfRenderer")[0] || null
    var rows = shelf ? (shelf.contents || []) : []
    if (!shelf) {
      // A continuation page carries the rows elsewhere.
      var appended = collect(data, "continuationItems")
      rows = appended.length ? appended[0] : (dig(data, ["continuationContents", "musicPlaylistShelfContinuation", "contents"]) || [])
    }
    var tracks = items(rows, { thumbPx: 120 })
    var play = firstPlaylistPlay(h.buttons)
    // Only the user's own playlists come with the editable header. A song
    // can be taken out of those, except Liked songs.
    var own = collect(data, "musicEditablePlaylistDetailHeaderRenderer")[0] || null
    var playlistId = play ? String(play.playlistId || "") : (shelf && shelf.playlistId ? String(shelf.playlistId) : "")
    if (!playlistId && own && own.playlistId) playlistId = String(own.playlistId)
    var author = text(h.straplineTextOne) || String(dig(h, ["facepile", "avatarStackViewModel", "text", "content"]) || "")
    return {
      kind: "playlist",
      title: text(h.title),
      subtitle: segments(runs(h.secondSubtitle || h.subtitle)).map(segText).filter(Boolean).join(" · "),
      author: author,
      thumb: bestThumb(thumbsOf(h.thumbnail), 544),
      playlistId: playlistId,
      editable: !!own && playlistId.replace(/^VL/, "") !== "LM",
      tracks: tracks,
      continuation: continuationOf(shelf || data)
    }
  }

  function artist(data) {
    var h = collect(data, "musicImmersiveHeaderRenderer")[0] || collect(data, "musicVisualHeaderRenderer")[0] || responsiveHeader(data) || {}
    var shuffle = dig(h, ["playButton", "buttonRenderer", "navigationEndpoint", "watchEndpoint"]) || null
    var radio = dig(h, ["startRadioButton", "buttonRenderer", "navigationEndpoint", "watchEndpoint"]) ||
      dig(h, ["startRadioButton", "buttonRenderer", "navigationEndpoint", "watchPlaylistEndpoint"]) || null
    return {
      kind: "artist",
      title: text(h.title),
      subtitle: text(h.monthlyListenerCount) || text(h.subscriptionButton && dig(h.subscriptionButton, ["subscribeButtonRenderer", "subscriberCountText"])),
      thumb: bestThumb(thumbsOf(h.thumbnail), 544),
      shuffle: shuffle && shuffle.playlistId ? { videoId: shuffle.videoId || "", playlistId: shuffle.playlistId, params: shuffle.params || "" } : null,
      radio: radio && radio.playlistId ? { videoId: radio.videoId || "", playlistId: radio.playlistId, params: radio.params || "" } : null,
      sections: sections(data, { thumbPx: 240 })
    }
  }

  // Which parser a browse id wants.
  function browseKind(id) {
    id = String(id || "")
    if (/^MPRE/.test(id)) return "album"
    if (/^(UC|MPLA)/.test(id)) return "artist"
    if (/^VL/.test(id)) return "playlist"
    return "sections"
  }

  function browse(id, data) {
    var kind = browseKind(id)
    if (kind === "album") return album(data)
    if (kind === "artist") return artist(data)
    if (kind === "playlist") return playlist(data)
    var h = responsiveHeader(data)
    return { kind: "page", title: h ? text(h.title) : "", sections: sections(data, { thumbPx: 240 }) }
  }

  // ------------------------------------------------------------------ watch

  // From a `next` reply: the lyrics tab's browse id and the like status.
  function watchInfo(data) {
    var tabs = collect(data, "tabRenderer")
    var lyricsId = "", relatedId = ""
    for (var i = 0; i < tabs.length; i++) {
      var be = dig(tabs[i], ["endpoint", "browseEndpoint"])
      if (!be || !be.browseId || tabs[i].unselectable) continue
      if (/^MPLYt/.test(be.browseId)) lyricsId = String(be.browseId)
      else if (/^MPTRt/.test(be.browseId)) relatedId = String(be.browseId)
    }
    var likes = collect(data, "likeButtonRenderer")
    var like = likes.length && likes[0].likeStatus ? String(likes[0].likeStatus) : ""
    var queue = items(collect(data, "playlistPanelRenderer")[0] ? collect(data, "playlistPanelRenderer")[0].contents : [], { thumbPx: 120 })
    return { lyricsId: lyricsId, relatedId: relatedId, likeStatus: like, queue: queue }
  }

  // Timed lines (from the mobile client's reply), else plain text.
  function lyrics(timedData, plainData) {
    var out = { kind: "none", lines: [], text: "", source: "" }
    var timed = collect(timedData, "timedLyricsData")[0]
    if (Array.isArray(timed) && timed.length) {
      var lines = []
      for (var i = 0; i < timed.length; i++) {
        var l = timed[i] || {}
        var t = parseInt(dig(l, ["cueRange", "startTimeMilliseconds"]), 10)
        if (!isFinite(t)) continue
        lines.push({ t: t, text: String(l.lyricLine || "") })
      }
      if (lines.length) {
        out.kind = "timed"
        out.lines = lines
        out.source = String(collect(timedData, "sourceMessage")[0] || "")
        return out
      }
    }
    var shelf = collect(plainData, "musicDescriptionShelfRenderer")[0]
    if (shelf && text(shelf.description)) {
      out.kind = "plain"
      out.text = text(shelf.description)
      out.source = text(shelf.footer)
    }
    return out
  }

  // `music/get_queue` → queue entries for the app's store.
  function queueEntries(data) {
    var datas = (data && data.queueDatas) || []
    var out = []
    for (var i = 0; i < datas.length; i++) if (datas[i] && datas[i].content) out.push(datas[i].content)
    return out
  }

  // `next` asked with a queue continuation → the page's entries for the
  // app's store and the token for the page after it ("" at the end). The
  // songs the app itself leaves out of a page (unplayable ones, or anything
  // that is not a queue entry) are left out here too.
  function queuePage(data) {
    var c = (data && data.continuationContents && data.continuationContents.playlistPanelContinuation) || {}
    var entries = (c.contents || []).filter(function (e) {
      var r = e && (e.playlistPanelVideoRenderer || dig(e, ["playlistPanelVideoWrapperRenderer", "primaryRenderer", "playlistPanelVideoRenderer"]))
      return !!r && !r.unplayableText
    })
    var next = ""
    var conts = c.continuations || []
    for (var i = 0; i < conts.length && !next; i++) {
      var d = conts[i] && (conts[i].nextRadioContinuationData || conts[i].nextContinuationData)
      if (d && d.continuation) next = String(d.continuation)
    }
    return { entries: entries, continuation: next }
  }

  // `account/account_menu` → the signed-in account, for Settings > Account.
  function accountInfo(data) {
    var header = collect(data, "activeAccountHeaderRenderer")[0] || {}
    return {
      name: text(header.accountName),
      email: text(header.email) || text(header.channelHandle),
      avatar: bestThumb(thumbsOf(header.accountPhoto), 64)
    }
  }

  // `playlist/get_add_to_playlist` → the playlists a song can be saved to,
  // as YouTube Music lists them: the recently used ones first (`recent`),
  // then the rest, none twice. `count` is its "889 tracks" line. The reply
  // does not say whether a playlist has the song already.
  function addToPlaylist(data) {
    var all = []
    var rs = collect(data, "playlistAddToOptionRenderer")
    for (var i = 0; i < rs.length; i++) {
      var id = rs[i] && rs[i].playlistId ? String(rs[i].playlistId) : ""
      if (id) all.push({ id: id, title: text(rs[i].title), count: text(rs[i].shortBylineText) })
    }
    var byId = {}
    all.forEach(function (p) { byId[p.id] = p })
    var recent = []
    var cards = collect(collect(data, "topShelf")[0], "musicTwoRowItemRenderer")
    for (var j = 0; j < cards.length; j++) {
      var ep = dig(cards[j], ["navigationEndpoint", "playlistEditEndpoint"])
      var rid = ep && ep.playlistId ? String(ep.playlistId) : ""
      if (!rid || recent.some(function (p) { return p.id === rid })) continue
      var known = byId[rid]
      recent.push({ id: rid, title: known ? known.title : text(cards[j].title), count: known ? known.count : text(cards[j].subtitle), recent: true })
    }
    var rest = all.filter(function (p) { return !recent.some(function (r) { return r.id === p.id }) })
    rest.forEach(function (p) { p.recent = false })
    return { playlists: recent.concat(rest) }
  }

  // `browse/edit_playlist` for one added song: "added", "duplicate" (the
  // check refused it: FAILED, no results, and a toast offering "Add
  // anyway") or "failed". Read from the shape, never from the words.
  function playlistEditResult(res) {
    if (!res) return "failed"
    if (res.status === "STATUS_SUCCEEDED") return "added"
    var toast = collect(res.actions, "addToToastAction").length > 0
    if (res.status === "STATUS_FAILED" && !res.playlistEditResults && toast) return "duplicate"
    return "failed"
  }

  // ------------------------------------------------------------------ share

  var SHARE_ID = /^[A-Za-z0-9_-]{11}$/
  var SHARE_HOSTS = { "music.youtube.com": 1, "www.youtube.com": 1, "youtube.com": 1, "youtu.be": 1 }

  // The link Solfa hands out for a song: nothing but its id, on YouTube Music.
  function shareUrl(videoId) {
    return typeof videoId === "string" && SHARE_ID.test(videoId) ? "https://music.youtube.com/watch?v=" + videoId : ""
  }

  // A link YouTube Music gave for `videoId`, cut down to what is safe to
  // pass on: an allow-list, not a list of what to remove. Only https on
  // YouTube's own hosts; the id comes from `v` (or the path of youtu.be) and
  // must be the song asked about; the result is always the canonical
  // https://music.youtube.com/watch?v=<id>, so `si` (who shared it),
  // `feature`, `list`, `t`, `drli` and whatever YouTube adds later are gone.
  // "" when the link is not one of those.
  function cleanShareUrl(url, videoId) {
    if (typeof url !== "string" || !SHARE_ID.test(String(videoId))) return ""
    var m = /^https:\/\/([^\/?#]+)(\/[^?#]*)?(?:\?([^#]*))?(?:#.*)?$/i.exec(url.trim())
    if (!m) return ""
    var host = m[1].toLowerCase()
    if (!Object.prototype.hasOwnProperty.call(SHARE_HOSTS, host)) return ""
    var path = m[2] || ""
    var id = ""
    if (host === "youtu.be") {
      var seg = /^\/([^\/]+)\/?$/.exec(path)
      id = seg ? seg[1] : ""
    } else {
      if (path !== "/watch") return ""
      var found = []
      var pairs = (m[3] || "").split("&")
      for (var i = 0; i < pairs.length; i++) {
        var eq = pairs[i].indexOf("=")
        if (eq > 0 && pairs[i].slice(0, eq) === "v") {
          try { found.push(decodeURIComponent(pairs[i].slice(eq + 1))) } catch (e) { return "" }
        }
      }
      if (found.length !== 1) return ""
      id = found[0]
    }
    return SHARE_ID.test(id) && id === videoId ? shareUrl(id) : ""
  }

  // The `serializedShareEntity` of a song's "Share" menu item, found in a
  // `next` reply or in the app's queue items: the one of the entry whose
  // videoId is `videoId`. "" when there is none.
  function shareEntity(data, videoId) {
    var rs = collect(data, "playlistPanelVideoRenderer")
    for (var i = 0; i < rs.length; i++) {
      if (!rs[i] || rs[i].videoId !== videoId) continue
      var eps = collect(rs[i].menu, "shareEntityEndpoint")
      for (var j = 0; j < eps.length; j++) {
        var e = eps[j] && eps[j].serializedShareEntity
        if (typeof e === "string" && e.length > 0 && e.length <= 512) return e
      }
    }
    return ""
  }

  // `share/get_share_panel` → the link its "Copy link" row copies: the
  // unified share panel's copyLinkRenderer.shortUrl. Raw, with `si` and the
  // rest still on it; cleanShareUrl is what makes it fit to pass on.
  function sharePanelUrl(data) {
    var c = collect(data, "copyLinkRenderer")[0]
    return c && typeof c.shortUrl === "string" ? c.shortUrl : ""
  }

  // `browse/edit_playlist` for one removed song: true only when it says so.
  function playlistRemoveResult(res) {
    return !!res && res.status === "STATUS_SUCCEEDED"
  }

  return {
    text: text,
    seconds: seconds,
    bestThumb: bestThumb,
    sizedImage: sizedImage,
    listItem: listItem,
    twoRow: twoRow,
    panelVideo: panelVideo,
    items: items,
    search: search,
    suggestions: suggestions,
    sections: sections,
    gridToken: gridToken,
    gridPage: gridPage,
    album: album,
    playlist: playlist,
    artist: artist,
    browse: browse,
    browseKind: browseKind,
    watchInfo: watchInfo,
    lyrics: lyrics,
    queueEntries: queueEntries,
    queuePage: queuePage,
    accountInfo: accountInfo,
    addToPlaylist: addToPlaylist,
    playlistEditResult: playlistEditResult,
    shareUrl: shareUrl,
    cleanShareUrl: cleanShareUrl,
    shareEntity: shareEntity,
    sharePanelUrl: sharePanelUrl,
    playlistRemoveResult: playlistRemoveResult,
    SEARCH_FILTERS: SEARCH_FILTERS
  }
})()

if (typeof module !== "undefined" && module.exports) module.exports = SolfaParse;
