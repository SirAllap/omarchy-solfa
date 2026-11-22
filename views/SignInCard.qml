import QtQuick
import "../lib"
import qs.Ui
import qs.Commons

// Signing in (in a plain Google window of its own, which Google accepts),
// and the way out of any page that is not YouTube Music (Google's cookie
// page, a Google page, or a page that failed to load).
Column {
  id: card

  property var svc: null
  property QtObject bar: null
  readonly property color fg: bar ? bar.foreground : Calm.fg
  // The calm error tone of the mockup (Theme.err).
  readonly property color err: Qt.rgba(0.725, 0.439, 0.486, 1)
  readonly property string family: Calm.font
  // gated: the engine sits on a page other than YouTube Music.
  readonly property bool waiting: svc ? svc.gated : false
  readonly property bool shown: svc && svc.engine ? !!svc.engine.shown : false
  readonly property bool signingIn: svc ? svc.signingIn : false
  // The window reached the app and is hidden: Google's cookie is being saved.
  readonly property bool saving: signingIn && svc && svc.engine ? !!svc.engine.signinSaving : false
  readonly property string host: svc && svc.account ? (svc.account.host || "") : ""
  readonly property bool cookies: host === "consent.youtube.com"
  readonly property bool google: /(^|\.)google\.[a-z.]+$/.test(host) || host === "www.youtube.com"
  readonly property bool broken: waiting && !signingIn && !cookies && !google
  // The last sign-in window closed without the account in.
  readonly property bool failed: svc ? !!svc.signinError && !signingIn : false

  spacing: 12

  // Something is happening while a sign-in runs: Solfa's disc breathes.
  Item {
    id: pulse
    anchors.horizontalCenter: parent.horizontalCenter
    width: 62
    height: 62
    readonly property bool bad: card.failed && !card.signingIn
    // The calm tile.
    Rectangle {
      anchors.fill: parent
      radius: 20
      color: Calm.a(pulse.bad ? card.err : Calm.accent, 0.16)
      border.width: 1
      border.color: Calm.a(pulse.bad ? card.err : Calm.accent, 0.45)
    }
    // the disc of Solfa's mark while signing in, a person otherwise, a bang when it failed
    Text {
      anchors.centerIn: parent
      text: card.signingIn ? String.fromCodePoint(0xF0025) : card.failed ? "!" : String.fromCodePoint(0xF0004)
      textFormat: Text.PlainText
      color: pulse.bad ? card.err : Calm.accent
      font.family: card.family
      font.pixelSize: 26
      font.bold: pulse.bad
    }
    // Drawn once as a smooth texture, so scaling does not shimmer.
    layer.enabled: true
    layer.smooth: true
    layer.mipmap: true
    transformOrigin: Item.Center
    // A slow breath: grows and brightens, then settles, never a hard beat.
    SequentialAnimation {
      loops: Animation.Infinite
      running: card.signingIn && card.visible
      ParallelAnimation {
        NumberAnimation { target: pulse; property: "scale"; from: 0.92; to: 1.08; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { target: pulse; property: "opacity"; from: 0.55; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
      }
      ParallelAnimation {
        NumberAnimation { target: pulse; property: "scale"; from: 1.08; to: 0.92; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { target: pulse; property: "opacity"; from: 1.0; to: 0.55; duration: 1400; easing.type: Easing.InOutSine }
      }
    }
  }

  Text {
    width: parent.width
    text: card.saving ? "Saving your sign-in"
      : card.signingIn ? "Sign in in the Google window"
      : !card.waiting ? (card.failed ? "Signing in did not finish" : "Sign in to YouTube Music")
      : card.broken ? "YouTube Music did not load"
      : card.shown ? "Finish in the YouTube Music window"
      : card.cookies ? "YouTube Music needs you once"
      : "Signing in was not finished"
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    color: card.fg
    font.family: card.family
    font.pixelSize: 18
    font.bold: true
  }

  Text {
    width: parent.width
    text: card.saving
      ? "You are in. Chrome writes the new sign-in cookies to disk every 30 seconds, and Solfa waits for that so the sign-in is not lost. This takes under a minute, only this once; no need to do anything."
      : card.signingIn
      ? "YouTube Music waits while it is open. Solfa closes the window soon after you are in, and plays again; closing it yourself also works."
      : !card.waiting && card.failed
      ? "YouTube Music is still signed out. Try again: Google asks which account this time."
      : !card.waiting
      ? "Your playlists, liked songs and likes need your Google account. A Google window opens once; Solfa closes it when you are signed in."
      : card.broken ? "Check the connection, then try again."
      : card.shown ? "Answer Google's cookie question, then hide the window."
      : card.cookies ? "In the EU, Google asks every new browser whether YouTube may use cookies for tracking and personalised ads. Solfa is a new browser to Google, so it asks once. Your answer is sent to Google and kept. Music plays either way."
      : "Sign in, or go back to YouTube Music without signing in."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    color: Util.alpha(card.fg, 0.64)
    font.family: card.family
    font.pixelSize: 13
  }

  // Google's cookie question: the answer is the main thing here, its two
  // choices side by side and alike (neither one is pushed). Signing in or
  // answering in the window are other ways, set apart below.
  readonly property bool asking: waiting && cookies && !shown

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 8

    HitButton {
      visible: !card.shown && !card.broken && !card.signingIn && !card.asking
      text: "Sign in"
      fontFamily: card.family
      foreground: Calm.onAccent
      background: Calm.accent
      radius: height / 2
      onClicked: if (card.svc) card.svc.signIn()
    }
    HitButton {
      // Closes the sign-in window; YouTube Music comes back signed out.
      // Not while the sign-in is being saved: cancelling then loses it.
      visible: card.signingIn && !card.saving
      text: "Cancel"
      fontFamily: card.family
      foreground: card.err
      background: Util.alpha(card.err, 0.14)
      radius: height / 2
      onClicked: if (card.svc) card.svc.hideWindow()
    }
    HitButton {
      visible: card.shown
      text: "Hide the window"
      fontFamily: card.family
      foreground: card.fg
      background: Util.alpha(card.fg, 0.08)
      radius: height / 2
      onClicked: if (card.svc) card.svc.hideWindow()
    }
    HitButton {
      // Hiding also takes the engine back to the app from a sign-in page.
      visible: card.waiting && card.google && !card.shown && !card.signingIn
      text: "Back to YouTube Music"
      fontFamily: card.family
      foreground: card.fg
      background: Util.alpha(card.fg, 0.08)
      radius: height / 2
      onClicked: if (card.svc) card.svc.hideWindow()
    }
    HitButton {
      visible: card.broken
      text: "Try again"
      fontFamily: card.family
      foreground: Calm.onAccent
      background: Calm.accent
      radius: height / 2
      onClicked: if (card.svc) card.svc.restartEngine()
    }
  }

  // ---- the cookie question
  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    visible: card.asking
    spacing: 10

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Answer Google's cookie question"
      textFormat: Text.PlainText
      color: card.fg
      font.family: card.family
      font.pixelSize: 13
      font.bold: true
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 12
      HitButton {
        text: "Reject all"
        fontFamily: card.family
        foreground: Calm.accent
        bordered: true
        radius: height / 2
        onClicked: if (card.svc) card.svc.answerCookies(false)
      }
      HitButton {
        text: "Accept all"
        fontFamily: card.family
        foreground: Calm.accent
        bordered: true
        radius: height / 2
        onClicked: if (card.svc) card.svc.answerCookies(true)
      }
    }
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 220
      height: 1
      color: Util.alpha(card.fg, 0.2)
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 4
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Or:"
        textFormat: Text.PlainText
        color: Util.alpha(card.fg, 0.55)
        font.family: card.family
        font.pixelSize: 11
      }
      HitButton {
        text: "Sign in with Google"
        fontFamily: card.family
        foreground: Util.alpha(card.fg, 0.75)
        onClicked: if (card.svc) card.svc.signIn()
      }
      HitButton {
        text: "Answer in the window"
        fontFamily: card.family
        foreground: Util.alpha(card.fg, 0.75)
        onClicked: if (card.svc) card.svc.showWindow()
      }
    }
  }
}
