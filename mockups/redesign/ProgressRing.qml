import QtQuick

// The cover ring of the bar widget: a thin track and a glowing arc.
Item {
  id: r
  property real value: 0.4
  property real size: 30
  property bool playing: true
  property int seed: 0
  property bool has: true
  property bool volume: false
  property string idleIcon: "album"
  property real breath: 0
  width: size; height: size
  SequentialAnimation on breath { running: r.playing && r.has && Motion.live; loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 1500; easing.type: Easing.InOutSine } NumberAnimation { to: 0; duration: 1500; easing.type: Easing.InOutSine } }
  Glow { anchors.centerIn: parent; width: r.size * 1.9; height: width; color: Theme.hue(r.seed, 0.6); strength: r.has && r.playing ? 0.22 + 0.2 * r.breath : 0 }
  DotRing { anchors.centerIn: parent; size: r.size; value: r.has ? r.value : 0; from: r.volume ? Theme.ok : Theme.accent; to: r.volume ? "#8fd3ff" : Theme.accent2 }
  Cover { visible: r.has; anchors.centerIn: parent; width: r.size - 8; height: width; round: true; seed: r.seed; breathe: true; playing: r.playing }
  Rectangle { visible: !r.has; anchors.centerIn: parent; width: r.size - 8; height: width; radius: width / 2; color: Theme.wash
    Icon { anchors.centerIn: parent; name: r.idleIcon; size: r.size * 0.42; color: Theme.faint } }
}
