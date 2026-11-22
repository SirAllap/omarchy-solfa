.pragma library

// The small maths behind Solfa's motion. Ideas only: a spring that never
// jumps, glows that die away exponentially, smoothstep scrolling, waves by
// priority and seeded variation. No state; every function is pure.

var glowTau = 520      // ms: a glow fades as exp(-t / glowTau)
var flashTau = 380     // ms: the bright flash fades faster
var scrollMs = 180     // ms: smoothstep scroll of a lyric line
var typeMs = 30        // ms per letter of a new title or lyric line
var idleMs = 8000      // quiet time before the cover looks elsewhere

// 0 for high priority, 150 ms for medium, 300 ms for low.
function waveDelay(priority) { return priority <= 0 ? 0 : priority === 1 ? 150 : 300 }

// Open choreography (Panel 'tms' timeline, 0 to 600 ms): each part reads
// the one clock through ramp(), so it cannot stick half-way. The two
// cubic-bezier curves are the Material 3 expressive tokens.
function ramp(ms, delay, dur) { return Math.max(0, Math.min(1, (ms - delay) / dur)) }
function bez(x1, y1, x2, y2, t) {
  if (t <= 0) return 0
  if (t >= 1) return 1
  var lo = 0, hi = 1, s = t, u
  for (var i = 0; i < 18; i++) {
    u = 1 - s
    if (3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s < t) lo = s; else hi = s
    s = (lo + hi) / 2
  }
  u = 1 - s
  return 3 * u * u * s * y1 + 3 * u * s * s * y2 + s * s * s
}
function spatial(ms, delay, dur) { return bez(0.38, 1.21, 0.22, 1, ramp(ms, delay, dur)) }
function spatialClamped(ms, delay, dur) { return Math.min(1, spatial(ms, delay, dur)) }
function effects(ms, delay, dur) { return bez(0.34, 0.8, 0.34, 1, ramp(ms, delay, dur)) }

function smoothstep(x) { x = Math.max(0, Math.min(1, x)); return x * x * (3 - 2 * x) }
function decay(ageMs, tau) { return Math.exp(-Math.max(0, ageMs) / tau) }

// The same seed always gives the same number in [0, 1): no flicker between frames.
function rand(seed) {
  var x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453
  return x - Math.floor(x)
}

// Where the cover looks: a unit step of at most `reach` pixels toward (dx, dy).
function gaze(dx, dy, reach) {
  var L = Math.max(1, Math.hypot(dx, dy))
  return { x: dx / L * reach, y: dy / L * reach }
}
