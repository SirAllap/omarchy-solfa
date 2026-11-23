import QtQuick
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
  readonly property string family: bar ? bar.fontFamily : Style.font.family

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
  readonly property var rows: !info ? [] : info.tracks ? Model.trackRows(finding ? Model.filterTracks(info.tracks, query) : info.tracks) : Model.sectionRows(info.sections, info.kind === "artist" ? 6 : 0)
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: inputFocused ? [["↵ ↓", "to the list"], ["esc", query === "" ? "close" : "clear"]]
    : findable ? [["↵", "play or open"], ["F", "find", true], ["e", "play next"], ["esc", finding ? "close find" : "back"]]
    : [["↵", "play or open"], ["e", "play next"], ["esc", "back"]]

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
      // An empty page or the same token again would loop for ever.
      if (!r.ok || got.length === 0 || view.info.continuation === token || !view.info.continuation) view.loadingAll = false
      else view.loadMore()
    })
  }

  // ---- find in this playlist

  function startFind() {
    if (!view.findable) return
    view.finding = true
    view.loadError = ""
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

  // F is the only key this page takes (f is like).
  function key(t) {
    if (t === "F" && view.findable) { view.startFind(); return true }
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

  Row {
    id: head
    width: parent.width
    spacing: Style.space(12)

    RoundCover {
      id: cover
      width: Style.space(56)
      height: width
      source: view.info ? (view.info.thumb || "") : ""
      foreground: view.fg
      fill: Util.alpha(view.fg, 0.08)
      fontFamily: view.family
      glyph: view.info && view.info.kind === "artist" ? Icons.artist : Icons.album
    }

    Column {
      width: parent.width - cover.width - actions.width - parent.spacing * 2
      anchors.verticalCenter: cover.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        text: view.info && view.info.title ? view.info.title : (view.page ? view.page.title : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: view.fg
        font.family: view.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        width: parent.width
        text: !view.info ? (view.busy ? "Loading" : view.error)
          : view.info.kind === "album" ? [Model.artistsText(view.info.artists), view.info.subtitle].filter(Boolean).join(" — ")
          : view.info.kind === "playlist" ? [view.info.author, view.info.subtitle].filter(Boolean).join(" — ")
          : (view.info.subtitle || "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Util.alpha(view.fg, 0.65)
        font.family: view.family
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: actions
      anchors.verticalCenter: cover.verticalCenter
      spacing: Style.space(4)
      Button {
        visible: !!view.info && (view.info.kind === "artist" ? !!view.info.radio : !!view.info.playlistId)
        iconText: view.info && view.info.kind === "artist" ? Icons.radio : Icons.play
        text: view.info && view.info.kind === "artist" ? "Radio" : "Play"
        fontFamily: view.family
        foreground: view.fg
        bordered: true
        onClicked: view.playAll(false)
      }
      Button {
        visible: !!view.info && (view.info.kind === "artist" ? !!view.info.shuffle : !!view.info.playlistId)
        iconText: Icons.shuffle
        tooltipText: "Shuffle"
        fontFamily: view.family
        foreground: view.fg
        onClicked: view.playAll(true)
      }
      Button {
        objectName: "findButton"
        visible: view.findable
        iconText: Icons.search
        tooltipText: view.info && view.info.kind === "album" ? "Find in this album (F)" : "Find in this playlist (F)"
        fontFamily: view.family
        foreground: view.fg
        selected: view.finding
        onClicked: if (view.finding) view.closeFind(); else view.startFind()
      }
    }
  }

  Item {
    id: findBar
    objectName: "findBar"
    visible: view.finding
    anchors.top: head.bottom
    anchors.topMargin: visible ? Style.space(10) : 0
    width: parent.width
    height: visible ? findField.implicitHeight : 0

    TextField {
      id: findField
      objectName: "findField"
      anchors.left: parent.left
      anchors.right: findStatus.left
      anchors.rightMargin: Style.space(8)
      placeholderText: view.info && view.info.kind === "album" ? "Find in this album" : "Find in this playlist"
      font.family: view.family
      onTextEdited: view.typed()
      onAccepted: view.fieldToList()
      Keys.onEscapePressed: function (e) { view.escapeField(); e.accepted = true }
      Keys.onDownPressed: function (e) { view.fieldToList(); e.accepted = true }
    }
    Text {
      id: findStatus
      objectName: "findStatus"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(150)
      horizontalAlignment: Text.AlignRight
      text: view.info && view.info.tracks ? Model.findStatus(view.query, view.rows.length, view.info.tracks.length, view.loadingAll, view.loadError !== "") : ""
      textFormat: Text.PlainText
      elide: Text.ElideLeft
      color: Util.alpha(view.fg, 0.6)
      font.family: view.family
      font.pixelSize: Style.font.caption
    }
  }

  RowList {
    id: list
    objectName: "detailList"
    anchors.top: findBar.bottom
    anchors.topMargin: Style.space(10)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.busy ? "Loading" : view.error !== "" ? view.error
      : view.finding && view.query.trim() !== "" ? (view.loadingAll ? "No match yet" : "No song matches") : ""
    onActivated: function (i) { view.panel.activateRow(view.rows[i], view.contextList()) }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
    onHeaderActivated: function (i) { var r = view.rows[i]; if (r.more) view.panel.openPage({ browseId: r.more, title: r.header }, r.moreParams) }
    onAtYEndChanged: if (atYEnd) view.loadMore()
  }
}
