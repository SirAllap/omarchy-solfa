import QtQuick
import "../lib"
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

// Your library: playlists, liked songs, albums, artists. Needs sign-in.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: Calm.font

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
  // Playlists and albums are a grid of covers (three across), artists a grid
  // of round ones (two across); liked songs stay a list.
  readonly property bool gridMode: section !== "songs"
  readonly property int columns: section === "artists" ? 2 : 3
  readonly property var allRows: !info ? [] : info.tracks ? Model.trackRows(info.tracks) : Model.sectionRows(info.sections)
  readonly property var rows: gridMode ? allRows.filter(function (r) { return !r.header }) : allRows
  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: signedIn ? [["↵", "play or open"], ["[ ]", "section"], ["e", "play next"]] : [["↵", "sign in"]]

  function shown() { if (signedIn && !cache[section]) load() }
  function move(dy) {
    if (!gridMode) { list.cursor = Model.moveCursor(rows, list.cursor, dy); return }
    // Up and down step a whole row of the grid.
    list.cursor = rows.length === 0 ? -1 : Math.max(0, Math.min(rows.length - 1, (list.cursor < 0 ? -columns : list.cursor) + dy * columns))
  }

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
    }, 60000)
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
    spacing: Style.space(6)
    visible: view.signedIn
    Repeater {
      model: view.sections
      delegate: PillChip {
        required property var modelData
        text: modelData.label
        family: view.family
        on: view.section === modelData.key
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

  GridView {
    id: grid
    visible: view.signedIn && view.gridMode
    anchors.top: chips.bottom
    anchors.topMargin: Style.space(12)
    // Wider than the view by the gap and by the room a lifted card needs, so
    // every column fits and the 1.04 lift of a card at the edge is not cut.
    anchors.left: parent.left
    anchors.leftMargin: -Style.space(6)
    anchors.right: parent.right
    anchors.rightMargin: -(Style.space(6) + gap)
    anchors.bottom: parent.bottom
    leftMargin: Style.space(6)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: view.gridMode ? view.rows : []
    readonly property real gap: Style.space(12)
    readonly property bool round: view.section === "artists"
    readonly property real cardW: (view.width - gap * (view.columns - 1)) / view.columns
    cellWidth: cardW + gap
    // The vertical gap between tile rows: was 4 / 10 px, now 12 / 20, so a tile's
    // name and count never touch the tiles below. The tiles themselves are unchanged.
    readonly property real vGap: round ? Style.space(12) : Style.space(20)
    cellHeight: round ? Style.space(134) + vGap : cardW + Style.space(38) + vGap
    currentIndex: list.cursor
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)

    Text {
      anchors.centerIn: parent
      visible: view.rows.length === 0
      text: view.busy ? "Loading" : view.error !== "" ? view.error : "Nothing here yet"
      color: Calm.a(Calm.fg, 0.6)
      font.family: view.family
      font.pixelSize: Style.font.body
    }

    delegate: Item {
      id: card
      required property var modelData
      required property int index
      readonly property var item: modelData.item || ({})
      readonly property bool hot: index === list.cursor
      readonly property real coverSize: grid.round ? Math.min(grid.cardW, Style.space(134) - Style.space(38)) : grid.cardW
      width: grid.cardW
      height: grid.cellHeight - grid.vGap + (grid.round ? Style.space(4) : Style.space(10))
      scale: hot || cardMouse.containsMouse ? 1.04 : 1
      Behavior on scale { enabled: !Style.reduceMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      RoundCover {
        id: art
        x: grid.round ? (parent.width - width) / 2 : 0
        width: card.coverSize
        height: width
        cornerRadius: grid.round ? -1 : Style.space(16)
        source: card.item.thumb || ""
        foreground: Calm.fg
        fill: Calm.a(Calm.fg, 0.08)
        glyph: grid.round ? Icons.artist : card.item.kind === "album" ? Icons.album : Icons.note
        Rectangle {
          anchors.fill: parent
          visible: card.hot
          radius: grid.round ? width / 2 : Style.space(16)
          color: Qt.rgba(0, 0, 0, 0.35)
          Rectangle {
            anchors.centerIn: parent
            width: Style.space(40); height: width; radius: width / 2
            color: Calm.accent
            Text { anchors.centerIn: parent; text: Icons.play; color: Calm.onAccent; font.pixelSize: Style.space(18) }
          }
        }
      }
      Text {
        y: art.height + Style.space(6)
        width: parent.width
        horizontalAlignment: grid.round ? Text.AlignHCenter : Text.AlignLeft
        text: card.item.title || card.item.name || ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Calm.fg
        font.family: view.family
        font.pixelSize: Style.space(13)
        font.weight: Font.DemiBold
      }
      Text {
        y: art.height + Style.space(23)
        width: parent.width
        horizontalAlignment: grid.round ? Text.AlignHCenter : Text.AlignLeft
        text: Model.rowSubtitle(card.item)
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Calm.a(Calm.fg, 0.36)
        font.family: view.family
        font.pixelSize: Style.space(11)
      }
      MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { list.cursor = card.index; view.panel.activateRow(view.rows[card.index], view.info && view.info.playlistId ? view.info.playlistId : "") }
      }
    }
  }

  // Soft fade where tiles run under the grid's bottom edge: none is cut hard.
  Rectangle {
    visible: grid.visible
    anchors.left: grid.left; anchors.right: grid.right; anchors.bottom: grid.bottom
    height: Style.space(16)
    opacity: grid.atYEnd ? 0 : 1
    Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 120 } }
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(Calm.surface.r, Calm.surface.g, Calm.surface.b, 0) }
      GradientStop { position: 1; color: Calm.surface }
    }
  }

  RowList {
    id: list
    visible: view.signedIn && !view.gridMode
    anchors.top: chips.bottom
    anchors.topMargin: Style.space(12)  // mockup: list starts 12 px under the chips
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    playingId: view.svc ? view.svc.videoId : ""
    panelOpen: !!(view.svc && view.svc.panelOpen)
    actionsFor: function (row) { return view.panel ? view.panel.itemActions(row) : [] }
    emptyText: view.busy ? "Loading" : view.error !== "" ? view.error : "Nothing here yet"
    onActivated: function (i) { view.panel.activateRow(view.rows[i], view.info && view.info.playlistId ? view.info.playlistId : "") }
    onAction: function (name, i) { view.panel.runAction(name, view.rows[i]) }
    onArtistActivated: function (i, artist) { view.panel.openArtistLink(artist) }
  }
}
