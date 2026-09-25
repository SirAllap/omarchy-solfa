import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/Icons.js" as Icons

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

  signal backRequested()
  signal showAllKeys()

  readonly property var sections: [
    { key: "account", label: "Account" }, { key: "sound", label: "Sound" },
    { key: "playback", label: "Playback" }, { key: "bar", label: "Bar and alerts" },
    { key: "keys", label: "Keys" }, { key: "advanced", label: "Advanced" }, { key: "about", label: "About" }
  ]
  property int navIndex: 0
  readonly property string section: root.sections[root.navIndex].key
  // "nav" (left column has the cursor) or "content" (right column does).
  property string column: "content"
  property int cursor: 0
  // Handlers for the current section's rows, in the same order they are
  // drawn: { change(dir), act(), toggle() } — a row supplies whichever it
  // needs; move()/change()/act() below call through them.
  property var handlers: []

  readonly property real navWidth: Style.space(150)

  // ---- transient, per-open UI state (never persisted) -------------------

  property string accountNote: ""
  // Two-step confirms (Switch account, Sign out, Erase): one Enter arms,
  // the next one on the same row runs it. Anything else disarms: moving the
  // cursor, changing column or section, the view going away (the panel
  // closed), or armTimeoutMs with no second Enter.
  property bool switchArmed: false
  property bool signOutArmed: false
  property bool eraseArmed: false
  readonly property int armTimeoutMs: 5000
  readonly property bool armTimerRunning: armTimer.running
  function disarm() {
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
  onVisibleChanged: if (!root.visible) root.disarm()
  property string cacheNote: ""
  property string eraseNote: ""
  property string engineVersionText: ""

  function rebuildHandlers() {
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
    if (root.column === "nav") { root.column = "content"; root.cursor = 0; return }
    var h = root.handlers[root.cursor]
    if (!h) return
    if (h.act) h.act()
    else if (h.toggle) h.toggle()
    else if (h.change) h.change(1)
  }
  function switchColumn() { root.column = root.column === "nav" ? "content" : "nav" }

  // ---- pointer API: a click is the keyboard's cursor move plus its key ----
  // Every row routes its click through the same handlers the keyboard uses,
  // so a click and an Enter can never disagree (the two-step confirms
  // included: a second click on an armed row runs it, like a second Enter).

  function pointAt(i) { root.column = "content"; root.cursor = i }
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
            { toggle: function () { svc.saveSetting("eqLoudness", !svc.setting("eqLoudness", false)) } }
          ])
      }
      case "playback": return [
        { change: function (dir) { svc.nudgeSleepMode(dir) }, act: function () { svc.nudgeSleepMode(1) } },
        { toggle: function () { svc.saveSetting("startPaused", !svc.setting("startPaused", false)) } },
        { change: function (dir) { svc.saveSetting("startVolume", Model.cycleList(["last", "25", "50", "75", "100"], String(svc.setting("startVolume", "last")), dir)) } },
        { toggle: function () { svc.saveSetting("autostart", !svc.setting("autostart", true)) } },
        { change: function (dir) { svc.saveSetting("browser", Model.cycleList(["", "/usr/bin/chromium", "/usr/bin/google-chrome-stable", "/usr/bin/brave", "/usr/bin/vivaldi-stable"], svc.setting("browser", ""), dir)) } }
      ]
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
    // The row's index in its section's handlers: the keyboard cursor lands
    // on it, and a click anywhere on the row runs it.
    property int row: -1
    readonly property bool focused: row >= 0 && root.column === "content" && root.cursor === row
    width: parent ? parent.width : 0
    // Grows with a wrapped help line. A fixed height with the text centred
    // on it pushed a two-line help's title above the row's top, where the
    // content's clip cut it off.
    height: Math.max(Style.space(46), rowText.implicitHeight + Style.space(12))
    default property alias controlChildren: controlSlot.children

    Rectangle {
      anchors.fill: parent
      radius: Style.spacing.labelGap
      color: rowShell.focused ? Style.selectedFillFor(rowShell.fg, Color.accent)
                              : (rowHover.containsMouse ? Util.alpha(rowShell.fg, 0.05) : "transparent")
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
      anchors.leftMargin: Style.space(6)
      anchors.right: controlSlot.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        text: rowShell.label
        textFormat: Text.PlainText
        color: rowShell.fg
        font.family: rowShell.family
        font.pixelSize: Style.font.body
      }
      Text {
        visible: rowShell.help !== ""
        width: parent.width
        text: rowShell.help
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Util.alpha(rowShell.fg, 0.5)
        font.family: rowShell.family
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: controlSlot
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
    }
  }

  component MiniToggle: Rectangle {
    id: toggle
    property color fg: root.fg
    property bool active: false
    width: Style.space(38)
    height: Style.space(20)
    radius: height / 2
    color: active ? Util.alpha(Color.accent, 0.35) : Util.alpha(fg, 0.12)
    border.width: 1
    border.color: active ? Color.accent : Util.alpha(fg, 0.25)
    Rectangle {
      width: parent.height - 4
      height: width
      radius: width / 2
      color: toggle.active ? Color.accent : toggle.fg
      anchors.verticalCenter: parent.verticalCenter
      x: toggle.active ? parent.width - width - 2 : 2
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
  }

  component Chip: Rectangle {
    id: chip
    property color fg: root.fg
    property string label: ""
    property bool active: false
    signal clicked()
    width: chipText.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.space(12)
    color: active ? Style.selectedFillFor(fg, Color.accent) : "transparent"
    border.width: 1
    border.color: active ? Color.accent : Util.alpha(fg, 0.2)
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      textFormat: Text.PlainText
      color: chip.active ? Color.accent : Util.alpha(chip.fg, 0.8)
      font.family: root.family
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      anchors.fill: parent
      anchors.topMargin: Math.min(0, (parent.height - Style.space(32)) / 2)
      anchors.bottomMargin: anchors.topMargin
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // A value with ‹ › steppers, e.g. "400 MB", "12 h", "50%".
  // A click on its left half steps down, on its right half up; `row` is the
  // RowShell's own index (the row itself would only ever step up).
  component StepValue: Item {
    id: stepValue
    property color fg: root.fg
    property string value: ""
    property int row: -1
    implicitWidth: stepRowItems.implicitWidth
    implicitHeight: Math.max(stepRowItems.implicitHeight, Style.space(32))
    width: implicitWidth
    height: implicitHeight
    Row {
      id: stepRowItems
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text { text: Icons.chevronLeft; color: Util.alpha(root.fg, 0.45); font.family: root.family; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
      Text { text: stepValue.value; color: stepValue.fg; font.family: root.family; font.pixelSize: Style.font.body; textFormat: Text.PlainText }
      Text { text: Icons.chevronRight; color: Util.alpha(root.fg, 0.45); font.family: root.family; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
    }
    MouseArea {
      anchors.fill: parent
      enabled: stepValue.row >= 0
      cursorShape: Qt.PointingHandCursor
      onClicked: function (mouse) { root.stepRow(stepValue.row, mouse.x < width / 2 ? -1 : 1) }
    }
  }

  component QuietButton: Rectangle {
    id: qbtn
    property color fg: root.fg
    property string label: ""
    property bool danger: false
    // Standalone (Account) buttons carry their own row; inside a RowShell
    // they leave it at -1 and the row takes the click.
    property int row: -1
    readonly property bool focused: row >= 0 && root.column === "content" && root.cursor === row
    width: qbtnText.implicitWidth + Style.space(20)
    height: Style.space(26)
    radius: Style.space(6)
    color: focused ? Style.selectedFillFor(fg, Color.accent) : Util.alpha(fg, 0.06)
    border.width: danger || focused ? 1 : 0
    border.color: danger ? Color.urgent : Color.accent
    Text {
      id: qbtnText
      anchors.centerIn: parent
      text: qbtn.label
      textFormat: Text.PlainText
      color: qbtn.danger ? Color.urgent : (qbtn.focused ? Color.accent : qbtn.fg)
      font.family: root.family
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      // 32 px tall at least, like every other hit box in the panel.
      anchors.fill: parent
      anchors.topMargin: Math.min(0, (parent.height - Style.space(32)) / 2)
      anchors.bottomMargin: anchors.topMargin
      enabled: qbtn.row >= 0
      cursorShape: Qt.PointingHandCursor
      onClicked: root.clickRow(qbtn.row)
    }
  }

  // ---- top row: back affordance ------------------------------------------

  Item {
    id: backRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: backLabel.implicitHeight

    Text {
      id: backLabel
      objectName: "settingsBack"
      text: "‹ Settings"
      textFormat: Text.PlainText
      color: root.fg
      font.family: root.family
      font.pixelSize: Style.font.title
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.backRequested() }
    }
  }

  // ---- body: left section list + right rows -----------------------------

  Row {
    id: body
    anchors.top: backRow.bottom
    anchors.topMargin: Style.space(14)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: Style.space(16)

    Column {
      id: nav
      width: root.navWidth
      height: parent.height
      spacing: Style.space(2)
      Repeater {
        model: root.sections
        delegate: Item {
          required property var modelData
          required property int index
          width: nav.width
          height: Style.space(30)
          readonly property bool navFocused: root.column === "nav" && index === root.navIndex
          Rectangle {
            anchors.fill: parent
            radius: Style.spacing.labelGap
            color: navFocused ? Style.selectedFillFor(root.fg, Color.accent) : "transparent"
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            textFormat: Text.PlainText
            color: modelData.key === root.section ? Color.accent : Util.alpha(root.fg, 0.85)
            font.family: root.family
            font.pixelSize: Style.font.body
            font.bold: modelData.key === root.section
          }
          MouseArea {
            anchors.fill: parent
            onClicked: { root.navIndex = index; root.column = "content" }
          }
        }
      }
    }

    Item {
      id: content
      width: parent.width - nav.width - parent.spacing
      height: parent.height
      clip: true

      // ---- Account ----
      Column {
        visible: root.section === "account"
        width: parent.width
        spacing: Style.space(14)

        Row {
          visible: root.signedIn
          spacing: Style.space(14)

          // Centred on the row (never on the name column: a taller avatar
          // would then start above the row and be cut flat by the clip).
          RoundCover {
            id: avatar
            objectName: "accountAvatar"
            width: Style.space(52)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            source: root.svc && root.svc.accountDetails.avatar ? root.svc.accountDetails.avatar : ""
            fill: Util.alpha(root.fg, 0.12)
            foreground: root.fg
            glyph: root.svc ? root.initialsFor(root.svc.accountDetails.name) : "?"
            fontFamily: root.family
          }

          Column {
            id: nameCol
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: root.svc ? (root.svc.accountDetails.name || "Signed in") : ""
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.subtitle
            }
            Text {
              visible: root.svc && root.svc.accountDetails.email !== ""
              text: root.svc ? root.svc.accountDetails.email : ""
              textFormat: Text.PlainText
              color: Util.alpha(root.fg, 0.6)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
            Text {
              objectName: "accountHelp"
              text: "Signed in to YouTube Music"
              textFormat: Text.PlainText
              color: Util.alpha(root.fg, 0.5)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }
        Text {
          visible: !root.signedIn
          text: "Signed out"
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.family
          font.pixelSize: Style.font.subtitle
        }

        Row {
          visible: !root.signedIn
          spacing: Style.space(8)
          QuietButton {
            objectName: "accountSignIn"
            label: "Sign in"
            row: 0
          }
        }
        Row {
          visible: root.signedIn
          spacing: Style.space(8)
          QuietButton {
            objectName: "accountSwitch"
            label: root.switchArmed ? "Press again to switch" : "Switch account"
            danger: root.switchArmed
            row: 0
          }
          QuietButton {
            objectName: "accountSignOut"
            label: root.signOutArmed ? "Press again to sign out" : "Sign out"
            danger: root.signOutArmed
            row: 1
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
          font.pixelSize: Style.font.caption
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
        spacing: Style.space(10)

        RowShell {
          objectName: "eqRow"
          label: "Equalizer"
          row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("eqEnabled", false) : false }
        }

        Item {
          width: parent.width
          height: presetRow.implicitHeight + Style.space(8)
          Rectangle {
            anchors.fill: parent
            radius: Style.spacing.labelGap
            color: root.column === "content" && root.cursor === 1 ? Style.selectedFillFor(root.fg, Color.accent) : "transparent"
          }
          MouseArea { anchors.fill: parent; onClicked: root.pointAt(1) }
          Row {
            id: presetRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Repeater {
              model: Model.EQ_PRESET_ORDER
              delegate: Chip {
                required property string modelData
                objectName: "eqPreset_" + modelData
                label: Model.EQ_PRESET_LABELS[modelData]
                active: root.svc && root.svc.setting("eqPreset", "flat") === modelData
                onClicked: { root.pointAt(1); root.setEqPreset(modelData) }
              }
            }
          }
        }

        Row {
          spacing: Style.space(10)
          Repeater {
            model: 10
            delegate: Item {
              id: bandCell
              required property int index
              readonly property real db: root.section === "sound" ? Model.eqBandDb(root.currentBands(), index) : 0
              readonly property bool bandFocused: root.column === "content" && root.cursor === index + 2
              width: bandCol.implicitWidth + Style.space(8)
              height: bandCol.implicitHeight + Style.space(8)

              Rectangle {
                anchors.fill: parent
                radius: Style.spacing.labelGap
                color: bandCell.bandFocused ? Style.selectedFillFor(root.fg, Color.accent) : "transparent"
              }

              Column {
                id: bandCol
                anchors.centerIn: parent
                spacing: Style.space(4)
                Item {
                  id: track
                  objectName: "eqBandTrack" + bandCell.index
                  width: Style.space(18)
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
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: parent.height
                    color: Util.alpha(root.fg, 0.15)
                  }
                  Rectangle {
                    width: Style.space(14); height: width; radius: width / 2
                    color: bandCell.db !== 0 ? Color.accent : root.fg
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (parent.height / 2) - (bandCell.db / 12) * (parent.height / 2) - height / 2
                    border.width: bandCell.bandFocused ? 2 : 0
                    border.color: Util.alpha(Color.accent, 0.6)
                  }
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: (bandCell.db > 0 ? "+" : "") + bandCell.db
                  textFormat: Text.PlainText
                  color: Util.alpha(root.fg, 0.6)
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Model.EQ_BAND_HZ[bandCell.index]
                  textFormat: Text.PlainText
                  color: Util.alpha(root.fg, 0.45)
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
          StepValue { objectName: "preampStep"; row: 12; value: (root.svc ? root.svc.setting("eqPreamp", 0) : 0) + " dB" }
        }
        RowShell {
          label: "Even out loudness"
          help: "A compressor: quiet songs come up, loud ones do not clip"
          row: 13
          MiniToggle { active: root.svc ? !!root.svc.setting("eqLoudness", false) : false }
        }
      }

      // ---- Playback ----
      Column {
        visible: root.section === "playback"
        width: parent.width
        spacing: Style.space(6)

        RowShell {
          label: "Sleep timer"
          help: "Fades the volume over 10 s, then pauses"
          row: 0
          StepValue { row: 0; value: root.svc ? Model.sleepLabel(root.svc.sleepMode) : "Off" }
        }
        RowShell {
          label: "When Solfa starts"
          row: 1
          StepValue { row: 1; value: root.svc && root.svc.setting("startPaused", false) ? "Resume paused" : "Resume playing" }
        }
        RowShell {
          label: "Volume at start"
          row: 2
          StepValue { row: 2; value: root.svc && root.svc.setting("startVolume", "last") === "last" ? "Last used" : root.svc.setting("startVolume", "last") + "%" }
        }
        RowShell {
          label: "Start with the shell"
          row: 3
          MiniToggle { active: root.svc ? !!root.svc.setting("autostart", true) : true }
        }
        RowShell {
          label: "Browser for the engine"
          help: "An absolute path to a Chromium-family browser (never a bare command)"
          row: 4
          StepValue { row: 4; value: (function () { var b = root.svc ? root.svc.setting("browser", "") : ""; return b !== "" ? b.split("/").pop() : "Auto" })() }
        }
      }

      // ---- Bar and alerts ----
      Column {
        visible: root.section === "bar"
        width: parent.width
        spacing: Style.space(6)

        RowShell { label: "Previous, play/pause and next in the bar"; row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("barControls", true) : true } }
        RowShell { label: "Song title in the bar"; row: 1
          MiniToggle { active: root.svc ? !!root.svc.setting("showTitle", true) : true } }
        RowShell { label: "Title width in the bar"; row: 2
          StepValue { row: 2; value: (root.svc ? root.svc.setting("maxLabelWidth", 160) : 160) + " px" } }
        RowShell { label: "Show in the bar when nothing is loaded"; row: 3
          MiniToggle { active: root.svc ? !!root.svc.setting("showWhenIdle", true) : true } }
        RowShell { label: "Notify when the song changes"; row: 4
          MiniToggle { active: root.svc ? !!root.svc.setting("notify", true) : true } }
      }

      // ---- Keys ----
      Column {
        visible: root.section === "keys"
        width: parent.width
        spacing: Style.space(6)

        RowShell {
          objectName: "globalKeysRow"
          label: "Global shortcuts"
          help: "Super+M panel, Super+Alt+M play/pause, Super+Alt+N next, Super+Alt+B previous, Super+Alt+L like"
          row: 0
          MiniToggle { active: root.svc ? !!root.svc.setting("globalKeys", true) : true }
        }
        RowShell {
          label: "Every key"
          row: 1
          QuietButton { label: "All keys" }
        }
      }

      // ---- Advanced ----
      Column {
        visible: root.section === "advanced"
        width: parent.width
        spacing: Style.space(6)

        RowShell { label: "Refresh the page when memory passes"; help: "Applies on next start"; row: 0
          StepValue { row: 0; value: Model.recycleHeapMbFor(root.svc ? root.svc.setting("recycleHeapMb", 400) : 400) + " MB" } }
        RowShell { label: "Refresh at least every"; help: "Applies on next start"; row: 1
          StepValue { row: 1; value: Model.recycleHoursFor(root.svc ? root.svc.setting("recycleHours", 12) : 12) + " h" } }
        RowShell { label: "Clear cache"; help: root.cacheNote !== "" ? root.cacheNote : "Keeps you signed in"; row: 2
          QuietButton { label: "Clear" } }
        RowShell { label: "Reset settings"; row: 3
          QuietButton { label: "Reset" } }
        RowShell {
          label: "Erase engine data"
          help: root.eraseArmed ? "Press again to erase. This signs you out." : (root.eraseNote !== "" ? root.eraseNote : "Deletes the profile; signs you out")
          row: 4
          QuietButton { label: root.eraseArmed ? "Press again" : "Erase"; danger: true }
        }
      }

      // ---- About ----
      Column {
        visible: root.section === "about"
        width: parent.width
        spacing: Style.space(6)

        Text { text: "Solfa " + (root.svc ? (root.svc.solfaVersion || "0.1.0") : "0.1.0"); textFormat: Text.PlainText; color: root.fg; font.family: root.family; font.pixelSize: Style.font.body }
        Text { text: "Engine: " + root.engineVersionText; textFormat: Text.PlainText; color: Util.alpha(root.fg, 0.6); font.family: root.family; font.pixelSize: Style.font.caption }
      }
    }
  }
}
