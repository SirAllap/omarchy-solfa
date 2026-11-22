import QtQuick
import "../lib"
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
  readonly property string family: Calm.font

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
    signal clicked()
    height: Style.space(36)
    width: pillRow.width + Style.space(30)
    radius: height / 2
    color: primary ? Calm.accent : pillMouse.containsMouse ? Calm.a(Calm.fg, 0.12) : Calm.wash
    border.width: primary ? 0 : 1
    border.color: Calm.hair
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
        text: pill.text
        color: pill.primary ? Calm.onAccent : Calm.fg
        font.family: view.family
        font.pixelSize: Style.space(13)
        font.weight: Font.DemiBold
      }
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }

  Item {
    id: head
    width: parent.width
    height: cover.height

    RoundCover {
      id: cover
      width: Style.space(118)
      height: width
      cornerRadius: view.info && view.info.kind === "artist" ? -1 : Style.space(20)
      source: view.info ? (view.info.thumb || "") : ""
      foreground: Calm.fg
      fill: Calm.a(Calm.fg, 0.08)
      fontFamily: ""
      glyph: view.info && view.info.kind === "artist" ? Icons.artist : Icons.album
    }

    Column {
      x: cover.width + Style.space(20)  // mockup DetailView: 20 px between cover and text
      width: parent.width - x
      anchors.verticalCenter: cover.verticalCenter
      spacing: Style.space(4)
      Text {
        visible: !!view.info
        text: view.info ? (view.info.kind === "artist" ? "ARTIST" : view.info.kind === "playlist" ? "PLAYLIST" : "ALBUM") : ""
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
        text: !view.info ? (view.busy ? "Loading" : view.error)
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
      }
    }
  }

  RowList {
    id: list
    anchors.top: head.bottom
    anchors.topMargin: Style.space(20)  // mockup: list 20 px under the cover
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    panelOpen: !!(view.svc && view.svc.panelOpen)
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.busy ? "Loading" : view.error
    onActivated: function (i) { view.panel.activateRow(view.rows[i], view.contextList()) }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
    onHeaderActivated: function (i) { var r = view.rows[i]; if (r.more) view.panel.openPage({ browseId: r.more, title: r.header }, r.moreParams) }
    onAtYEndChanged: if (atYEnd) view.loadMore()
  }
}
