# Solfa redesign mockup

A look at the whole Solfa UI, rebuilt as plain Qt Quick scenes with fake data. No engine, no
Quickshell imports, nothing here touches `Panel.qml`, `BarWidget.qml`, `views/` or `Service.qml`.

- Tokens: `Theme.qml`. Fake songs: `Fake.qml`.
- Parts: `Cover` (breathes with the music), `ProgressBar` (glow follows the head), `TabBar` (tabs morph, one pill glides on a spring),
  `TrackRow` / `GridCard` (slide in one after another), `Toggle`, `Slider`, `Select`, `Btn`, `IconButton` (springs on hover and press).
- Views: `QueueView`, `SearchView`, `LibraryView`, `LyricsView`, `HistoryView`, `DetailView`, `SettingsView`, `SignInCard`, `OffCard`, `BarPill`.
- `PanelFrame.qml` puts them together. `Scene02..Scene51.qml` and `BarScene.qml` are one state each;
  `Gallery.qml` is the contact sheet; `Demo.qml` is the animated tour.

## Render (offscreen only, no window is ever shown)

    ./render.sh [out-dir]       # every scene to a PNG (default ~/Documents/projects/agentglass/solfa-redesign)
    ./render-gif.sh [out.gif]   # the Demo scene, frame by frame, then ffmpeg

Both set `QT_QPA_PLATFORM=offscreen` and use Qt's `qml` tool on OpenGL. Needs `QT_FORCE_STDERR_LOGGING=1` to see QML errors.
Regenerate `qmldir` after adding a component: list every non-scene `.qml` file in it.

## Motion ideas (from a study of the MIT project HANCORE-linux/rumb)

Only ideas; no code or assets copied, so no MIT notice is needed.
Motion.qml holds the one reduce-motion switch, the decay constants, wave delays, smoothstep and seeded random.
Cover looks at the pressed control (spring), EventGlow, Comet, DotRing, Typewriter, WaveItem and MotionLab show each idea.

Open it from the repo root, no engine, fake data:

    qml mockups/redesign/Gallery.qml
    quickshell -p "$PWD/mockups/redesign/shell.qml"
