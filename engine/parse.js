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
  // a song with its music-video twin: the primary one is what plays.
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
  function search(data, opts) {
    opts = opts || {}
    var out = { top: null, songs: [], videos: [], albums: [], artists: [], playlists: [], other: [], continuation: "" }
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
    var author = text(h.straplineTextOne) || String(dig(h, ["facepile", "avatarStackViewModel", "text", "content"]) || "")
    return {
      kind: "playlist",
      title: text(h.title),
      subtitle: segments(runs(h.secondSubtitle || h.subtitle)).map(segText).filter(Boolean).join(" · "),
      author: author,
      thumb: bestThumb(thumbsOf(h.thumbnail), 544),
      playlistId: play ? String(play.playlistId || "") : (shelf && shelf.playlistId ? String(shelf.playlistId) : ""),
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

  // `account/account_menu` → the signed-in account, for Settings > Account.
  function accountInfo(data) {
    var header = collect(data, "activeAccountHeaderRenderer")[0] || {}
    return {
      name: text(header.accountName),
      email: text(header.email) || text(header.channelHandle),
      avatar: bestThumb(thumbsOf(header.accountPhoto), 64)
    }
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
    album: album,
    playlist: playlist,
    artist: artist,
    browse: browse,
    browseKind: browseKind,
    watchInfo: watchInfo,
    lyrics: lyrics,
    queueEntries: queueEntries,
    accountInfo: accountInfo,
    SEARCH_FILTERS: SEARCH_FILTERS
  }
})()

if (typeof module !== "undefined" && module.exports) module.exports = SolfaParse;
