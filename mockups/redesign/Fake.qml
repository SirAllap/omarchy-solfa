pragma Singleton
import QtQuick

// Made-up songs and lines. Nothing here is a real artist or a real account.
QtObject {
  readonly property var tracks: [
    { t: "Glass Harbour", a: "Nova Reyes", al: "Low Tide Radio", d: "3:42", seed: 0 },
    { t: "Paper Lanterns", a: "The Quiet Meridian", al: "Small Hours", d: "4:08", seed: 1 },
    { t: "Static Bloom", a: "Orla Vance", al: "Static Bloom", d: "2:57", seed: 2 },
    { t: "Seventeen Windows", a: "Kite & Compass", al: "Seventeen Windows", d: "3:21", seed: 3 },
    { t: "Slow Neon", a: "Hollow Parade", al: "Afterglow", d: "5:03", seed: 4 },
    { t: "Velvet Static", a: "Mira Okafor", al: "Weather Maps", d: "3:36", seed: 5 },
    { t: "North of Anywhere", a: "Dune Choir", al: "Long Light", d: "4:44", seed: 6 },
    { t: "Tin Moon", a: "Nova Reyes", al: "Low Tide Radio", d: "3:15", seed: 7 }
  ]
  readonly property var lyrics: [
    "The harbour lights go soft and low",
    "I count the boats that never leave",
    "Every wave a thing I almost said",
    "Every tide a door I left ajar",
    "So hold the glass up to the sky",
    "And let the evening do the rest",
    "We were never lost, just slow",
    "Just learning how the water goes",
    "Stay a little, stay a little more",
    "The night is made of what we keep"
  ]
  readonly property var playlists: [
    { t: "Late Night Drive", n: "48 songs", seed: 3 }, { t: "Focus Flow", n: "112 songs", seed: 5 },
    { t: "Morning Light", n: "36 songs", seed: 1 }, { t: "Rainy Day Mix", n: "64 songs", seed: 6 },
    { t: "Road Trip", n: "90 songs", seed: 2 }, { t: "Deep Cuts", n: "27 songs", seed: 7 }
  ]
  readonly property var artists: [
    { t: "Nova Reyes", n: "2.4M listeners", seed: 0 }, { t: "Orla Vance", n: "810K listeners", seed: 2 },
    { t: "Dune Choir", n: "1.1M listeners", seed: 6 }, { t: "Mira Okafor", n: "530K listeners", seed: 5 }
  ]
}
