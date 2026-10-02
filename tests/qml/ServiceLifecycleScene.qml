import QtQuick
import QtQml
import Quickshell

// The real Service.qml and BarWidget.qml in a private Quickshell, offscreen,
// driven the way the Omarchy shell drives them: one Service, a bar widget
// that is built, handed `bar` and then `settings` (in that order), and
// destroyed and built again when another widget in the bar moves.
// tests/test_widget_move.py gives it a fake bridge and a list of steps in
// SOLFA_SCENE_STEPS; every step is logged, and the fake bridge logs what it
// is asked (a bridge.quit among it).
ShellRoot {
  id: scene

  property var steps: JSON.parse(Quickshell.env("SOLFA_SCENE_STEPS") || "[]")
  property var widgets: ({})
  property var svc: null

  QtObject {
    id: shellApi
    function serviceFor(id) { return scene.svc }
    function updateEntryInline(id, settings) { console.log("WRITE " + JSON.stringify(settings)); return true }
    function summon() { return true }
    function hide() { return true }
    function toggle() { return true }
  }

  QtObject {
    id: barApi
    property var shell: shellApi
    property bool vertical: false
    property int barSize: 26
    property color barForeground: "white"
    property string fontFamily: "monospace"
    function showTooltip() {}
    function hideTooltip() {}
  }

  Component { id: serviceComponent; Service {} }
  Component { id: widgetComponent; BarWidget {} }
  Item { id: stage }

  // The shell's Bar.injectProps: `bar` first, then `settings`; and once
  // more on the next turn of the event loop.
  function inject(w, entry) {
    w.bar = barApi
    w.moduleName = "io.github.sirallap.solfa"
    w.settings = JSON.parse(JSON.stringify(entry))
  }

  function run(step) {
    console.log("STEP " + JSON.stringify(step))
    if (step.do === "service") {
      scene.svc = serviceComponent.createObject(stage)
    } else if (step.do === "dropService") {
      if (scene.svc) scene.svc.destroy()
      scene.svc = null
    } else if (step.do === "build") {
      var w = widgetComponent.createObject(stage)
      var ws = Object.assign({}, scene.widgets)
      ws[step.name] = w
      scene.widgets = ws
      scene.inject(w, step.entry)
      Qt.callLater(function () { scene.inject(w, step.entry) })
    } else if (step.do === "destroy") {
      if (scene.widgets[step.name]) scene.widgets[step.name].destroy()
    } else if (step.do === "inject") {
      scene.inject(scene.widgets[step.name], step.entry)
    } else if (step.do === "save") {
      scene.svc.saveSetting(step.key, step.value)
    } else if (step.do === "quit") {
      Qt.quit()
    }
  }

  Instantiator {
    model: scene.steps
    delegate: Timer {
      required property var modelData
      interval: modelData.at
      running: true
      onTriggered: scene.run(modelData)
    }
  }
}
