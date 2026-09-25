import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "views" as Views

// The sign-in card says when a sign-in window closed without the account in
// (test_signin_card.py): against a fake service with Service.qml's
// signingIn / gated / signinError. Logs one "STATE {...}" line and saves a
// frame of the failed card when SOLFA_SCENE_OUT is set.
ShellRoot {
  component FakeSvc: QtObject {
    property bool signingIn: false
    property bool gated: false
    property string signinError: ""
    property var engine: ({ shown: false })
    property var account: ({ host: "music.youtube.com" })
    property int signInCalls: 0
    function signIn() { signInCalls++ }
  }
  FakeSvc { id: fakeSvc }

  FloatingWindow {
    id: win
    implicitWidth: 420
    implicitHeight: 200
    visible: true
    color: Color.popups.background

    Item {
      id: stage
      anchors.fill: parent
      Views.SignInCard { id: card; width: parent.width - 40; x: 20; y: 20; svc: fakeSvc }
    }
    function texts() { return { title: card.children[0].text, body: card.children[1].text } }
    property var log: ({})
    property int stepIndex: 0
    property var steps: [
      function () { win.log.signedOut = win.texts() },
      function () { fakeSvc.signinError = "signin-failed" },
      function () {
        win.log.failed = win.texts()
        var out = Quickshell.env("SOLFA_SCENE_OUT")
        if (out) stage.grabToImage(function (r) { r.saveToFile(out) })
      },
      // A new try: the window is open, the old failure is not shown.
      function () { fakeSvc.signingIn = true; fakeSvc.gated = true },
      function () { win.log.retrying = win.texts(); fakeSvc.engine = { shown: false, signinSaving: true } },
      function () {
        win.log.saving = win.texts()
        console.log("STATE " + JSON.stringify(win.log))
        Qt.quit()
      }
    ]
    Timer {
      interval: 250; repeat: true; running: true
      onTriggered: {
        if (win.stepIndex >= win.steps.length) return
        try { win.steps[win.stepIndex++]() } catch (e) { console.log("STEPERROR " + e); Qt.quit() }
      }
    }
  }
}
