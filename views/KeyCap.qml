import QtQuick
import qs.Commons
import "../lib"

// One key, drawn as a calm keycap: 20 px high, radius 5, Calm.raised with a
// hairline, the glyph centred on the cap by the font's own metrics (ascent
// and descent, not the line box), 11.5 px medium. Every key hint in Solfa
// (footer, "all keys" sheet, Settings, the off card) is built from this.
Rectangle {
  id: cap

  property string text: ""

  implicitHeight: Style.space(20)
  implicitWidth: Math.max(implicitHeight, glyph.implicitWidth + Style.space(10))
  radius: Style.space(5)
  color: Calm.raised
  border.width: 1
  border.color: Calm.hair

  FontMetrics {
    id: fm
    font: glyph.font
  }

  Text {
    id: glyph
    // The font's own metrics, not the line box: the baseline goes where the
    // middle of the letters (between the x-height and the capital height) meets
    // the middle of the cap, so "esc", "R" and "n" all look centred.
    x: Math.round((cap.width - width) / 2)
    y: Math.round(cap.height / 2 + (fm.capitalHeight + fm.xHeight) / 4 - fm.ascent)
    width: implicitWidth
    height: Math.ceil(fm.ascent + fm.descent)
    verticalAlignment: Text.AlignTop
    topPadding: 0
    bottomPadding: 0
    text: cap.text
    textFormat: Text.PlainText
    color: Calm.fg
    font.family: Calm.font
    font.weight: Font.Medium
    // 11.5 px: Qt's pixelSize is whole, so the size goes in points (1 px = 0.75 pt).
    font.pointSize: Style.space(11.5) * 0.75
  }
}
