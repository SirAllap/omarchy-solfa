import QtQuick

// Every state of the bar widget, each on its own strip of a fake bar.
HostWindow {
  cw: 800
  ch: 620
  settleMs: 2600
  readonly property var rows: [
    ["Playing", "playing", false, false, 34], ["Playing, pointer over it", "playing", true, false, 34], ["Paused", "paused", false, false, 34],
    ["Advert", "ad", false, false, 34], ["Nothing loaded", "idle", false, false, 34], ["Solfa is off", "off", false, false, 34],
    ["Compact: cover only", "playing", false, true, 34], ["Small bar (26 px)", "playing", false, false, 26], ["Wheel turned: ring shows volume", "playing", true, false, 34, true] ]
  Column { spacing: 10
    Text { text: "BAR WIDGET"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.6 }
    Repeater { model: rows
      Item { width: 800; height: 56
        Rectangle { width: 800; height: 48; radius: 14; color: "#0f1117"; border.width: 1; border.color: Theme.hair
          Row { x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 7
            Repeater { model: 5; Rectangle { width: index === 1 ? 22 : 8; height: 8; radius: 4; color: index === 1 ? Theme.accent : Qt.rgba(1, 1, 1, 0.2) } } }
          Text { x: 120; anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 }
          Text { anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: "21:42   Sun 22"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 }
          BarPill { x: 330; anchors.verticalCenter: parent.verticalCenter; state: modelData[1]; hot: modelData[2]; compact: modelData[3]; barSize: modelData[4]; volume: modelData.length > 5 } }
      } }
  }
}
