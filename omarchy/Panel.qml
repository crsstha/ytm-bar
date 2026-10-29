import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Player popup plus the pill label. Now-playing is polled straight from Pear
// Desktop's API Server (GET /api/v1/song); everything else goes through
// bin/ytm-bar, which owns the token and the queue parsing.
Panel {
  id: root
  moduleName: "crsstha.ytmusic"
  ipcTarget: "crsstha.ytmusic"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("../bin/ytm-bar")).replace(/^file:\/\//, ""))
  readonly property string api: "http://127.0.0.1:26538"
  readonly property int maxTitleLength: 30
  // Card background opacity; Hyprland blurs what shows through (omarchy/bindings.lua).
  readonly property real cardOpacity: 0.75

  property string token: ""
  // "offline" (app closed), "unauthorized" (no/expired token), "idle" (nothing loaded), "ok".
  property string status: "offline"
  property var song: null
  property var player: ({ like: "INDIFFERENT", shuffle: false, repeat: "NONE", volume: 0, muted: false, queue: [] })
  property bool connecting: false
  property string message: ""

  // Sliders: after a seek/volume change, hold the new value until Pear reports
  // it, so the knob doesn't snap back to the stale value and jump forward again.
  property real pendingSeek: -1
  property real pendingVolume: -1
  // Progress glides between polls: elapsedBase as of elapsedAt, advanced locally while playing.
  property real elapsedBase: 0
  property double elapsedAt: 0
  property double clockMs: 0
  // Set while Pear lags behind the displayed position (e.g. buffering after a
  // seek): the knob waits for it instead of stepping backwards.
  property bool elapsedHeld: false
  readonly property real elapsed: song
    ? Math.min(song.songDuration || 0, elapsedBase + (playing && !elapsedHeld ? Math.max(0, (clockMs - elapsedAt) / 1000) : 0))
    : 0
  readonly property real volume: pendingVolume >= 0 ? pendingVolume : player.volume

  property string searchQuery: ""
  property string searchedQuery: ""
  property var searchResults: []
  property string searchError: ""
  readonly property bool searchActive: searchQuery.trim() !== ""
  readonly property bool searching: searchActive && searchedQuery !== searchQuery.trim()

  readonly property bool playing: status === "ok" && song !== null && !song.isPaused
  readonly property string label: buildLabel()
  // The pill draws a wave instead of the play/pause icon while a song is loaded.
  readonly property bool showWave: status === "ok" && song !== null
  readonly property string waveTitle: song ? truncate(song.title) : ""
  readonly property bool dimmed: status !== "ok" || !playing
  readonly property string tooltip: status === "offline" ? "Start YouTube Music" : (song ? song.title + " — " + song.artist : "")

  function glyph(code) { return String.fromCodePoint(code) }
  readonly property string iconMusic: glyph(0xF075A)
  readonly property string iconPlay: glyph(0xF040A)
  readonly property string iconPause: glyph(0xF03E4)
  readonly property string iconPrevious: glyph(0xF04AE)
  readonly property string iconNext: glyph(0xF04AD)
  readonly property string iconLike: glyph(0xF0513)
  readonly property string iconLikeOff: glyph(0xF0514)
  readonly property string iconDislike: glyph(0xF0511)
  readonly property string iconDislikeOff: glyph(0xF0512)
  readonly property string iconShuffle: glyph(0xF049D)
  readonly property string iconRepeat: glyph(0xF0456)
  readonly property string iconRepeatOne: glyph(0xF0458)
  readonly property string iconVolume: glyph(0xF057E)
  readonly property string iconMuted: glyph(0xF075F)
  readonly property string iconSearch: glyph(0xF0349)
  readonly property string iconPlayNext: glyph(0xF0415)

  function open() { root.controller.show(); root.refreshPlayer() }
  function openFromHotkey() {
    root.open()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }
  function close() { root.controller.hide() }
  function toggle() {
    if (root.status === "offline" && !root.opened) { root.startApp(); return }
    root.opened ? root.close() : root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function truncate(text) {
    return text.length > maxTitleLength ? text.slice(0, maxTitleLength - 1).trim() + "…" : text
  }

  function clock(seconds) {
    var s = Math.max(0, Math.floor(seconds || 0))
    var m = Math.floor(s / 60)
    s = s % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  function buildLabel() {
    if (status === "offline") return iconMusic
    if (status === "unauthorized") return iconMusic + " Connect"
    if (status !== "ok" || !song) return iconMusic
    return (playing ? iconPause : iconPlay) + " " + truncate(song.title)
  }

  // ---- Live now-playing: poll the API directly (cheap, localhost).
  function poll() {
    if (pollRequest) {
      pollRequest.abort()
      pollRequest = null
    }
    var xhr = new XMLHttpRequest()
    pollRequest = xhr
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || pollRequest !== xhr) return
      pollRequest = null
      if (xhr.status === 200) {
        try {
          var next = JSON.parse(xhr.responseText)
          var sameSong = root.song && next.videoId === root.song.videoId
          root.song = next
          root.status = "ok"
          root.syncElapsed(next.elapsedSeconds || 0, sameSong)
        } catch (e) {
          root.song = null
          root.status = "idle"
        }
      } else if (xhr.status === 204) {
        root.song = null
        root.status = "idle"
      } else if (xhr.status === 401 || xhr.status === 403) {
        root.song = null
        root.status = "unauthorized"
      } else {
        root.song = null
        root.status = "offline"
      }
    }
    xhr.open("GET", root.api + "/api/v1/song")
    if (root.token) xhr.setRequestHeader("Authorization", "Bearer " + root.token)
    xhr.send()
  }
  property var pollRequest: null

  function syncElapsed(reported, sameSong) {
    var now = Date.now()
    if (root.pendingSeek >= 0) {
      // Ignore stale positions until Pear has actually moved to the seek target.
      if (sameSong && Math.abs(reported - root.pendingSeek) > 2.5) return
      root.pendingSeek = -1
    }
    var shown = root.elapsed
    // Pear reports whole seconds and stalls while buffering; if it's slightly
    // behind, hold the knob where it is until Pear catches up.
    var behind = shown - reported
    root.elapsedHeld = sameSong && root.playing && behind > 0.25 && behind < 3
    root.elapsedBase = root.elapsedHeld ? shown : reported
    root.elapsedAt = now
    root.clockMs = now
  }

  function seek(seconds) {
    root.pendingSeek = seconds
    root.elapsedHeld = false
    root.elapsedBase = seconds
    root.elapsedAt = Date.now()
    root.clockMs = root.elapsedAt
    pendingTimeout.restart()
    root.action("seek", [String(Math.round(seconds))])
  }

  function setVolume(percent) {
    root.pendingVolume = percent
    pendingTimeout.restart()
    root.action("volume", [String(Math.round(percent))])
  }

  // ---- Everything else goes through bin/ytm-bar.
  function action(name, args) {
    if (root.status === "unauthorized" && name !== "auth") { root.connect(); return }
    if (root.status !== "ok" && root.status !== "idle") return
    Quickshell.execDetached([root.cli, name].concat(args || []))
    settleTimer.restart()
  }

  function refreshPlayer() {
    if (root.status !== "ok" && root.status !== "idle") return
    if (stateProc.running) return
    stateProc.command = [root.cli, "state"]
    stateProc.running = true
  }

  // ---- Search: debounced while typing, immediate on Enter.
  function runSearch() {
    var query = root.searchQuery.trim()
    if (query === "" || searchProc.running || query === root.searchedQuery) return
    searchProc.query = query
    searchProc.command = [root.cli, "search", query]
    searchProc.running = true
  }

  function clearSearch() {
    root.searchQuery = ""
    root.searchedQuery = ""
    root.searchResults = []
    root.searchError = ""
    searchField.text = ""
  }

  // Clicking a result plays it now; "+" queues it to play next.
  function playResult(videoId, now) {
    root.action(now ? "play" : "add", [videoId])
    if (now) root.clearSearch()
  }

  function connect() {
    if (authProc.running) return
    root.connecting = true
    root.message = "Approve “ytm-bar” in YouTube Music…"
    authProc.command = [root.cli, "auth"]
    authProc.running = true
  }

  function parse(text) {
    try { return JSON.parse(text) } catch (e) { return { ok: false, error: "ytm-bar printed no JSON" } }
  }

  // The app lives on the hidden special:music workspace (see omarchy/bindings.lua).
  function startApp() {
    Quickshell.execDetached([root.cli, "start"])
    root.message = ""
  }

  function showWindow() {
    Quickshell.execDetached([root.cli, "window"])
    root.close()
  }

  FileView {
    id: tokenFile
    path: Quickshell.env("HOME") + "/.config/ytm-bar/token"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.token = text().trim()
      root.poll()
    }
    onLoadFailed: root.token = ""
  }

  // 1s while the popup is open or music plays, slower otherwise.
  Timer {
    interval: root.opened || root.playing ? 1000 : (root.status === "offline" ? 5000 : 2000)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.poll()
  }

  // Like/shuffle/repeat/volume/queue only matter while the popup is open.
  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refreshPlayer()
  }

  // After an action, give Pear a moment to apply it, then re-read.
  Timer {
    id: settleTimer
    interval: 350
    onTriggered: {
      root.poll()
      root.refreshPlayer()
    }
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      id: stateOut
      waitForEnd: true
    }
    onExited: {
      var result = root.parse(stateOut.text)
      if (!result.ok) return
      if (root.pendingVolume >= 0 && Math.abs(result.volume - root.pendingVolume) <= 1) root.pendingVolume = -1
      root.player = result
    }
  }

  // Advances the progress knob between polls while the popup shows it.
  Timer {
    interval: 250
    running: root.opened && root.playing
    repeat: true
    onTriggered: root.clockMs = Date.now()
  }

  // Never hold a slider value forever (e.g. Pear clamped or ignored the change).
  Timer {
    id: pendingTimeout
    interval: 4000
    onTriggered: {
      root.pendingSeek = -1
      root.pendingVolume = -1
    }
  }

  Timer {
    id: searchDebounce
    interval: 350
    onTriggered: root.runSearch()
  }

  Process {
    id: searchProc
    property string query: ""
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
    }
    onExited: {
      var result = root.parse(searchOut.text)
      root.searchedQuery = query
      root.searchResults = result.ok ? result.results : []
      root.searchError = result.ok ? "" : (result.error || "Search failed")
      // The query changed while this one ran.
      if (root.searchActive && root.searchQuery.trim() !== query) root.runSearch()
    }
  }

  Process {
    id: authProc
    stdout: StdioCollector {
      id: authOut
      waitForEnd: true
    }
    onExited: {
      var result = root.parse(authOut.text)
      root.connecting = false
      root.message = result.ok ? "" : (result.error || "Couldn't connect")
      tokenFile.reload()
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playPause(): void { root.action("toggle") }
    function next(): void { root.action("next") }
    function previous(): void { root.action("previous") }
    function like(): void { root.action("like") }
    function status(): string { return JSON.stringify({ status: root.status, label: root.label, song: root.song }) }
  }

  component SectionHeader: Text {
    textFormat: Text.PlainText
    color: Qt.darker(root.bar.foreground, 1.5)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.letterSpacing: 1
  }

  component Control: PanelActionButton {
    property bool on: false
    // Rows align items by their top edge; centre them so the bigger play button lines up.
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    foreground: on ? Color.accent : root.bar.foreground
    hoverColor: Color.accent
    fontFamily: root.bar.fontFamily
  }

  component TextButton: Rectangle {
    id: textButton
    property string text: ""
    signal clicked()
    width: buttonLabel.implicitWidth + Style.space(16)
    height: buttonLabel.implicitHeight + Style.space(6)
    radius: Math.min(4, Style.cornerRadius)
    color: buttonArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
    border.width: 1
    border.color: Qt.darker(root.bar.foreground, 1.8)

    Text {
      id: buttonLabel
      anchors.centerIn: parent
      text: textButton.text
      color: buttonArea.containsMouse ? Style.hoverStateColor(root.bar.foreground, Color.accent) : root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: buttonArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: textButton.clicked()
    }
  }

  component QueueRow: Item {
    id: row
    required property var modelData
    width: parent ? parent.width : 0
    height: rowTitle.implicitHeight + Style.space(8)

    Rectangle {
      anchors.fill: parent
      radius: Math.min(4, Style.cornerRadius)
      color: rowArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
    }
    Text {
      id: rowTitle
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.right: rowLength.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: row.modelData.title + (row.modelData.artist ? "  ·  " + row.modelData.artist : "")
      color: row.modelData.current ? Color.accent : root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      id: rowLength
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      text: row.modelData.length
      color: Qt.darker(root.bar.foreground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.modelData.current ? Qt.ArrowCursor : Qt.PointingHandCursor
      onClicked: if (!row.modelData.current) root.action("jump", [String(row.modelData.index)])
    }
  }

  component ResultRow: Item {
    id: result
    required property var modelData
    width: parent ? parent.width : 0
    height: Math.max(resultText.implicitHeight, nextButton.height) + Style.space(8)

    Rectangle {
      anchors.fill: parent
      radius: Math.min(4, Style.cornerRadius)
      color: resultArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
    }
    MouseArea {
      id: resultArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.playResult(result.modelData.videoId, true)
    }
    Column {
      id: resultText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.right: nextButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: result.modelData.title
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        width: parent.width
        visible: text !== ""
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: (result.modelData.kind === "Video" ? "Video · " : "") + result.modelData.detail
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
    Control {
      id: nextButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: root.iconPlayNext
      tooltipText: "Play next"
      onClicked: root.playResult(result.modelData.videoId, false)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    // KeyboardPanel doesn't expose its card's colour, so walk up from our content
    // to the card (the BorderSurface holding it) and make its background
    // see-through, keeping the theme colour.
    Component.onCompleted: {
      for (var card = keyCatcher.parent; card; card = card.parent) {
        if ("borderSpec" in card && "color" in card) {
          card.color = Qt.binding(function() {
            var c = Color.popups.background
            return Qt.rgba(c.r, c.g, c.b, root.cardOpacity)
          })
          return
        }
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroller.width
          spacing: Style.space(8)

          // ---- Not connected: approve a token in YouTube Music.
          Column {
            visible: root.status === "unauthorized"
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "Connect the bar to YouTube Music. You'll be asked to approve “ytm-bar” in the app."
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }
            TextButton {
              text: root.connecting ? "Waiting for approval…" : "Connect"
              onClicked: root.connect()
            }
          }

          // ---- Running but nothing loaded.
          Column {
            visible: root.status === "idle" && !root.searchActive
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: "Nothing playing in YouTube Music"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.italic: true
            }
            TextButton {
              text: "Show YouTube Music"
              onClicked: root.showWindow()
            }
          }

          // ---- Search.
          TextField {
            id: searchField
            visible: root.status === "ok" || root.status === "idle"
            width: parent.width
            placeholderText: root.iconSearch + "  Search YouTube Music"
            foreground: root.bar.foreground
            accent: Color.accent
            font.family: root.bar.fontFamily
            onTextEdited: {
              root.searchQuery = text
              if (!root.searchActive) root.clearSearch()
              else searchDebounce.restart()
            }
            onAccepted: {
              searchDebounce.stop()
              root.runSearch()
            }
            Keys.onEscapePressed: function(event) {
              if (text !== "") root.clearSearch()
              else root.close()
              event.accepted = true
            }
          }

          Column {
            visible: root.searchActive && searchField.visible
            width: parent.width
            spacing: Style.space(2)

            SectionHeader { text: root.searching ? "SEARCHING…" : "RESULTS" }
            Repeater { model: root.searchResults; delegate: ResultRow {} }
            SectionHeader {
              visible: !root.searching && (root.searchError !== "" || root.searchResults.length === 0)
              text: root.searchError !== "" ? root.searchError : "No songs found"
              font.italic: true
              font.letterSpacing: 0
            }
          }

          Text {
            visible: root.message !== ""
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.message
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---- Now playing (replaced by results while searching).
          Column {
            visible: root.status === "ok" && root.song !== null && !root.searchActive
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(12)

              Rectangle {
                id: art
                width: Style.space(72)
                height: Style.space(72)
                radius: Math.min(4, Style.cornerRadius)
                color: Qt.darker(root.bar.foreground, 4)
                clip: true

                Image {
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  source: root.song && root.song.imageSrc ? root.song.imageSrc : ""
                  visible: source !== ""
                }
                Text {
                  anchors.centerIn: parent
                  visible: !(root.song && root.song.imageSrc)
                  text: root.iconMusic
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              Column {
                width: parent.width - art.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: root.song ? root.song.title : ""
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: root.song ? root.song.artist : ""
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  visible: text !== ""
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: root.song && root.song.album ? root.song.album : ""
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            // Progress — drag or click to seek.
            PanelSlider {
              id: progress
              bar: root.bar
              width: parent.width
              minimum: 0
              maximum: Math.max(1, root.song ? root.song.songDuration : 1)
              step: 1
              integer: true
              value: root.elapsed
              onReleased: function(value) { root.seek(value) }
            }
            Item {
              width: parent.width
              height: elapsedText.implicitHeight

              Text {
                id: elapsedText
                anchors.left: parent.left
                textFormat: Text.PlainText
                text: root.clock(progress.dragging ? progress.liveValue : progress.value)
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: root.clock(root.song ? root.song.songDuration : 0)
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // Controls.
            Item {
              width: parent.width
              height: playButton.height

              Row {
                anchors.centerIn: parent
                spacing: Style.space(10)

                Control {
                  iconText: root.player.like === "DISLIKE" ? root.iconDislike : root.iconDislikeOff
                  on: root.player.like === "DISLIKE"
                  tooltipText: "Dislike"
                  onClicked: root.action("dislike")
                }
                Control {
                  iconText: root.iconShuffle
                  on: root.player.shuffle
                  tooltipText: "Shuffle"
                  onClicked: root.action("shuffle")
                }
                Control {
                  iconText: root.iconPrevious
                  tooltipText: "Previous"
                  onClicked: root.action("previous")
                }
                Control {
                  id: playButton
                  iconText: root.playing ? root.iconPause : root.iconPlay
                  fontSize: Style.font.icon * 1.4
                  tooltipText: root.playing ? "Pause" : "Play"
                  onClicked: root.action("toggle")
                }
                Control {
                  iconText: root.iconNext
                  tooltipText: "Next"
                  onClicked: root.action("next")
                }
                Control {
                  iconText: root.player.repeat === "ONE" ? root.iconRepeatOne : root.iconRepeat
                  on: root.player.repeat !== "NONE"
                  tooltipText: root.player.repeat === "ONE" ? "Repeat one" : (root.player.repeat === "ALL" ? "Repeat all" : "Repeat off")
                  onClicked: root.action("repeat")
                }
                Control {
                  iconText: root.player.like === "LIKE" ? root.iconLike : root.iconLikeOff
                  on: root.player.like === "LIKE"
                  tooltipText: "Like"
                  onClicked: root.action("like")
                }
              }
            }

            // Volume.
            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                id: volumeIcon
                anchors.verticalCenter: parent.verticalCenter
                text: root.player.muted ? root.iconMuted : root.iconVolume
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.icon
              }
              PanelSlider {
                bar: root.bar
                width: parent.width - volumeIcon.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                minimum: 0
                maximum: 100
                step: 5
                integer: true
                value: root.volume
                onReleased: function(value) { root.setVolume(value) }
              }
            }

            Rectangle {
              width: parent.width
              height: Style.spacing.hairline
              color: root.bar.foreground
              opacity: 0.12
            }

            SectionHeader { text: "UP NEXT" }
            Repeater { model: root.player.queue; delegate: QueueRow {} }
            SectionHeader {
              visible: root.player.queue.length === 0
              text: "Queue is empty"
              font.italic: true
              font.letterSpacing: 0
            }
          }
        }
      }
    }
  }
}
