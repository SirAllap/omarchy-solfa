import QtQuick

// The bar widget. state: playing | paused | idle | off | ad. compact hides the title and the buttons.
Item {
  id: b
  property string state: "playing"
  property bool compact: false
  property bool hot: false
  property bool volume: false   // the wheel was turned: the ring shows the volume for a moment
  property bool showTitle: true
  property bool showButtons: true
  property int barSize: 34
  readonly property bool has: state === "playing" || state === "paused" || state === "ad"
  height: barSize
  width: pill.width
  Rectangle { id: pill; height: parent.height; radius: height / 2; width: row.width + 14
    color: b.hot ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.045); border.width: 1; border.color: b.hot ? Theme.a(Theme.accent, 0.5) : Theme.hair
    Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 160 } }
    Behavior on width { enabled: !Motion.reduce; SpringAnimation { spring: 4.2; damping: 0.4; epsilon: 0.4 } }
    Glow { visible: b.hot; anchors.centerIn: parent; width: parent.width * 1.4; height: 100; color: Theme.accent; strength: 0.18 }
    Row { id: row; anchors.verticalCenter: parent.verticalCenter; x: 5; spacing: 8
      ProgressRing { anchors.verticalCenter: parent.verticalCenter; size: b.barSize - 8; volume: b.volume; value: b.state === "idle" || b.state === "off" ? 0 : (b.volume ? 0.72 : 0.42); has: b.has; idleIcon: b.state === "off" ? "power" : "album"; playing: b.state === "playing"; seed: 0 }
      Column { visible: !b.compact && b.showTitle; anchors.verticalCenter: parent.verticalCenter; width: 150; spacing: 0
        Text { width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
          color: b.has ? Theme.fg : Theme.dim
          text: b.state === "ad" ? "Advert" : (b.has ? "Glass Harbour" : (b.state === "off" ? "Solfa is off" : "Nothing playing")) }
        Text { width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 10; color: b.state === "ad" ? Theme.warn : Theme.faint
          text: b.state === "ad" ? "your song starts in 0:12" : (b.has ? "Nova Reyes" : (b.state === "off" ? "click to turn on" : "click to search")) } }
      Row { visible: !b.compact && b.showButtons && b.has; anchors.verticalCenter: parent.verticalCenter; spacing: 0; opacity: b.hot ? 1 : 0.8
        IconButton { icon: "prev"; size: 26; glyph: 13 }
        IconButton { icon: b.state === "paused" ? "play" : "pause"; size: 28; glyph: 14; primary: true; hot: b.hot }
        IconButton { icon: "next"; size: 26; glyph: 13 } }
      Item { visible: b.compact && b.has; width: 4; height: 1 }
    }
  }
}
