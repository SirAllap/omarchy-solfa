.pragma library
// The calm palette of the approved mockup (mockups/redesign/Theme.qml):
// graphite surfaces and one muted violet accent. The views use these instead
// of the shell theme's colours, so the panel looks the same on every theme.
var bg = Qt.rgba(0.051, 0.055, 0.067, 1)
var surface = Qt.rgba(0.082, 0.090, 0.106, 1)
var raised = Qt.rgba(0.118, 0.129, 0.149, 1)
var fg = Qt.rgba(0.902, 0.910, 0.925, 1)
var accent = Qt.rgba(0.561, 0.541, 0.659, 1)
var hair = Qt.rgba(1, 1, 1, 0.075)
var wash = Qt.rgba(1, 1, 1, 0.05)
// The mockup's UI font; icons keep the shell's glyph font (they are not in Inter).
// Inter when installed; otherwise "" so Qt uses the theme (shell) font.
var font = Qt.fontFamilies().indexOf("Inter") >= 0 ? "Inter" : ""
function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
