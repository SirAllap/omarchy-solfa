import QtQuick
import qs.Commons
import "../lib"

// "All keys": a calm sheet over the lower panel. A title and "esc close",
// then the keys in groups (small-caps header, two columns of rows). It
// scrolls with soft fade edges and always comes to rest on a row boundary,
// so no row is left cut in half. Opens with a 180 ms fade and rise; there
// is no motion under reduce-motion. Only the picture: the keys themselves
// are handled by the panel.
Item {
  id: sheet

  property bool shown: false
  property QtObject bar: null

  // The real bindings of Panel.onKey, grouped. In "keys", " / " between
  // two keys is plain text; every key is its own cap.
  readonly property var groups: [
    { title: "Playback", rows: [
      ["space", "Play / pause"], ["n / p", "Next / previous"], [", / .", "Seek 10 s"], ["- / =", "Volume down / up"],
      ["m", "Mute"], ["f / d", "Like / dislike"], ["r", "Repeat"], ["s", "Shuffle"] ] },
    { title: "Navigate", rows: [
      ["↑ / ↓", "Move"], ["← / →", "Switch tab"], ["1-5", "Go to a tab"], ["tab", "Next tab"],
      ["/", "Search"], ["↵", "Play or open"], ["backspace", "Back"], ["esc", "Back / close"], ["?", "Show / hide keys"] ] },
    { title: "Queue", rows: [
      ["e", "Play next"], ["a", "Add to queue"], ["R", "Start radio"], ["S", "Save to a playlist"],
      ["x", "Remove"], ["J / K", "Move down / up"] ] },
    { title: "Library", rows: [
      ["[ / ]", "Filter / section"], ["g", "Go to artist"], ["o", "Go to album"], ["w", "YouTube window"], ["i", "Sign in"] ] }
  ]

  readonly property real inset: Style.space(2)
  readonly property real pad: Style.space(20)
  // Every line (a header or a row of two) is one pitch high, and the scroll
  // moves and rests in whole pitches: no row is ever left half hidden.
  readonly property real rowH: Math.round(Style.space(28))
  readonly property real gutter: Style.space(14)
  readonly property int lines: groups.reduce(function (n, g) { return n + 1 + Math.ceil(g.rows.length / 2) }, 0)

  // 0 closed, 1 open: the fade and the rise.
  property real p: shown ? 1 : 0
  Behavior on p { enabled: !Style.reduceMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  visible: p > 0.001
  opacity: p

  onShownChanged: if (shown) { snapAnim.stop(); flick.contentY = 0 }

  // A very soft shadow, layered rectangles (no GPU effect): the sheet sits above the list.
  Item {
    anchors.fill: parent
    Repeater {
      model: 6
      Rectangle {
        required property int index
        readonly property real s: 2.5 * (index + 1)
        x: sheet.inset - s
        y: sheet.inset - s + Style.space(5)
        width: sheetCard.width + 2 * s
        height: sheetCard.height + 2 * s
        radius: sheetCard.radius + s
        color: Qt.rgba(0, 0, 0, Calm.light ? 0.012 : 0.03)
      }
    }
  }

  Rectangle {
    id: sheetCard
    objectName: "keysSheetCard"
    x: sheet.inset
    y: sheet.inset
    width: sheet.width - 2 * sheet.inset
    height: sheet.height - 2 * sheet.inset
    radius: Style.space(20)
    color: Calm.surface
    border.width: 1
    border.color: Calm.outline
    transform: Translate { y: (1 - sheet.p) * Style.space(12) }

    // Takes the clicks so the list underneath does not.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: function (w) { w.accepted = false } }

    Item {
      id: head
      x: sheet.pad
      y: Style.space(16)
      width: parent.width - 2 * sheet.pad
      height: Style.space(28)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Keys"
        textFormat: Text.PlainText
        color: Calm.fg
        font.family: Calm.font
        font.pixelSize: Style.space(18)
        font.weight: Font.DemiBold
      }
      KeyHint { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; keys: "esc"; label: "close"; labelPx: Style.space(12) }
    }

    Flickable {
      id: flick
      objectName: "keysScroll"
      x: sheet.pad
      y: head.y + head.height + Style.space(6)
      width: parent.width - 2 * sheet.pad
      // A whole number of lines tall: what is left below is padding.
      height: Math.max(sheet.rowH, Math.floor((parent.height - y - Style.space(10)) / sheet.rowH) * sheet.rowH)
      clip: true
      contentWidth: width
      contentHeight: sheet.lines * sheet.rowH
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      readonly property real maxY: Math.max(0, contentHeight - height)
      readonly property bool busy: dragging || flicking || snapAnim.running || settle.running

      function snap() {
        var to = Math.max(0, Math.min(maxY, Math.round(contentY / sheet.rowH) * sheet.rowH))
        if (Math.abs(to - contentY) < 0.5) return
        snapAnim.stop()
        snapAnim.to = to
        snapAnim.start()
      }
      NumberAnimation { id: snapAnim; target: flick; property: "contentY"; duration: Style.duration(140); easing.type: Easing.OutCubic }
      // The scroll came to rest (wheel, drag or flick): settle on a row.
      Timer { id: settle; interval: 130; onTriggered: if (!flick.dragging && !flick.flicking && !snapAnim.running) flick.snap() }
      onContentYChanged: if (!snapAnim.running) settle.restart()

      Column {
        id: body
        width: flick.width
        spacing: 0
        Repeater {
          id: secRep
          model: sheet.groups
          delegate: Item {
            id: sec
            required property var modelData
            readonly property real headH: sheet.rowH
            width: body.width
            height: headH + Math.ceil(modelData.rows.length / 2) * sheet.rowH
            Text {
              y: 0
              height: sec.headH
              bottomPadding: Style.space(3)
              verticalAlignment: Text.AlignBottom
              text: sec.modelData.title
              textFormat: Text.PlainText
              color: Calm.muted
              font.family: Calm.font
              font.pixelSize: Style.space(10.5)
              font.weight: Font.DemiBold
              font.capitalization: Font.AllUppercase
              font.letterSpacing: Style.space(0.9)
            }
            Repeater {
              model: sec.modelData.rows
              delegate: KeyHint {
                required property var modelData
                required property int index
                x: (index % 2) * (sec.width + sheet.gutter) / 2
                y: sec.headH + Math.floor(index / 2) * sheet.rowH + (sheet.rowH - implicitHeight) / 2
                keys: modelData[0]
                label: modelData[1]
                labelPx: Style.space(12.5)
                maxWidth: (sec.width - sheet.gutter) / 2
              }
            }
          }
        }
      }
    }

    // Soft fades where more rows wait above or below.
    // Short at rest (a row is never dimmed much), longer while the list moves
    // (a row passing the edge dissolves instead of being cut).
    property real fadeH: flick.busy ? Style.space(22) : Style.space(6)
    Behavior on fadeH { enabled: !Style.reduceMotion; NumberAnimation { duration: 120 } }
    Rectangle {
      x: flick.x; y: flick.y; width: flick.width; height: sheetCard.fadeH
      opacity: flick.contentY > 1 ? 1 : 0
      Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 120 } }
      gradient: Gradient {
        GradientStop { position: 0; color: Calm.surface }
        GradientStop { position: 1; color: Calm.a(Calm.surface, 0) }
      }
    }
    Rectangle {
      x: flick.x; y: flick.y + flick.height - height; width: flick.width; height: sheetCard.fadeH
      opacity: flick.contentY < flick.maxY - 1 ? 1 : 0
      Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 120 } }
      gradient: Gradient {
        GradientStop { position: 0; color: Calm.a(Calm.surface, 0) }
        GradientStop { position: 1; color: Calm.surface }
      }
    }
  }

  // For the panel: one line up or down (the keys that scroll are its to wire).
  function scrollBy(dir) {
    var to = Math.max(0, Math.min(flick.maxY, Math.round(flick.contentY / sheet.rowH) * sheet.rowH + dir * sheet.rowH))
    snapAnim.stop(); snapAnim.to = to; snapAnim.start()
  }
}
