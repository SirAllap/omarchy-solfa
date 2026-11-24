import QtQuick
import "../lib"
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// An album, a playlist, an artist, or a "show all" shelf, opened from any
// list. Esc goes back. On a playlist or an album, F (or the button by Play)
// opens a field that filters the songs as you type; it loads the rest of
// the playlist first, since a page holds only the first 100.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: Calm.font

  property var page: null        // { id, params, title }
  property var info: null
  property bool busy: false
  property bool loadingMore: false
  property string error: ""
  // Find: the field is open (`finding`), what it holds, whether the pages
  // after the first are being fetched for it, and why they stopped.
  property bool finding: false
  property string query: ""
  property bool loadingAll: false
  property string loadError: ""
  // Bumped when the page changes or the view is left: an answer that was
  // asked before that is dropped.
  property int seq: 0
  readonly property bool findable: !!info && !!info.tracks && info.kind !== "artist"
  readonly property bool inputFocused: finding && findField.activeFocus
  // Rows come from the filtered tracks, so a row's index is its place in
  // the list on screen, not in info.tracks: always go through `rows`.
  readonly property var rows: !info ? [] : info.tracks ? Model.trackRows(finding ? matchedTracks() : info.tracks) : Model.sectionRows(info.sections, info.kind === "artist" ? 6 : 0)
  // Find: a page that arrives only adds to info.tracks, so only the new
  // tracks are filtered and appended to the last result. A new query or a
  // different list starts again. Plain cache: not a binding input.
  readonly property var findCache: ({ query: null, first: null, n: 0, out: [] })
  function matchedTracks() {
    var tracks = info.tracks, c = findCache
    var same = c.query === query && c.n <= tracks.length && c.first === tracks[0]
    var out = same ? c.out.concat(Model.filterTracks(tracks.slice(c.n), query)) : Model.filterTracks(tracks, query)
    c.query = query; c.first = tracks[0]; c.n = tracks.length; c.out = out
    return out
  }
  // Find stops fetching at this many pages or songs, whichever comes first.
  readonly property int findMaxPages: 20
  readonly property int findMaxTracks: 2000
  property int findPages: 0
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  // With the find field focused: the field's hints. Otherwise x only where
  // it works (a row of the user's own playlist), and F (pinned) where there
  // are songs to find.
  readonly property bool removableHere: Model.removable(info, current)
  readonly property var hints: inputFocused ? [["↵ ↓", "to the list"], ["esc", query === "" ? "close" : "clear"]]
    : findable ? (removableHere
        ? [["↵", "play or open"], ["x", "remove"], ["F", "find", true], ["e", "play next"], ["esc", finding ? "close find" : "back"]]
        : [["↵", "play or open"], ["F", "find", true], ["e", "play next"], ["esc", finding ? "close find" : "back"]])
    : [["↵", "play or open"], ["e", "play next"], ["esc", "back"]]
  // Rows whose removal is on its way (by setVideoId): a second x sends nothing.
  property var removing: ({})

  function shown() {}
  function move(dy) {
    list.cursor = Model.moveCursor(rows, list.cursor, dy)
    if (dy > 0 && list.cursor >= rows.length - 3) loadMore()
  }

  function open(p) {
    view.seq++
    view.loadingMore = false
    resetFind()
    view.page = p
    view.info = p.info || null
    view.error = ""
    if (view.info) { list.cursor = Model.firstRow(view.rows); return }
    view.busy = true
    var s = view.seq
    var args = { id: p.id }
    if (p.params) args.params = p.params
    svc.request("browse", args, function (r) {
      if (s !== view.seq) return
      view.busy = false
      if (!r.ok) { view.error = Model.errorText(r.error); return }
      view.info = r.data
      view.page.info = r.data
      list.cursor = Model.firstRow(view.rows)
    })
  }

  // The next page of a long list (the cursor reached the bottom, or the
  // find field wants all of it). While `loadingAll`, each answer asks for
  // the one after it until there is none, or one fails.
  function loadMore() {
    if (!view.info || !view.info.continuation || view.loadingMore) return
    view.loadingMore = true
    var s = view.seq
    var token = view.info.continuation
    svc.request("browse", { id: view.page.id, continuation: token }, function (r) {
      if (s !== view.seq) return
      view.loadingMore = false
      var got = r.ok ? (r.data.tracks || []) : []
      var d
      if (r.ok) {
        d = Object.assign({}, view.info)
        d.tracks = (d.tracks || []).concat(got)
        d.continuation = r.data.continuation || ""
        view.info = d
        view.page.info = d
      } else if (view.loadingAll) {
        view.loadError = Model.errorText(r.error)
        if (view.panel) view.panel.say(view.loadError)
      }
      if (!view.loadingAll) return
      view.findPages++
      if (r.ok && view.info.continuation && (view.findPages >= view.findMaxPages || view.info.tracks.length >= view.findMaxTracks)) {
        view.loadingAll = false
        view.loadError = "Only the first " + view.info.tracks.length + " songs were loaded"
        return
      }
      // An empty page or the same token again would loop for ever.
      if (!r.ok || got.length === 0 || view.info.continuation === token || !view.info.continuation) view.loadingAll = false
      else view.loadMore()
    })
  }

  // x, Delete or the row's button: the song leaves the playlist, no
  // confirmation, and the row goes without reloading the page.
  function remove(row) {
    if (!Model.removable(view.info, row) || !svc) return
    var sid = row.item.setVideoId
    if (view.removing[sid]) return
    view.removing[sid] = true
    var page = view.page
    var title = view.info.title || (page ? page.title : "")
    var listId = view.info.playlistId
    // Where the row was and what followed it, for the undo (from the whole
    // list, not the found rows).
    var rec = Model.removalRecord(view.info, sid)
    var undo = rec ? Object.assign({ playlistId: Model.bareListId(listId), videoId: row.item.videoId, setVideoId: sid, title: title }, rec) : null
    svc.request("playlist.remove", { playlistId: listId, videoId: row.item.videoId, setVideoId: sid }, function (r) {
      delete view.removing[sid]
      if (!r.ok) { svc.report(r.error); return }
      if (page) page.info = Model.withoutTrack(page.info, sid)
      var at = list.cursor   // the list moves it when its rows change
      if (view.page === page) {
        view.info = Model.withoutTrack(view.info, sid)
        list.cursor = Model.cursorAfterRemoval(at, view.rows.length)
        if (view.panel) view.panel.say(Model.removedMessage(title), undo)
      }
      // Other pages of it, and Now Playing when this row is the song playing.
      if (view.panel) view.panel.trackRemoved(listId, sid)
    })
  }

  // A row of the playlist on screen left it from elsewhere (Now Playing's
  // button): it goes from the list as if removed here, without a reload.
  function trackRemoved(playlistId, setVideoId) {
    if (!view.info || view.info.kind !== "playlist" || Model.bareListId(view.info.playlistId) !== Model.bareListId(playlistId)) return
    var d = Model.withoutTrack(view.info, setVideoId)
    if (d === view.info) return
    var at = list.cursor
    view.info = d
    if (view.page) view.page.info = Model.withoutTrack(view.page.info, setVideoId)
    list.cursor = Model.cursorAfterRemoval(at, view.rows.length)
  }

  // A row put back by an undo (Panel.trackRestored): it comes back into the
  // list where it was, and the cursor stays on the song it was on.
  function trackRestored(playlistId, track, before, placed) {
    if (!view.info || view.info.kind !== "playlist" || Model.bareListId(view.info.playlistId) !== Model.bareListId(playlistId)) return
    var d = Model.withTrackRestored(view.info, track, before, placed)
    if (d === view.info) return
    var keep = view.current
    // A row back in the middle is not a page added at the end: the found
    // rows are worked out again from the whole list.
    view.findCache.query = null
    view.info = d
    if (view.page) view.page.info = Model.withTrackRestored(view.page.info, track, before, placed)
    var at = Model.rowIndex(view.rows, keep)
    if (at >= 0) list.cursor = at
  }

  // ---- find in this playlist

  function startFind() {
    if (!view.findable) return
    view.finding = true
    view.loadError = ""
    view.findPages = 0
    findField.forceActiveFocus()
    findField.selectAll()
    if (view.info.continuation) { view.loadingAll = true; view.loadMore() }
  }

  // The filter shut, with no song left out: nothing is fetched any more.
  function resetFind() {
    view.finding = false
    view.loadingAll = false
    view.loadError = ""
    view.query = ""
    findField.text = ""
  }

  // Esc, or the button again: back to the whole list, on the same song.
  function closeFind() {
    var row = view.current
    resetFind()
    var at = Model.rowIndex(view.rows, row)
    list.cursor = at >= 0 ? at : Model.firstRow(view.rows)
    if (view.panel) view.panel.focusKeys()
  }

  function typed() {
    view.query = findField.text
    list.cursor = Model.firstRow(view.rows)
  }

  // Esc in the field: the text first, then the field.
  function escapeField() {
    if (findField.text !== "") { findField.text = ""; typed() }
    else closeFind()
  }

  // Enter or Down in the field: on to the list, on its first song.
  function fieldToList() {
    if (view.rows.length === 0) return
    list.cursor = Model.firstRow(view.rows)
    if (view.panel) view.panel.focusKeys()
  }

  // The page went away (back to a tab, the panel shut): stop and forget.
  function leave() {
    view.seq++
    view.loadingMore = false
    resetFind()
  }

  Connections {
    target: view.panel
    function onPagesChanged() { if (view.panel.pages.length === 0) view.leave() }
    function onOpenedChanged() { if (!view.panel.opened) view.leave() }
  }

  // F finds; x removes from a playlist of the user's (f is like). Typed in
  // the find field, both are the field's: they never get here.
  function key(t) {
    if (t === "F" && view.findable) { view.startFind(); return true }
    if (t === "x" && Model.removable(view.info, view.current)) { remove(view.current); return true }
    return false
  }

  // Tracks play in their list's context: an album keeps playing the album.
  function contextList() { return view.info && view.info.kind !== "artist" ? (view.info.playlistId || "") : "" }

  function playAll(shuffle) {
    if (!view.info) return
    var s, a
    if (view.info.kind === "artist") {
      s = shuffle ? view.info.shuffle : view.info.radio
      if (!s) return
      a = { playlistId: s.playlistId }
      if (s.videoId) a.videoId = s.videoId
      if (s.params) a.params = s.params
      svc.request("play", a)
      return
    }
    if (!view.info.playlistId) return
    var args = { playlistId: view.info.playlistId }
    if (shuffle) args.params = "wAEB8gECKAE%3D"
    svc.request("play", args)
  }

  // The mockup's pill button: 36 px, the primary one filled with the accent.
  component Pill: Rectangle {
    id: pill
    property string text: ""
    property string glyph: ""
    property bool primary: false
    property bool active: false   // a toggle that is on (Find, with its field open)
    property string keyHint: ""   // a key that does the same, drawn as a KeyCap
    property string tooltipText: ""
    signal clicked()
    height: Style.space(36)
    width: pillRow.width + Style.space(30)
    radius: height / 2
    color: primary ? Calm.accent : active ? Calm.a(Calm.accent, 0.18) : pillMouse.containsMouse ? Calm.a(Calm.fg, 0.12) : Calm.wash
    border.width: primary ? 0 : 1
    border.color: active ? Calm.a(Calm.accent, 0.85) : Calm.hair
    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(7)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pill.glyph
        color: pill.primary ? Calm.onAccent : Calm.fg
        font.pixelSize: Style.space(15)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: pill.text !== ""
        text: pill.text
        color: pill.primary ? Calm.onAccent : Calm.fg
        font.family: view.family
        font.pixelSize: Style.space(13)
        font.weight: Font.DemiBold
      }
      KeyCap {
        anchors.verticalCenter: parent.verticalCenter
        visible: pill.keyHint !== ""
        text: pill.keyHint
      }
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
    // A calm tip under the pill while the pointer rests on it.
    Rectangle {
      z: 10
      visible: pill.tooltipText !== "" && pillMouse.containsMouse
      y: pill.height + Style.space(6)
      width: tipText.implicitWidth + Style.space(20)
      height: Style.space(26)
      radius: Style.space(8)
      color: Calm.raised
      border.width: 1
      border.color: Calm.hair
      Text {
        id: tipText
        anchors.centerIn: parent
        text: pill.tooltipText
        textFormat: Text.PlainText
        color: Calm.fg
        font.family: view.family
        font.pixelSize: Style.space(12)
      }
    }
  }

  // The mockup's Back: a pill at the top left of the page, with its esc key.
  Row {
    id: backRow
    objectName: "backRow"
    height: Style.space(36)
    spacing: Style.space(8)
    Pill {
      objectName: "backButton"
      glyph: Icons.back
      text: "Back"
      onClicked: if (view.panel) view.panel.back()
    }
    KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "esc" }
  }

  Item {
    id: head
    y: backRow.height + Style.space(12)
    width: parent.width
    height: Math.max(cover.height, headCol.height)

    RoundCover {
      id: cover
      width: Style.space(view.compact ? 56 : 118)
      height: width
      cornerRadius: view.info && view.info.kind === "artist" ? -1 : Style.space(20)
      hold: true
      source: (view.info && view.info.thumb) || (view.page ? (view.page.thumb || "") : "")
      foreground: Calm.fg
      fill: Calm.a(Calm.fg, 0.08)
      fontFamily: ""
      glyph: view.info && view.info.kind === "artist" ? Icons.artist : Icons.album
    }

    Column {
      id: headCol
      x: cover.width + Style.space(20)  // mockup DetailView: 20 px between cover and text
      width: parent.width - x
      anchors.verticalCenter: cover.verticalCenter
      spacing: Style.space(4)
      Text {
        readonly property string kind: view.info ? view.info.kind : (view.page ? view.page.kind : "")
        visible: (!!view.info || kind !== "") && !view.compact
        height: visible ? implicitHeight : 0
        text: kind === "artist" ? "ARTIST" : kind === "playlist" ? "PLAYLIST" : kind === "album" ? "ALBUM" : ""
        color: Calm.accent
        font.family: view.family
        font.pixelSize: Style.space(11)
        font.weight: Font.Bold
        font.letterSpacing: 1.4
      }
      Text {
        width: parent.width
        text: view.info && view.info.title ? view.info.title : (view.page ? view.page.title : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Calm.fg
        font.family: view.family
        font.pixelSize: Style.space(24)
        font.weight: Font.Bold
        font.letterSpacing: -0.5
      }
      Text {
        width: parent.width
        text: !view.info ? (view.busy ? (view.page && view.page.subtitle ? view.page.subtitle : "") : view.error)
          : view.info.kind === "album" ? [Model.artistsText(view.info.artists), view.info.subtitle].filter(Boolean).join(" · ")
          : view.info.kind === "playlist" ? [view.info.author, view.info.subtitle].filter(Boolean).join(" · ")
          : (view.info.subtitle || "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Calm.a(Calm.fg, 0.64)
        font.family: view.family
        font.pixelSize: Style.space(12)
      }
      Row {
        id: actions
        topPadding: Style.space(8)
        spacing: Style.space(8)
        Pill {
          visible: !!view.info && (view.info.kind === "artist" ? !!view.info.radio : !!view.info.playlistId)
          primary: true
          glyph: view.info && view.info.kind === "artist" ? Icons.radio : Icons.play
          text: view.info && view.info.kind === "artist" ? "Radio" : "Play"
          onClicked: view.playAll(false)
        }
        Pill {
          visible: !!view.info && (view.info.kind === "artist" ? !!view.info.shuffle : !!view.info.playlistId)
          glyph: Icons.shuffle
          text: "Shuffle"
          onClicked: view.playAll(true)
        }
        Pill {
          objectName: "findButton"
          visible: view.findable
          active: view.finding
          glyph: Icons.search
          keyHint: "F"
          tooltipText: view.info && view.info.kind === "album" ? "Find in this album (F)" : "Find in this playlist (F)"
          onClicked: if (view.finding) view.closeFind(); else view.startFind()
        }
      }
    }
  }

  // The find bar wears the redesign's search field: a 46 px pill, accent ring
  // while it has focus, the count of matches on its right.
  Item {
    id: findBar
    objectName: "findBar"
    visible: view.finding
    anchors.top: head.bottom
    anchors.topMargin: visible ? Style.space(14) : 0
    width: parent.width
    height: visible ? Style.space(46) : 0

    Rectangle {
      id: findBox
      anchors.fill: parent
      radius: height / 2
      color: findField.activeFocus ? Calm.a(Calm.fg, 0.07) : Calm.wash
      border.width: findField.activeFocus ? 1.5 : 1
      border.color: findField.activeFocus ? Calm.a(Calm.accent, 0.85) : Calm.hair
      Behavior on color { enabled: !Style.reduceMotion; ColorAnimation { duration: 200 } }
      Behavior on border.color { enabled: !Style.reduceMotion; ColorAnimation { duration: 200 } }

      Text {
        x: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.search
        color: findField.activeFocus ? Calm.accent : Calm.a(Calm.fg, 0.64)
        font.pixelSize: Style.space(19)
      }
      Text {
        x: Style.space(46)
        anchors.verticalCenter: parent.verticalCenter
        visible: findField.text === ""
        text: findField.placeholderText
        color: Calm.a(Calm.fg, 0.36)
        font.family: view.family
        font.pixelSize: Style.space(14)
      }
      TextInput {
        id: findField
        objectName: "findField"
        property string placeholderText: view.info && view.info.kind === "album" ? "Find in this album" : "Find in this playlist"
        anchors.left: parent.left
        anchors.leftMargin: Style.space(46)
        anchors.right: findStatus.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        color: Calm.fg
        selectionColor: Calm.a(Calm.accent, 0.5)
        selectedTextColor: Calm.fg
        font.family: view.family
        font.pixelSize: Style.space(15)
        onTextEdited: view.typed()
        onAccepted: view.fieldToList()
        Keys.onEscapePressed: function (e) { view.escapeField(); e.accepted = true }
        Keys.onDownPressed: function (e) { view.fieldToList(); e.accepted = true }
      }
      Text {
        id: findStatus
        objectName: "findStatus"
        anchors.right: parent.right
        anchors.rightMargin: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(130)
        horizontalAlignment: Text.AlignRight
        text: view.info && view.info.tracks ? Model.findStatus(view.query, view.rows.length, view.info.tracks.length, view.loadingAll, view.loadError !== "") : ""
        textFormat: Text.PlainText
        elide: Text.ElideLeft
        color: Calm.a(Calm.fg, 0.6)
        font.family: view.family
        font.pixelSize: Style.space(12)
      }
    }
  }

  // What the panel reads to grow its height: the list wants room for this
  // many rows (6 tracks at 58 px + 8 px gap), and says how tall it is now.
  // While the rows load and their count is known (from the tile), grey placeholder
  // rows fill the grown height: never a tall empty card with a word in the middle.
  // Short screens (set by the Panel): a smaller cover and no kind label, so more rows fit.
  readonly property bool compact: !!(panel && panel.compactHead === true)
  readonly property int skeletonRows: busy && rows.length === 0 && page ? (page.count > 0 ? Math.min(page.count, 6) : 6) : 0
  readonly property real wantListH: rows.length > 0 ? Math.min(rows.length, 6) * Style.space(66) : 0

  RowList {
    id: list
    objectName: "detailList"
    fadeBottom: false
    anchors.top: findBar.bottom
    anchors.topMargin: view.finding ? Style.space(10) : Style.space(20)  // mockup: list 20 px under the cover
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    panelOpen: !!(view.svc && view.svc.panelOpen)
    isPlaying: view.svc ? view.svc.isPlaying !== false : true
    actionsFor: function (row) {
      var out = view.panel ? view.panel.itemActions(row) : []
      if (Model.removable(view.info, row)) out.push({ name: "remove", icon: Icons.close, tip: "Remove from this playlist (x)" })
      return out
    }
    emptyText: view.busy ? (view.skeletonRows > 0 ? "" : "Loading") : view.error !== "" ? view.error
      : view.finding && view.query.trim() !== "" ? (view.loadingAll ? "No match yet" : "No song matches") : ""
    onActivated: function (i) { view.panel.activateRow(view.rows[i], view.contextList()) }
    onAction: function (name, i) { if (name === "remove") view.remove(view.rows[i]); else view.panel.runAction(name, view.rows[i], list.actionAnchor) }
    onArtistActivated: function (i, artist) { view.panel.openArtistLink(artist) }
    onHeaderActivated: function (i) { var r = view.rows[i]; if (r.more) view.panel.openPage({ browseId: r.more, title: r.header }, r.moreParams) }
    onAtYEndChanged: if (atYEnd) view.loadMore()
  }

  Item {
   id: skeletonBox
   anchors.fill: list
   clip: true
   visible: view.skeletonRows > 0
   Column {
    objectName: "detailSkeleton"
    anchors.top: parent.top
    anchors.left: parent.left; anchors.right: parent.right
    spacing: Style.space(8)
    Repeater {
      model: view.skeletonRows
      Item {
        width: parent.width; height: Style.space(58)
        opacity: 0.7
        SequentialAnimation on opacity {
          running: view.skeletonRows > 0 && !Style.reduceMotion; loops: Animation.Infinite
          NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.55; duration: 600; easing.type: Easing.InOutSine }
        }
        Rectangle { x: Style.space(14); anchors.verticalCenter: parent.verticalCenter; width: Style.space(52); height: width; radius: Style.space(12); color: Calm.wash }
        Rectangle { x: Style.space(80); y: Style.space(12); width: parent.width * 0.42; height: Style.space(13); radius: height / 2; color: Calm.wash }
        Rectangle { x: Style.space(80); y: Style.space(33); width: parent.width * 0.26; height: Style.space(11); radius: height / 2; color: Calm.wash }
      }
    }
   }
  }

  // Soft fade where rows run under the list's edges, so none is cut hard:
  // the card colour fades in over the last ~16 px; the top one only once scrolled.
  Rectangle {
    objectName: "detailFadeTop"
    anchors.left: list.left; anchors.right: list.right; anchors.top: list.top
    height: Style.space(16)
    opacity: list.contentY > 1 ? 1 : 0
    Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 120 } }
    gradient: Gradient {
      GradientStop { position: 0; color: Calm.surface }
      GradientStop { position: 1; color: Qt.rgba(Calm.surface.r, Calm.surface.g, Calm.surface.b, 0) }
    }
  }
  Rectangle {
    objectName: "detailFadeBottom"
    anchors.left: list.left; anchors.right: list.right; anchors.bottom: list.bottom
    height: Style.space(16)
    opacity: list.atYEnd ? 0 : 1
    Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 120 } }
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(Calm.surface.r, Calm.surface.g, Calm.surface.b, 0) }
      GradientStop { position: 1; color: Calm.surface }
    }
  }
}
