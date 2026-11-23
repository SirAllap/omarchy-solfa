import QtQuick

// A dot that flies from one place to another along a small arc, with a tail.
// Used when a song is sent to the queue: the dot lands on the Queue tab.
Item {
  id: c
  property color color: Theme.accent
  property real x0: 0; property real y0: 0; property real x1: 0; property real y1: 0
  property real arc: 40
  property real t: 1
  signal arrived()
  visible: t < 1
  function fly(ax, ay, bx, by, kind, seed) {
    if (Motion.reduce) { arrived(); return }
    x0 = ax; y0 = ay; x1 = bx; y1 = by; color = Motion.eventColor(kind)
    arc = 26 + 44 * Motion.rand(seed || 1)
    anim.stop(); t = 0; anim.start()
  }
  NumberAnimation { id: anim; target: c; property: "t"; from: 0; to: 1; duration: 760; easing.type: Easing.InOutCubic; onFinished: c.arrived() }
  Repeater {
    model: 7
    Item {
      readonly property real tt: Math.max(0, Math.min(1, c.t - index * 0.035))
      x: c.x0 + (c.x1 - c.x0) * tt
      y: c.y0 + (c.y1 - c.y0) * tt - Math.sin(Math.PI * tt) * c.arc
      opacity: (1 - index / 7) * (c.t > 0 ? 1 : 0)
      Glow { x: -width / 2; y: -height / 2; width: 34 - index * 3; height: width; color: c.color; keep: true; strength: 0.3 }
      Rectangle { x: -width / 2; y: -height / 2; width: 9 - index; height: width; radius: width / 2; color: index === 0 ? "#fff" : c.color }
    }
  }
}
