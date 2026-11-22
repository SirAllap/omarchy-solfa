import QtQuick

// Text that writes itself, 30 ms per letter, with a blinking cursor.
// It keeps its full height from the start so nothing below it jumps.
Item {
  id: t
  property string text: ""
  property int pixelSize: 14
  property int weight: Font.Normal
  property color color: Theme.fg
  property int maxLines: 2
  property bool typing: true
  property real shown: text.length
  property bool recent: false
  property bool blink: true
  implicitHeight: ghost.implicitHeight
  height: implicitHeight
  function restart() {
    anim.stop()
    if (Motion.reduce || !typing) { shown = text.length; return }
    shown = 0
    recent = true; fade.restart()
    anim.duration = Math.max(1, text.length) * Motion.typeMs
    anim.from = 0; anim.to = text.length; anim.start()
  }
  onTextChanged: restart()
  onTypingChanged: if (typing) restart(); else { anim.stop(); shown = text.length }
  NumberAnimation { id: anim; target: t; property: "shown"; easing.type: Easing.Linear }
  Timer { id: fade; interval: 1700; onTriggered: t.recent = false }
  Timer { interval: 530; repeat: true; running: t.recent; onTriggered: t.blink = !t.blink }
  Text { id: ghost; width: parent.width; text: t.text; opacity: 0; wrapMode: Text.WordWrap; maximumLineCount: t.maxLines
    font.family: Theme.font; font.pixelSize: t.pixelSize; font.weight: t.weight }
  Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: t.maxLines; elide: Text.ElideRight
    text: t.text.substring(0, Math.floor(t.shown)) + ((t.recent && t.blink) ? "\u258D" : "")
    color: t.color; font.family: Theme.font; font.pixelSize: t.pixelSize; font.weight: t.weight; font.letterSpacing: t.pixelSize > 18 ? -0.4 : 0 }
}
