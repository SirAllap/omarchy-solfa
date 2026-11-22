import QtQuick

Item {
  id: f
  property string text: ""
  property bool focused: false
  property bool busy: false
  height: 46
  Glow { anchors.centerIn: parent; width: parent.width * 1.1; height: 150; color: Theme.accent; strength: f.focused ? 0.2 : 0; Behavior on strength { enabled: !Motion.reduce; NumberAnimation { duration: 260 } } }
  Rectangle { anchors.fill: parent; radius: 23; color: f.focused ? Qt.rgba(1, 1, 1, 0.07) : Theme.wash
    border.width: f.focused ? 1.5 : 1; border.color: f.focused ? Theme.a(Theme.accent, 0.85) : Theme.hair
    Behavior on border.color { enabled: !Motion.reduce; ColorAnimation { duration: 200 } } Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 200 } } }
  Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 19; color: f.focused ? Theme.accent : Theme.dim }
  Text { x: 46; anchors.verticalCenter: parent.verticalCenter; visible: f.text === ""; text: "Search songs, albums, artists and playlists"; color: Theme.faint; font.family: Theme.font; font.pixelSize: 14 }
  Text { id: t; x: 46; anchors.verticalCenter: parent.verticalCenter; text: f.text; color: Theme.fg; font.family: Theme.font; font.pixelSize: 15 }
  Rectangle { visible: f.focused; x: t.x + t.width + 1; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 20; radius: 1; color: Theme.accent
    SequentialAnimation on opacity { running: f.focused; loops: Animation.Infinite; NumberAnimation { to: 0; duration: 520 } NumberAnimation { to: 1; duration: 520 } } }
  Spinner { visible: f.busy; anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; size: 18 }
  Rectangle { visible: !f.focused && !f.busy && f.text === ""; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: 7; color: Theme.wash; border.width: 1; border.color: Theme.hair
    Text { anchors.centerIn: parent; text: "/"; color: Theme.dim; font.family: "monospace"; font.pixelSize: 12 } }
  IconButton { visible: f.text !== "" && !f.busy; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; icon: "close"; size: 30; glyph: 14 }
}
