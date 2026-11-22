import QtQuick
import qs.Ui
import qs.Commons
import "lib/Model.js" as Model
import "lib/Icons.js" as Icons
import "lib/Calm.js" as Calm
import "views" as Views

// The panel: now playing at the top, then Queue, Search, Library, Lyrics
// and History, and pages (album, artist, playlist) opened from any list.
// Everything works from the keyboard; the hint line says how.
Panel {
  id: root
  moduleName: "io.github.sirallap.solfa"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null

  readonly property color fg: Calm.fg
  readonly property string family: Calm.font

  readonly property var tabs: [
    { key: "queue", label: "Queue", icon: Icons.tabQueue }, { key: "search", label: "Search", icon: Icons.search },
    { key: "library", label: "Library", icon: Icons.tabLibrary }, { key: "lyrics", label: "Lyrics", icon: Icons.tabLyrics },
    { key: "history", label: "History", icon: Icons.tabHistory }
  ]
  property string tab: "queue"
  property var pages: []
  readonly property var view: pages.length > 0 ? detailView
    : tab === "queue" ? queueView : tab === "search" ? searchView : tab === "library" ? libraryView : tab === "history" ? historyView : lyricsView
  property bool allKeys: false
  property string flash: ""
  // Settings replaces the panel body; the gear in BrandCorner and Esc are
  // the only ways in and out — no new key letter is spent on it.
  property bool settingsOpen: false
  // "Save to playlist": the song being saved ({ videoId, title }), or null.
  property var saveItem: null
  readonly property bool saveOpen: saveItem !== null
  function toggleSettings() {
    if (!root.settingsOpen) root.saveItem = null
    root.settingsOpen = !root.settingsOpen
  }
  function closeSettings() { root.settingsOpen = false }

  onOpenedChanged: {
    if (svc) svc.panelOpen = opened
    if (!opened) { allKeys = false; settingsOpen = false; saveItem = null; return }
    if (svc) svc.lastError = ""  // old news from while it was closed
    if (svc && !svc.hasTrack && tab === "queue") tab = "search"
    // With autostart off, opening the panel is what starts YouTube Music.
    if (svc && svc.bridgeUp && svc.engine.status === "stopped") svc.startEngine()
    Qt.callLater(function () {
      root.focusKeys()
      if (root.view && root.view.shown) root.view.shown()
    })
  }

  function focusKeys() { keys.forceActiveFocus() }

  function showTab(key) {
    pages = []
    tab = key
    Qt.callLater(function () {
      if (root.view.shown) root.view.shown()
      if (key === "search") searchView.focusInput()
      else root.focusKeys()
    })
  }

  function cycleTab(d) {
    var i = 0
    for (var k = 0; k < tabs.length; k++) if (tabs[k].key === tab) i = k
    showTab(tabs[(i + d + tabs.length) % tabs.length].key)
  }

  function openPage(item, params) {
    if (!item || !item.browseId) return
    var p = { id: item.browseId, title: item.title || "", params: params || "" }
    pages = pages.concat([p])
    detailView.open(p)
    focusKeys()
  }

  function back() {
    if (pages.length === 0) { root.close(); return }
    var rest = pages.slice(0, -1)
    pages = rest
    if (rest.length) detailView.open(rest[rest.length - 1])
    focusKeys()
  }

  // The song a row stands for, or else the one playing: what S saves.
  function saveRow(row) {
    var it = row && row.item && row.item.videoId ? row.item : (svc && svc.hasTrack && !svc.isAd ? { videoId: svc.videoId, title: svc.title } : null)
    if (it) openSave(it)
  }
  function openSave(item) {
    if (!item || !item.videoId || !svc) return
    if (!svc.signedIn) { say("Sign in to save songs to a playlist"); return }
    root.allKeys = false
    root.saveItem = { videoId: item.videoId, title: item.title || "" }
  }
  function closeSave() {
    root.saveItem = null
    focusKeys()
  }

  function say(text) { root.flash = text; flashTimer.restart() }
  Timer { id: flashTimer; interval: 2600; onTriggered: root.flash = "" }

  // Only the open panel shows an error (there is one panel per bar, and a
  // closed one would swallow it).
  Connections {
    target: root.svc
    function onLastErrorChanged() { if (root.opened && root.svc.lastError) { root.say(root.svc.lastError); root.svc.lastError = "" } }
  }

  // The bar matches panels by the widget that hosts them, not by this item.
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // ---- rows: what Enter and the row buttons do, the same everywhere

  function itemActions(row) {
    var it = row && row.item
    if (!it) return []
    if (it.videoId) return [
      { name: "next", icon: Icons.playNext, tip: "Play next (e)" },
      { name: "queue", icon: Icons.plus, tip: "Add to queue (a)" },
      { name: "radio", icon: Icons.radio, tip: "Start radio (R)" },
      { name: "save", icon: Icons.savePlaylist, tip: "Save to a playlist (S)" }
    ]
    if (it.kind === "artist") return [{ name: "play", icon: Icons.shuffle, tip: "Shuffle this artist" }]
    if (it.playlistId) return [{ name: "play", icon: Icons.play, tip: "Play" }]
    return []
  }

  function activateRow(row, contextList) {
    var it = row && row.item
    if (!it || !svc) return
    if (it.videoId) {
      var args = { videoId: it.videoId }
      if (contextList) args.playlistId = contextList
      else if (it.playlistId) args.playlistId = it.playlistId
      svc.request("play", args, function (r) { if (r.ok) root.say("Playing " + it.title); else svc.report(r.error) })
    } else if (it.browseId) {
      openPage(it)
    }
  }

  function runAction(name, row) {
    var it = row && row.item
    if (!it || !svc) return
    if (name === "next" || name === "queue") {
      svc.enqueue(it, name === "next", function (r) {
        if (r.ok) root.say(name === "next" ? "Plays next: " + it.title : "Added to the queue: " + it.title)
        else svc.report(r.error)
      })
    } else if (name === "save") {
      root.saveRow(row)
    } else if (name === "radio") {
      svc.radioFor(it)
      root.say("Radio from " + it.title)
    } else if (name === "play") {
      svc.playItem(it, function (r) { if (r.ok) root.say("Playing " + it.title); else svc.report(r.error) })
    }
  }

  // ---- keys

  function onKey(event) {
    var t = event.text
    var k = event.key
    var inField = root.pages.length === 0 && root.tab === "search" && searchView.inputFocused
    if (k === Qt.Key_Escape) {
      if (root.allKeys) root.allKeys = false
      else if (root.saveOpen) saveView.back()
      else if (root.settingsOpen) root.closeSettings()
      else root.back()
      event.accepted = true
      return
    }
    // Signing in: the keyboard may fall back here while Google's window is
    // open or hidden (saving). A stray key must not cancel it or start
    // another; the card's Cancel button is the way out.
    if (root.svc && root.svc.signingIn) {
      event.accepted = true
      return
    }
    // The picker's field takes the typing; a key that reaches here means the
    // field lost the focus (a click elsewhere): give it back, nothing else.
    if (root.saveOpen) {
      saveView.focusField()
      event.accepted = true
      return
    }
    if (root.settingsOpen) {
      if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { settingsView.switchColumn(); event.accepted = true; return }
      if (k === Qt.Key_Down) { settingsView.move(1); event.accepted = true; return }
      if (k === Qt.Key_Up) { settingsView.move(-1); event.accepted = true; return }
      if (k === Qt.Key_Left) { settingsView.change(-1); event.accepted = true; return }
      if (k === Qt.Key_Right) { settingsView.change(1); event.accepted = true; return }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { settingsView.act(); event.accepted = true; return }
      event.accepted = true
      return
    }
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      root.switchPanel((event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1)
      event.accepted = true
      return
    }
    if (inField) {
      if (k === Qt.Key_Up) { event.accepted = true }
      return
    }
    var v = root.view
    var cur = v && v.current ? v.current : null
    if (k === Qt.Key_Down || t === "j") { v.move(1); event.accepted = true; return }
    if (k === Qt.Key_Up || t === "k") { v.move(-1); event.accepted = true; return }
    if (k === Qt.Key_Left || t === "h") { if (root.pages.length) root.back(); else root.cycleTab(-1); event.accepted = true; return }
    if (k === Qt.Key_Right || t === "l") { if (!root.pages.length) root.cycleTab(1); event.accepted = true; return }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (svc.closed) svc.startEngine()
      else if (v === queueView) queueView.activate()
      else if (v === libraryView && !libraryView.signedIn) svc.signIn()
      else if (cur) root.activateRow(cur, v === detailView ? detailView.contextList() : "")
      event.accepted = true
      return
    }
    if (k === Qt.Key_Space) { svc.togglePlaying(); event.accepted = true; return }
    if (k === Qt.Key_Backspace) { root.back(); event.accepted = true; return }
    if (k === Qt.Key_Delete) { if (v === queueView) queueView.key("x"); event.accepted = true; return }
    if (!t) return
    if (v && v.key && v.key(t)) { event.accepted = true; return }
    var handled = true
    switch (t) {
      case "/": root.showTab("search"); break
      case "1": root.showTab("queue"); break
      case "2": root.showTab("search"); break
      case "3": root.showTab("library"); break
      case "4": root.showTab("lyrics"); break
      case "5": root.showTab("history"); break
      case "n": svc.next(); break
      case "p": svc.previous(); break
      case ",": svc.seekBy(-10); break
      case ".": svc.seekBy(10); break
      case "-": svc.nudgeVolume(-1); break
      case "=": case "+": svc.nudgeVolume(1); break
      case "m": svc.toggleMute(); break
      case "f": svc.toggleLike(); break
      case "d": svc.dislike(); break
      case "r": svc.cycleRepeat(); break
      case "s": svc.shuffle(); root.say("Queue shuffled"); break
      case "a": if (cur) root.runAction("queue", cur); break
      case "e": if (cur) root.runAction("next", cur); break
      case "R": if (cur && cur.item && cur.item.videoId) root.runAction("radio", cur); else if (svc.hasTrack) { svc.radioFor(svc.player); root.say("Radio from " + svc.title) } break
      case "S": root.saveRow(cur); break
      case "g": root.openArtist(cur); break
      case "o": root.openAlbum(cur); break
      case "[": if (v === searchView) searchView.cycleFilter(-1); else if (v === libraryView) libraryView.cycleSection(-1); break
      case "]": if (v === searchView) searchView.cycleFilter(1); else if (v === libraryView) libraryView.cycleSection(1); break
      case "w": if (svc.gated) svc.signIn(); else svc.showWindow(); break
      case "W": svc.hideWindow(); break
      case "i": if (brand.showSignIn) svc.signIn(); else handled = false; break
      case "?": root.allKeys = !root.allKeys; break
      default: handled = false
    }
    event.accepted = handled
  }

  // g / o: the artist or album of the row under the cursor, else of the song.
  function openArtist(row) {
    var it = row && row.item && row.item.videoId ? row.item : (svc.hasTrack ? svc.player : null)
    var a = it && it.artists && it.artists.length && it.artists[0].id ? it.artists[0] : null
    if (a) openPage({ browseId: a.id, title: a.name })
  }
  function openAlbum(row) {
    var it = row && row.item && row.item.videoId ? row.item : (svc.hasTrack ? svc.player : null)
    if (it && it.album && it.album.id) openPage({ browseId: it.album.id, title: it.album.name })
  }


  // ---- surface

  Item { id: anchorDummy; visible: false }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem || anchorDummy
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    // The shell lets a plugin set the border (KeyboardPanel.qml:69): a hairline
    // in place of the theme's lilac frame. Its radius (:517) and background
    // (:514) are fixed there; the fill below follows that radius.
    borderSpec: Border.flat(Calm.hair, 1)
    contentWidth: panel.fittedContentWidth(Style.space(460))
    // Gated or off, the card is all there is: no empty stage under it.
    contentHeight: root.svc && root.svc.gated && !root.settingsOpen
      ? panel.fittedContentHeight(hero.implicitHeight + gate.implicitHeight + Style.space(20))
      : root.svc && root.svc.closed && !root.settingsOpen
      ? panel.fittedContentHeight(hero.implicitHeight + offCard.implicitHeight + Style.space(28))
      : panel.cappedContentHeight(Style.space(780))

    // A plain Item, not a FocusScope: a scope hands focus back to the child
    // that had it, so the search field would keep the keys after Enter.
    // Keys the field does not take still bubble up to here.
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (event) { root.onKey(event) }

      // The calm graphite fill, inside the shell's own frame: the same corner
      // radius (less the border the shell draws), and no border of its own,
      // so there is one frame and one radius.
      Rectangle {
        z: -2
        anchors.fill: parent
        anchors.margins: -Style.spacing.popupPadding
        // The shell's real border width (zero in the test stand-in, which draws none).
        radius: Math.max(0, Style.cornerRadius - Border.top(panel.borderSpec))
        color: Calm.surface
      }

      Views.NowPlaying {
        id: hero
        objectName: "panelHero"
        // Settings replaces the whole body: no hero, no transport, no tabs.
        visible: !root.settingsOpen
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        svc: root.svc
        bar: root.bar
        topInset: brand.height
        onSaveRequested: root.saveRow(null)
      }

      // Solfa's name and the power button, top right: far from play.
      Views.BrandCorner {
        id: brand
        objectName: "panelBrand"
        anchors.top: parent.top
        anchors.right: parent.right
        // The power button's box reaches into the card's padding, like "?".
        anchors.rightMargin: -Math.min(Style.space(8), Math.max(0, Style.spacing.popupPadding - Style.space(2)))
        svc: root.svc
        foreground: root.fg
        fontFamily: root.family
        settingsOpen: root.settingsOpen
        showLeft: false
        onGearClicked: root.toggleSettings()
      }

      // The name, top left (Settings puts its own back row there).
      Views.BrandCorner {
        objectName: "panelBrandLeft"
        anchors.top: parent.top
        anchors.left: parent.left
        visible: !root.settingsOpen
        svc: root.svc
        foreground: root.fg
        fontFamily: root.family
        showRight: false
      }

      Views.SignInCard {
        id: gate
        anchors.top: hero.bottom
        anchors.topMargin: Style.space(12)
        width: parent.width
        visible: root.svc ? root.svc.gated && !root.settingsOpen : false
        svc: root.svc
        bar: root.bar
      }

      Views.OffCard {
        id: offCard
        objectName: "offCard"
        anchors.top: hero.bottom
        anchors.topMargin: Style.space(18)
        width: parent.width
        visible: keys.off && !root.settingsOpen
        svc: root.svc
        bar: root.bar
      }

      // While YouTube Music waits on Google (cookies, sign-in) there is one
      // thing to do: the card above. Nothing below it would work yet.
      readonly property bool gated: root.svc ? root.svc.gated : false
      // Off, the same: only the way back on.
      readonly property bool off: root.svc ? root.svc.closed === true : false
      readonly property bool blocked: gated || off

      // The tab bar's pill: a faint rounded track, and one accent pill that
      // glides under the open tab (a still pill under reduce-motion).
      Rectangle {
        visible: tabRow.visible && root.pages.length === 0
        x: tabRow.x - Style.space(4); y: tabRow.y - Style.space(4)
        width: tabRow.width + Style.space(8); height: tabRow.height + Style.space(8)
        radius: height / 2
        color: Util.alpha(root.fg, 0.05)
        border.width: 1; border.color: Util.alpha(root.fg, 0.08)
      }
      Rectangle {
        id: tabPill
        visible: tabRow.visible && root.pages.length === 0
        x: tabRow.x + tabRow.pillX; y: tabRow.y
        width: tabRow.pillW; height: tabRow.height
        radius: height / 2
        color: Util.alpha(Calm.accent, 0.2)
        border.width: 1; border.color: Util.alpha(Calm.accent, 0.45)
      }

      Row {
        id: tabRow
        objectName: "panelTabs"
        visible: !keys.blocked && !root.settingsOpen
        anchors.top: gate.visible ? gate.bottom : hero.bottom
        anchors.topMargin: Style.space(22)
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        width: parent.width - Style.space(8)
        spacing: Style.space(2)
        // One number drives the whole bar: "pos" is the open tab as a real
        // index. The pill (x and width), each tab's width and each label's
        // fade all read it, so they land together. A critically damped
        // spring (about 260 ms, no overshoot); a new click re-aims it mid-glide.
        readonly property bool hasActive: root.pages.length === 0
        readonly property int target: { for (var i = 0; i < root.tabs.length; i++) if (root.tabs[i].key === root.tab) return i; return 0 }
        property real pos: target
        Behavior on pos { enabled: !Style.reduceMotion; SpringAnimation { spring: 11; damping: 1; epsilon: 0.001 } }
        // 1 while a tab is open, 0 while a detail page covers the bar.
        property real act: hasActive ? 1 : 0
        Behavior on act { enabled: !Style.reduceMotion; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        property var labelWs: []
        function setLabelW(i, w) { var c = labelWs.slice(); c[i] = w; labelWs = c }
        function labelW(i) { return labelWs[i] || 0 }
        readonly property real lo: Math.max(0, Math.min(root.tabs.length - 1, Math.floor(pos)))
        readonly property real frac: Math.max(0, Math.min(1, pos - lo))
        // The open tab's full width: its label, its icon and some air.
        readonly property real activeW: (labelW(lo) * (1 - frac) + labelW(Math.min(lo + 1, root.tabs.length - 1)) * frac + Style.space(56)) * act
        readonly property real restW: (width - spacing * (root.tabs.length - 1) - activeW) / (root.tabs.length - act)
        // How open tab i is: 1 under the pill, 0 away from it.
        function weight(i) { return act * Math.max(0, 1 - Math.abs(pos - i)) }
        function tabW(i) { return restW + (activeW - restW) * (act > 0 ? weight(i) / act : 0) }
        function tabX(i) { var x = 0; for (var j = 0; j < i; j++) x += tabW(j) + spacing; return x }
        readonly property real pillX: tabX(lo) + (tabX(Math.min(lo + 1, root.tabs.length - 1)) - tabX(lo)) * frac
        readonly property real pillW: activeW

        Repeater {
          model: root.tabs
          delegate: TextMetrics {
            required property var modelData
            required property int index
            font.family: root.family; font.pixelSize: Style.font.body; font.weight: Font.DemiBold
            text: modelData.label
            onWidthChanged: tabRow.setLabelW(index, width)
            Component.onCompleted: tabRow.setLabelW(index, width)
          }
        }

        Repeater {
          id: tabRep
          model: root.tabs
          // No frame of its own: the one gliding pill marks the open tab, and
          // hover is a soft fill of the same shape (same radius as the pill).
          delegate: Item {
            id: tabBtn
            required property var modelData
            required property int index
            readonly property real open: tabRow.weight(index)
            width: tabRow.tabW(index)
            height: Style.space(38)
            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: Util.alpha(root.fg, 0.07)
              opacity: tabBtn.open < 0.5 && tabMouse.containsMouse ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            Row {
              anchors.centerIn: parent
              spacing: 0
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tabBtn.modelData.icon
                textFormat: Text.PlainText
                color: tabBtn.open > 0.5 ? Calm.accent : Util.alpha(root.fg, tabMouse.containsMouse ? 1 : 0.7)
                font.family: root.family
                font.pixelSize: Style.space(20)
              }
              // The name opens and closes with the pill: width and opacity
              // follow its progress.
              Item {
                anchors.verticalCenter: parent.verticalCenter
                width: (tabRow.labelW(tabBtn.index) + Style.space(8)) * tabBtn.open
                height: labelText.implicitHeight
                clip: true
                visible: tabBtn.open > 0.001
                Text {
                  id: labelText
                  x: Style.space(8)
                  opacity: tabBtn.open
                  text: tabBtn.modelData.label
                  textFormat: Text.PlainText
                  color: root.fg
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  font.weight: Font.DemiBold
                }
              }
            }
            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showTab(tabBtn.modelData.key)
            }
          }
        }
      }

      Row {
        anchors.verticalCenter: tabRow.verticalCenter
        anchors.right: parent.right
        spacing: Style.space(6)
        visible: root.pages.length > 0 && !root.settingsOpen
        Views.HitButton {
          iconText: Icons.back
          text: "Back"
          fontFamily: root.family
          foreground: root.fg
          fontSize: Style.font.caption
          onClicked: root.back()
        }
      }

      // Settings takes it all, from the top row down: its "‹ Settings" back
      // row sits level with the brand corner, which stays (gear, power).
      Item {
        id: stage
        visible: root.settingsOpen || !keys.blocked
        anchors.top: root.settingsOpen ? parent.top : tabRow.bottom
        anchors.topMargin: root.settingsOpen ? 0 : Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(8)

        // The view change: the old view fades out and the new one in, each
        // sliding a few px, on one 200 ms OutCubic clock (instant with reduce motion).
        property var last: root.view
        property var prev: null
        property real mix: 1
        readonly property real slidePx: Style.space(8)
        function fade(v) { return root.view === v ? mix : (prev === v ? 1 - mix : 0) }
        function slide(v) { return root.view === v ? (1 - mix) * slidePx : (prev === v ? -mix * slidePx : 0) }
        function shows(v) { return root.view === v || prev === v }
        Connections {
          target: root
          function onViewChanged() {
            stage.prev = stage.last
            stage.last = root.view
            if (Style.reduceMotion) { mixAnim.stop(); stage.prev = null; stage.mix = 1; return }
            stage.mix = 0
            mixAnim.restart()
          }
        }
        NumberAnimation { id: mixAnim; target: stage; property: "mix"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic; onFinished: stage.prev = null }

        Views.QueueView { id: queueView; objectName: "queueView"; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(queueView); opacity: stage.fade(queueView); active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(queueView) } }
        Views.SearchView { id: searchView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(searchView); opacity: stage.fade(searchView); active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(searchView) } }
        Views.LibraryView { id: libraryView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(libraryView); opacity: stage.fade(libraryView); active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(libraryView) } }
        Views.LyricsView { id: lyricsView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(lyricsView); opacity: stage.fade(lyricsView); active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(lyricsView) } }
        Views.HistoryView { id: historyView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(historyView); opacity: stage.fade(historyView); active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(historyView) } }
        Views.DetailView { id: detailView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(detailView); opacity: stage.fade(detailView); svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(detailView) } }

        Views.SettingsView {
          id: settingsView
          objectName: "settingsView"
          anchors.fill: parent
          visible: root.settingsOpen
          svc: root.svc
          fg: root.fg
          family: root.family
          onBackRequested: root.closeSettings()
          onShowAllKeys: { root.settingsOpen = false; root.allKeys = true }
        }

        Views.SaveView {
          id: saveView
          objectName: "saveView"
          anchors.fill: parent
          visible: root.saveOpen && !root.settingsOpen
          svc: root.svc
          bar: root.bar
          panel: root
          item: root.saveItem
        }

        // Every key, on "?".
        Rectangle {
          anchors.fill: parent
          visible: root.allKeys
          clip: true
          color: Color.popups.background
          radius: Style.spacing.labelGap
          Flow {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(10)
            Repeater {
              model: Model.ALL_KEY_HINTS
              delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar; width: (parent.width - Style.space(10)) / 2 }
            }
          }
        }
      }

      // The toast: what just happened, a calm pill over the foot of the list.
      Rectangle {
        id: toast
        z: 5
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(10)
        width: toastRow.implicitWidth + Style.space(32)
        height: Style.space(36)
        radius: height / 2
        color: Calm.raised
        border.width: 1
        border.color: Calm.hair
        opacity: root.flash !== "" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Row {
          id: toastRow
          anchors.centerIn: parent
          spacing: Style.space(8)
          Text { anchors.verticalCenter: parent.verticalCenter; text: Icons.check; textFormat: Text.PlainText; color: Calm.accent; font.family: Style.font.family; font.pixelSize: Style.font.icon }
          Text { anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, keys.width - Style.space(100)); elide: Text.ElideRight; text: root.flash; textFormat: Text.PlainText; color: Calm.fg; font.family: Calm.font; font.pixelSize: Style.font.body; font.weight: Font.DemiBold }
        }
      }

      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(32)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - allKeysButton.width - Style.space(4)
          visible: false   // the toast pill below shows it
          text: root.flash
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Calm.accent
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (root.settingsOpen ? 0 : allKeysButton.width + Style.space(4))
          clip: true
          visible: !keys.blocked && !root.settingsOpen && !root.saveOpen
          spacing: Style.space(12)
          Repeater {
            model: Model.footerHints(root.view ? root.view.hints : null,
                                     !!(root.svc && root.svc.hasTrack && !root.svc.isAd && root.svc.signedIn),
                                     root.pages.length === 0 && root.view === searchView && searchView.inputFocused)
            delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar }
          }
        }

        // The picker's keys: the field takes the letters, so only these.
        Row {
          objectName: "saveHints"
          anchors.verticalCenter: parent.verticalCenter
          visible: root.saveOpen && !root.settingsOpen
          spacing: Style.space(12)
          Repeater {
            model: saveView.creating ? [["↵", "create"], ["esc", "back"]] : saveView.dupCurrent ? [["↵", "add anyway"], ["↑↓", "move"], ["esc", "back"]] : [["↑↓", "move"], ["↵", "choose"], ["esc", "back"]]
            delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar }
          }
        }

        // Settings has its own, fixed hints: movement, not song controls.
        Row {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.settingsOpen && root.flash === ""
          spacing: Style.space(12)
          Repeater {
            model: [["↑↓", "move"], ["←→", "change"], ["Tab", "sections"], ["Esc", "back"]]
            delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar }
          }
        }

        // Every key is one "?" away: typed, or clicked here.
        Views.HitButton {
          id: allKeysButton
          anchors.right: parent.right
          // "all keys" lines up with the edge: the box reaches into the card's
          // padding, never past it.
          anchors.rightMargin: -Math.min(Style.space(8), Math.max(0, Style.spacing.popupPadding - Style.space(2)))
          anchors.verticalCenter: parent.verticalCenter
          // Sized for the longer label: "close" does not shrink the box.
          width: allKeysSizer.implicitWidth + Style.space(16)
          visible: !keys.blocked && !root.settingsOpen
          foreground: root.fg
          onClicked: root.allKeys = !root.allKeys
          Views.KeyHint {
            id: allKeysHint
            anchors.centerIn: parent
            keys: "?"
            label: root.allKeys ? "close" : "all keys"
            bar: root.bar
          }
        }
        Views.KeyHint { id: allKeysSizer; visible: false; keys: "?"; label: "all keys"; bar: root.bar }
      }
    }
  }
}
