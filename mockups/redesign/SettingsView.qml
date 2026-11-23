import QtQuick

// Replaces the whole panel. section: account | accountout | sound | playback | bar | keys | advanced | about
// mode: normal | open (a menu is open) | confirm (erase asks first)
Item {
  id: v
  property string section: "sound"
  property string mode: "normal"
  property bool active: true
  readonly property var rail: [
    { key: "account", icon: "user", title: "Account" }, { key: "sound", icon: "volume", title: "Sound" },
    { key: "playback", icon: "play", title: "Playback" }, { key: "bar", icon: "bolt", title: "Bar and alerts" },
    { key: "keys", icon: "keyboard", title: "Keys" }, { key: "advanced", icon: "gear", title: "Advanced" },
    { key: "about", icon: "album", title: "About" } ]
  readonly property string sec: section === "accountout" ? "account" : section
  readonly property int idx: { for (var i = 0; i < rail.length; i++) if (rail[i].key === sec) return i; return 0 }

  // header
  Rectangle { y: 14; x: 20; width: bk.width + 24; height: 34; radius: 17; color: Theme.wash; border.width: 1; border.color: Theme.hair
    Row { id: bk; anchors.centerIn: parent; spacing: 4; Icon { name: "back"; size: 15; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter } Text { text: "Settings"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter } } }
  KeyCap { y: 22; anchors.right: parent.right; anchors.rightMargin: 24; keys: "esc"; label: "close" }

  // rail with a sliding pill
  Rectangle { x: 20; y: 70; width: 52; height: v.rail.length * 52 + 8; radius: 26; color: Theme.wash; border.width: 1; border.color: Theme.hair }
  Rectangle { id: rpill; x: 24; width: 44; height: 44; radius: 22; y: 74 + v.idx * 52
    Behavior on y { enabled: !Motion.reduce; SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.4 } }
    color: Theme.a(Theme.accent, 0.2); border.width: 1; border.color: Theme.a(Theme.accent, 0.5)
    Glow { anchors.centerIn: parent; width: 120; height: 120; color: Theme.accent; strength: 0.16 } }
  Repeater { model: v.rail
    Item { x: 24; y: 74 + index * 52; width: 44; height: 44
      Icon { anchors.centerIn: parent; name: modelData.icon; size: 19; color: index === v.idx ? Theme.accent : Theme.dim; Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 200 } } } } }

  // page
  Item { id: page; x: 92; y: 66; width: parent.width - 92 - 24; height: parent.height - 66 - 20; clip: false
    Text { id: heading; text: v.rail[v.idx].title; color: Theme.fg; font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: -0.5 }

    // ---- Account
    Item { y: 44; width: parent.width; visible: v.sec === "account"
      Rectangle { width: parent.width; height: 120; radius: 20; color: Theme.raised; border.width: 1; border.color: Theme.hair
        Glow { x: -40; y: -40; width: 240; height: 240; color: v.section === "account" ? Theme.ok : Theme.accent; strength: 0.18 }
        Row { x: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 14
          Rectangle { width: 56; height: 56; radius: 28; color: v.section === "account" ? "transparent" : Theme.wash; border.width: 1; border.color: Theme.hair
            gradient: v.section === "account" ? av : null
            Icon { anchors.centerIn: parent; name: "user"; size: 24; color: v.section === "account" ? "#14101f" : Theme.dim } }
          Column { anchors.verticalCenter: parent.verticalCenter; spacing: 5
            Text { text: v.section === "account" ? "Signed in to YouTube Music" : "Signed out"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { text: v.section === "account" ? "Premium · library and likes on" : "Library and likes are off"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 }
            Btn { compact: true; kind: v.section === "account" ? "quiet" : "primary"; icon: v.section === "account" ? "" : "user"; text: v.section === "account" ? "Sign out" : "Sign in" } } }
      }
      Gradient { id: av; GradientStop { position: 0; color: Theme.accent } GradientStop { position: 1; color: Theme.accent2 } }
      SettingRow { y: 136; label: "Show Premium badge"; help: "In the panel header"; Toggle { checked: v.section === "account" } }
    }

    // ---- Sound
    Item { y: 44; width: parent.width; visible: v.sec === "sound"
      Column { width: parent.width
        SettingRow { label: "Equalizer"; Select { value: "Warm"; options: ["Flat", "Warm", "Bass boost", "Vocal", "Bright"]; open: v.mode === "open" } }
        Item { width: parent.width; height: 132
          Row { x: 4; y: 10; spacing: 22
            Repeater { model: [0.5, 0.68, 0.46, 0.58, 0.72]
              Item { width: 40; height: 112
                Rectangle { x: 17; y: 0; width: 6; height: 84; radius: 3; color: Qt.rgba(1, 1, 1, 0.1) }
                Rectangle { x: 17; y: 84 * (1 - modelData); width: 6; height: 84 * modelData; radius: 3
                  gradient: Gradient { GradientStop { position: 0; color: Theme.accent2 } GradientStop { position: 1; color: Theme.accent } } }
                Glow { x: 20 - 24; y: 84 * (1 - modelData) - 24; width: 48; height: 48; color: Theme.accent2; strength: 0.4 }
                Rectangle { x: 12; y: 84 * (1 - modelData) - 8; width: 16; height: 16; radius: 8; color: "#fff" }
                Text { y: 94; width: 40; horizontalAlignment: Text.AlignHCenter; text: ["60", "250", "1k", "4k", "12k"][index]; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 } } } } }
        SettingRow { label: "Preamp"; Slider { width: 150; value: 0.55; labelRight: "+2 dB" } }
        SettingRow { label: "Even out loudness"; help: "Quiet and loud songs sound alike"; Toggle { checked: true } }
        SettingRow { label: "Sleep timer"; Select { value: "Off"; options: ["Off", "15 minutes", "30 minutes", "1 hour"] } }
      } }

    // ---- Playback
    Item { y: 44; width: parent.width; visible: v.sec === "playback"
      Column { width: parent.width
        SettingRow { label: "When Solfa starts"; Select { value: "Resume"; options: ["Do nothing", "Resume", "Play my radio"] } }
        SettingRow { label: "Volume at start"; Slider { width: 150; value: 0.6; labelRight: "60%" } }
        SettingRow { label: "Start with the shell"; help: "Turns YouTube Music on at login"; Toggle { checked: true } }
        SettingRow { label: "Browser for the engine"; Select { value: "Brave"; options: ["Chromium", "Brave", "Chrome"]; open: v.mode === "open" } }
        SettingRow { label: "Brave's ad blocker"; help: "Keeps Brave's shields on"; Toggle { checked: false } }
      } }

    // ---- Bar and alerts
    Item { y: 44; width: parent.width; visible: v.sec === "bar"
      Column { width: parent.width
        SettingRow { label: "Previous, play/pause and next in the bar"; Toggle { checked: true } }
        SettingRow { label: "Song title in the bar"; Toggle { checked: true } }
        SettingRow { label: "Title width in the bar"; Slider { width: 120; value: 0.45; labelRight: "180" } }
        SettingRow { label: "Show in the bar when nothing is loaded"; Toggle { checked: false } }
        SettingRow { label: "Notify when the song changes"; help: "A small card with the cover"; Toggle { checked: true } }
      } }

    // ---- Keys
    Item { y: 44; width: parent.width; visible: v.sec === "keys"
      Column { width: parent.width
        SettingRow { label: "Global shortcuts"; help: "Play, next, previous and like from anywhere"; Toggle { checked: true } }
        SettingRow { label: "Every key"; Btn { compact: true; icon: "keyboard"; text: "All keys" } }
        Item { width: parent.width; height: 8 }
        Grid { columns: 2; columnSpacing: 20; rowSpacing: 10; width: parent.width
          Repeater { model: [["↵", "play"], ["space", "pause"], ["n", "next"], ["p", "previous"], ["l", "like"], ["/", "search"], ["tab", "next tab"], ["e", "play next"], ["a", "add to queue"], ["R", "start radio"], ["[ ]", "section"], ["esc", "back"]]
            KeyCap { keys: modelData[0]; label: modelData[1] } } } } }

    // ---- Advanced
    Item { y: 44; width: parent.width; visible: v.sec === "advanced"
      Column { width: parent.width
        SettingRow { label: "Refresh the page when memory passes"; help: "Applies on next start"; Select { value: "1 GB"; options: ["Never", "700 MB", "1 GB", "2 GB"] } }
        SettingRow { label: "Refresh at least every"; help: "Applies on next start"; Select { value: "12 hours"; options: ["Never", "6 hours", "12 hours", "24 hours"] } }
        SettingRow { label: "Reduce motion"; help: "Stops springs, glows, comets and typing"; Toggle { checked: Motion.reduce; onToggled: Motion.reduce = checked } }
        SettingRow { label: "Clear cache"; help: "Keeps you signed in"; Btn { compact: true; text: "Clear" } }
        SettingRow { label: "Reset settings"; Btn { compact: true; text: "Reset" } }
        SettingRow { label: "Erase engine data"; help: v.mode === "confirm" ? "Signs you out and deletes the profile." : "Deletes the profile and signs you out"; danger: true
          Row { spacing: 6
            Btn { visible: v.mode === "confirm"; compact: true; text: "Keep" }
            Btn { compact: true; kind: "danger"; icon: "trash"; text: v.mode === "confirm" ? "Yes, erase" : "Erase" } } }
      } }

    // ---- About
    Item { y: 44; width: parent.width; visible: v.sec === "about"
      Column { width: parent.width; spacing: 14
        Rectangle { width: parent.width; height: 150; radius: 20; color: Theme.raised; border.width: 1; border.color: Theme.hair
          Glow { anchors.centerIn: parent; width: 360; height: 240; color: Theme.accent2; strength: 0.16 }
          Column { anchors.centerIn: parent; spacing: 8
            Logo { size: 54; anchors.horizontalCenter: parent.horizontalCenter }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Solfa 0.1.0"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Engine: Chromium 132"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 } } }
        Text { width: parent.width; wrapMode: Text.WordWrap; text: "A YouTube Music player for the Omarchy shell. The web app plays the audio. It is never seen and never takes focus."; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 }
        Row { spacing: 8; Btn { icon: "globe"; text: "Changelog" } Btn { icon: "warn"; text: "Report an issue" } }
      } }
  }
}
