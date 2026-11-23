import QtQuick

// A value picker shown as a pill with a chevron; "open" shows its menu.
Item {
  id: s
  property string value: "Choose"
  property var options: []
  property bool open: false
  property bool hot: false
  width: pill.width; height: 32
  z: open ? 20 : 0
  Rectangle {
    id: pill
    width: txt.width + 46; height: 32; radius: 16
    color: s.open || s.hot ? Qt.rgba(1, 1, 1, 0.12) : Theme.wash
    border.width: 1; border.color: s.open ? Theme.a(Theme.accent, 0.7) : Theme.hair
    Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 150 } }
    Text { id: txt; x: 16; anchors.verticalCenter: parent.verticalCenter; text: s.value; color: Theme.fg; font.family: Theme.font; font.pixelSize: 13 }
    Icon { x: parent.width - 28; anchors.verticalCenter: parent.verticalCenter; name: "chev"; size: 14; color: Theme.dim; rotation: s.open ? 180 : 0; Behavior on rotation { enabled: !Motion.reduce; SpringAnimation { spring: 5; damping: 0.5; epsilon: 0.5 } } }
    MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: s.open = !s.open }
  }
  Rectangle {
    visible: opacity > 0.01
    opacity: s.open ? 1 : 0
    y: 38; x: pill.width - width
    width: 168; height: s.options.length * 32 + 12; radius: 14
    color: Theme.raised; border.width: 1; border.color: Theme.hair
    transformOrigin: Item.TopRight
    scale: s.open ? 1 : 0.92
    Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 140 } }
    Behavior on scale { enabled: !Motion.reduce; SpringAnimation { spring: 6; damping: 0.45; epsilon: 0.001 } }
    Column {
      x: 6; y: 6; width: parent.width - 12
      Repeater {
        model: s.options
        Rectangle {
          width: parent.width; height: 32; radius: 9
          color: modelData === s.value ? Theme.a(Theme.accent, 0.18) : "transparent"
          Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: modelData === s.value ? Theme.accent : Theme.fg; font.family: Theme.font; font.pixelSize: 13 }
          Icon { visible: modelData === s.value; x: parent.width - 28; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 14; color: Theme.accent }
        }
      }
    }
  }
}
