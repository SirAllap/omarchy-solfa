pragma Singleton
import QtQuick
// Qualified: a bare `Color` can resolve to a Qt builtin instead of the shell singleton.
import qs.Commons as Commons

// The calm palette of the approved mockup (mockups/redesign/Theme.qml),
// derived live from the shell theme (Commons.Color) so a light theme gets a
// light card with dark ink. Every token is a binding: a theme switch repaints
// without a restart. The graphite values are the fallback when the shell
// gives no colour.
QtObject {
  id: calm

  function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
  function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function mix(x, y, t) { return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, 1) }
  // WCAG contrast of ink over an opaque backdrop, so the panel's text follows the same >= 4.5:1
  // rule as the bar pill, on any theme (a mid-grey card reads with neither the theme's faint grey
  // text nor a 60 % muted ink).
  function _lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
  function _rl(c) { return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b) }
  function ratio(x, y) { var p = _rl(x), q = _rl(y); return (Math.max(p, q) + 0.05) / (Math.min(p, q) + 0.05) }
  function reads(ink, back) { return ratio(ink, back) >= 4.5 }
  function valid(c) { return c !== undefined && c !== null && c.a !== undefined }

  readonly property color darkSurface: Qt.rgba(0.082, 0.090, 0.106, 1)
  readonly property color darkFg: Qt.rgba(0.902, 0.910, 0.925, 1)
  readonly property color lightFg: Qt.rgba(0.102, 0.106, 0.122, 1)
  readonly property color darkAccent: Qt.rgba(0.561, 0.541, 0.659, 1)

  readonly property color _shellSurface: Commons.Color.popups && valid(Commons.Color.popups.background) ? Commons.Color.popups.background : darkSurface
  readonly property color _shellBg: valid(Commons.Color.background) ? Commons.Color.background : darkSurface
  // Opaque, whatever alpha the theme's popup colour has: it is blended over the
  // theme background and forced to alpha 1, so the card, pill and bridge never
  // show the desktop through.
  readonly property real _sa: _shellSurface.a
  readonly property color surface: Qt.rgba(_shellSurface.r * _sa + _shellBg.r * (1 - _sa), _shellSurface.g * _sa + _shellBg.g * (1 - _sa), _shellSurface.b * _sa + _shellBg.b * (1 - _sa), 1)
  readonly property bool light: lum(surface) > 0.5
  readonly property color ink: light ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
  readonly property color raised: mix(surface, ink, light ? 0.06 : 0.045)
  readonly property color bg: light ? mix(surface, ink, 0.1) : mix(surface, ink, -0.4)
  // Text: the shell's popup text when it reads on the card, else picked by luminance.
  readonly property color _shellText: Commons.Color.popups && valid(Commons.Color.popups.text) ? Commons.Color.popups.text : (light ? lightFg : darkFg)
  readonly property color fg: {
    var s = Qt.rgba(_shellText.r, _shellText.g, _shellText.b, 1)
    var cands = [s, light ? lightFg : darkFg, light ? darkFg : lightFg, Qt.rgba(0, 0, 0, 1), Qt.rgba(1, 1, 1, 1)]
    var best = cands[0]
    for (var i = 0; i < cands.length; i++) {
      if (reads(cands[i], surface)) return cands[i]
      if (ratio(cands[i], surface) > ratio(best, surface)) best = cands[i]
    }
    return best
  }
  // Secondary ink: fg at 60 %, raised only as far as it needs to keep 4.5:1 on the card.
  readonly property color muted: {
    for (var t = 0.6; t < 1; t += 0.05) { var m = mix(surface, fg, t); if (reads(m, surface)) return a(fg, t) }
    return fg
  }
  readonly property color _shellAccent: valid(Commons.Color.accent) ? Commons.Color.accent : darkAccent
  readonly property color _accent0: Math.abs(lum(_shellAccent) - lum(surface)) > 0.2 ? _shellAccent : (light ? mix(darkAccent, ink, 0.35) : darkAccent)
  // Accent as a fill or an icon/large glyph: the theme's own colour while it reaches 3:1 on the
  // card (WCAG non-text contrast); only below that is it moved toward the text colour, as little
  // as it takes. The hue is never changed otherwise.
  function _accentAt(min) {
    for (var t = 0; t <= 1.0001; t += 0.05) { var m = mix(_accent0, fg, t); if (ratio(m, surface) >= min) return m }
    return fg
  }
  readonly property color accent: _accentAt(3)
  // Accent as small TEXT (links, labels): 4.5:1 on the card.
  readonly property color accentText: _accentAt(4.5)
  // Ink on an accent fill (primary buttons, the active chip).
  readonly property color onAccent: lum(accent) > 0.5 ? Qt.rgba(0.051, 0.055, 0.067, 1) : Qt.rgba(1, 1, 1, 1)
  readonly property color hair: a(fg, light ? 0.14 : 0.075)
  // The liquid shape's one outer outline (pill + bridge + card): fg at 14-18 %, stronger on light.
  readonly property color outline: a(fg, light ? 0.18 : 0.14)
  readonly property color wash: a(fg, light ? 0.07 : 0.05)
  // The mockup's UI font; icons keep the shell's glyph font (they are not in Inter).
  readonly property string font: Qt.fontFamilies().indexOf("Inter") >= 0 ? "Inter" : ""
}
