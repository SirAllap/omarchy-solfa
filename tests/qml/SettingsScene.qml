import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model
import "views" as Views

// The real Settings view (test_settings.py): a gear in a real BrandCorner
// reaching it, then a scripted keyboard walk through every section against
// a fake service (records every call it makes, like ClosedScene.qml's
// FakeSvc), logging one "STATE {...}" line. Also saves evidence frames when
// SOLFA_SCENE_OUT (Sound, bass preset), SOLFA_SCENE_OUT2 (Account, real
// data), SOLFA_SCENE_OUT3 (Playback) and SOLFA_SCENE_OUT4 (Advanced) are
// set — the real run for the report. test_settings.py only sets the first
// two; the others are for ad hoc evidence renders.
ShellRoot {
  id: scene

  component FakeSvc: QtObject {
    property bool bridgeUp: true
    property bool signingIn: false
    property bool closed: false
    property bool signedIn: true
    property bool premium: false
    property bool ready: true
    property var account: ({ signedIn: true, host: "music.youtube.com" })
    property var settings: ({
      barControls: true, showTitle: true, maxLabelWidth: 160, showWhenIdle: true, notify: true,
      globalKeys: true, autostart: true, browser: "",
      eqEnabled: false, eqPreset: "flat", eqBands: "[0,0,0,0,0,0,0,0,0,0]", eqPreamp: 0, eqLoudness: false,
      startPaused: false, startVolume: "last", recycleHeapMb: 400, recycleHours: 12
    })
    function setting(name, fallback) {
      var v = settings ? settings[name] : undefined
      return v === undefined || v === null ? fallback : v
    }
    property var savedCalls: []
    function saveSetting(key, value) {
      var next = Object.assign({}, settings)
      next[key] = value
      settings = next
      savedCalls.push([key, value])
    }
    property bool resetCalled: false
    function resetSettings() { resetCalled = true }
    property int signInCalls: 0
    function signIn() { signInCalls++ }

    property string sleepMode: "off"
    property var sleepCalls: []
    function nudgeSleepMode(dir) { sleepCalls.push(dir); sleepMode = Model.nextSleepOption(sleepMode, dir) }

    property string solfaVersion: "0.1.0-fixture"
    property int engineVersionCalls: 0
    function engineVersion(cb) { engineVersionCalls++; if (cb) cb({ ok: true, data: { product: "FakeChrome/999.0 (fixture)" } }) }
    property int clearCacheCalls: 0
    function clearCache(cb) { clearCacheCalls++; if (cb) cb({ ok: true, data: { cleared: true } }) }
    property int eraseCalls: 0
    function eraseProfile(cb) { eraseCalls++; if (cb) cb({ ok: true, data: { erased: true } }) }
    property var accountDetails: ({ name: "", email: "", avatar: "" })
    property int accountInfoCalls: 0
    function accountInfo(cb) {
      accountInfoCalls++
      accountDetails = { name: "Alex Example", email: "alex@example.com", avatar: "" }
      if (cb) cb({ ok: true, data: accountDetails })
    }
    property int accountSwitchCalls: 0
    function accountSwitch(cb) { accountSwitchCalls++; if (cb) cb({ ok: true, data: { navigated: true } }) }
    property int accountSignOutCalls: 0
    function accountSignOut(cb) {
      accountSignOutCalls++
      accountDetails = { name: "", email: "", avatar: "" }
      if (cb) cb({ ok: true, data: { navigated: true } })
    }
  }
  FakeSvc { id: fakeSvc }

  property int showAllKeysCount: 0
  property int backRequestedCount: 0
  property int gearClickedCount: 0

  FloatingWindow {
    id: win
    implicitWidth: 660
    implicitHeight: 480
    visible: true
    color: Color.popups.background

    Item {
      id: stage
      anchors.fill: parent

      // The real panel card (KeyboardPanel.qml): popups background + the
      // shell's corner radius, so text isn't rendered over transparent/white.
      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Color.popups.background
      }

      // Same top row as the real panel: the brand corner top-right, the
      // Settings view (whose own back row sits at its top) filling the rest.
      Views.BrandCorner {
        id: corner
        objectName: "corner"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        svc: fakeSvc
        settingsOpen: settingsView.visible
        onGearClicked: scene.gearClickedCount++
      }

      Views.SettingsView {
        id: settingsView
        objectName: "settingsView"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        svc: fakeSvc
        onBackRequested: scene.backRequestedCount++
        onShowAllKeys: scene.showAllKeysCount++
      }
    }

    TestCase { id: tc; name: "settings"; when: false }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }

    // The mouse walk: every kind of row again, by real clicks this time
    // (the right-hand body once had no pointer handling at all, so only
    // the keyboard reached it). Sections are switched between frames so
    // the clicked items are laid out and visible. Logs one "MOUSE {...}".
    property var mouseLog: ({})
    function click(name, fx, fy) {
      var it = win.find(stage, name)
      if (!it) { win.mouseLog[name + "Missing"] = true; return }
      tc.mouseClick(it, fx === undefined ? it.width / 2 : it.width * fx, fy === undefined ? it.height / 2 : it.height * fy)
    }
    function inSection(index, fn) {
      settingsView.navIndex = index
      settle.pending = fn
      settle.restart()
    }
    function mouseWalk() {
      var m = win.mouseLog
      settingsView.column = "nav"
      inSection(0, function () {
        var switchBefore = fakeSvc.accountSwitchCalls, signOutBefore = fakeSvc.accountSignOutCalls
        win.click("accountSwitch")
        m.switchArmedAfterClick = settingsView.switchArmed
        m.switchCallsAfterOneClick = fakeSvc.accountSwitchCalls - switchBefore
        win.click("accountSwitch")
        m.switchCallsAfterTwoClicks = fakeSvc.accountSwitchCalls - switchBefore
        win.click("accountSignOut")
        m.signOutArmedAfterClick = settingsView.signOutArmed
        m.signOutCallsAfterOneClick = fakeSvc.accountSignOutCalls - signOutBefore
        win.click("accountSignOut")
        m.signOutCallsAfterTwoClicks = fakeSvc.accountSignOutCalls - signOutBefore

        inSection(1, function () {
          var eqBefore = !!fakeSvc.setting("eqEnabled", false)
          win.click("eqRow")
          m.eqToggledByClick = !!fakeSvc.setting("eqEnabled", false) !== eqBefore
          win.click("eqPreset_treble")
          m.presetAfterChip = fakeSvc.setting("eqPreset", "")
          win.click("eqBandTrack3", 0.5, 0)    // the top of the track: +12 dB
          m.band3AfterClick = Model.parseEqBands(fakeSvc.setting("eqBands", "[]"))[3]
          m.presetAfterBand = fakeSvc.setting("eqPreset", "")
          m.cursorAfterBand = settingsView.cursor
          var preampBefore = fakeSvc.setting("eqPreamp", 0)
          win.click("preampStep", 0.1)         // the left arrow: one dB down
          m.preampDelta = fakeSvc.setting("eqPreamp", 0) - preampBefore

          inSection(4, function () {
            var row = win.find(stage, "globalKeysRow")
            var text = row ? win.find(row, "rowText") : null
            m.keysRowTextTop = text ? text.y : null
            m.keysRowTextFits = row && text ? text.y + text.height <= row.height : null
            var keysBefore = !!fakeSvc.setting("globalKeys", true)
            win.click("globalKeysRow")
            m.globalKeysToggledByClick = !!fakeSvc.setting("globalKeys", true) !== keysBefore
            win.grab(Quickshell.env("SOLFA_SCENE_OUT5"), function () {
              console.log("MOUSE " + JSON.stringify(m))
              Qt.quit()
            })
          })
        })
      })
    }

    // A toggle's knob animates (MiniToggle's Behavior on x, 120ms); grabbing
    // right after flipping it would catch the fill already switched but the
    // knob still mid-slide. Settle past that before grabbing.
    Timer { id: settle; interval: 220; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function grab(path, cb) {
      if (!path) { cb(); return }
      settle.pending = function () {
        stage.grabToImage(function (r) { r.saveToFile(path); cb() })
      }
      settle.restart()
    }

    // The scripted walk: exercises every kind of row (toggle, stepper,
    // preset cycle, band edit, two-step confirm, async button, nav move,
    // Tab between columns) against the fake service above.
    Timer {
      interval: 300
      running: true
      onTriggered: {
        var initial = { section: settingsView.section, column: settingsView.column, cursor: settingsView.cursor }

        // Tab into the nav column, move to "bar" (index 3), Enter into content.
        settingsView.switchColumn()
        settingsView.move(1); settingsView.move(1); settingsView.move(1)
        var navSection = settingsView.section
        settingsView.act()
        // Toggle "Previous, play/pause and next in the bar" with ←→.
        settingsView.change(1)
        var barToggleSaved = fakeSvc.savedCalls[fakeSvc.savedCalls.length - 1]

        // Sound: the master toggle, then preset cycle, then edit band 0
        // (which switches to custom).
        settingsView.switchColumn(); settingsView.move(-2); settingsView.act()  // bar(3) -> sound(1)
        var soundSection = settingsView.section
        settingsView.change(1)          // cursor 0: Equalizer off -> on
        var eqEnabledAfterToggle = fakeSvc.setting("eqEnabled", false)
        settingsView.move(1)            // cursor -> preset row
        settingsView.change(1)          // flat -> bass
        var presetAfterCycle = fakeSvc.setting("eqPreset", "")

        win.grab(Quickshell.env("SOLFA_SCENE_OUT"), function () {
          settingsView.move(1)            // cursor -> band 0
          settingsView.change(1)          // bass[0] + 1 dB, preset -> custom
          var bandsAfterEdit = Model.parseEqBands(fakeSvc.setting("eqBands", "[]"))
          var presetAfterEdit = fakeSvc.setting("eqPreset", "")

          // Playback: a clean frame of the section, then the sleep timer stepper.
          settingsView.switchColumn(); settingsView.move(1); settingsView.act()  // sound(1) -> playback(2)

          win.grab(Quickshell.env("SOLFA_SCENE_OUT3"), function () {
            settingsView.change(1)
            var sleepAfter = fakeSvc.sleepMode

            // Keys: "All keys" button.
            settingsView.switchColumn(); settingsView.move(2); settingsView.act()  // playback(2) -> keys(4)
            settingsView.move(1)
            settingsView.act()

            // Advanced: a clean frame of the section, then clear cache
            // (async-in-fake, resolves at once) and the two-step erase confirm.
            settingsView.switchColumn(); settingsView.move(1); settingsView.act()  // keys(4) -> advanced(5)

            win.grab(Quickshell.env("SOLFA_SCENE_OUT4"), function () {
              settingsView.move(2)
              settingsView.act()  // Clear cache
              var cacheNoteAfter = settingsView.cacheNote
              settingsView.move(2)
              settingsView.act()  // arm erase
              var eraseArmTimerRunning = settingsView.armTimerRunning
              // Moving off the row disarms it: coming back needs two fresh Enters.
              settingsView.move(1); settingsView.move(-1)
              var eraseArmedAfterMove = settingsView.eraseArmed
              settingsView.act()  // arm erase again
              // The panel closing (the view hidden) disarms it too.
              settingsView.visible = false
              var eraseArmedAfterHide = settingsView.eraseArmed
              settingsView.visible = true
              var eraseCallsBeforeConfirm = fakeSvc.eraseCalls
              settingsView.act()  // arm erase
              var armedAfterFirst = settingsView.eraseArmed
              settingsView.act()  // confirm erase
              var armedAfterSecond = settingsView.eraseArmed

              // Account: entering the section fetches the real account info
              // at once (the fake resolves synchronously); "Switch account"
              // needs one Enter, "Sign out" needs two.
              settingsView.switchColumn(); settingsView.move(-5); settingsView.act()  // advanced(5) -> account(0)
              var accountInfoCallsAfterEnter = fakeSvc.accountInfoCalls
              var accountNameShown = fakeSvc.accountDetails.name
              var accountEmailShown = fakeSvc.accountDetails.email
              var avatarItem = win.find(stage, "accountAvatar")
              var helpItem = win.find(stage, "accountHelp")
              var avatarY = avatarItem ? avatarItem.y : null
              var accountHelpShown = helpItem ? helpItem.text : null

              win.grab(Quickshell.env("SOLFA_SCENE_OUT2"), function () {
                settingsView.act()  // arm Switch account (cursor 0)
                var switchArmedAfterFirst = settingsView.switchArmed
                var switchCallsAfterFirst = fakeSvc.accountSwitchCalls
                settingsView.act()  // confirm Switch account
                var accountSwitchNoteAfter = settingsView.accountNote
                settingsView.move(1)
                settingsView.act()  // arm sign-out
                var signOutArmedAfterFirst = settingsView.signOutArmed
                var signOutCallsAfterFirst = fakeSvc.accountSignOutCalls
                settingsView.act()  // confirm sign-out
                var signOutArmedAfterSecond = settingsView.signOutArmed

                // About: version text, engine version fetched on entry.
                settingsView.switchColumn(); settingsView.move(6); settingsView.act()  // account(0) -> about(6)
                var aboutSection = settingsView.section
                var engineVersionAfter = settingsView.engineVersionText

                // Back affordance and the gear, both reachable with a click.
                var back = win.find(stage, "settingsBack")
                var gear = win.find(stage, "gearButton")

                console.log("STATE " + JSON.stringify({
                  initial: initial,
                  navSection: navSection, barToggleSaved: barToggleSaved,
                  soundSection: soundSection, eqEnabledAfterToggle: eqEnabledAfterToggle, presetAfterCycle: presetAfterCycle,
                  bandsAfterEdit: bandsAfterEdit, presetAfterEdit: presetAfterEdit,
                  sleepCalls: fakeSvc.sleepCalls, sleepAfter: sleepAfter,
                  showAllKeysCount: scene.showAllKeysCount,
                  clearCacheCalls: fakeSvc.clearCacheCalls, cacheNoteAfter: cacheNoteAfter,
                  armedAfterFirst: armedAfterFirst, armedAfterSecond: armedAfterSecond, eraseCalls: fakeSvc.eraseCalls,
                  eraseArmTimerRunning: eraseArmTimerRunning, eraseArmedAfterMove: eraseArmedAfterMove,
                  eraseArmedAfterHide: eraseArmedAfterHide, eraseCallsBeforeConfirm: eraseCallsBeforeConfirm,
                  armTimeoutMs: settingsView.armTimeoutMs,
                  switchArmedAfterFirst: switchArmedAfterFirst, switchCallsAfterFirst: switchCallsAfterFirst,
                  accountInfoCallsAfterEnter: accountInfoCallsAfterEnter,
                  accountNameShown: accountNameShown, accountEmailShown: accountEmailShown,
                  avatarY: avatarY, accountHelpShown: accountHelpShown,
                  accountSwitchCalls: fakeSvc.accountSwitchCalls, accountSwitchNoteAfter: accountSwitchNoteAfter,
                  signOutArmedAfterFirst: signOutArmedAfterFirst, signOutCallsAfterFirst: signOutCallsAfterFirst,
                  signOutArmedAfterSecond: signOutArmedAfterSecond, accountSignOutCalls: fakeSvc.accountSignOutCalls,
                  aboutSection: aboutSection, engineVersionCalls: fakeSvc.engineVersionCalls, engineVersionAfter: engineVersionAfter,
                  solfaVersionShown: fakeSvc.solfaVersion,
                  backHitOk: !!back, gear: gear ? { w: gear.width, h: gear.height, tooltip: gear.tooltipText } : null
                }))
                tc.mouseClick(gear, gear.width / 2, gear.height / 2)
                tc.mouseClick(back, back.width / 2, back.height / 2)
                console.log("CLICKS " + JSON.stringify({ gearClicked: scene.gearClickedCount, backRequested: scene.backRequestedCount }))
                win.mouseWalk()
              })
            })
          })
        })
      }
    }
  }
}
