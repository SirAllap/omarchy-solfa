import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model
import "views" as Views

// The account UI follows the sign-in state (test_account_state.py): the
// header strip's "Sign in" button and "Premium" badge, and Settings >
// Account's rows, against a fake service that mirrors Service.qml's
// signedIn / premium / ready. Steps run one frame apart so the layout has
// settled; logs one "STATE {...}" line and saves a frame per state when
// SOLFA_SCENE_OUT (signed out), _OUT2 (free) and _OUT3 (Premium) are set.
ShellRoot {
  id: scene

  component FakeSvc: QtObject {
    property bool bridgeUp: true
    property bool signingIn: false
    property bool closed: false
    property bool engineReady: true
    property bool signedIn: false
    property bool premiumFlag: false
    readonly property bool ready: bridgeUp && engineReady
    readonly property bool premium: signedIn && premiumFlag
    property var settings: ({})
    function setting(name, fallback) { return fallback }
    property int signInCalls: 0
    function signIn() { signInCalls++ }
    property int accountInfoCalls: 0
    property var accountDetails: ({ name: "", email: "", avatar: "" })
    function accountInfo(cb) {
      accountInfoCalls++
      accountDetails = { name: "Alex Example", email: "alex@example.com", avatar: "" }
      if (cb) cb({ ok: true, data: accountDetails })
    }
    property int switchCalls: 0
    function accountSwitch(cb) { switchCalls++; if (cb) cb({ ok: true, data: {} }) }
    property int signOutCalls: 0
    function accountSignOut(cb) { signOutCalls++; if (cb) cb({ ok: true, data: {} }) }
    function engineVersion(cb) { if (cb) cb({ ok: true, data: { product: "Fake/1" } }) }
    property string solfaVersion: "0.0.0-fixture"
  }
  FakeSvc { id: fakeSvc }

  FloatingWindow {
    id: win
    implicitWidth: 560
    implicitHeight: 260
    visible: true
    color: Color.popups.background

    Item {
      id: stage
      anchors.fill: parent

      Rectangle { anchors.fill: parent; radius: Style.cornerRadius; color: Color.popups.background }

      Views.BrandCorner {
        id: corner
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        svc: fakeSvc
      }

      Views.SettingsView {
        id: settingsView
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        anchors.topMargin: 44
        svc: fakeSvc
      }
    }

    TestCase { id: tc; name: "account"; when: false }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }
    function shown(name) { var it = find(stage, name); return !!it && it.visible }
    function click(name) {
      var it = find(stage, name)
      if (it) tc.mouseClick(it, it.width / 2, it.height / 2)
    }
    // The header's visible items, left to right, must not overlap.
    function stripOverlaps() {
      var kids = []
      for (var i = 0; i < corner.children.length; i++) if (corner.children[i].visible) kids.push(corner.children[i])
      kids.sort(function (a, b) { return a.x - b.x })
      for (var j = 1; j < kids.length; j++) if (kids[j].x < kids[j - 1].x + kids[j - 1].width) return true
      return false
    }
    function snapshot() {
      return {
        signInButton: shown("signInButton"), premiumBadge: shown("premiumBadge"),
        accountSignIn: shown("accountSignIn"), accountSwitch: shown("accountSwitch"), accountSignOut: shown("accountSignOut"),
        handlers: settingsView.handlers.length, cursor: settingsView.cursor,
        overlaps: stripOverlaps(), signInCalls: fakeSvc.signInCalls
      }
    }

    // Saves the stage as a PNG once a toggle's or a fade's animation is done.
    Timer { id: settle; interval: 220; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function grab(path, cb) {
      if (!path) { cb(); return }
      settle.pending = function () { stage.grabToImage(function (r) { r.saveToFile(path); cb() }) }
      settle.restart()
    }

    property var log: ({})
    property int stepIndex: 0
    property var steps: [
      // 0: signed out, engine ready.
      function () { win.log.initialSection = settingsView.section },
      function () {
        var m = win.log
        m.signedOut = win.snapshot()
        win.click("signInButton"); m.callsAfterHeaderClick = fakeSvc.signInCalls
        win.click("accountSignIn"); m.callsAfterSettingsClick = fakeSvc.signInCalls
        settingsView.column = "content"; settingsView.cursor = 0; settingsView.act()
        m.callsAfterKey = fakeSvc.signInCalls
        m.infoCallsSignedOut = fakeSvc.accountInfoCalls
        win.grab(Quickshell.env("SOLFA_SCENE_OUT"), function () { win.next() })
      },
      // Signed in, free account.
      function () { fakeSvc.signedIn = true },
      function () {
        win.log.free = win.snapshot()
        win.log.infoCallsSignedIn = fakeSvc.accountInfoCalls
        win.grab(Quickshell.env("SOLFA_SCENE_OUT2"), function () { win.next() })
      },
      // Signed in, Premium.
      function () { fakeSvc.premiumFlag = true },
      function () {
        win.log.premium = win.snapshot()
        win.grab(Quickshell.env("SOLFA_SCENE_OUT3"), function () { win.next() })
      },
      // Sign out while the cursor is on the second row: the rows shrink to one.
      function () { settingsView.cursor = 1; fakeSvc.signedIn = false },
      function () {
        win.log.afterSignOut = win.snapshot()
        // A stale Premium flag never shows signed out; a starting engine or
        // the sign-in window open shows no button.
        fakeSvc.engineReady = false
      },
      function () {
        win.log.engineStarting = win.snapshot()
        fakeSvc.engineReady = true; fakeSvc.signingIn = true
      },
      function () {
        win.log.signingIn = win.snapshot()
        // Signed in with Premium, but the engine is down: nothing is known.
        fakeSvc.signingIn = false; fakeSvc.signedIn = true; fakeSvc.premiumFlag = true; fakeSvc.engineReady = false
      },
      function () {
        win.log.premiumEngineDown = win.snapshot()
        console.log("STATE " + JSON.stringify(win.log))
        Qt.quit()
      }
    ]
    function next() { stepTimer.restart() }
    Timer {
      id: stepTimer
      interval: 250
      onTriggered: {
        if (win.stepIndex >= win.steps.length) return
        var fn = win.steps[win.stepIndex++]
        try { fn() } catch (e) { console.log("STEPERROR " + e); Qt.quit(); return }
        // Steps that grab call next() themselves once the file is written.
        if (fn.toString().indexOf("grab") < 0) win.next()
      }
    }
    Component.onCompleted: stepTimer.start()
  }
}
