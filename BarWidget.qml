import QtQuick
import QtQuick.Shapes
import "lib"
import qs.Ui
import qs.Commons
import "lib/Model.js" as Model
import "lib/Icons.js" as Icons
import "views" as Views

// The bar pill: a round cover in a progress ring, the song, and previous /
// play-pause / next. Left click opens the panel, middle click plays or
// pauses, right click skips, the wheel sets the volume (Shift+wheel seeks).
BarWidget {
  id: root
  moduleName: "io.github.sirallap.solfa"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("io.github.sirallap.solfa") : null

  // The service reads its settings from this widget's shell.json entry,
  // and saves new ones back through the shell's plugin API (Settings).
  // The shell assigns this widget's `bar` before its `settings`, so for a
  // moment `settings` is still the empty default: that is not an entry, and
  // the service must never see it (it would start the engine on defaults).
  function pushSettings() {
    if (!root.svc || !root.bar || !Model.hasSettings(root.settings)) return
    if (typeof root.svc.adoptSettings === "function") root.svc.adoptSettings(root.settings)
    else root.svc.settings = root.settings
    root.svc.shell = root.bar ? root.bar.shell : null
  }
  onSvcChanged: { pushSettings(); injectPanel() }
  onSettingsChanged: { pushSettings(); injectPanel() }
  onBarChanged: { pushSettings(); injectPanel() }
  Component.onCompleted: pushSettings()

  // ---- the shape Bar.findPanelWidget expects (shell summon/hide/toggle)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var p = panelLoader.item
    if (!p) return
    p.bar = root.bar
    p.settings = root.settings
    p.anchorItem = root
    p.hostWidget = root
    p.svc = root.svc
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // ---- state
  readonly property bool hasTrack: svc ? svc.hasTrack : false
  // Closed: Solfa's mark and name, dimmed, and nothing else. Any click
  // starts it again (a left click also opens the panel).
  readonly property bool closed: svc ? svc.closed : false
  readonly property bool playing: svc ? svc.isPlaying : false
  readonly property bool showControls: root.setting("barControls", true) && hasTrack && !vertical
  readonly property bool signingIn: svc ? svc.signingIn : false
  readonly property bool showTitle: root.setting("showTitle", true) && (hasTrack || closed || signingIn) && !vertical
  readonly property real maxLabelWidth: Number(root.setting("maxLabelWidth", 160)) || 160
  // The pill is painted with Calm.surface, not the bar's colour, so its ink is Calm.fg / Calm.muted
  // (chosen by the surface's luminance): the bar's own foreground is white on a dark bar
  // and invisible on a light pill, and the other way round.
  readonly property color fg: restInk ? restPlan.ink : Calm.fg
  readonly property string family: Calm.font
  // The bar is shared: the title only. Artist, album and time are in the tooltip.
  readonly property string label: signingIn ? "Signing in…" : svc && hasTrack ? svc.title : closed ? "Solfa" : ""

  visible: hasTrack || root.setting("showWhenIdle", true)
  // Even padding: the pill's side padding equals the gap above and below the cover.
  readonly property real pillHeight: Math.min(height, barSize) - Style.space(4)
  // Pill look (a design option, default "hover"):
  //   solid   - Calm.surface fill, as before
  //   outline - no fill, only the hairline (Calm.outline)
  //   tint    - the bar colour mixed 8% toward the ink, no outline
  //   glass   - Calm.surface at 55% alpha over the bar, plus the hairline
  //   hover   - no fill when idle; the tint only on hover (and the panel, below, keeps the join)
  property string pillStyle: "hover"
  readonly property color barBg: Color.bar && Calm.valid(Color.bar.background) ? Color.bar.background : Calm.bg
  readonly property color pillTint: Qt.rgba(barBg.r + (Calm.fg.r - barBg.r) * 0.08, barBg.g + (Calm.fg.g - barBg.g) * 0.08, barBg.b + (Calm.fg.b - barBg.b) * 0.08, barBg.a)
  readonly property bool pillHot: barMouse.containsMouse || root.opened

  // The bar as the shell really paints it (plugins/bar/Bar.qml:1838): its colour is
  // Commons.Color.bar.background (Color.qml:80, theme alpha in) = barBg; the setting
  // shell.json bar.background (opaque | glassy | none, the facade's shell.barConfig, live)
  // makes a glassy bar min(alpha, 0.35) (Bar.qml:89) and a none bar clear (bar.transparent).
  readonly property string barLook: {
    if (bar && bar.transparent === true) return "none"
    var c = bar && bar.shell ? bar.shell.barConfig : null
    if (c && c.background) return String(c.background)
    return c && c.transparent === true ? "none" : "opaque"
  }
  readonly property real barAlpha: barLook === "none" ? 0 : barLook === "glassy" ? Math.min(barBg.a, 0.35) : barBg.a
  readonly property bool barSeeThrough: barAlpha < 0.95

  // At rest ("hover" look) the pill has no fill, so on a see-through bar the title and icons sit
  // on the wallpaper. The soft backdrop is the bar colour at alpha >= 0.72, raised only as far as
  // the ink needs to keep 4.5:1 over the worst wallpapers (white, black, mid-pink). The ink is
  // the theme's text when it reads on that backdrop, else black or white, whichever reads better.
  function _lin(c) { return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  function _rl(r, g, b) { return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b) }
  function _worst(ink, c, a) {
    var walls = [[1, 1, 1], [0, 0, 0], [0.91, 0.44, 0.63]]
    var li = _rl(ink.r, ink.g, ink.b), worst = 99
    for (var i = 0; i < walls.length; i++) {
      var lb = _rl(c.r * a + walls[i][0] * (1 - a), c.g * a + walls[i][1] * (1 - a), c.b * a + walls[i][2] * (1 - a))
      worst = Math.min(worst, (Math.max(li, lb) + 0.05) / (Math.min(li, lb) + 0.05))
    }
    return worst
  }
  function _plan(c, barA, seeThrough, themeInk) {
    var a = seeThrough ? Math.max(barA, 0.72) : barA
    var cands = [themeInk, Calm.lightFg, Calm.darkFg]
    for (;;) {
      var best = cands[0], bw = seeThrough ? _worst(cands[0], c, a) : _opaqueRatio(cands[0], c)
      if (bw < 4.5) {
        for (var i = 1; i < cands.length; i++) {
          var wv = seeThrough ? _worst(cands[i], c, a) : _opaqueRatio(cands[i], c)
          if (wv > bw) { best = cands[i]; bw = wv }
        }
      }
      if (bw >= 4.5 || !seeThrough || a >= 1) return { alpha: a, ink: best, ratio: bw }
      a = Math.min(1, a + 0.04)
    }
  }
  function _opaqueRatio(ink, c) {
    var li = _rl(ink.r, ink.g, ink.b), lb = _rl(c.r, c.g, c.b)
    return (Math.max(li, lb) + 0.05) / (Math.min(li, lb) + 0.05)
  }
  readonly property var restPlan: _plan(barBg, barAlpha, barSeeThrough, Calm.fg)
  // The rest look of the "hover" style: its ink and its backdrop follow the bar. Hover and open
  // keep the surface-based colours.
  readonly property bool restInk: pillStyle === "hover" && !pillHot
  readonly property bool restBackdrop: restInk && barSeeThrough
  // While the panel is open every style fills with Calm.surface: the card and the bridge are that
  // colour, and the pill must join them without a seam.
  readonly property color pillFill: root.opened ? Calm.surface
    : pillStyle === "outline" ? "transparent"
    : pillStyle === "tint" ? pillTint
    : pillStyle === "glass" ? Calm.a(Calm.surface, 0.55)
    : pillStyle === "hover" ? (pillHot ? pillTint : restBackdrop ? Calm.a(barBg, restPlan.alpha) : "transparent")
    : Calm.surface
  readonly property bool pillOutlined: !root.opened && (pillStyle === "outline" || pillStyle === "glass")
  readonly property real pillPad: Math.max(4, Math.round((pillHeight - coverSlot.height) / 2))
  implicitWidth: visible ? body.implicitWidth + 2 * pillPad : 0
  implicitHeight: barSize
  // The shell underlines a widget whose panel is open. Solfa shows that state
  // with a lighter pill instead, so the mark is pointed at an item far
  // outside the bar, where it is never seen.
  readonly property Item openPanelIndicatorItem: offMark
  Item { id: offMark; x: -100000; width: 1; height: 1 }

  // The pill's drawn box, snapped to whole pixels so the fill, the squared-off half and
  // the outline share one edge (a half-pixel offset between them showed as a seam or a
  // double line). Panel.qml reads pillBoxX/Y/W/H to put the bridge on the same box.
  readonly property real pillBoxW: Math.round(body.implicitWidth + 2 * pillPad)
  readonly property real pillBoxH: Math.round(pillHeight)
  readonly property real pillBoxX: Math.round((width - pillBoxW) / 2)
  readonly property real pillBoxY: Math.round((height - pillBoxH) / 2)

  // The widget is a quiet pill. One colour for pill, bridge and card: the same opaque
  // Calm.surface binding, no animation, tint or alpha of its own, so the three never
  // differ by a shade.
  Rectangle {
    x: root.pillBoxX
    y: root.pillBoxY
    width: root.pillBoxW
    height: root.pillBoxH
    radius: height / 2
    visible: !root.closed
    // One colour for pill, bridge and card: the same opaque Calm.surface binding, no
    // animation, tint or alpha of its own, so the three never differ by a shade.
    color: root.pillFill
    border.width: root.pillOutlined ? 1 : 0
    border.color: Calm.outline
  }
  // While the panel is open the pill opens straight down into the card: its bottom half
  // is squared off (same colour), so the bridge's curves start at the pill's two ends.
  // It starts at the pill's middle line, never above it, so the round top ends stay round.
  Rectangle {
    visible: root.opened && !root.closed
    x: root.pillBoxX
    y: root.pillBoxY + Math.floor(root.pillBoxH / 2)
    width: root.pillBoxW
    height: root.pillBoxH - Math.floor(root.pillBoxH / 2)
    color: Calm.surface
  }
  // The pill's part of the one outer hairline: up the left side, over the rounded top,
  // down the right side. No line along the bottom: the bridge continues the contour
  // from the two ends. Its top ends are the same quarter circles as the fill's.
  Shape {
    id: pillRing
    readonly property real r: height / 2 - 0.5
    visible: root.opened && !root.closed
    x: root.pillBoxX
    y: root.pillBoxY
    width: root.pillBoxW
    height: root.pillBoxH
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: true
    layer.samples: 8
    ShapePath {
      fillColor: "transparent"
      strokeColor: Calm.outline
      strokeWidth: 1
      startX: 0.5; startY: pillRing.height
      PathLine { x: 0.5; y: pillRing.r + 0.5 }
      PathArc { x: pillRing.r + 0.5; y: 0.5; radiusX: pillRing.r; radiusY: pillRing.r }
      PathLine { x: pillRing.width - pillRing.r - 0.5; y: 0.5 }
      PathArc { x: pillRing.width - 0.5; y: pillRing.r + 0.5; radiusX: pillRing.r; radiusY: pillRing.r }
      PathLine { x: pillRing.width - 0.5; y: pillRing.height }
    }
  }

  Row {
    id: body
    anchors.centerIn: parent
    spacing: Style.space(6)
    opacity: root.closed ? 0.45 : 1
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Views.BarCover {
      id: coverSlot
      anchors.verticalCenter: parent.verticalCenter
      barSize: root.barSize
      hasTrack: root.hasTrack
      progress: root.svc ? root.svc.progress : 0
      ringColor: root.playing ? Calm.accent : (root.restInk ? Calm.a(root.fg, 0.6) : Calm.muted)
      trackColor: root.restBackdrop ? Calm.a(root.fg, 0.2) : Calm.hair
      source: root.svc ? root.svc.thumb : ""
      foreground: root.fg
      fill: root.hasTrack ? Util.alpha(root.fg, 0.08) : "transparent"
      fontFamily: root.family
      dim: root.hasTrack && !root.playing
      // idle: an album; off: the power mark (as in the mockup)
      glyph: root.closed ? Icons.power : Icons.album
      opacity: root.closed || (root.svc && (root.svc.ready || root.svc.hasTrack)) ? 1 : 0.55

      // While a sign-in runs (the panel closes when the Google window is
      // used), the bar's icon breathes: something is happening.
      transformOrigin: Item.Center
      SequentialAnimation on scale {
        loops: Animation.Infinite
        running: root.signingIn
        onRunningChanged: if (!running) coverSlot.scale = 1
        NumberAnimation { from: 0.85; to: 1.1; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.1; to: 0.85; duration: 1400; easing.type: Easing.InOutSine }
      }
    }

    Text {
      id: labelText
      visible: root.showTitle
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(root.maxLabelWidth, implicitWidth)
      text: root.label
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.fg
      font.family: root.family
      font.pixelSize: Style.font.body
    }

    Row {
      visible: root.showControls
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      BarIconButton {
        bar: root.bar
        foreground: root.fg
        text: Icons.previous
        tooltipText: "Previous"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.previous() }
      }
      BarIconButton {
        bar: root.bar
        foreground: root.fg
        text: root.playing ? Icons.pause : Icons.play
        tooltipText: root.playing ? "Pause" : "Play"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.togglePlaying() }
      }
      BarIconButton {
        bar: root.bar
        foreground: root.fg
        text: Icons.next
        tooltipText: "Next"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.next() }
      }
    }
  }

  // Clicks and wheel on the cover and the title (the buttons take their own).
  MouseArea {
    id: barMouse
    x: body.x
    y: 0
    width: coverSlot.width + (labelText.visible ? labelText.width + body.spacing : 0) + root.pillPad
    height: parent.height
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    property real wheelAcc: 0

    onClicked: function (mouse) {
      if (root.closed) {
        root.svc.startEngine()
        if (mouse.button === Qt.LeftButton) root.toggle()
        return
      }
      if (mouse.button === Qt.MiddleButton) { if (root.svc) root.svc.togglePlaying() }
      else if (mouse.button === Qt.RightButton) { if (root.svc) root.svc.next() }
      else root.toggle()
    }
    onWheel: function (wheel) {
      if (!root.svc || !root.hasTrack) return
      var w = Util.wheelSteps(wheelAcc, wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x)
      wheelAcc = w.remainder
      if (w.steps === 0) return
      if (wheel.modifiers & Qt.ShiftModifier) root.svc.seekBy(w.steps * 5)
      else root.svc.nudgeVolume(w.steps)
    }
    onEntered: {
      if (!root.bar) return
      var s = root.svc
      var tip = s && s.hasTrack
        ? s.title + (s.artist ? "\n" + s.artist : "") + (s.album ? "\n" + s.album : "")
          + "\n" + Model.fmtTime(s.position) + " of " + Model.fmtTime(s.duration) + ", volume " + (s.muted ? "muted" : s.volume + "%")
        : s && s.closed ? "Solfa is off. Click to turn it on."
        : (s ? (s.engineLine || "Nothing playing. Click to search.") : "Solfa")
      root.bar.showTooltip(root, tip)
    }
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
