import QtQuick

// A glow and a short flash that start on an event and die away smoothly:
// glow ~ exp(-t/520 ms), flash ~ exp(-t/380 ms). The colour is the meaning.
Item {
  id: g
  property color color: Theme.accent
  property real age: 99999
  property real size: 320
  width: 1; height: 1
  readonly property real glow: Math.exp(-age / Motion.glowTau)
  readonly property real flash: Math.exp(-age / Motion.flashTau)
  function fire(kind) {
    if (Motion.reduce) return
    color = Motion.eventColor(kind)
    anim.stop(); age = 0; anim.start()
  }
  NumberAnimation { id: anim; target: g; property: "age"; from: 0; to: 3200; duration: 3200 }
  Glow { x: -width / 2; y: -height / 2; width: g.size; height: g.size; color: g.color; keep: true; strength: 0.3 * g.glow; visible: g.age < 3000 }
  Glow { x: -width / 2; y: -height / 2; width: g.size * 0.38; height: width; keep: true; color: "#fff"; strength: 0.16 * g.flash; visible: g.age < 2000 }
  Rectangle { x: -width / 2; y: -height / 2; width: 24 + g.age * 0.12; height: width; radius: width / 2; color: "transparent"
    border.width: 2; border.color: g.color; opacity: 0.45 * g.flash; visible: g.age < 2000 }
}
