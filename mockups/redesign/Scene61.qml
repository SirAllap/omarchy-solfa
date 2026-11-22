import QtQuick
HostWindow {
  settleMs: 1500
  PanelFrame { overlay: "settings"; settingsSection: "advanced"; Component.onCompleted: Motion.reduce = true }
}
