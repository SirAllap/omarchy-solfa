import QtQuick

// Tabs that morph: the chosen tab grows to show its name, the others fold
// to an icon, and one pill glides and settles with a little spring.
Item {
  id: tb
  property var tabs: []
  property string current: ""
  signal picked(string key)
  height: 46
  readonly property int idx: { for (var i = 0; i < tabs.length; i++) if (tabs[i].key === current) return i; return -1 }

  Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.wash; border.width: 1; border.color: Theme.hair }
  Rectangle {
    id: pill
    visible: tb.idx >= 0
    y: 4; height: 38; radius: 19
    x: 4 + tb.idx * (tb.restWidth + 2)
    width: tb.activeWidth
    Behavior on x { enabled: !Motion.reduce; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.4 } }
    Behavior on width { enabled: !Motion.reduce; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.4 } }
    color: Theme.a(Theme.accent, 0.2)
    border.width: 1; border.color: Theme.a(Theme.accent, 0.45)
    Glow { anchors.centerIn: parent; width: parent.width * 1.4; height: parent.height * 3; color: Theme.accent; strength: 0.16 }
  }
  Row {
    id: row
    x: 4; y: 4; height: 38; spacing: 2
    Repeater {
      id: rep
      model: tb.tabs
      Item {
        id: tab
        readonly property bool on: modelData.key === tb.current
        readonly property bool hot: tb.hotKey === modelData.key
        height: 38
        width: on ? 14 + 18 + 8 + lbl.implicitWidth + 14 : (tb.width - 8 - 2 * (tb.tabs.length - 1) - tb.activeWidth) / (tb.idx < 0 ? tb.tabs.length : Math.max(1, tb.tabs.length - 1))
        Behavior on width { enabled: !Motion.reduce; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.4 } }
        Icon { x: tab.on ? 14 : (parent.width - 18) / 2; anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: 18; color: tab.on ? Theme.accent : (tab.hot || ma.containsMouse ? Theme.fg : Theme.dim)
          Behavior on x { enabled: !Motion.reduce; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.4 } } }
        Text { id: lbl; x: 14 + 18 + 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: Theme.fg; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
          opacity: tab.on ? 1 : 0; Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: tab.on ? 260 : 90 } } }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: tb.picked(modelData.key) }
      }
    }
  }
  property string hotKey: ""
  readonly property real restWidth: (width - 8 - 2 * (tabs.length - 1) - activeWidth) / Math.max(1, tabs.length - 1)
  // centre of a tab in this item's coordinates (where a comet lands)
  function tabCenter(key) {
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === key) { var it = rep.itemAt(i); return it.mapToItem(tb, it.width / 2, it.height / 2) }
    return Qt.point(0, 0)
  }
  readonly property real activeWidth: { var i = idx; if (i < 0) return 0; return 14 + 18 + 8 + labelWidth + 14 }
  property real labelWidth: 52
  TextMetrics { id: tm; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; text: tb.idx >= 0 ? tb.tabs[tb.idx].label : "" ; onWidthChanged: tb.labelWidth = width }
}
