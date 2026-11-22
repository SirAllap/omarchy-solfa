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
