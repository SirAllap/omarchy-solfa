import QtQuick
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
  function pushSettings() {
    if (!root.svc) return
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
  readonly property bool showTitle: root.setting("showTitle", true) && (hasTrack || closed) && !vertical
  readonly property real maxLabelWidth: Number(root.setting("maxLabelWidth", 160)) || 160
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  // The bar is shared: the title only. Artist, album and time are in the tooltip.
  readonly property string label: svc && hasTrack ? svc.title : closed ? "Solfa" : ""

  visible: hasTrack || root.setting("showWhenIdle", true)
  implicitWidth: visible ? body.implicitWidth + Style.space(10) : 0
  implicitHeight: barSize

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
      ringColor: root.playing ? Color.accent : Util.alpha(root.fg, 0.45)
      trackColor: Util.alpha(root.fg, 0.15)
      source: root.svc ? root.svc.thumb : ""
      foreground: root.fg
      fill: root.hasTrack ? Util.alpha(root.fg, 0.08) : "transparent"
      fontFamily: root.family
      dim: root.hasTrack && !root.playing
      opacity: root.closed || (root.svc && (root.svc.ready || root.svc.hasTrack)) ? 1 : 0.55
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
        text: Icons.previous
        tooltipText: "Previous"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.previous() }
      }
      BarIconButton {
        bar: root.bar
        text: root.playing ? Icons.pause : Icons.play
        tooltipText: root.playing ? "Pause" : "Play"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.togglePlaying() }
      }
      BarIconButton {
        bar: root.bar
        text: Icons.next
        tooltipText: "Next"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.svc.next() }
      }
    }
  }

  // Clicks and wheel on the cover and the title (the buttons take their own).
  MouseArea {
    x: body.x
    y: 0
    width: coverSlot.width + (labelText.visible ? labelText.width + body.spacing : 0) + Style.space(5)
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
