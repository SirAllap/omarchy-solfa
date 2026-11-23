import QtQuick
import QtQuick.Shapes
import qs.Ui
import qs.Commons
import "lib/Model.js" as Model
import "lib/Icons.js" as Icons
import "lib"
import "lib/Motion.js" as Motion
import "views" as Views
import QtQuick.Controls as QC

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

  // One line of key hints, laid out left to right: a hint that would run past
  // availW is dropped whole, and so is everything after it. Fades on opacity.
  component HintLine: Item {
    id: line
    property var hints: []
    property real availW: width
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: availW
    height: Style.space(20)
    visible: opacity > 0.01
    Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    function layout() {
      var x = 0, ok = true
      for (var i = 0; i < rep.count; i++) {
        var it = rep.itemAt(i)
        if (!it) continue
        ok = ok && x + it.width <= line.availW + 0.5
        it.px = x
        it.fits = ok
        x += it.width + Style.space(10)
      }
    }
    onAvailWChanged: Qt.callLater(layout)
    Repeater {
      id: rep
      model: line.hints
      onCountChanged: Qt.callLater(line.layout)
      delegate: Views.KeyHint {
        required property var modelData
        property real px: 0
        property bool fits: false
        x: px
        visible: fits
        anchors.verticalCenter: parent.verticalCenter
        keys: modelData[0]
        label: modelData[1]
        onWidthChanged: Qt.callLater(line.layout)
      }
    }
  }
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

  // c: the link of the song playing, on the clipboard.
  function copyLink() {
    if (!svc || !svc.hasTrack || svc.isAd) { say("Nothing to share"); return }
    svc.copyLink(function (url, source, ok) {
      // ok is false when wl-copy did not run or failed: say so, never "copied".
      root.say(!url ? "Nothing to share" : ok === false ? "Could not copy the link" : "Link copied")
    })
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
    // A text field has the keys: Search's, or the find field of a page.
    var inField = !!(root.view && root.view.inputFocused)
    if (k === Qt.Key_Escape) {
      if (root.allKeys) root.allKeys = false
      else if (root.saveOpen) saveView.back()
      else if (root.settingsOpen) root.closeSettings()
      else if (root.pages.length > 0 && detailView.finding) detailView.closeFind()
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
      // Tab moves to the next bar panel when there is one; with none, it walks the tabs.
      var dir = (event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1
      if (!root.switchPanel(dir) && root.pages.length === 0) root.cycleTab(dir)
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
      case "c": root.copyLink(); break
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
    // The shell's card is restyled in keys below (no border, mockup radius);
    // this is the border it starts with, until that runs.
    borderSpec: Border.none()
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
      // The content lives in 'body', always full height; the clip on this
      // box is masked while it opens.
      readonly property real fullH: parent.height - anchors.topMargin
      default property alias content: body.data
      Item { id: body; x: 0; y: 0; width: keys.width; height: keys.fullH }
      // The mockup's margins inside the card: 28 px at the sides, 24 px at the top.
      anchors.leftMargin: Math.max(0, Style.space(28) - Style.spacing.popupPadding)
      anchors.rightMargin: anchors.leftMargin
      anchors.topMargin: Math.max(0, Style.space(24) - Style.spacing.popupPadding)
      focus: true
      Keys.onPressed: function (event) { root.onKey(event) }

      // The frame is the mockup's (PanelFrame.qml): a graphite card with
      // rounded corners, no border and no shadow of our own (a solid offset shape under the card read as a second frame). The shell draws
      // its own card (KeyboardPanel.qml:514-517: popups background, theme
      // border, Style.cornerRadius = Hyprland rounding), so we find that card
      // above us at runtime and restyle it to the same shape: one frame, one
      // radius. If it cannot be found the card below is still ours.
      property Item hostCard: null
      property Item bridgeItem: null
      property Item shadowItem: null
      Component.onDestruction: { if (bridgeItem) bridgeItem.destroy(); if (shadowItem) shadowItem.destroy() }
      // The merged shape (pill + bridge + card) has ONE outer hairline (Calm.hair, 1 px,
      // anti-aliased): the pill's own U-shaped line (BarWidget), the bridge's two side
      // arcs, and this ring on the card. The bridge is drawn above the card (and above the
      // pill, its window being over the bar), so its fill hides the card's top line between
      // the arcs: nothing is drawn between pill and bridge or bridge and card.
      Component {
        id: rimComp
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          radius: parent.radius
          border.width: 1
          border.color: Calm.outline
          antialiasing: true
        }
      }
      // A very soft shadow under the card only: clipped below the card's top edge, so none
      // falls on the join.
      Component {
        id: shadowComp
        Item {
          id: shadow
          property Item card: null
          visible: !!card && card.visible
          opacity: card ? card.opacity : 0
          z: card ? card.z - 1 : 0
          x: card ? card.x - 24 : 0
          y: card ? card.y + Style.space(10) : 0
          width: card ? card.width + 48 : 0
          height: card ? card.height + 40 : 0
          clip: true
          Repeater {
            model: 8
            Rectangle {
              required property int index
              readonly property real s: 1.5 * (index + 1)
              x: 24 - s
              y: -Style.space(10) - s + 4
              width: shadow.card.width + 2 * s
              height: shadow.card.height + 2 * s
              radius: shadow.card.radius + s
              color: Qt.rgba(0, 0, 0, Calm.light ? 0.009 : 0.012)
            }
          }
        }
      }
      // Two drops, the pill's and the card's, stretch toward each other,
      // touch and merge: one card-coloured shape with a concave neck
      // (cubic curves). The panel window is full-screen and above the bar,
      // so the whole bridge is drawn here; the bar's own window ends at the
      // pill's bottom (about 2 px below it), so BarWidget cannot draw into
      // the gap. It stretches on open (0 to 450 ms, a small spring wobble at
      // the snap) and is static under reduce-motion. Closing: the host hides
      // the card at once, so it goes with it.
      Component {
        id: bridgeComp
        Item {
          id: bridge
          property Item card: null
          // The pill's own drawn box (BarWidget.pillBox*, whole pixels), so the bridge meets the
          // pill's two ends exactly; the widget's width is only the fallback.
          readonly property Item pillHost: panel.anchorItem && panel.anchorItem.pillBoxW !== undefined ? panel.anchorItem : null
          readonly property real pillW: Math.round(pillHost ? pillHost.pillBoxW : panel.anchorW)   // the pill's full width, end to end
          readonly property real cx: panel.anchorScreenPos.x + (pillHost ? pillHost.pillBoxX + pillHost.pillBoxW / 2 : panel.anchorW / 2)
          readonly property real barBottom: Math.round(panel.barThickness)     // the bar window's bottom edge (screen y)
          readonly property real pillBottom: Math.round(panel.barThickness - Style.space(2))   // the pill's bottom edge
          readonly property real cardTop: card ? Math.round(card.y) : 0
          readonly property real ov: 1                               // 1 px into the pill and into the card: no seam
          readonly property real gapH: Math.max(0, cardTop - pillBottom)
          // Each side is a true inverted corner: a concave quarter circle of radius r = bar
          // bottom to card top, tangent to the pill's side at the bar's bottom edge and to the
          // card's top edge. Everything between pill, bar edge and card is filled first.
          readonly property real r: Math.max(0, cardTop - barBottom)
          readonly property real p: Motion.spatial(keys.tms, 0, 250)
          // On open the circle grows from the card up (rr 0 to r), a straight neck above it.
          readonly property real rr: Math.round(r * Math.max(0, Math.min(1, p)))
          readonly property real rx: r + pillW                        // its right end
          readonly property real yC: cardTop - y                     // the card's top edge inside this item
          // Visible from the first frame: the pill squares off the moment the panel opens, so a frame
          // without the bridge would show a flat-bottomed pill floating above the card.
          visible: !!card && card.visible && root.opened && gapH > 0.5
          opacity: card ? card.opacity : 0
          x: Math.round(cx - pillW / 2) - r                          // whole pixels: both sides alike
          y: pillBottom - ov
          z: card ? card.z + 0.5 : 0   // above the card: its fill hides the card's top line between the arcs
          width: pillW + 2 * r
          height: yC + ov
          // (No MSAA layer: its sample pattern is not mirror-symmetric; the curve renderer
          // anti-aliases the arcs itself, the same way on both sides.)
          // One half is the only path there is: the right side, from just past the pill's centre
          // line out to the arc's foot. The left side is the same half drawn again, flipped
          // about the centre line, so the two corners are exact mirror images.
          readonly property real m: width / 2
          Component {
            id: halfComp
            Shape {
              width: bridge.width; height: bridge.height
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: Calm.surface
                strokeWidth: -1
                startX: bridge.m - 1; startY: 0
                PathLine { x: bridge.rx; y: 0 }
                PathLine { x: bridge.rx; y: bridge.yC - bridge.rr }
                PathArc { x: bridge.rx + bridge.rr; y: bridge.yC
                  radiusX: Math.max(0.01, bridge.rr); radiusY: Math.max(0.01, bridge.rr); direction: PathArc.Counterclockwise }
                PathLine { x: bridge.rx + bridge.rr; y: bridge.yC + bridge.ov }
                PathLine { x: bridge.m - 1; y: bridge.yC + bridge.ov }
              }
              // The outline: down the pill's side (on from the pill's own line), then the arc (centre
              // line half a pixel inside the fill, radius rr + 0.5), ending flat on the card ring's
              // centre line. Tangent all along, 1 px wide.
              ShapePath {
                fillColor: "transparent"
                strokeColor: Calm.outline
                strokeWidth: 1
                capStyle: ShapePath.FlatCap
                startX: bridge.rx - 0.5; startY: 0
                PathLine { x: bridge.rx - 0.5; y: bridge.yC - bridge.rr }
                PathArc { x: bridge.rx + bridge.rr; y: bridge.yC + 0.5
                  radiusX: bridge.rr + 0.5; radiusY: bridge.rr + 0.5; direction: PathArc.Counterclockwise }
              }
            }
          }
          Loader { anchors.fill: parent; sourceComponent: halfComp }
          Loader {
            anchors.fill: parent
            sourceComponent: halfComp
            transform: Scale { xScale: -1; origin.x: bridge.m }
          }
        }
      }
      readonly property real frameRadius: Style.space(26)
      Component.onCompleted: {
        var p = keys.parent
        while (p && !(("borderSpec" in p) && ("radius" in p) && ("color" in p))) p = p.parent
        if (!p) return
        p.borderSpec = Border.none()
        p.radius = Qt.binding(function () { return keys.frameRadius })
        // Opaque derived surface, never the theme's see-through popup colour (the bridge copies this).
        p.color = Qt.binding(function () { return Calm.surface })
        keys.hostCard = p
        // The liquid bridge: a drop between the bar pill and the card (see bridgeComp).
        rimComp.createObject(p)
        if (keys.shadowItem) { keys.shadowItem.destroy(); keys.shadowItem = null }
        if (p.parent) keys.shadowItem = shadowComp.createObject(p.parent, { card: p })
        // One bridge per card: the content is reloaded on every open.
        if (keys.bridgeItem) { keys.bridgeItem.destroy(); keys.bridgeItem = null }
        var canBridge = !!p.parent && ("anchorScreenPos" in panel) && ("barThickness" in panel)
        if (canBridge) keys.bridgeItem = bridgeComp.createObject(p.parent, { card: p })
        // One line per open, so a live log says why the bridge shows or not.
        console.info("solfa bridge: made=" + !!keys.bridgeItem
          + " cardY=" + p.y + " barThickness=" + (canBridge ? panel.barThickness : "n/a")
          + " barBottom=" + (canBridge ? Math.round(panel.barThickness) : "n/a") + " pillBottom=" + (canBridge ? Math.round(panel.barThickness - Style.space(2)) : "n/a") + " gap=" + (canBridge ? Math.round(p.y - panel.barThickness) : "n/a")
          + " pillX=" + (canBridge ? panel.anchorScreenPos.x : "n/a") + " pillW=" + (canBridge ? panel.anchorW : "n/a")
          + " window=" + (p.parent ? p.parent.width + "x" + p.parent.height : "n/a"))
      }

      // Open: one timeline, 'tms', runs 0 to 350 ms and everything below
      // reads it, so nothing can stick half-way. The card frame is never
      // masked or clipped; the content fades in and drops 8 px while the liquid
      // bridge stretches (250 ms); the header, cover, title, seek bar, transport, volume row, tab pill and
      // first list rows follow with their own delays (NowPlaying, RowList
      // and the pill read 'tms'). The feel (not the code) follows
      // caelestia-dots/shell (GPL-3.0; Material 3 expressive tokens): the
      // spatial curve 0.38 1.21 0.22 1 and the effects curve 0.34 0.8 0.34 1
      // (Motion.js). Only this item's own geometry, opacity and scale move:
      // never the host card, 'visible', 'active' or 'opened'. Closing, reduce
      // motion or a new open jump to the end state (350) at once.
      property real tms: 350
      // Only what is inside the frame moves: the card (outline, corners) is
      // drawn from frame 1; the content fades in and drops 8 px.
      opacity: Motion.effects(tms, 0, 160)
      transform: Translate { y: -Style.space(8) * (1 - Motion.effects(keys.tms, 0, 200)) }
      NumberAnimation {
        id: enterAnim
        target: keys
        property: "tms"
        from: 0
        to: 350
        duration: Style.duration(350)
        easing.type: Easing.Linear
      }
      Connections {
        target: root
        function onOpenedChanged() {
          enterAnim.stop()
          keys.tms = 350
          if (root.opened && !Style.reduceMotion) { keys.tms = 0; enterAnim.start() }
        }
      }

      Views.NowPlaying {
        id: hero
        objectName: "panelHero"
        openMs: keys.tms
        // Settings replaces the whole body: no hero, no transport, no tabs.
        visible: !root.settingsOpen
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        svc: root.svc
        bar: root.bar
        topInset: brand.height
        onSaveRequested: root.saveRow(null)
        onRadioRequested: { if (root.svc && root.svc.hasTrack) { root.svc.radioFor(root.svc.player); root.say("Radio from " + root.svc.title) } }
        onShareRequested: root.copyLink()
      }

      // Solfa's name and the power button, top right: far from play.
      Views.BrandCorner {
        id: brand
        objectName: "panelBrand"
        anchors.top: parent.top
        anchors.right: parent.right
        // The power button's 36 px box ends 21 px from the card's edge: its 22 px icon ends 28 px in.
        anchors.rightMargin: Style.space(4) - Style.spacing.popupPadding
        svc: root.svc
        foreground: root.fg
        fontFamily: root.family
        settingsOpen: root.settingsOpen
        showLeft: false
        opacity: Motion.effects(keys.tms, 0, 180)
        transform: Translate { y: -Style.space(8) * (1 - Motion.effects(keys.tms, 0, 180)) }
        // Settings has its own header: "‹ Settings" and "esc close".
        visible: !root.settingsOpen
        onGearClicked: root.toggleSettings()
      }

      // The name, top left (Settings puts its own back row there).
      Views.BrandCorner {
        objectName: "panelBrandLeft"
        opacity: Motion.effects(keys.tms, 0, 180)
        transform: Translate { y: -Style.space(8) * (1 - Motion.effects(keys.tms, 0, 180)) }
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
        visible: tabRow.visible
        x: tabRow.x - Style.space(4); y: tabRow.y - Style.space(4)
        width: tabRow.width + Style.space(8); height: tabRow.height + Style.space(8)
        radius: height / 2
        color: Util.alpha(root.fg, 0.05)
        border.width: 1; border.color: Util.alpha(root.fg, 0.08)
      }
      Rectangle {
        id: tabPill
        visible: tabRow.visible
        x: tabRow.x + tabRow.pillX - Style.space(60) * (1 - Motion.spatial(keys.tms, 110, 200)); y: tabRow.y
        opacity: Motion.effects(keys.tms, 110, 160)
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
        anchors.topMargin: Style.space(28)
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        width: parent.width - Style.space(8)
        spacing: Style.space(2)
        // One number drives the whole bar: "pos" is the open tab as a real
        // index. The pill (x and width), each tab's width and each label's
        // fade all read it, so they land together. A critically damped
        // spring (about 260 ms, no overshoot); a new click re-aims it mid-glide.
        // A page keeps its parent tab lit: the strip looks the same in every view.
        readonly property bool hasActive: true
        readonly property int target: { for (var i = 0; i < root.tabs.length; i++) if (root.tabs[i].key === root.tab) return i; return 0 }
        property real pos: target
        Behavior on pos { enabled: !Style.reduceMotion; SpringAnimation { spring: 11; damping: 1; epsilon: 0.001 } }
        // 1 while a tab is open.
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
          // An Item wrapper: a Repeater delegate must be an Item, or it is
          // dropped after its first run and later width changes never arrive.
          delegate: Item {
            id: metricsHost
            required property var modelData
            required property int index
            TextMetrics {
              id: metrics
              font.family: root.family; font.pixelSize: Style.font.body; font.weight: Font.DemiBold
              text: metricsHost.modelData.label
              onWidthChanged: if (tabRow) tabRow.setLabelW(metricsHost.index, width)
              Component.onCompleted: if (tabRow) tabRow.setLabelW(metricsHost.index, width)
            }
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
              Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 120 } }
            }
            Row {
              anchors.centerIn: parent
              spacing: 0
              Views.VIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: tabBtn.modelData.key
                size: Style.space(22)
                stroke: 1.7
                color: tabBtn.open > 0.5 ? Calm.accent : Util.alpha(root.fg, tabMouse.containsMouse ? 1 : 0.7)
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
              QC.ToolTip.visible: containsMouse
              QC.ToolTip.delay: 400
              QC.ToolTip.text: String(tabBtn.index + 1)
            }
          }
        }
      }

      // Settings takes it all, from the top row down: its "‹ Settings" back
      // row sits level with the brand corner, which stays (gear, power).
      Item {
        id: stage
        visible: root.settingsOpen || !keys.blocked
        anchors.top: root.settingsOpen ? parent.top : tabRow.bottom
        anchors.topMargin: root.settingsOpen ? 0 : Style.space(12)
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

        Views.QueueView { id: queueView; objectName: "queueView"; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(queueView); opacity: stage.fade(queueView); enabled: root.view === queueView; active: root.opened && root.view === queueView && !root.settingsOpen; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(queueView) } }
        Views.SearchView { id: searchView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(searchView); opacity: stage.fade(searchView); enabled: root.view === searchView; active: root.opened && root.view === searchView && !root.settingsOpen; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(searchView) } }
        Views.LibraryView { id: libraryView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(libraryView); opacity: stage.fade(libraryView); enabled: root.view === libraryView; active: root.opened && root.view === libraryView && !root.settingsOpen; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(libraryView) } }
        Views.LyricsView { id: lyricsView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(lyricsView); opacity: stage.fade(lyricsView); enabled: root.view === lyricsView; active: root.opened && root.view === lyricsView && !root.settingsOpen; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(lyricsView) } }
        Views.HistoryView { id: historyView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(historyView); opacity: stage.fade(historyView); enabled: root.view === historyView; active: root.opened && root.view === historyView && !root.settingsOpen; svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(historyView) } }
        Views.DetailView { id: detailView; objectName: "detailView"; enabled: root.view === detailView; anchors.fill: parent; visible: !root.settingsOpen && stage.shows(detailView); opacity: stage.fade(detailView); svc: root.svc; bar: root.bar; panel: root; transform: Translate { y: stage.slide(detailView) } }

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

        // Every key, on "?": a calm sheet over the lower panel (views/KeysSheet.qml).
        Views.KeysSheet {
          id: keysSheet
          objectName: "keysSheet"
          anchors.fill: parent
          z: 4
          shown: root.allKeys
          bar: root.bar
          panelKey: root.svc ? Model.keyChord(root.svc.panelKeyChosen ? root.svc.panelKeyChosen.keys : "SUPER + ALT + M") : "Super + Alt + M"
          playPauseKey: root.svc ? Model.keyChord(root.svc.playPauseKeyChosen ? root.svc.playPauseKeyChosen.keys : "SUPER + ALT + P") : "Super + Alt + P"
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
        Behavior on opacity { enabled: !Style.reduceMotion; NumberAnimation { duration: 160 } }
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
        // Settings has no key-hint footer.
        height: root.settingsOpen ? 0 : Style.space(32)

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

        // The view's own keys, one line. A hint that does not fit is dropped whole
        // (the last ones first), and a change of view crossfades between two layers.
        Item {
          id: hintStack
          objectName: "footerHints"
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - allKeysButton.width - Style.space(4)
          height: Style.space(20)
          visible: !keys.blocked && !root.settingsOpen && !root.saveOpen
          readonly property bool typing: !!(root.view && root.view.inputFocused)   // Search's field or a page's find field
          // Last, so it is the first dropped when the line is short: the real panel key.
          readonly property var hints: Model.footerHints(root.view ? root.view.hints : null,
                                                         !!(root.svc && root.svc.hasTrack && !root.svc.isAd && root.svc.signedIn),
                                                         typing)
            .concat(typing || !root.svc ? [] : [[Model.keyChord(root.svc.panelKeyChosen ? root.svc.panelKeyChosen.keys : "SUPER + ALT + M"), "open"]])
          readonly property string hintsKey: JSON.stringify(hints)
          property bool front: true   // true: layer A is the one showing
          onHintsKeyChanged: {
            if (front) layerB.hints = hints; else layerA.hints = hints
            front = !front
          }
          Component.onCompleted: layerA.hints = hints
          HintLine { id: layerA; opacity: hintStack.front ? 1 : 0; availW: hintStack.width }
          HintLine { id: layerB; opacity: hintStack.front ? 0 : 1; availW: hintStack.width }
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
