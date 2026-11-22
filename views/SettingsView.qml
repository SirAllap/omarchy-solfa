import QtQuick
import "../lib/Calm.js" as Calm
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model

// The Settings view: replaces the panel body (Panel.qml puts it in `stage`,
// same place as Queue/Search/Library/Lyrics). Left column = sections, right
// column = that section's rows. Keyboard: ↑↓ move (sections in the left
// column, rows in the right), ←→ change a row's value, Tab switches
// column, Enter acts (same as ←→ for a stepper, toggles a switch, runs a
// button), Esc goes back (handled by Panel, which owns "?" too).
//
// Every section here is real: bound to real settings (svc.saveSetting),
// and Account/Sound reach the bridge for real (account.info/signout, the
// agent's WebAudio EQ graph). Audio quality (bitrate/codec) is out of
// scope and not built.
Item {
  id: root

  property var svc: null
  property color fg: Color.foreground
  property string family: Style.font.family
  // A calm, muted red for what destroys data (not the shell's loud urgent red).
  readonly property color dangerColor: "#c4727f"

  signal backRequested()
  signal showAllKeys()

  readonly property var sections: [
    { key: "account", label: "Account", icon: "user" },
    { key: "sound", label: "Sound", icon: "volume" },
    { key: "playback", label: "Playback", icon: "play" },
    { key: "bar", label: "Bar and alerts", icon: "bolt" },
    { key: "keys", label: "Keys", icon: "keyboard" },
    { key: "advanced", label: "Advanced", icon: "gear" },
    { key: "about", label: "About", icon: "album" }
  ]
  readonly property string sectionLabel: root.sections[root.navIndex].label
  // The one open dropdown (its pill), or null. The menu itself is drawn at
  // the bottom of this file, above everything, so no row's clip cuts it.
  property var menuSrc: null
  function closeMenu() { root.menuSrc = null }
  property int navIndex: 0
  readonly property string section: root.sections[root.navIndex].key
  // "nav" (left column has the cursor) or "content" (right column does).
  property string column: "content"
  property int cursor: 0
  // True once the keyboard has moved (arrow, Tab): only then is the row under
  // the cursor filled. Opening Settings, or a click, leaves every row flat.
  property bool kbd: false
  // Handlers for the current section's rows, in the same order they are
  // drawn: { change(dir), act(), toggle() } — a row supplies whichever it
  // needs; move()/change()/act() below call through them.
  property var handlers: []

  // The mockup's narrow icon rail (no text menu): the room it leaves is what
  // lets all 10 EQ bands fit in a 460 px panel.
  readonly property real railWidth: Style.space(52)

  // ---- transient, per-open UI state (never persisted) -------------------

  property string accountNote: ""
  // Two-step confirms (Switch account, Sign out, Erase): one Enter arms,
  // the next one on the same row runs it. Anything else disarms: moving the
  // cursor, changing column or section, the view going away (the panel
  // closed), or armTimeoutMs with no second Enter.
  property bool switchArmed: false
  property bool signOutArmed: false
  property bool eraseArmed: false
  // A setting read that survives a null service (load and teardown).
  function settingOr(key, fallback) { return root.svc ? root.svc.setting(key, fallback) : fallback }
  readonly property int armTimeoutMs: 5000
  readonly property bool armTimerRunning: armTimer.running
  function disarm() {
    root.closeMenu()
    root.switchArmed = false
    root.signOutArmed = false
    root.eraseArmed = false
  }
  Timer {
    id: armTimer
    interval: root.armTimeoutMs
    running: root.switchArmed || root.signOutArmed || root.eraseArmed
    onTriggered: root.disarm()
  }
  onCursorChanged: root.disarm()
  onColumnChanged: root.disarm()
  onVisibleChanged: { root.kbd = false; if (!root.visible) root.disarm() }
  property string cacheNote: ""
  property string eraseNote: ""
  property string engineVersionText: ""
  // "Chrome/155.0.8059.84" -> "Chromium 155"; anything else shows as it came.
  function engineLabel(s) {
    var m = /Chrome\/(\d+)/.exec(s || "")
    return m ? "Chromium " + m[1] : s
  }

  function rebuildHandlers() {
    root.kbd = false
    root.cursor = 0
    root.handlers = root.buildHandlers(root.section)
  }
  onSectionChanged: {
    root.disarm()
    root.accountNote = ""
    root.cacheNote = ""
    root.eraseNote = ""
    root.rebuildHandlers()
    if (root.section === "about" && root.svc) {
      root.engineVersionText = "…"
      root.svc.engineVersion(function (r) { root.engineVersionText = r.ok ? r.data.product : "not running" })
    }
    if (root.section === "account" && root.svc && root.svc.signedIn) root.svc.accountInfo(function () {})
  }
  Component.onCompleted: root.rebuildHandlers()

  // Playback has one more row (Brave's ad blocker) while the engine is
  // Brave; the cursor stays where it was when that row comes or goes.
  readonly property bool braveEngine: root.svc ? Model.isBraveBrowser(root.svc.setting("browser", "")) : false
  onBraveEngineChanged: {
    if (root.section !== "playback") return
    var at = root.cursor
    root.handlers = root.buildHandlers(root.section)
    root.cursor = Math.min(at, Math.max(0, root.handlers.length - 1))
  }

  // Account shows one action signed out and two signed in, so its rows
  // (and the keyboard's) follow the sign-in state, however it changes.
  readonly property bool signedIn: root.svc ? root.svc.signedIn === true : false
  onSignedInChanged: {
    if (root.section !== "account") return
    root.disarm()
    root.rebuildHandlers()
    if (root.signedIn && root.svc) root.svc.accountInfo(function () {})
  }

  // ---- keyboard API, called by Panel.qml ---------------------------------

  function move(dir) {
    root.kbd = true
    if (root.column === "nav") {
      root.navIndex = (root.navIndex + dir + root.sections.length) % root.sections.length
    } else if (root.handlers.length > 0) {
      root.cursor = (root.cursor + dir + root.handlers.length) % root.handlers.length
    }
  }
  function change(dir) {
    if (root.column !== "content") return
    var h = root.handlers[root.cursor]
    if (!h) return
    if (h.toggle) h.toggle()
    else if (h.change) h.change(dir)
  }
  function act() {
    if (root.column === "nav") { root.kbd = true; root.column = "content"; root.cursor = 0; return }
    var h = root.handlers[root.cursor]
    if (!h) return
    if (h.act) h.act()
    else if (h.toggle) h.toggle()
    else if (h.change) h.change(1)
  }
  function switchColumn() { root.kbd = true; root.column = root.column === "nav" ? "content" : "nav" }

  // ---- pointer API: a click is the keyboard's cursor move plus its key ----
  // Every row routes its click through the same handlers the keyboard uses,
  // so a click and an Enter can never disagree (the two-step confirms
  // included: a second click on an armed row runs it, like a second Enter).

  function pointAt(i) { root.kbd = false; root.column = "content"; root.cursor = i }
  function clickRow(i) { root.pointAt(i); root.act() }
  function stepRow(i, dir) { root.pointAt(i); root.change(dir) }

  // ---- handlers per section ----------------------------------------------

  function buildHandlers(sec) {
    var svc = root.svc
    if (!svc) return []
    switch (sec) {
      case "account": return svc.signedIn ? [
        { act: function () { root.actSwitch() } },
        { act: function () { root.actSignOut() } }
      ] : [
        { act: function () { root.actSignIn() } }
      ]
      case "sound": {
        var bandHandlers = []
        for (var i = 0; i < 10; i++) (function (idx) {
          bandHandlers.push({ change: function (dir) { root.stepBand(idx, dir) } })
        })(i)
        return [
          { toggle: function () { svc.saveSetting("eqEnabled", !svc.setting("eqEnabled", false)) } },
          { change: function (dir) { root.stepEqPreset(dir) }, act: function () { root.stepEqPreset(1) } }
        ]
          .concat(bandHandlers)
          .concat([
            { change: function (dir) { svc.saveSetting("eqPreamp", Model.stepNumber(svc.setting("eqPreamp", 0), dir, -12, 0)) } },
            { toggle: function () { svc.saveSetting("eqLoudness", !svc.setting("eqLoudness", false)) } },
            { change: function (dir) { svc.nudgeSleepMode(dir) }, act: function () { svc.nudgeSleepMode(1) } }
          ])
      }
      case "playback": return [
        { toggle: function () { svc.saveSetting("startPaused", !svc.setting("startPaused", false)) } },
        { change: function (dir) { svc.saveSetting("startVolume", Model.cycleList(["last", "25", "50", "75", "100"], String(svc.setting("startVolume", "last")), dir)) } },
        { toggle: function () { svc.saveSetting("autostart", !svc.setting("autostart", true)) } },
        { change: function (dir) { svc.saveSetting("browser", Model.cycleList(Model.browserChoices(svc.browsers, svc.setting("browser", "")), svc.setting("browser", ""), dir)) } }
      ].concat(root.braveEngine ? [
        { toggle: function () { svc.saveSetting("braveAdBlock", !svc.setting("braveAdBlock", false)) } }
      ] : [])
      case "bar": return [
        { toggle: function () { svc.saveSetting("barControls", !svc.setting("barControls", true)) } },
        { toggle: function () { svc.saveSetting("showTitle", !svc.setting("showTitle", true)) } },
        { change: function (dir) { svc.saveSetting("maxLabelWidth", Model.stepNumber(svc.setting("maxLabelWidth", 160), dir * 20, 80, 400)) } },
        { toggle: function () { svc.saveSetting("showWhenIdle", !svc.setting("showWhenIdle", true)) } },
        { toggle: function () { svc.saveSetting("notify", !svc.setting("notify", true)) } }
      ]
      case "keys": return [
        { toggle: function () { svc.saveSetting("globalKeys", !svc.setting("globalKeys", true)) } },
        { act: function () { root.showAllKeys() } }
      ]
      case "advanced": return [
        { change: function (dir) { svc.saveSetting("recycleHeapMb", Model.stepNumber(Model.recycleHeapMbFor(svc.setting("recycleHeapMb", 400)), dir * 50, Model.RECYCLE_HEAP_MB_RANGE[0], Model.RECYCLE_HEAP_MB_RANGE[1])) } },
        { change: function (dir) { svc.saveSetting("recycleHours", Model.stepNumber(Model.recycleHoursFor(svc.setting("recycleHours", 12)), dir, Model.RECYCLE_HOURS_RANGE[0], Model.RECYCLE_HOURS_RANGE[1])) } },
        { toggle: function () { svc.saveSetting("reduceMotion", !svc.setting("reduceMotion", false)) } },
        { act: function () { root.cacheNote = "Clearing…"; svc.clearCache(function (r) { root.cacheNote = r.ok ? "Cleared" : "Could not clear the cache" }) } },
        { act: function () { svc.resetSettings() } },
        { act: function () { root.actErase() } }
      ]
      case "about": return []
      default: return []
    }
  }

  function stepEqPreset(dir) {
    root.setEqPreset(Model.cycleList(Model.EQ_PRESET_ORDER, root.svc.setting("eqPreset", "flat"), dir))
  }
  function setEqPreset(key) {
    var svc = root.svc
    svc.saveSetting("eqPreset", key)
    if (key !== "custom") svc.saveSetting("eqBands", JSON.stringify(Model.eqBandsFor(key, null)))
  }
  function stepBand(index, dir) {
    var bands = root.currentBands()
    root.setBand(index, Model.stepNumber(bands[index], dir, -12, 12))
  }
  function setBand(index, db) {
    var svc = root.svc
    var bands = root.currentBands().slice()
    var next = Math.max(-12, Math.min(12, Math.round(db)))
    // A drag lands on the same whole dB many times over; save only a change.
    if (bands[index] === next && svc.setting("eqPreset", "flat") === "custom") return
    bands[index] = next
    svc.saveSetting("eqBands", JSON.stringify(bands))
    svc.saveSetting("eqPreset", "custom")
  }
  function actErase() {
    if (!root.eraseArmed) { root.disarm(); root.eraseArmed = true; return }
    root.eraseArmed = false
    root.cacheNote = ""
    root.eraseNote = "Erasing…"
    root.svc.eraseProfile(function (r) { root.eraseNote = r.ok ? "Erased; starting clean" : Model.errorText(r.error) })
  }
  function actSwitch() {
    if (!root.switchArmed) { root.disarm(); root.switchArmed = true; return }
    root.switchArmed = false
    root.accountNote = "Switching…"
    root.svc.accountSwitch(function (r) { root.accountNote = r.ok ? "" : Model.errorText(r.error) })
  }
  // Two-letter fallback for the round avatar when there is no picture.
  function initialsFor(name) {
    if (!name) return "?"
    var parts = name.trim().split(/\s+/)
    var first = parts[0] ? parts[0][0] : ""
    var last = parts.length > 1 ? parts[parts.length - 1][0] : ""
    return String(first + last).toUpperCase() || "?"
  }
  function actSignIn() {
    root.accountNote = ""
    root.svc.signIn()
  }
  function actSignOut() {
    if (!root.signOutArmed) { root.disarm(); root.signOutArmed = true; return }
    root.signOutArmed = false
    root.accountNote = "Signing out…"
    root.svc.accountSignOut(function (r) { root.accountNote = r.ok ? "" : Model.errorText(r.error) })
  }

  // Bands shown for the current preset (or the custom bands themselves).
  function currentBands() {
    var svc = root.svc
    if (!svc) return Model.EQ_PRESETS.flat
    var preset = svc.setting("eqPreset", "flat")
    if (preset === "custom") return Model.parseEqBands(svc.setting("eqBands", Model.SETTINGS_DEFAULTS.eqBands))
    return Model.eqBandsFor(preset, null)
  }

  // ---- reusable pieces (same tokens as the rest of the panel) -----------

  component RowShell: Item {
    id: rowShell
    property color fg: root.fg
    property string family: root.family
    property string label: ""
    property string help: ""
    property color labelColor: fg
    // The row's index in its section's handlers: the keyboard cursor lands
    // on it, and a click anywhere on the row runs it.
    property int row: -1
    readonly property bool focused: row >= 0 && root.kbd && root.column === "content" && root.cursor === row
    width: parent ? parent.width : 0
    // Grows with a wrapped help line. A fixed height with the text centred
    // on it pushed a two-line help's title above the row's top, where the
    // content's clip cut it off.
    height: Math.max(Style.space(50), rowText.implicitHeight + Style.space(12))
    default property alias controlChildren: controlSlot.children

    // Hairline between rows (calm list, no boxes).
    Rectangle {
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      height: 1
      color: Util.alpha(rowShell.fg, 0.08)
    }
    Rectangle {
      anchors.fill: parent
      radius: Style.space(10)
      color: rowShell.focused ? Calm.a(Calm.accent, 0.12) : "transparent"
    }

    // Below the controls, so a control with its own pointer handling (a
    // stepper's arrows) gets the click first.
    MouseArea {
      id: rowHover
      anchors.fill: parent
      enabled: rowShell.row >= 0
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.clickRow(rowShell.row)
    }

    Column {
      id: rowText
      objectName: "rowText"
      anchors.left: parent.left
      anchors.right: controlSlot.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: rowShell.label
        textFormat: Text.PlainText
        color: rowShell.labelColor
        font.family: rowShell.family
        font.pixelSize: Style.space(14)
      }
      Text {
        visible: rowShell.help !== ""
        width: parent.width
        text: rowShell.help
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Util.alpha(rowShell.fg, 0.5)
        font.family: rowShell.family
        font.pixelSize: Style.space(12)
      }
    }

    Row {
      id: controlSlot
      anchors.right: parent.right
      anchors.rightMargin: 1
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
    }
  }

  component MiniToggle: Rectangle {
    id: toggle
    property color fg: root.fg
    property bool active: false
    // Mockup Toggle: 44x26, 20 px knob 3 px in; the on state is a solid accent
    // with no outline, the off state a wash with one hairline.
    width: Style.space(44)
    height: Style.space(26)
    radius: height / 2
    color: active ? Calm.accent : Calm.a(Qt.rgba(1, 1, 1, 1), 0.1)
    border.width: active ? 0 : 1
    border.color: Calm.hair
    Rectangle {
      width: parent.height - Style.space(6)
      height: width
      radius: width / 2
      color: toggle.active ? "white" : Util.alpha(toggle.fg, 0.64)
      anchors.verticalCenter: parent.verticalCenter
      x: toggle.active ? parent.width - width - Style.space(3) : Style.space(3)
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
  }

  // A pill with a value and a chevron, like the mockup's "Warm v" / "Off v".
  // Clicking it opens the one menu layer at the bottom of this file; picking
  // an entry fires picked(key). The keyboard keeps stepping the same value
  // through the row's handler, so a click and a key can never disagree.
  component Dropdown: Rectangle {
    id: dd
    property color fg: root.fg
    property string text: ""
    property var options: []          // [{ key, label }]
    property string current: ""       // the key of the chosen entry
    property int row: -1
    signal picked(string key)
    readonly property bool focused: row >= 0 && root.kbd && root.column === "content" && root.cursor === row
    readonly property bool opened: root.menuSrc === dd
    implicitWidth: ddRow.implicitWidth + Style.space(28)
    width: implicitWidth
    height: Style.space(32)
    radius: height / 2
    color: dd.opened || dd.focused ? Calm.a(Calm.accent, 0.12) : Util.alpha(dd.fg, 0.06)
    border.width: 1
    border.color: dd.opened || dd.focused ? Calm.accent : Calm.hair
    Row {
      id: ddRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text { text: dd.text; textFormat: Text.PlainText; color: dd.fg; font.family: root.family; font.pixelSize: Style.font.body }
      Icon { name: "chev"; size: Style.space(14); stroke: 1.9; color: Util.alpha(dd.fg, 0.6); rotation: dd.opened ? 180 : 0; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        var wasOpen = dd.opened
        if (dd.row >= 0) root.pointAt(dd.row)
        if (wasOpen) root.closeMenu(); else root.menuSrc = dd
      }
    }
  }

  // A horizontal slider with its value on the right (mockup Preamp, Volume).
  // A press or drag sets the value, snapped to `step`; the row's own handler
  // moves it by the arrow keys.
  component SliderRow: Item {
    id: sl
    property int row: -1
    property real from: 0
    property real to: 1
    property real step: 1
    property real value: 0
    property string suffix: ""
    property real barW: Style.space(130)
    property real valueW: Style.space(56)
    signal moved(real v)
    readonly property bool focused: row >= 0 && root.kbd && root.column === "content" && root.cursor === row
    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
    implicitWidth: barW + Style.space(14) + valueW
    implicitHeight: Style.space(32)
    width: implicitWidth
    height: implicitHeight
    Item {
      id: slBar
      objectName: "sliderBar"
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: sl.barW
      height: Style.space(20)
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: Style.space(4); radius: height / 2
        color: Util.alpha(root.fg, 0.12)
      }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: slKnob.x + slKnob.width / 2; height: Style.space(4); radius: height / 2
        color: Calm.accent
      }
      Rectangle {
        id: slKnob
        width: Style.space(16); height: width; radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sl.frac * (slBar.width - width)
        color: "white"
        border.width: sl.focused ? 2 : 0
        border.color: Calm.a(Calm.accent, 0.8)
      }
      MouseArea {
        anchors.fill: parent
        anchors.topMargin: -Style.space(6); anchors.bottomMargin: -Style.space(6)
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        function place(mouse) {
          var f = Math.max(0, Math.min(1, (mouse.x - slKnob.width / 2) / (slBar.width - slKnob.width)))
          var v = sl.from + Math.round(f * (sl.to - sl.from) / sl.step) * sl.step
          if (sl.row >= 0) root.pointAt(sl.row)
          sl.moved(Math.max(sl.from, Math.min(sl.to, v)))
        }
        onPressed: function (mouse) { place(mouse) }
        onPositionChanged: function (mouse) { if (pressed) place(mouse) }
      }
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: sl.valueW
      horizontalAlignment: Text.AlignRight
      text: (sl.from < 0 && sl.value > 0 ? "+" : "") + sl.value + sl.suffix
      textFormat: Text.PlainText
      color: Util.alpha(root.fg, 0.6)
      font.family: root.family
      font.pixelSize: Style.space(15)
    }
  }

  component QuietButton: Rectangle {
    id: qbtn
    property color fg: root.fg
    property string label: ""
    property bool danger: false
    property string icon: ""
    // Standalone (Account) buttons carry their own row; inside a RowShell
    // they leave it at -1 and the row takes the click.
    property int row: -1
    // A button with its own onClicked (not a row's click) sets this.
    property bool standalone: false
    signal clicked()
    readonly property bool focused: row >= 0 && root.kbd && root.column === "content" && root.cursor === row
    width: qbtnRow.implicitWidth + Style.space(28)
    height: Style.space(32)
    radius: height / 2
    color: danger ? Calm.a(root.dangerColor, 0.1) : (focused ? Calm.a(Calm.accent, 0.12) : Calm.wash)
    border.width: 1
    border.color: danger ? Calm.a(root.dangerColor, 0.55) : (focused ? Calm.accent : Calm.hair)
    Row {
      id: qbtnRow
      anchors.centerIn: parent
      spacing: Style.space(7)
      Icon { visible: qbtn.icon !== ""; name: qbtn.icon; size: Style.space(16); color: qbtnText.color; anchors.verticalCenter: parent.verticalCenter }
      Text {
        id: qbtnText
        anchors.verticalCenter: parent.verticalCenter
        text: qbtn.label
        textFormat: Text.PlainText
        color: qbtn.danger ? root.dangerColor : (qbtn.focused ? Calm.accent : qbtn.fg)
        font.family: root.family
        font.pixelSize: Style.space(15)
        font.bold: true
      }
    }
    MouseArea {
      // 32 px tall at least, like every other hit box in the panel.
      anchors.fill: parent
      anchors.topMargin: Math.min(0, (parent.height - Style.space(32)) / 2)
      anchors.bottomMargin: anchors.topMargin
      enabled: qbtn.row >= 0 || qbtn.standalone
      cursorShape: Qt.PointingHandCursor
      onClicked: { if (qbtn.row >= 0) root.clickRow(qbtn.row); else qbtn.clicked() }
    }
  }

  // ---- top row: back affordance ------------------------------------------

  Item {
    id: backRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: backLabel.implicitHeight
    anchors.leftMargin: Style.space(12)

    Rectangle {
      anchors.fill: backLabel
      anchors.leftMargin: -Style.space(12); anchors.rightMargin: -Style.space(12)
      anchors.topMargin: -Style.space(4); anchors.bottomMargin: -Style.space(4)
      radius: height / 2
      color: backHover.containsMouse ? Util.alpha(root.fg, 0.1) : Util.alpha(root.fg, 0.06)
      border.width: 1
      border.color: Calm.hair
      MouseArea { id: backHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }
    Text {
      id: backLabel
      objectName: "settingsBack"
      text: "Settings"
      leftPadding: Style.space(18)
      textFormat: Text.PlainText
      color: root.fg
      font.family: root.family
      font.pixelSize: Style.font.title
      Icon { name: "back"; size: Style.space(15); color: root.fg; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.backRequested() }
    }
    KeyHint { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; keys: "esc"; label: "close"; keyPx: Style.space(11); labelPx: Style.space(12) }
  }

  // ---- body: left section list + right rows -----------------------------

  Row {
    id: body
    anchors.top: backRow.bottom
    anchors.topMargin: Style.space(26)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: Style.space(16)

    Rectangle {
      id: nav
      objectName: "settingsRail"
      width: root.railWidth
      height: railCol.implicitHeight + Style.space(16)
      radius: width / 2
      color: Util.alpha(root.fg, 0.05)
      Column {
        id: railCol
        anchors.centerIn: parent
        spacing: Style.space(6)
        Repeater {
          model: root.sections
          delegate: Item {
            required property var modelData
            required property int index
            objectName: "railItem_" + modelData.key
            width: Style.space(40)
            height: width
            readonly property bool current: modelData.key === root.section
            readonly property bool navFocused: root.column === "nav" && index === root.navIndex
            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: parent.current ? Calm.a(Calm.accent, 0.22) : (parent.navFocused ? Calm.a(Calm.accent, 0.12) : "transparent")
              border.width: parent.current || parent.navFocused ? 1 : 0
              border.color: parent.current ? Calm.a(Calm.accent, 0.5) : Calm.hair
            }
            Icon {
              anchors.centerIn: parent
              name: modelData.icon
              size: Style.space(20)
              color: parent.current ? Calm.accent : Util.alpha(root.fg, 0.6)
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.navIndex = index; root.column = "content" }
            }
          }
        }
      }
    }

    Item {
      id: content
      width: parent.width - nav.width - parent.spacing
      height: parent.height
      clip: true
      readonly property real sectionTop: sectionTitle.height + Style.space(15)

      // The section's name, big, like the mockup.
      Text {
        id: sectionTitle
        objectName: "sectionTitle"
        text: root.sectionLabel
        textFormat: Text.PlainText
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.display
        font.bold: true
      }

      // ---- Account ----
      Column {
        visible: root.section === "account"
        width: parent.width
        y: content.sectionTop
        spacing: Style.space(14)

        // The mockup's card: a round avatar, who, and the account pills.
        Rectangle {
          width: parent.width
          height: acctRow.implicitHeight + Style.space(32)
          radius: Style.space(18)
          color: Util.alpha(root.fg, 0.05)
          border.width: 1
          border.color: Calm.hair
          Row {
            id: acctRow
            anchors.left: parent.left; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(18)
            spacing: Style.space(16)

            // The real picture when there is one, else a person on the accent
            // disc. Centred on the row, never cut by the clip.
            Item {
              id: avatar
              objectName: "accountAvatar"
              width: Style.space(48)
              height: width
              anchors.verticalCenter: parent.verticalCenter
              readonly property url pic: root.signedIn && root.svc && root.svc.accountDetails.avatar ? root.svc.accountDetails.avatar : ""
              RoundCover {
                anchors.fill: parent
                source: avatar.pic
                fill: Calm.accent
                foreground: root.fg
                glyph: ""
                fontFamily: root.family
              }
              Icon { visible: avatar.pic == ""; anchors.centerIn: parent; name: "user"; size: Style.space(24); color: "#15161a" }
            }

            Column {
              id: nameCol
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - avatar.width - parent.spacing
              spacing: Style.space(4)
              Text {
                objectName: "accountHelp"
                width: parent.width
                text: root.signedIn ? "Signed in to YouTube Music" : "Signed out"
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.fg
                font.family: root.family
                font.pixelSize: Style.space(15)
                font.weight: Font.DemiBold
              }
              Text {
                visible: root.signedIn && text !== ""
                width: parent.width
                elide: Text.ElideRight
                text: !root.svc ? "" : (root.svc.accountDetails.name || "") + (root.svc.accountDetails.name && root.svc.accountDetails.email ? " · " : "") + (root.svc.accountDetails.email || "")
                textFormat: Text.PlainText
                color: Util.alpha(root.fg, 0.6)
                font.family: root.family
                font.pixelSize: Style.space(12.5)
              }
              Flow {
                width: parent.width
                spacing: Style.space(8)
                topPadding: Style.space(4)
                QuietButton {
                  visible: !root.signedIn
                  objectName: "accountSignIn"
                  label: "Sign in"
                  row: 0
                }
                QuietButton {
                  visible: root.signedIn
                  objectName: "accountSwitch"
                  label: root.switchArmed ? "Press again to switch" : "Switch account"
                  danger: root.switchArmed
                  row: 0
                }
                QuietButton {
                  visible: root.signedIn
                  objectName: "accountSignOut"
                  label: root.signOutArmed ? "Press again to sign out" : "Sign out"
                  danger: root.signOutArmed
                  row: 1
                }
              }
            }
          }
        }
        Text {
          objectName: "accountHelpText"
          text: root.signedIn && root.svc && root.svc.importedSession
                ? "Copied from your browser. Signing out here leaves your browser signed in; signing out there signs Solfa out too."
              : root.signedIn ? "Switching signs you out, then opens Google's account chooser."
              : "Signing in opens a Google window. It closes when you are in."
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          width: parent.width
          color: Util.alpha(root.fg, 0.5)
          font.family: root.family
          font.pixelSize: Style.space(12)
        }
        Text {
          visible: root.accountNote !== ""
          text: root.accountNote
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.6)
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
      }

      // ---- Sound ----
      Column {
        visible: root.section === "sound"
        width: parent.width
        y: content.sectionTop
        spacing: 0

        // Equalizer on/off, and the preset as a dropdown on the right.
        RowShell {
          objectName: "eqRow"
          label: "Equalizer"
          row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("eqEnabled", false) : false }
          Dropdown {
            objectName: "eqPresetDrop"
            row: 1
            text: Model.EQ_PRESET_LABELS[root.settingOr("eqPreset", "flat")] || "Flat"
            current: root.settingOr("eqPreset", "flat")
            options: Model.EQ_PRESET_ORDER.map(function (k) { return { key: k, label: Model.EQ_PRESET_LABELS[k] } })
            onPicked: function (key) { root.setEqPreset(key) }
          }
        }

        // All 10 bands, each its own slider; the cell width comes from the
        // room we have, so they always fit.
        Row {
          id: bandRow
          topPadding: Style.space(14)
          bottomPadding: Style.space(14)
          readonly property real cellW: Math.floor(parent.width / 10)
          Repeater {
            model: 10
            delegate: Item {
              id: bandCell
              required property int index
              readonly property real db: root.section === "sound" ? Model.eqBandDb(root.currentBands(), index) : 0
              readonly property bool bandFocused: root.kbd && root.column === "content" && root.cursor === index + 2
              width: bandRow.cellW
              height: bandCol.implicitHeight + Style.space(8)

              Rectangle {
                anchors.fill: parent
                radius: Style.spacing.labelGap
                color: bandCell.bandFocused ? Calm.a(Calm.accent, 0.12) : "transparent"
              }

              Column {
                id: bandCol
                anchors.centerIn: parent
                spacing: Style.space(8)
                Item {
                  id: track
                  objectName: "eqBandTrack" + bandCell.index
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Style.space(20)
                  height: Style.space(90)
                  // Press or drag on the track: the knob goes where the
                  // pointer is (whole dB, -12..+12, like the arrow keys).
                  // Margins reach the knob's half hanging past either end.
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(7)
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    function place(mouse) {
                      var y = mouse.y - Style.space(7)
                      root.pointAt(bandCell.index + 2)
                      root.setBand(bandCell.index, (track.height / 2 - y) / (track.height / 2) * 12)
                    }
                    onPressed: function (mouse) { place(mouse) }
                    onPositionChanged: function (mouse) { if (pressed) place(mouse) }
                  }
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(6); height: parent.height; radius: width / 2
                    color: Util.alpha(root.fg, 0.12)
                  }
                  // The fill rises from the bottom to the knob, like the mockup.
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: Style.space(6); radius: width / 2
                    height: parent.height - knob.y - knob.height / 2
                    color: Calm.accent
                  }
                  Rectangle {
                    id: knob
                    width: Style.space(20); height: width; radius: width / 2
                    color: "white"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (parent.height / 2) - (bandCell.db / 12) * (parent.height / 2) - height / 2
                    border.width: bandCell.bandFocused ? 2 : 0
                    border.color: Calm.a(Calm.accent, 0.8)
                  }
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Model.EQ_BAND_HZ[bandCell.index]
                  textFormat: Text.PlainText
                  color: Util.alpha(root.fg, 0.5)
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        RowShell {
          label: "Preamp"
          row: 12
          SliderRow {
            objectName: "preampSlider"
            row: 12
            from: -12; to: 0; step: 1
            suffix: " dB"
            value: root.settingOr("eqPreamp", 0)
            onMoved: function (v) { root.svc.saveSetting("eqPreamp", v) }
          }
        }
        RowShell {
          label: "Even out loudness"
          help: "Quiet and loud songs sound alike"
          row: 13
          MiniToggle { active: root.svc ? !!root.svc.setting("eqLoudness", false) : false }
        }
        RowShell {
          label: "Sleep timer"
          row: 14
          Dropdown {
            row: 14
            text: root.svc ? Model.sleepLabel(root.svc.sleepMode) : "Off"
            options: Model.SLEEP_OPTIONS.map(function (k) { return { key: k, label: Model.sleepLabel(k) } })
            onPicked: function (key) {
              // The service only steps through its options; walk to the one asked for.
              for (var n = 0; n < Model.SLEEP_OPTIONS.length && root.svc.sleepMode !== key; n++) root.svc.nudgeSleepMode(1)
            }
          }
        }
      }

      // ---- Playback ----
      Column {
        visible: root.section === "playback"
        width: parent.width
        y: content.sectionTop
        spacing: 0

        RowShell {
          label: "When Solfa starts"
          row: 0
          Dropdown {
            row: 0
            text: root.settingOr("startPaused", false) ? "Resume paused" : "Resume playing"
            options: [{ key: "play", label: "Resume playing" }, { key: "paused", label: "Resume paused" }]
            onPicked: function (key) { root.svc.saveSetting("startPaused", key === "paused") }
          }
        }
        RowShell {
          label: "Volume at start"
          row: 1
          Dropdown {
            row: 1
            text: root.settingOr("startVolume", "last") === "last" ? "Last used" : root.settingOr("startVolume", "last") + "%"
            options: ["last", "25", "50", "75", "100"].map(function (k) { return { key: k, label: k === "last" ? "Last used" : k + "%" } })
            onPicked: function (key) { root.svc.saveSetting("startVolume", key) }
          }
        }
        RowShell {
          label: "Start with the shell"
          help: "Turns YouTube Music on at login"
          row: 2
          MiniToggle { active: root.svc ? !!root.svc.setting("autostart", true) : true }
        }
        RowShell {
          label: "Browser for the engine"
          row: 3
          Dropdown {
            row: 3
            text: Model.browserLabel(root.svc ? root.svc.setting("browser", "") : "")
            options: root.svc ? Model.browserChoices(root.svc.browsers, root.svc.setting("browser", "")).map(function (k) { return { key: k, label: Model.browserLabel(k) } }) : []
            onPicked: function (key) { root.svc.saveSetting("browser", key) }
          }
        }
        RowShell {
          visible: root.braveEngine
          label: "Brave's ad blocker"
          help: "Lets Brave fetch its filter lists, so it can block adverts. Off keeps the engine from any background updates"
          row: 4
          MiniToggle { active: root.svc ? !!root.svc.setting("braveAdBlock", false) : false }
        }
      }

      // ---- Bar and alerts ----
      Column {
        visible: root.section === "bar"
        width: parent.width
        y: content.sectionTop
        spacing: 0

        RowShell { label: "Previous, play/pause and next in the bar"; row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("barControls", true) : true } }
        RowShell { label: "Song title in the bar"; row: 1
          MiniToggle { active: root.svc ? !!root.svc.setting("showTitle", true) : true } }
        RowShell { label: "Title width in the bar"; row: 2
          SliderRow {
            objectName: "titleWidthSlider"
            barW: Style.space(100)
            valueW: Style.space(36)
            row: 2
            from: 80; to: 400; step: 20
            value: root.settingOr("maxLabelWidth", 160)
            onMoved: function (v) { root.svc.saveSetting("maxLabelWidth", v) }
          } }
        RowShell { label: "Show in the bar when nothing is loaded"; row: 3
          MiniToggle { active: root.svc ? !!root.svc.setting("showWhenIdle", true) : true } }
        RowShell { label: "Notify when the song changes"; help: "A small card with the cover"; row: 4
          MiniToggle { active: root.svc ? !!root.svc.setting("notify", true) : true } }
      }

      // ---- Keys ----
      Column {
        visible: root.section === "keys"
        width: parent.width
        y: content.sectionTop
        spacing: 0

        RowShell {
          objectName: "globalKeysRow"
          label: "Global shortcuts"
          help: "Play, next, previous and like from anywhere"
          row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("globalKeys", true) : true }
        }
        RowShell {
          label: "Every key"
          row: 1
          QuietButton { label: "All keys"; icon: "keyboard" }
        }
        // The keys that work in the panel, two columns (the real bindings).
        Grid {
          objectName: "keyGrid"
          width: parent.width
          topPadding: Style.space(12)
          columns: 2
          rowSpacing: Style.space(10)
          readonly property var keyList: [
            ["↵", "play"], ["space", "pause"], ["n", "next"], ["p", "previous"],
            ["f", "like"], ["/", "search"], ["tab", "next tab"], ["e", "play next"],
            ["a", "add to queue"], ["R", "start radio"], ["[ ]", "section"], ["esc", "back"]
          ]
          Repeater {
            model: parent.keyList
            delegate: KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; keyPx: Style.space(11); labelPx: Style.space(12); width: content.width / 2 }
          }
        }
      }

      // ---- Advanced ----
      Column {
        visible: root.section === "advanced"
        width: parent.width
        y: content.sectionTop
        spacing: 0

        RowShell { label: "Refresh the page when memory passes"; help: "Applies on next start"; row: 0
          Dropdown {
            row: 0
            text: Model.recycleHeapMbFor(root.svc ? root.svc.setting("recycleHeapMb", 400) : 400) + " MB"
            options: [200, 300, 400, 500, 600, 700].map(function (k) { return { key: String(k), label: k + " MB" } })
            onPicked: function (key) { root.svc.saveSetting("recycleHeapMb", Number(key)) }
          } }
        RowShell { label: "Refresh at least every"; help: "Applies on next start"; row: 1
          Dropdown {
            row: 1
            text: Model.recycleHoursFor(root.svc ? root.svc.setting("recycleHours", 12) : 12) + " hours"
            options: [1, 2, 4, 6, 12, 24, 48, 72].map(function (k) { return { key: String(k), label: k + " hours" } })
            onPicked: function (key) { root.svc.saveSetting("recycleHours", Number(key)) }
          } }
        RowShell { label: "Reduce motion"; help: "Stops springs, glows, comets and typing"; row: 2
          MiniToggle { active: root.settingOr("reduceMotion", false) } }
        RowShell { label: "Clear cache"; help: root.cacheNote !== "" ? root.cacheNote : "Keeps you signed in"; row: 3
          QuietButton { label: "Clear" } }
        RowShell { label: "Reset settings"; row: 4
          QuietButton { label: "Reset" } }
        RowShell {
          label: "Erase engine data"
          help: root.eraseArmed ? "Press again to erase. This signs you out." : (root.eraseNote !== "" ? root.eraseNote : "Deletes the profile; signs you out")
          row: 5
          labelColor: root.dangerColor
          QuietButton { visible: root.eraseArmed; standalone: true; label: "Keep"; onClicked: root.disarm() }
          QuietButton { label: root.eraseArmed ? "Yes, erase" : "Erase"; icon: "trash"; danger: true }
        }
      }

      // ---- About ----
      Column {
        visible: root.section === "about"
        width: parent.width
        y: content.sectionTop
        spacing: Style.space(14)

        Rectangle {
          width: parent.width
          height: aboutCol.implicitHeight + Style.space(44)
          radius: Style.space(18)
          color: Util.alpha(root.fg, 0.05)
          border.width: 1
          border.color: Calm.hair
          Column {
            id: aboutCol
            anchors.centerIn: parent
            spacing: Style.space(10)
            Logo { anchors.horizontalCenter: parent.horizontalCenter; size: Style.space(72) }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Solfa " + (root.svc ? (root.svc.solfaVersion || "0.1.0") : "0.1.0"); textFormat: Text.PlainText; color: root.fg; font.family: root.family; font.pixelSize: Style.space(16); font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Engine: " + root.engineLabel(root.engineVersionText); textFormat: Text.PlainText; color: Util.alpha(root.fg, 0.6); font.family: root.family; font.pixelSize: Style.space(12) }
          }
        }
        Text {
          width: parent.width
          text: "A YouTube Music player for the Omarchy shell. The web app plays the audio. It is never seen and never takes focus."
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: Util.alpha(root.fg, 0.6)
          font.family: root.family
          font.pixelSize: Style.space(12.5)
        }
        Row {
          spacing: Style.space(8)
          Repeater {
            model: [
              { label: "Changelog", icon: "globe", url: "https://github.com/SirAllap/omarchy-solfa/releases", obj: "aboutChangelog" },
              { label: "Report an issue", icon: "warn", url: "https://github.com/SirAllap/omarchy-solfa/issues/new", obj: "aboutReport" }
            ]
            delegate: Rectangle {
              required property var modelData
              objectName: modelData.obj
              width: pillRow.implicitWidth + Style.space(32)
              height: Style.space(36)
              radius: height / 2
              color: pillMa.containsMouse ? Util.alpha(root.fg, 0.1) : Util.alpha(root.fg, 0.06)
              border.width: 1
              border.color: Calm.hair
              Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Style.space(8)
                Icon { name: modelData.icon; size: Style.space(16); color: root.fg; anchors.verticalCenter: parent.verticalCenter }
                Text { text: modelData.label; textFormat: Text.PlainText; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
              }
              MouseArea { id: pillMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(modelData.url) }
            }
          }
        }
      }
    }
  }

  // ---- the open dropdown's menu, above every row -----------------------

  Item {
    id: menuLayer
    anchors.fill: parent
    visible: root.menuSrc !== null
    z: 50
    MouseArea { anchors.fill: parent; onClicked: root.closeMenu() }
    Rectangle {
      id: menuBox
      readonly property point pos: root.menuSrc ? root.menuSrc.mapToItem(root, 0, 0) : Qt.point(0, 0)
      readonly property real srcW: root.menuSrc ? root.menuSrc.width : 0
      readonly property real srcH: root.menuSrc ? root.menuSrc.height : 0
      width: Math.max(Style.space(150), srcW)
      height: menuCol.implicitHeight + Style.space(12)
      x: Math.max(0, Math.min(root.width - width, pos.x + srcW - width))
      y: Math.max(0, Math.min(pos.y + srcH + Style.space(6), root.height - height))
      radius: Style.space(14)
      color: Calm.raised
      border.width: 1
      border.color: Calm.hair
      Column {
        id: menuCol
        anchors.fill: parent
        anchors.margins: Style.space(6)
        Repeater {
          model: root.menuSrc ? root.menuSrc.options : []
          delegate: Rectangle {
            required property var modelData
            objectName: "menuItem_" + modelData.key
            readonly property bool chosen: root.menuSrc !== null && modelData.key === root.menuSrc.current
            width: menuCol.width
            height: Style.space(34)
            radius: Style.space(10)
            color: chosen ? Calm.a(Calm.accent, 0.22) : "transparent"
            Text {
              anchors.left: parent.left; anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              textFormat: Text.PlainText
              color: parent.chosen ? Calm.accent : Calm.fg
              font.family: root.family
              font.pixelSize: Style.font.body
            }
            Icon {
              visible: parent.chosen
              anchors.right: parent.right; anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              name: "check"
              size: Style.space(16)
              color: Calm.accent
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { var key = modelData.key; var src = root.menuSrc; root.closeMenu(); if (src) src.picked(key) }
            }
          }
        }
      }
    }
  }
}
