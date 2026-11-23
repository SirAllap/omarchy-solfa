import QtQuick

// A ring of dots: lit up to "value", a bigger dot at the head. For progress
// or volume around the round cover of the bar widget.
Item {
  id: r
  property real value: 0.4
  property real size: 34
  property int dots: size < 30 ? 22 : 30
  property color from: Theme.accent
  property color to: Theme.accent2
  property bool shimmer: true
  property real phase: 0
  width: size; height: size
  NumberAnimation on phase { running: r.shimmer && Motion.live; from: 0; to: 1; duration: 2400; loops: Animation.Infinite }
  Repeater {
    model: r.dots
    Rectangle {
      readonly property real f: index / r.dots
      readonly property bool lit: f < r.value
      readonly property bool head: lit && (index + 1) / r.dots >= r.value
      readonly property real d: Math.max(1.6, r.size * (head ? 0.1 : 0.062))
      width: d; height: d; radius: d / 2
      x: r.size / 2 + (r.size / 2 - 1.5) * Math.cos(f * 2 * Math.PI - Math.PI / 2) - d / 2
      y: r.size / 2 + (r.size / 2 - 1.5) * Math.sin(f * 2 * Math.PI - Math.PI / 2) - d / 2
      color: lit ? Qt.tint(r.from, Theme.a(r.to, f)) : Qt.rgba(1, 1, 1, 0.16)
      opacity: lit ? (head ? 1 : 0.75 + 0.25 * Math.max(0, Math.cos((f - r.phase) * 6.28))) : 1
      Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 160 } }
    }
  }
}
