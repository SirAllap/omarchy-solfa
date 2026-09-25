import QtQuick
import qs.Ui
import qs.Commons
import "lib/Model.js" as Model
import "lib/Icons.js" as Icons
import "views" as Views

// The panel: now playing at the top, then Queue, Search, Library and
// Lyrics, and pages (album, artist, playlist) opened from any list.
// Everything works from the keyboard; the hint line says how.
Panel {
  id: root
  moduleName: "io.github.sirallap.solfa"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  readonly property var tabs: [
    { key: "queue", label: "Queue" }, { key: "search", label: "Search" },
    { key: "library", label: "Library" }, { key: "lyrics", label: "Lyrics" }
  ]
  property string tab: "queue"
  property var pages: []
  readonly property var view: pages.length > 0 ? detailView
    : tab === "queue" ? queueView : tab === "search" ? searchView : tab === "library" ? libraryView : lyricsView
  property bool allKeys: false
  property string flash: ""
  // Settings replaces the panel body; the gear in BrandCorner and Esc are
  // the only ways in and out — no new key letter is spent on it.
  property bool settingsOpen: false
  function toggleSettings() { root.settingsOpen = !root.settingsOpen }
  function closeSettings() { root.settingsOpen = false }

  onOpenedChanged: {
    if (svc) svc.panelOpen = opened
    if (!opened) { allKeys = false; settingsOpen = false; return }
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
      { name: "radio", icon: Icons.radio, tip: "Start radio (R)" }
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
    contentWidth: panel.fittedContentWidth(Style.space(560))
    // Gated or off, the card is all there is: no empty stage under it.
    contentHeight: root.svc && root.svc.gated && !root.settingsOpen
      ? panel.fittedContentHeight(hero.implicitHeight + gate.implicitHeight + Style.space(20))
      : root.svc && root.svc.closed && !root.settingsOpen
      ? panel.fittedContentHeight(hero.implicitHeight + offCard.implicitHeight + Style.space(28))
      : panel.cappedContentHeight(Style.space(660))

    // A plain Item, not a FocusScope: a scope hands focus back to the child
    // that had it, so the search field would keep the keys after Enter.
    // Keys the field does not take still bubble up to here.
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (event) { root.onKey(event) }

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
        reserveRight: brand.width
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
        onGearClicked: root.toggleSettings()
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

      Row {
        id: tabRow
        objectName: "panelTabs"
        visible: !keys.blocked && !root.settingsOpen
        anchors.top: gate.visible ? gate.bottom : hero.bottom
        anchors.topMargin: Style.space(14)
        anchors.left: parent.left
        spacing: Style.space(4)

        Repeater {
          model: root.tabs
          delegate: Views.HitButton {
            required property var modelData
            required property int index
            text: modelData.label
            fontFamily: root.family
            foreground: root.fg
            selected: root.pages.length === 0 && root.tab === modelData.key
            tooltipText: String(index + 1)
            onClicked: root.showTab(modelData.key)
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

        Views.QueueView { id: queueView; anchors.fill: parent; visible: !root.settingsOpen && root.view === queueView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.SearchView { id: searchView; anchors.fill: parent; visible: !root.settingsOpen && root.view === searchView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.LibraryView { id: libraryView; anchors.fill: parent; visible: !root.settingsOpen && root.view === libraryView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.LyricsView { id: lyricsView; anchors.fill: parent; visible: !root.settingsOpen && root.view === lyricsView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.DetailView { id: detailView; anchors.fill: parent; visible: !root.settingsOpen && root.view === detailView; svc: root.svc; bar: root.bar; panel: root }

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

      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(32)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - allKeysButton.width - Style.space(4)
          visible: root.flash !== ""
          text: root.flash
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Color.accent
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (root.settingsOpen ? 0 : allKeysButton.width + Style.space(4))
          clip: true
          visible: root.flash === "" && !keys.blocked && !root.settingsOpen
          spacing: Style.space(12)
          Repeater {
            model: Model.footerHints(root.view ? root.view.hints : null,
                                     !!(root.svc && root.svc.hasTrack && !root.svc.isAd && root.svc.signedIn),
                                     root.pages.length === 0 && root.view === searchView && searchView.inputFocused)
            delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar }
          }
        }

        // Settings has its own, fixed hints: movement, not song controls.
        Row {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.settingsOpen
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
