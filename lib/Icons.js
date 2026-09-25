.pragma library

// Nerd Font (Material Design) glyphs, by name. Checked present in the
// Nerd Fonts Omarchy ships.
var play = String.fromCodePoint(0xF040A)
var pause = String.fromCodePoint(0xF03E4)
var next = String.fromCodePoint(0xF04AD)
var previous = String.fromCodePoint(0xF04AE)
var note = String.fromCodePoint(0xF075A)
var volume = String.fromCodePoint(0xF057E)
var volumeOff = String.fromCodePoint(0xF0581)
var heart = String.fromCodePoint(0xF02D1)
var heartOutline = String.fromCodePoint(0xF02D5)
var thumbDown = String.fromCodePoint(0xF0511)
var shuffle = String.fromCodePoint(0xF049D)
var repeat = String.fromCodePoint(0xF0456)
var repeatOff = String.fromCodePoint(0xF0457)
var repeatOnce = String.fromCodePoint(0xF0458)
var plus = String.fromCodePoint(0xF0415)
var playNext = String.fromCodePoint(0xF0412)
var close = String.fromCodePoint(0xF0156)
var power = String.fromCodePoint(0xF0425)
var search = String.fromCodePoint(0xF0349)
var radio = String.fromCodePoint(0xF0439)
var up = String.fromCodePoint(0xF005D)
var down = String.fromCodePoint(0xF0045)
var back = String.fromCodePoint(0xF0141)
var album = String.fromCodePoint(0xF0025)
var artist = String.fromCodePoint(0xF0803)
var mic = String.fromCodePoint(0xF036F)
var gear = String.fromCodePoint(0xF0493)
var chevronLeft = String.fromCodePoint(0xF0141)
var chevronRight = String.fromCodePoint(0xF0142)

function repeatIcon(mode) { return mode === "ONE" ? repeatOnce : mode === "ALL" ? repeat : repeatOff }
function volumeIcon(level, muted) { return muted || level === 0 ? volumeOff : volume }
