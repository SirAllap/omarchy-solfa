import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model

// Your library: playlists, liked songs, albums, artists. Needs sign-in.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  readonly property var sections: [
    { key: "playlists", label: "Playlists" }, { key: "songs", label: "Liked songs" },
    { key: "albums", label: "Albums" }, { key: "artists", label: "Artists" }
  ]
  property string section: "playlists"
  property var cache: ({})
  property bool busy: false
  property string error: ""
  readonly property bool signedIn: svc ? svc.signedIn : false
  readonly property var info: cache[section] || null
  readonly property var rows: !info ? [] : info.tracks ? Model.trackRows(info.tracks) : Model.sectionRows(info.sections)
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: signedIn ? [["↵", "play or open"], ["[ ]", "section"], ["e", "play next"]] : [["↵", "sign in"]]

  function shown() { if (signedIn && !cache[section]) load() }
  function move(dy) { list.cursor = Model.moveCursor(rows, list.cursor, dy) }

  function load() {
    if (!svc || !signedIn) return
    var sec = view.section
    view.busy = true
    view.error = ""
    svc.request("library", { section: sec }, function (r) {
      view.busy = false
      if (!r.ok) { view.error = Model.errorText(r.error); return }
      var c = Object.assign({}, view.cache)
      c[sec] = r.data
      view.cache = c
      if (sec === view.section) list.cursor = Model.firstRow(view.rows)
    })
  }

  function setSection(key) { view.section = key; list.cursor = Model.firstRow(view.rows); if (!cache[key]) load() }
  function cycleSection(d) {
    var i = 0
    for (var k = 0; k < sections.length; k++) if (sections[k].key === view.section) i = k
    setSection(sections[(i + d + sections.length) % sections.length].key)
  }
  function refresh() { var c = Object.assign({}, view.cache); delete c[view.section]; view.cache = c; load() }

  // On screen: the panel is open on this view (see QueueView).
  property bool active: false
  onSignedInChanged: { view.cache = ({}); if (signedIn && active) load() }

  Row {
    id: chips
    spacing: Style.space(4)
    visible: view.signedIn
    Repeater {
      model: view.sections
      delegate: Button {
        required property var modelData
        text: modelData.label
        fontFamily: view.family
        fontSize: Style.font.caption
        selected: view.section === modelData.key
        foreground: view.fg
        verticalPadding: Style.space(3)
        horizontalPadding: Style.space(8)
        onClicked: view.setSection(modelData.key)
      }
    }
  }

  SignInCard {
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    visible: !view.signedIn
    svc: view.svc
    bar: view.bar
  }

  RowList {
    id: list
    visible: view.signedIn
    anchors.top: chips.bottom
    anchors.topMargin: Style.space(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.busy ? "Loading" : view.error !== "" ? view.error : "Nothing here yet"
    onActivated: function (i) { view.panel.activateRow(view.rows[i], view.info && view.info.playlistId ? view.info.playlistId : "") }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
  }
}
