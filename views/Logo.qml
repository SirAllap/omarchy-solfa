import QtQuick

// Solfa's logo, version C (the approved drawing, mockups/logo/05-logo-final-c.svg
// on solfa-logo): a dark vinyl record, a thin rim, five fine grooves, a soft
// sheen, a muted lilac label and a hole, all on one centre. Drawn on a 100 unit
// grid scaled to size, so every ring shares the centre at any size.
Item {
  id: root
  property real size: 20
  property color rim: "#e6e8ec"
  property color label: "#857f9e"
  property color disc: "#1d1f24"
  property color hole: "#121316"
  implicitWidth: size
  implicitHeight: size

  onRimChanged: cv.requestPaint()
  onLabelChanged: cv.requestPaint()
  onDiscChanged: cv.requestPaint()
  onHoleChanged: cv.requestPaint()

  Canvas {
    id: cv
    anchors.fill: parent
    antialiasing: true
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var s = width / 100
      function circle(r) { ctx.beginPath(); ctx.arc(50 * s, 50 * s, r * s, 0, 2 * Math.PI) }
      function tint(a) { return Qt.rgba(root.rim.r, root.rim.g, root.rim.b, a) }
      circle(46); ctx.fillStyle = root.disc; ctx.fill()
      ctx.strokeStyle = tint(0.8); ctx.lineWidth = 2 * s; ctx.stroke()
      ctx.strokeStyle = tint(0.22); ctx.lineWidth = 0.9 * s
      var g = [40, 36, 32, 28, 24]
      for (var i = 0; i < g.length; i++) { circle(g[i]); ctx.stroke() }
      ctx.beginPath()
      ctx.arc(50 * s, 50 * s, 38 * s, -120 * Math.PI / 180, -30 * Math.PI / 180)
      ctx.strokeStyle = tint(0.5); ctx.lineWidth = 2 * s; ctx.lineCap = "round"; ctx.stroke()
      circle(15); ctx.fillStyle = root.label; ctx.fill()
      circle(3.5); ctx.fillStyle = root.hole; ctx.fill()
    }
  }
}
