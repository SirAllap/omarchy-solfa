pragma Singleton
import QtQuick

// Motion rules shared by every part. Ideas only, taken from a study of the
// MIT project HANCORE-linux/rumb (no code or assets copied).
QtObject {
  // One switch for everything: reduce motion. Springs, glows, comets, typing and loops all stop.
  property bool reduce: false
  // Decorations only run while the panel is open and music plays.
  property bool panelOpen: true
  property bool playing: true
  readonly property bool live: panelOpen && playing && !reduce
  readonly property real glowTau: 520     // ms, event glow fades like exp(-t/tau)
  readonly property real flashTau: 380    // ms, the short bright flash
  readonly property int typeMs: 30        // ms per letter
  readonly property int scrollMs: 180     // ms, smoothstep scroll of a lyric line
  readonly property int glanceMs: 520     // ms, a glance at a control, then back
  property int idleMs: 8000               // quiet time before the cover looks elsewhere

  // Priority waves: high 0 ms, medium 150 ms, low 300 ms.
  function wave(p) { return reduce ? 0 : [0, 150, 300][p] }
  function smooth(x) { x = Math.max(0, Math.min(1, x)); return x * x * (3 - 2 * x) }
  // Seeded noise: same seed, same number, so variation never shakes between frames.
  function hash(n) {
    var x = Math.imul(n | 0, 0x9E3779B9) >>> 0
    x = (x ^ (x >>> 16)) >>> 0; x = Math.imul(x, 0x85EBCA6B) >>> 0; x = (x ^ (x >>> 13)) >>> 0
    return x
  }
  function rand(n) { return hash(n) / 4294967295 }
  // The colour says what happened.
  function eventColor(kind) {
    return kind === "like" ? "#b08a99" : kind === "queue" ? Theme.ok : kind === "next" ? Theme.accent
      : kind === "error" ? Theme.err : "#8a9fb5"
  }
}
