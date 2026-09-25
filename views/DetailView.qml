import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// An album, a playlist, an artist, or a "show all" shelf, opened from any
// list. Esc goes back.
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
  readonly property var rows: !info ? [] : info.tracks ? Model.trackRows(info.tracks) : Model.sectionRows(info.sections, info.kind === "artist" ? 6 : 0)
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: [["↵", "play or open"], ["e", "play next"], ["esc", "back"]]

  function shown() {}
  function move(dy) {
    list.cursor = Model.moveCursor(rows, list.cursor, dy)
    if (dy > 0 && list.cursor >= rows.length - 3) loadMore()
  }

  function open(p) {
    view.page = p
    view.info = p.info || null
    view.error = ""
    if (view.info) { list.cursor = Model.firstRow(view.rows); return }
    view.busy = true
    var want = p.id
    var args = { id: p.id }
    if (p.params) args.params = p.params
    svc.request("browse", args, function (r) {
      if (!view.page || view.page.id !== want) return
      view.busy = false
      if (!r.ok) { view.error = Model.errorText(r.error); return }
      view.info = r.data
      view.page.info = r.data
      list.cursor = Model.firstRow(view.rows)
    })
  }

  function loadMore() {
    if (!view.info || !view.info.continuation || view.loadingMore) return
    view.loadingMore = true
    var want = view.page.id
    svc.request("browse", { id: view.page.id, continuation: view.info.continuation }, function (r) {
      view.loadingMore = false
      if (!view.page || view.page.id !== want || !r.ok) return
      var d = Object.assign({}, view.info)
      d.tracks = (d.tracks || []).concat(r.data.tracks || [])
      d.continuation = r.data.continuation || ""
      view.info = d
      view.page.info = d
    })
  }

  // Tracks play in their list's context: an album keeps playing the album.
  function contextList() { return view.info && view.info.kind !== "artist" ? (view.info.playlistId || "") : "" }

  function playAll(shuffle) {
    if (!view.info) return
    if (view.info.kind === "artist") {
      var s = shuffle ? view.info.shuffle : view.info.radio
      if (!s) return
      var a = { playlistId: s.playlistId }
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
    }
  }

  RowList {
    id: list
    anchors.top: head.bottom
    anchors.topMargin: Style.space(10)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.busy ? "Loading" : view.error
    onActivated: function (i) { view.panel.activateRow(view.rows[i], view.contextList()) }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
    onHeaderActivated: function (i) { var r = view.rows[i]; if (r.more) view.panel.openPage({ browseId: r.more, title: r.header }, r.moreParams) }
    onAtYEndChanged: if (atYEnd) view.loadMore()
  }
}
