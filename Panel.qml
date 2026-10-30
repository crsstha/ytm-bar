import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Player popup plus the pill label, styled after the "Mini Player" design:
// dark glass with a warm glow, a segmented tab bar (Now, Search, Library, Home)
// and Settings (the YouTube Music login). Albums, artists and playlists open as
// a page on top of the tab. Everything talks to the ytm-bar service
// (bin/ytm-bar daemon) over HTTP; now-playing is polled from GET /song.
Panel {
  id: root
  moduleName: "crsstha.ytmusic"
  ipcTarget: "crsstha.ytmusic"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/ytm-bar")).replace(/^file:\/\//, ""))
  readonly property string api: "http://127.0.0.1:26539"
  readonly property int maxTitleLength: 30

  // ---- The design's look. The card is see-through; Hyprland blurs what shows
  // through (omarchy/bindings.lua).
  // The accent (and the glow) take the colour of the cover; the service works
  // it out (bin/ytm-bar cover_color), amber until then or without a song.
  readonly property color defaultAccent: "#f3c98b"
  property color accent: song && song.color ? song.color : defaultAccent
  Behavior on accent { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
  readonly property color ink: "#f2f2f0"
  readonly property color cardTint: Qt.rgba(18 / 255, 20 / 255, 24 / 255, 0.62)
  readonly property color glow: Qt.rgba(accent.r, accent.g, accent.b, 0.24)
  // Up next as a row of covers, or the editable list.
  property bool queueAsList: false
  // Memory in use (ytm-bar stats), refreshed while Settings is open.
  property var stats: null
  readonly property int cardRadius: 22
  readonly property int queueRows: 5
  readonly property string sansFont: geist.status === FontLoader.Ready ? geist.name : root.bar.fontFamily
  readonly property string monoFont: geistMono.status === FontLoader.Ready ? geistMono.name : root.bar.fontFamily
  function white(alpha) { return Qt.rgba(1, 1, 1, alpha) }

  FontLoader { id: geist; source: Qt.resolvedUrl("fonts/Geist.ttf") }
  FontLoader { id: geistMono; source: Qt.resolvedUrl("fonts/GeistMono.ttf") }

  // "offline" (service stopped), "idle" (nothing loaded), "ok".
  property string status: "offline"
  property var song: null
  property var player: ({ like: "INDIFFERENT", shuffle: false, repeat: "NONE", volume: 0, maxVolume: 100, boost: false,
                          eq: "flat", sleep: null, muted: false, loggedIn: false, queue: [], queueCount: 0 })
  // When `player` last arrived, so the sleep countdown can tick between updates.
  property double playerAt: 0
  readonly property real sleepLeft: player.sleep && player.sleep.mode === "min"
    ? Math.max(0, player.sleep.left - (playing ? (clockMs - playerAt) / 1000 : 0)) : 0
  readonly property string sleepLabel: !player.sleep ? "" : (player.sleep.mode === "end" ? "End of song" : clock(sleepLeft))

  // Dragging a queue row: its playlist index, and where it would land (-1: none).
  property int dragFrom: -1
  property int dragOver: -1
  property string message: ""

  // "now", "search", "library", "home" or "settings".
  property string tab: "now"
  // Open album/artist/playlist pages, newest last; Back pops one.
  property var pages: []
  readonly property var page: pages.length > 0 ? pages[pages.length - 1] : null

  property string searchQuery: ""
  property string searchFilter: "all"
  property string searchedKey: ""
  property var searchSections: []
  property string searchError: ""
  property int searchSeq: 0
  readonly property bool searchActive: searchQuery.trim() !== ""
  readonly property bool searching: searchActive && searchedKey !== searchKey()

  property var homeSections: []
  property string homeError: ""
  property bool homeLoading: false
  property var librarySections: []
  property string libraryError: ""
  property bool libraryLoading: false
  property bool libraryLoaded: false

  property var account: ({ loggedIn: false, name: "", handle: "", photo: "" })
  property bool loginBusy: false
  property string loginError: ""
  property bool showHeaderLogin: false
  // "Sign in with Google" runs in the service; its state comes with the player's.
  readonly property bool signingIn: root.player.signingIn === true
  onSigningInChanged: {
    if (root.signingIn) return
    if (root.player.loggedIn) root.reloadAccount()
    else root.loginError = root.player.signinError || ""
  }

  // Sliders: after a seek/volume change, hold the new value until the service reports
  // it, so the knob doesn't snap back to the stale value and jump forward again.
  property real pendingSeek: -1
  property real pendingVolume: -1
  // Progress glides between polls: elapsedBase as of elapsedAt, advanced locally while playing.
  property real elapsedBase: 0
  property double elapsedAt: 0
  property double clockMs: 0
  // Set while mpv lags behind the displayed position (e.g. buffering after a
  // seek): the knob waits for it instead of stepping backwards.
  property bool elapsedHeld: false
  readonly property real elapsed: song
    ? Math.min(song.songDuration || 0, elapsedBase + (playing && !elapsedHeld ? Math.max(0, (clockMs - elapsedAt) / 1000) : 0))
    : 0
  readonly property real volume: pendingVolume >= 0 ? pendingVolume : player.volume

  readonly property bool playing: status === "ok" && song !== null && !song.isPaused
  readonly property string label: buildLabel()
  // The pill draws a wave instead of the play/pause icon while a song is loaded.
  readonly property bool showWave: status === "ok" && song !== null
  readonly property string waveTitle: song ? truncate(song.title) : ""
  readonly property bool dimmed: status !== "ok" || !playing
  readonly property string tooltip: status === "offline" ? "Start the YouTube Music player" : (song ? song.title + " — " + song.artist : "")

  // The pill's label still uses the bar's icon font.
  readonly property string iconMusic: String.fromCodePoint(0xF075A)
  readonly property string iconPlayGlyph: String.fromCodePoint(0xF040A)
  readonly property string iconPauseGlyph: String.fromCodePoint(0xF03E4)

  // The design's icons: SVG paths on a 24×24 grid. "Fill" icons are solid.
  readonly property var icons: ({
    search: "M4 11a7 7 0 1 0 14 0a7 7 0 1 0 -14 0M20 20l-3.5-3.5",
    settings: "M4 7h10M18 7h2M4 17h4M12 17h8M14 7a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M8 17a2 2 0 1 0 4 0a2 2 0 1 0 -4 0",
    // Like is a heart (filled once liked); dislike, a heart struck through.
    dislike: "M3 3l18 18M19.5 12.572l-1.5 1.428m-2 2l-4 4l-7.5-7.428a5 5 0 0 1-1.288-5.068a4.976 4.976 0 0 1 1.788-2.504m3-1c1.56 0 3.05.727 4 2a5 5 0 1 1 7.5 6.572",
    like: "M19.5 12.572l-7.5 7.428l-7.5-7.428a5 5 0 1 1 7.5-6.566a5 5 0 1 1 7.5 6.572",
    likeFill: "M19.5 12.572l-7.5 7.428l-7.5-7.428a5 5 0 1 1 7.5-6.566a5 5 0 1 1 7.5 6.572",
    shuffle: "M3 6h3l11 12h4M3 18h3l3-3.3M14 9.3L17 6h4M18 3l3 3-3 3M18 15l3 3-3 3",
    repeat: "M17 2l3 3-3 3M4 11V9a4 4 0 0 1 4-4h12M7 22l-3-3 3-3M20 13v2a4 4 0 0 1-4 4H4",
    repeatOne: "M17 2l3 3-3 3M4 11V9a4 4 0 0 1 4-4h12M7 22l-3-3 3-3M20 13v2a4 4 0 0 1-4 4H4M11 10.5l1.2-1V14.5",
    previousFill: "M6 5h2v14H6zM20 5v14L9 12z",
    nextFill: "M16 5h2v14h-2zM4 5v14l11-7z",
    playFill: "M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z",
    pauseFill: "M7.2 5h1.6a1.2 1.2 0 0 1 1.2 1.2v11.6a1.2 1.2 0 0 1-1.2 1.2H7.2A1.2 1.2 0 0 1 6 17.8V6.2A1.2 1.2 0 0 1 7.2 5zM15.2 5h1.6a1.2 1.2 0 0 1 1.2 1.2v11.6a1.2 1.2 0 0 1-1.2 1.2h-1.6a1.2 1.2 0 0 1-1.2-1.2V6.2A1.2 1.2 0 0 1 15.2 5z",
    volume: "M11 5L6 9H3v6h3l5 4zM15.5 9a4 4 0 0 1 0 6",
    muted: "M11 5L6 9H3v6h3l5 4zM16 9.5l5 5M21 9.5l-5 5",
    chevron: "M9 6l6 6-6 6",
    list: "M9 6h11M9 12h11M9 18h11M5 6v.01M5 12v.01M5 18v.01",
    grid: "M4 4h6v6h-6zM14 4h6v6h-6zM4 14h6v6h-6zM14 14h6v6h-6z",
    back: "M15 6l-6 6 6 6",
    playNext: "M3 6h12M3 12h12M3 18h8M18 14v8M14 18h8",
    account: "M4 21a8 8 0 0 1 16 0M8 7a4 4 0 1 0 8 0a4 4 0 1 0 -8 0",
    moon: "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z",
    up: "M12 19V5M6 11l6-6 6 6",
    close: "M6 6l12 12M18 6L6 18",
    logout: "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"
  })

  readonly property var sleepOptions: [
    { label: "Off", value: "off" },
    { label: "15 min", value: "15" },
    { label: "30 min", value: "30" },
    { label: "1 hr", value: "60" },
    { label: "End of song", value: "end" }
  ]
  // The design's equalizer presets: gains (dB) for five bands, drawn as bars.
  readonly property var eqPresets: [
    { value: "flat", label: "Flat", gains: [0, 0, 0, 0, 0] },
    { value: "bass", label: "Bass", gains: [5, 4, 1, 0, 0] },
    { value: "vocal", label: "Vocal", gains: [-1, 0, 4, 3, 0] },
    { value: "treble", label: "Treble", gains: [0, 0, 1, 4, 5] },
    { value: "loudness", label: "Loudness", gains: [5, 2, 0, 2, 5] },
    { value: "night", label: "Night", gains: [-1, 0, 2, 1, -1] }
  ]

  function sleepSelected(value) {
    var sleep = root.player.sleep
    if (!sleep) return value === "off"
    if (sleep.mode === "end") return value === "end"
    return String(sleep.minutes) === value
  }

  readonly property var tabs: [
    { value: "now", label: "Playing" },
    { value: "search", label: "Search" },
    { value: "library", label: "Saved" },
    { value: "home", label: "For you" }
  ]
  readonly property var filters: [
    { value: "all", label: "All" },
    { value: "songs", label: "Songs" },
    { value: "albums", label: "Albums" },
    { value: "artists", label: "Artists" },
    { value: "playlists", label: "Playlists" },
    { value: "videos", label: "Videos" }
  ]

  function open() {
    if (root.tab === "now" && !root.song && root.pages.length === 0) root.setTab("search")
    root.controller.show()
    root.refreshPlayer()
  }
  function openFromHotkey() {
    root.open()
    root.setTab("search")
  }
  function close() {
    root.controller.hide()
    root.message = ""
  }
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
    if (status !== "ok" || !song) return iconMusic
    return (playing ? iconPauseGlyph : iconPlayGlyph) + " " + truncate(song.title)
  }

  // A stable hue per title, for the placeholder art gradient.
  function hueOf(text) {
    var h = 0
    for (var i = 0; i < (text || "").length; i++) h = (h * 31 + text.charCodeAt(i)) % 360
    return h / 360
  }

  // ---- The service. Every command answers one JSON object with "ok".
  function call(command, args, done) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var result
      try {
        result = JSON.parse(xhr.responseText)
      } catch (e) {
        result = { ok: false, error: xhr.status === 0 ? "The player service isn't running" : "The player service sent a bad reply" }
      }
      if (done) done(result)
    }
    xhr.open("POST", root.api + "/" + command)
    xhr.setRequestHeader("X-Ytm-Bar", "1")
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.send(JSON.stringify({ args: args || [] }))
  }

  // ---- Live now-playing: poll the service directly (cheap, localhost).
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
      } else {
        root.song = null
        root.status = "offline"
      }
    }
    xhr.open("GET", root.api + "/song")
    xhr.setRequestHeader("X-Ytm-Bar", "1")
    xhr.send()
  }
  property var pollRequest: null

  function syncElapsed(reported, sameSong) {
    var now = Date.now()
    if (root.pendingSeek >= 0) {
      // Ignore stale positions until mpv has actually moved to the seek target.
      if (sameSong && Math.abs(reported - root.pendingSeek) > 2.5) return
      root.pendingSeek = -1
    }
    var shown = root.elapsed
    // mpv stalls while buffering; if it's slightly behind, hold the knob where
    // it is until it catches up.
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

  function action(name, args) {
    if (root.status !== "ok" && root.status !== "idle") return
    if ((name === "like" || name === "dislike") && !root.player.loggedIn) {
      root.message = "Log in (Settings) to like songs."
      return
    }
    root.call(name, args, function(result) {
      root.message = result.ok ? "" : (result.error || "That didn't work")
      settleTimer.restart()
    })
  }

  function refreshPlayer() {
    if (root.status !== "ok" && root.status !== "idle") return
    if (stateBusy) return
    stateBusy = true
    root.call("state", [], function(result) {
      root.stateBusy = false
      if (!result.ok) return
      if (root.pendingVolume >= 0 && Math.abs(result.volume - root.pendingVolume) <= 1) root.pendingVolume = -1
      root.player = result
      root.playerAt = Date.now()
    })
  }
  property bool stateBusy: false

  // The player runs as a systemd user service (ytm-bar.service).
  function startApp() {
    Quickshell.execDetached([root.cli, "start"])
    root.message = ""
  }

  // ---- Tabs and pages.
  function setTab(name) {
    root.tab = name
    root.pages = []
    scroller.contentY = 0
    if (name === "home" && root.homeSections.length === 0) root.loadHome()
    if (name === "library" && !root.libraryLoaded) root.loadLibrary()
    if (name === "settings") {
      root.loadAccount()
      root.refreshPlayer()
    }
    if (name === "search") Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function openPage(entry) {
    var stack = root.pages.slice()
    stack.push({ type: entry.type, id: entry.id, title: entry.title, subtitle: entry.subtitle,
                 image: entry.image, sections: [], loading: true, error: "" })
    root.pages = stack
    scroller.contentY = 0
    root.call("open", [entry.type, entry.id], function(result) {
      var at = root.pages.findIndex(function(p) { return p.type === entry.type && p.id === entry.id })
      if (at < 0) return
      var updated = root.pages.slice()
      updated[at] = result.ok ? Object.assign(result, { loading: false, error: "" })
                              : Object.assign({}, updated[at], { loading: false, error: result.error || "Couldn't open it" })
      root.pages = updated
    })
  }

  function back() {
    root.pages = root.pages.slice(0, -1)
    scroller.contentY = 0
  }

  // Songs play (an album or playlist from that song on, like YouTube Music);
  // albums, artists and playlists open as a page.
  function activate(entry, context) {
    if (entry.type === "queue") {
      if (!entry.current) root.action("jump", [String(entry.index)])
    } else if (entry.type === "song" || entry.type === "video") {
      if (context && context.type !== "artist" && entry.index !== undefined)
        root.action("playall", [context.type, context.id, String(entry.index)])
      else
        root.action("play", [entry.id])
    } else {
      root.openPage(entry)
    }
  }

  // ---- Search: debounced while typing, immediate on Enter or a filter change.
  function searchKey() { return root.searchFilter + "\n" + root.searchQuery.trim() }

  function runSearch() {
    if (!root.searchActive || root.searchedKey === root.searchKey()) return
    var key = root.searchKey()
    var seq = ++root.searchSeq
    root.call("search", [root.searchQuery.trim(), root.searchFilter], function(result) {
      if (seq !== root.searchSeq) return  // a newer search is running
      root.searchedKey = key
      root.searchSections = result.ok ? result.sections : []
      root.searchError = result.ok ? "" : (result.error || "Search failed")
    })
  }

  function setFilter(name) {
    root.searchFilter = name
    searchDebounce.stop()
    root.runSearch()
  }

  function clearSearch() {
    root.searchQuery = ""
    root.searchedKey = ""
    root.searchSections = []
    root.searchError = ""
    root.searchSeq++
    searchField.text = ""
  }

  function loadHome() {
    root.homeLoading = true
    root.call("home", [], function(result) {
      root.homeLoading = false
      root.homeSections = result.ok ? result.sections : []
      root.homeError = result.ok ? "" : (result.error || "Couldn't load your home page")
    })
  }

  function loadLibrary() {
    if (!root.player.loggedIn) return
    root.libraryLoading = true
    root.call("library", [], function(result) {
      root.libraryLoading = false
      root.libraryLoaded = result.ok
      root.librarySections = result.ok ? result.sections : []
      root.libraryError = result.ok ? "" : (result.error || "Couldn't load your library")
    })
  }

  // ---- Settings: the YouTube Music login.
  function loadAccount() {
    root.call("account", [], function(result) {
      if (!result.ok) return
      root.account = result
      if (result.expired) root.loginError = "YouTube ended this login — sign in again"
    })
  }

  // After logging in or out, the library and home page change.
  function reloadAccount() {
    root.loadAccount()
    root.refreshPlayer()
    root.homeSections = []
    root.librarySections = []
    root.libraryLoaded = false
  }

  function login() {
    if (root.loginBusy) return
    root.loginBusy = true
    root.loginError = ""
    root.call("login", [headersEdit.text], function(result) {
      root.loginBusy = false
      if (result.ok) {
        headersEdit.text = ""
        root.reloadAccount()
      } else {
        root.loginError = result.error || "Couldn't log in"
      }
    })
  }

  function loadStats() {
    root.call("stats", [], function(result) { if (result.ok) root.stats = result })
  }
  Timer {
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.opened && root.tab === "settings" && root.page === null
    onTriggered: root.loadStats()
  }

  // Focus ytm-tui's terminal if it's open, otherwise start one.
  function openTui() {
    Quickshell.execDetached(["bash", "-lc", "omarchy-launch-or-focus-tui ytm-tui"])
    root.close()
  }

  function signin() {
    root.loginError = ""
    root.call("signin", [], function(result) {
      if (!result.ok) root.loginError = result.error || "Couldn't open the sign-in window"
      else root.refreshPlayer()
    })
  }

  function logout() {
    root.call("logout", [], function(result) { root.reloadAccount() })
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

  // After an action, give the service a moment to apply it, then re-read.
  Timer {
    id: settleTimer
    interval: 350
    onTriggered: {
      root.poll()
      root.refreshPlayer()
    }
  }

  // Advances the progress knob between polls while the popup shows it.
  Timer {
    interval: 250
    running: root.opened && root.playing
    repeat: true
    onTriggered: root.clockMs = Date.now()
  }

  // Never hold a slider value forever (e.g. mpv clamped or ignored the change).
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

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playPause(): void { root.action("toggle") }
    function next(): void { root.action("next") }
    function previous(): void { root.action("previous") }
    function like(): void { root.action("like") }
    // omarchy-shell crsstha.ytmusic show home|search|library|now|settings
    function show(tab: string): void {
      root.open()
      root.setTab(tab)
    }
    // omarchy-shell crsstha.ytmusic search "daft punk"
    function search(query: string): void {
      root.open()
      root.setTab("search")
      searchField.text = query
      root.searchQuery = query
      root.runSearch()
    }
    function status(): string { return JSON.stringify({ status: root.status, label: root.label, song: root.song }) }
  }

  // ---- Building blocks.

  component Label: Text {
    textFormat: Text.PlainText
    color: root.ink
    font.family: root.sansFont
    font.pixelSize: 13
    // Geist is a variable font: pass the weight as its axis too, or Qt draws
    // every weight as regular. Set `weight`, not font.weight.
    property int weight: Font.Normal
    font.weight: weight
    font.variableAxes: ({ "wght": weight })
    elide: Text.ElideRight
  }

  // Times, counts and lengths.
  component Mono: Label {
    font.family: root.monoFont
    font.pixelSize: 11
    color: root.white(0.5)
  }

  component SectionHeader: Label {
    text: ""
    font.pixelSize: 11
    weight: Font.DemiBold
    font.letterSpacing: 0.9
    font.capitalization: Font.AllUppercase
    color: root.white(0.45)
  }

  // Loading, empty and error lines, centred like the design's empty state.
  component Note: Label {
    width: parent ? parent.width : 0
    topPadding: 22
    bottomPadding: 22
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    elide: Text.ElideNone
    color: root.white(0.45)
  }

  // One of the design's SVG icons, stroked (2px on 24) or solid.
  component Icon: Item {
    id: icon
    property string name: ""
    property color color: root.white(0.55)
    property real size: 16
    property real stroke: 2
    readonly property bool solid: name.endsWith("Fill")
    width: size
    height: size

    Shape {
      width: 24
      height: 24
      scale: icon.size / 24
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: icon.solid ? "transparent" : icon.color
        strokeWidth: icon.solid ? 0 : icon.stroke
        fillColor: icon.solid ? icon.color : "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: root.icons[icon.name] || "" }
      }
    }
  }

  // The shell's tooltip, in the card's dark glass and Geist.
  component Tip: PanelToolTip {
    panelBackground: Qt.rgba(14 / 255, 16 / 255, 20 / 255, 0.94)
    panelBorder: root.white(0.12)
    panelForeground: root.ink
    fontFamily: root.sansFont
    fontSize: 12
  }

  // A borderless icon button that lights up on hover; `tip` names it on hover.
  component IconButton: Rectangle {
    id: iconButton
    property string icon: ""
    property string tip: ""
    property real iconSize: 16
    property color iconColor: root.white(0.55)
    signal clicked()
    width: 32
    height: 32
    radius: 10
    color: iconArea.containsMouse ? root.white(0.08) : "transparent"

    Icon {
      anchors.centerIn: parent
      name: iconButton.icon
      size: iconButton.iconSize
      color: iconButton.iconColor
    }
    MouseArea {
      id: iconArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: iconButton.clicked()
    }
    Tip {
      visible: iconButton.tip !== "" && iconArea.containsMouse
      text: iconButton.tip
    }
  }

  // Text buttons: white for the main action, glass for the rest.
  component Pill: Rectangle {
    id: pill
    property string text: ""
    property string icon: ""
    property bool primary: false
    signal clicked()
    width: pillRow.implicitWidth + 26
    height: 32
    radius: height / 2
    color: pill.primary ? (pillArea.containsMouse ? "#ffffff" : root.white(0.92))
      : (pillArea.containsMouse ? root.white(0.12) : root.white(0.06))
    border.width: pill.primary ? 0 : 1
    border.color: root.white(0.08)
    scale: pillArea.pressed ? 0.96 : 1

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: 7

      Icon {
        visible: pill.icon !== ""
        anchors.verticalCenter: parent.verticalCenter
        name: pill.icon
        size: 14
        color: pill.primary ? "#111111" : root.ink
      }
      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: pill.text
        weight: Font.Medium
        color: pill.primary ? "#111111" : root.ink
      }
    }
    MouseArea {
      id: pillArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }

  // Search filters.
  component Chip: Rectangle {
    id: chip
    property string text: ""
    property bool selected: false
    signal clicked()
    width: chipLabel.implicitWidth + 22
    height: 26
    radius: 13
    color: chip.selected ? root.white(0.12) : (chipArea.containsMouse ? root.white(0.06) : "transparent")
    border.width: 1
    border.color: chip.selected ? root.white(0.1) : root.white(0.07)

    Label {
      id: chipLabel
      anchors.centerIn: parent
      text: chip.text
      font.pixelSize: 12
      weight: Font.Medium
      color: chip.selected || chipArea.containsMouse ? "#ffffff" : root.white(0.6)
    }
    MouseArea {
      id: chipArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // The design's slim track: 4px rail, a fill, and (for progress) a knob.
  // Click or drag; `picked` fires on release.
  component Track: Item {
    id: track
    property real value: 0
    property real maximum: 1
    property bool knob: false
    property bool gradientFill: false
    property color fill: root.white(0.6)
    // Volume boost: where 100% sits on the track (0 = no marker); beyond it the fill is amber.
    property real unity: 0
    property real dragValue: 0
    readonly property bool dragging: trackArea.pressed
    readonly property real shown: dragging ? dragValue : value
    readonly property real fraction: maximum > 0 ? Math.max(0, Math.min(1, shown / maximum)) : 0
    signal picked(real value)
    height: 16

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: 4
      radius: 2
      color: root.white(0.12)
    }
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * track.fraction
      height: 4
      radius: 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: track.gradientFill ? root.white(0.75) : track.fill }
        GradientStop { position: 1; color: track.gradientFill ? "#ffffff" : track.fill }
      }
    }
    Rectangle {
      visible: track.unity > 0 && track.fraction > track.unity
      x: parent.width * track.unity
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * (track.fraction - track.unity)
      height: 4
      radius: 2
      color: root.accent
    }
    Rectangle {
      visible: track.unity > 0
      x: parent.width * track.unity - 1
      anchors.verticalCenter: parent.verticalCenter
      width: 2
      height: 10
      radius: 1
      color: root.white(0.35)
    }
    Rectangle {
      visible: track.knob
      x: parent.width * track.fraction - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: 20
      height: 20
      radius: 10
      color: root.white(0.12)

      Rectangle {
        anchors.centerIn: parent
        width: 12
        height: 12
        radius: 6
        color: "#ffffff"
      }
    }
    MouseArea {
      id: trackArea
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      function valueAt(x) { return Math.max(0, Math.min(1, x / width)) * track.maximum }
      onPressed: function(mouse) { track.dragValue = valueAt(mouse.x) }
      onPositionChanged: function(mouse) { if (pressed) track.dragValue = valueAt(mouse.x) }
      onReleased: track.picked(track.dragValue)
    }
  }

  // The seek bar as a waveform: one bar per slice of the song, played bars in
  // the accent. Heights are seeded from the song, so every song has its own.
  component WaveTrack: Item {
    id: wave
    property real value: 0
    property real maximum: 1
    property string seed: ""
    property real dragValue: 0
    readonly property bool dragging: waveArea.pressed
    readonly property real shown: dragging ? dragValue : value
    readonly property real fraction: maximum > 0 ? Math.max(0, Math.min(1, shown / maximum)) : 0
    readonly property int bars: Math.max(8, Math.floor((width + 2) / 5))
    readonly property var levels: {
      var h = 2166136261
      for (var i = 0; i < seed.length; i++) h = Math.imul(h ^ seed.charCodeAt(i), 16777619) >>> 0
      var out = []
      for (var b = 0; b < bars; b++) {
        h = Math.imul(h ^ (h >>> 15), 2246822507) >>> 0
        var noise = (h % 1000) / 1000
        // Smooth swells with a little grain, quieter at the very ends.
        var shape = 0.55 + 0.45 * Math.sin(b * 0.37 + (seed.length % 7)) * Math.sin(b * 0.11 + 1.3)
        var ends = Math.min(1, Math.min(b, bars - 1 - b) / 4 + 0.35)
        out.push(Math.max(0.12, Math.min(1, (shape * 0.7 + noise * 0.3) * ends)))
      }
      return out
    }
    signal picked(real value)
    height: 28

    Repeater {
      model: wave.bars
      delegate: Rectangle {
        required property int index
        readonly property bool played: (index + 0.5) / wave.bars <= wave.fraction
        x: index * wave.width / wave.bars
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(2, wave.width / wave.bars - 2)
        height: Math.max(3, wave.height * wave.levels[index])
        radius: width / 2
        color: played ? root.accent : root.white(waveArea.containsMouse ? 0.26 : 0.18)
      }
    }
    MouseArea {
      id: waveArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      function valueAt(x) { return Math.max(0, Math.min(1, x / width)) * wave.maximum }
      onPressed: function(mouse) { wave.dragValue = valueAt(mouse.x) }
      onPositionChanged: function(mouse) { if (pressed) wave.dragValue = valueAt(mouse.x) }
      onReleased: wave.picked(wave.dragValue)
    }
  }

  // Cover art with rounded corners; a gradient in the song's own hue until
  // (or instead of) the image.
  component Art: Item {
    id: art
    property string source: ""
    property string seed: ""
    property real radius: 8
    readonly property real hue: root.hueOf(seed)

    Rectangle {
      anchors.fill: parent
      radius: art.radius
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.hsla(art.hue, 0.35, 0.42, 1) }
        GradientStop { position: 1; color: Qt.hsla(art.hue, 0.3, 0.14, 1) }
      }
    }
    Image {
      id: artImage
      anchors.fill: parent
      visible: false
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: art.width * 2
      sourceSize.height: art.height * 2
      source: art.source
    }
    Item {
      id: artMask
      anchors.fill: parent
      layer.enabled: true
      visible: false
      Rectangle { anchors.fill: parent; radius: art.radius }
    }
    MultiEffect {
      anchors.fill: parent
      visible: artImage.status === Image.Ready
      source: artImage
      maskEnabled: true
      maskSource: artMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
    Rectangle {
      anchors.fill: parent
      radius: art.radius
      color: "transparent"
      border.width: 1
      border.color: root.white(0.1)
    }
  }

  // One row: a song, video, album, artist, playlist or queue item.
  component EntryRow: Rectangle {
    id: row
    required property var modelData
    property var context: null
    property bool large: false
    readonly property bool playable: modelData.type === "song" || modelData.type === "video"
    readonly property bool timed: playable || modelData.type === "queue"
    readonly property bool current: modelData.type === "queue" ? modelData.current === true
      : playable && root.song !== null && root.song.videoId === modelData.id
    // Queued songs after the current one can be moved, sent up next or removed.
    readonly property bool editable: modelData.type === "queue" && !current
    readonly property bool showActions: editable && hover.hovered && root.dragFrom < 0
    width: parent ? parent.width : 0
    height: rowArt.height + 12
    radius: 12
    opacity: editable && root.dragFrom === modelData.index ? 0.4 : 1
    color: modelData.type === "queue" && current ? root.white(0.07)
      : (hover.hovered && root.dragFrom < 0 ? root.white(0.06) : "transparent")

    HoverHandler { id: hover }
    MouseArea {
      anchors.fill: parent
      preventStealing: true
      cursorShape: !row.editable ? (row.current ? Qt.ArrowCursor : Qt.PointingHandCursor)
        : (root.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
      property real pressY: 0
      property bool dragged: false
      onPressed: function(mouse) {
        pressY = mouse.y
        dragged = false
      }
      // Drag a queued song up or down; the amber line shows where it lands.
      onPositionChanged: function(mouse) {
        if (!row.editable || !pressed) return
        var dy = mouse.y - pressY
        if (!dragged && Math.abs(dy) < 6) return
        dragged = true
        var queue = root.player.queue
        var first = queue.length > 0 ? queue[0].index + 1 : 0
        var last = queue.length > 0 ? queue[queue.length - 1].index : 0
        root.dragFrom = row.modelData.index
        root.dragOver = Math.max(first, Math.min(last, row.modelData.index + Math.round(dy / (row.height + 1))))
      }
      onReleased: {
        if (dragged) {
          if (root.dragOver >= 0 && root.dragOver !== root.dragFrom)
            root.action("move", [String(root.dragFrom), String(root.dragOver)])
          root.dragFrom = -1
          root.dragOver = -1
        }
      }
      onCanceled: {
        root.dragFrom = -1
        root.dragOver = -1
      }
      onClicked: if (!dragged) root.activate(row.modelData, row.context)
    }
    Rectangle {
      visible: row.editable && root.dragOver === row.modelData.index && root.dragFrom !== row.modelData.index
      width: parent.width
      height: 2
      radius: 1
      color: root.accent
    }
    Art {
      id: rowArt
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: row.large ? 56 : 40
      height: width
      radius: row.modelData.type === "artist" ? width / 2 : (row.large ? 10 : 8)
      source: row.modelData.image || ""
      seed: row.modelData.title
    }
    Column {
      anchors.left: rowArt.right
      anchors.leftMargin: 12
      anchors.right: trailing.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1

      Label {
        width: parent.width
        text: row.modelData.title
        font.pixelSize: row.large ? 15 : 13
        weight: row.large ? Font.DemiBold : Font.Medium
        color: row.current ? root.accent : root.white(0.92)
      }
      Label {
        width: parent.width
        visible: text !== ""
        text: row.modelData.subtitle || ""
        font.pixelSize: 12
        color: root.white(0.45)
      }
    }
    // Length (or "play next" while hovered) for songs; a chevron for things that open.
    Item {
      id: trailing
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(lengthText.implicitWidth, 28)
      height: 28

      Mono {
        id: lengthText
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: row.timed && !nextButton.visible && !row.showActions
        text: row.modelData.length || ""
        color: root.white(0.4)
      }
      Icon {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !row.timed
        name: "chevron"
        size: 14
        stroke: 2.2
        color: root.white(0.35)
      }
      IconButton {
        id: nextButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        radius: 8
        visible: row.playable && hover.hovered
        icon: "playNext"
        tip: "Play next"
        iconSize: 15
        iconColor: root.ink
        onClicked: root.action("add", [row.modelData.id])
      }
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      visible: row.showActions
      spacing: 2

      IconButton {
        width: 28
        height: 28
        radius: 8
        color: hovered ? root.white(0.14) : root.white(0.06)
        readonly property bool hovered: upHover.hovered
        HoverHandler { id: upHover }
        icon: "up"
        tip: "Play next"
        iconSize: 13
        iconColor: upHover.hovered ? "#ffffff" : root.white(0.8)
        onClicked: root.action("playnext", [String(row.modelData.index)])
      }
      IconButton {
        width: 28
        height: 28
        radius: 8
        color: removeHover.hovered ? Qt.rgba(1, 90 / 255, 90 / 255, 0.22) : root.white(0.06)
        HoverHandler { id: removeHover }
        icon: "close"
        tip: "Remove from queue"
        iconSize: 13
        iconColor: removeHover.hovered ? "#ffffff" : root.white(0.8)
        onClicked: root.action("remove", [String(row.modelData.index)])
      }
    }
  }

  // Titled sections of rows (search results, home, library, a page).
  component Sections: Column {
    id: list
    property var sections: []
    property var context: null
    width: parent ? parent.width : 0
    spacing: 8

    Repeater {
      model: list.sections
      delegate: Column {
        id: section
        required property var modelData
        width: list.width
        spacing: 1

        SectionHeader {
          leftPadding: 10
          topPadding: 8
          bottomPadding: 6
          text: section.modelData.title
        }
        Repeater {
          model: section.modelData.items
          delegate: EntryRow {
            context: list.context
            large: section.modelData.title === "Top result"
          }
        }
      }
    }
  }

  // ---- The card.

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // No inner padding: the content sets its own, like the design.
    padding: 0
    contentWidth: panel.fittedContentWidth(420)
    contentHeight: panel.fittedContentHeight(header.height + body.implicitHeight, 720)

    // KeyboardPanel doesn't expose its card, so walk up from our content to it
    // (the BorderSurface holding it) for the design's tint and corners.
    Component.onCompleted: {
      for (var card = keyCatcher.parent; card; card = card.parent) {
        if ("borderSpec" in card && "color" in card) {
          card.color = Qt.binding(function() { return root.cardTint })
          card.radius = root.cardRadius
          return
        }
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.pages.length > 0 ? root.back() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // The warm glow from the top-left corner, kept inside the rounded card.
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: "transparent"
          strokeWidth: 0
          fillGradient: RadialGradient {
            centerX: 130
            centerY: 30
            centerRadius: 190
            focalX: 130
            focalY: 30
            GradientStop { position: 0; color: root.glow }
            GradientStop { position: 1; color: "transparent" }
          }
          PathRectangle {
            width: keyCatcher.width
            height: keyCatcher.height
            radius: root.cardRadius - 1
          }
        }
      }

      // ---- Tabs and Settings.
      Item {
        id: header
        width: parent.width
        height: 12 + 36

        Rectangle {
          id: segments
          x: 12
          y: 12
          width: parent.width - 24 - settingsButton.width - 10
          height: 36
          radius: 12
          color: root.white(0.05)
          border.width: 1
          border.color: root.white(0.07)

          Row {
            x: 3
            y: 3
            spacing: 2

            Repeater {
              model: root.tabs
              delegate: Rectangle {
                id: tabButton
                required property var modelData
                readonly property bool active: root.tab === modelData.value && root.pages.length === 0
                width: (segments.width - 6 - 2 * 3) / 4
                height: 30
                radius: 9
                color: active ? root.white(0.12) : "transparent"

                Label {
                  anchors.centerIn: parent
                  text: tabButton.modelData.label
                  weight: Font.Medium
                  color: tabButton.active || tabArea.containsMouse ? "#ffffff" : root.white(0.6)
                }
                MouseArea {
                  id: tabArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setTab(tabButton.modelData.value)
                }
              }
            }
          }
        }
        IconButton {
          id: settingsButton
          x: parent.width - 12 - width
          y: 12
          width: 36
          height: 36
          icon: "settings"
          tip: "Settings"
          color: root.tab === "settings" ? root.white(0.12) : (hovered ? root.white(0.08) : "transparent")
          iconColor: root.tab === "settings" || hovered ? "#ffffff" : root.white(0.6)
          readonly property bool hovered: settingsHover.hovered
          HoverHandler { id: settingsHover }
          onClicked: root.setTab("settings")
        }
      }

      Flickable {
        id: scroller
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: body
          width: scroller.width

          Column {
            visible: root.status === "offline" || root.message !== ""
            width: parent.width
            leftPadding: 18
            rightPadding: 18
            topPadding: 12

            Note {
              visible: root.status === "offline"
              width: parent.width - 36
              topPadding: 10
              bottomPadding: 10
              text: "The player isn't running. Click the bar widget to start it, or run: systemctl --user start ytm-bar"
            }
            Label {
              visible: root.message !== ""
              width: parent.width - 36
              wrapMode: Text.Wrap
              elide: Text.ElideNone
              text: root.message
              font.pixelSize: 12
              color: root.accent
            }
          }

          // ---- An album, artist or playlist page.
          Column {
            visible: root.page !== null
            width: parent.width

            Row {
              x: 18
              topPadding: 18
              width: parent.width - 36
              spacing: 14

              Art {
                id: pageArt
                width: 88
                height: 88
                radius: root.page && root.page.type === "artist" ? 44 : 14
                source: root.page ? root.page.image || "" : ""
                seed: root.page ? root.page.title : ""
              }
              Column {
                width: parent.width - pageArt.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Label {
                  width: parent.width
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  text: root.page ? root.page.title : ""
                  font.pixelSize: 17
                  weight: Font.DemiBold
                  font.letterSpacing: -0.17
                }
                Label {
                  width: parent.width
                  text: root.page ? root.page.subtitle || "" : ""
                  font.pixelSize: 12
                  color: root.white(0.45)
                }
                Row {
                  topPadding: 4
                  spacing: 8

                  Pill {
                    text: "Back"
                    icon: "back"
                    onClicked: root.back()
                  }
                  Pill {
                    visible: root.page !== null && !root.page.loading && !root.page.error
                    text: "Play"
                    icon: "playFill"
                    primary: true
                    onClicked: root.action("playall", [root.page.type, root.page.id])
                  }
                }
              }
            }
            Note {
              visible: root.page !== null && (root.page.loading || root.page.error !== "")
              text: root.page ? (root.page.loading ? "Loading…" : root.page.error) : ""
            }
            Item { width: 1; height: 10 }
            Sections {
              x: 8
              width: parent.width - 16
              sections: root.page ? root.page.sections : []
              context: root.page
            }
            Item { width: 1; height: 10 }
          }

          // ---- Now: the player and the queue.
          Note {
            visible: root.page === null && root.tab === "now" && root.status === "idle"
            text: "Nothing playing — find something in Search or For you."
          }
          Column {
            visible: root.page === null && root.tab === "now" && root.status === "ok" && root.song !== null
            width: parent.width

            // Cover, title, like / dislike.
            Item {
              width: parent.width
              height: 18 + 76

              Art {
                id: cover
                x: 18
                y: 18
                width: 76
                height: 76
                radius: 14
                source: root.song && root.song.imageSrc ? root.song.imageSrc : ""
                seed: root.song ? root.song.title : ""
              }
              Column {
                anchors.left: cover.right
                anchors.leftMargin: 14
                anchors.right: rating.left
                anchors.rightMargin: 6
                anchors.verticalCenter: cover.verticalCenter
                spacing: 3

                Label {
                  width: parent.width
                  text: root.song ? root.song.title : ""
                  font.pixelSize: 17
                  weight: Font.DemiBold
                  font.letterSpacing: -0.17
                }
                Label {
                  width: parent.width
                  text: root.song ? root.song.artist : ""
                  color: root.white(0.7)
                }
                Label {
                  width: parent.width
                  visible: text !== ""
                  text: root.song && root.song.album ? root.song.album : ""
                  font.pixelSize: 12
                  color: root.white(0.45)
                }
              }
              Row {
                id: rating
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: cover.verticalCenter
                spacing: 2

                IconButton {
                  icon: "dislike"
                  tip: root.player.like === "DISLIKE" ? "Disliked" : "Dislike and skip"
                  iconColor: root.player.like === "DISLIKE" ? root.accent : root.white(0.55)
                  onClicked: root.action("dislike")
                }
                IconButton {
                  icon: root.player.like === "LIKE" ? "likeFill" : "like"
                  tip: root.player.like === "LIKE" ? "Liked — click to undo" : "Like"
                  iconColor: root.player.like === "LIKE" ? root.accent : root.white(0.55)
                  onClicked: root.action("like")
                }
              }
            }

            // Progress — drag or click to seek.
            Column {
              x: 18
              topPadding: 18
              width: parent.width - 36
              spacing: 6

              WaveTrack {
                id: progress
                width: parent.width
                maximum: Math.max(1, root.song ? root.song.songDuration : 1)
                value: root.elapsed
                seed: root.song ? root.song.videoId : ""
                onPicked: function(value) { root.seek(value) }
              }
              Item {
                width: parent.width
                height: Math.max(elapsedText.implicitHeight, sleepPill.visible ? sleepPill.height : 0)

                Mono {
                  id: elapsedText
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.clock(progress.shown)
                }
                // The sleep timer, when one is set; click to cancel it.
                Rectangle {
                  id: sleepPill
                  visible: root.player.sleep !== null && root.player.sleep !== undefined
                  anchors.centerIn: parent
                  width: sleepRow.implicitWidth + 16
                  height: 18
                  radius: 9
                  color: sleepArea.containsMouse ? root.white(0.12) : root.white(0.06)
                  border.width: 1
                  border.color: root.white(0.12)

                  Row {
                    id: sleepRow
                    anchors.centerIn: parent
                    spacing: 5

                    Icon {
                      anchors.verticalCenter: parent.verticalCenter
                      name: "moon"
                      size: 10
                      stroke: 2.4
                      color: root.accent
                    }
                    Mono {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.sleepLabel
                      font.pixelSize: 10
                      color: root.accent
                    }
                    Mono {
                      anchors.verticalCenter: parent.verticalCenter
                      text: "✕"
                      font.pixelSize: 10
                      color: root.white(0.4)
                    }
                  }
                  MouseArea {
                    id: sleepArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.action("sleep", ["off"])
                  }
                  Tip {
                    visible: sleepArea.containsMouse
                    text: "Cancel the sleep timer"
                  }
                }
                Mono {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: "-" + root.clock((root.song ? root.song.songDuration : 0) - progress.shown)
                }
              }
            }

            // Controls.
            Item {
              width: parent.width
              height: 10 + 56

              Row {
                x: 26
                y: 10
                readonly property real gaps: (parent.width - 52 - 36 * 2 - 44 * 2 - 56) / 4
                spacing: gaps

                IconButton {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 36
                  height: 36
                  radius: 18
                  icon: "shuffle"
                  tip: root.player.shuffle ? "Shuffle: on" : "Shuffle"
                  iconSize: 17
                  iconColor: root.player.shuffle ? root.accent : root.white(0.55)
                  onClicked: root.action("shuffle")
                }
                IconButton {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 44
                  height: 44
                  radius: 22
                  icon: "previousFill"
                  tip: "Previous"
                  iconSize: 20
                  iconColor: "#ffffff"
                  onClicked: root.action("previous")
                }
                Rectangle {
                  id: playButton
                  width: 56
                  height: 56
                  radius: 28
                  color: "#ffffff"
                  scale: playArea.pressed ? 0.95 : 1

                  Behavior on scale { NumberAnimation { duration: 90 } }

                  Icon {
                    anchors.centerIn: parent
                    name: root.playing ? "pauseFill" : "playFill"
                    size: 22
                    color: "#111111"
                  }
                  MouseArea {
                    id: playArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.action("toggle")
                  }
                  Tip {
                    visible: playArea.containsMouse
                    text: root.playing ? "Pause" : "Play"
                  }
                }
                IconButton {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 44
                  height: 44
                  radius: 22
                  icon: "nextFill"
                  tip: "Next"
                  iconSize: 20
                  iconColor: "#ffffff"
                  onClicked: root.action("next")
                }
                IconButton {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 36
                  height: 36
                  radius: 18
                  icon: root.player.repeat === "ONE" ? "repeatOne" : "repeat"
                  tip: ({ NONE: "Repeat", ALL: "Repeat: all", ONE: "Repeat: this song" })[root.player.repeat] || "Repeat"
                  iconSize: 17
                  iconColor: root.player.repeat !== "NONE" ? root.accent : root.white(0.55)
                  onClicked: root.action("repeat")
                }
              }
            }

            // Volume.
            Item {
              width: parent.width
              height: 12 + 16 + 16

              IconButton {
                id: muteButton
                x: 14
                y: 12 + (16 - height) / 2
                width: 28
                height: 28
                radius: 8
                icon: root.player.muted ? "muted" : "volume"
                tip: root.player.muted ? "Unmute" : "Mute"
                iconSize: 15
                iconColor: root.player.muted ? root.accent : root.white(0.55)
                onClicked: root.action("mute")
              }
              Track {
                anchors.left: muteButton.right
                anchors.leftMargin: 6
                anchors.right: volumeText.left
                anchors.rightMargin: 12
                y: 12
                opacity: root.player.muted ? 0.4 : 1
                maximum: root.player.maxVolume || 100
                unity: root.player.boost ? 100 / (root.player.maxVolume || 150) : 0
                value: root.volume
                onPicked: function(value) { root.setVolume(value) }
              }
              Mono {
                id: volumeText
                anchors.right: parent.right
                anchors.rightMargin: 20
                y: 12 + (16 - height) / 2
                width: 44
                horizontalAlignment: Text.AlignRight
                text: root.player.muted ? "Muted" : Math.round(root.volume) + "%"
                color: root.volume > 100 && !root.player.muted ? root.accent : root.white(0.5)
              }
            }

            // Up next, in a darker well along the bottom of the card.
            Rectangle {
              width: parent.width
              height: queueColumn.implicitHeight
              color: Qt.rgba(0, 0, 0, 0.18)
              bottomLeftRadius: root.cardRadius - 1
              bottomRightRadius: root.cardRadius - 1

              Rectangle {
                width: parent.width
                height: 1
                color: root.white(0.07)
              }
              Column {
                id: queueColumn
                width: parent.width
                topPadding: 14
                bottomPadding: 8

                Item {
                  x: 18
                  width: parent.width - 36
                  height: upNext.implicitHeight + 8

                  SectionHeader { id: upNext; text: "Up next" }
                  Mono {
                    anchors.right: queueMode.left
                    anchors.rightMargin: 6
                    anchors.baseline: upNext.baseline
                    text: root.player.queueCount + (root.player.queueCount === 1 ? " track" : " tracks")
                    color: root.white(0.35)
                  }
                  // Covers or the list (where songs can be moved and removed).
                  IconButton {
                    id: queueMode
                    anchors.right: parent.right
                    anchors.rightMargin: -8
                    anchors.verticalCenter: upNext.verticalCenter
                    width: 26
                    height: 26
                    iconSize: 14
                    icon: root.queueAsList ? "grid" : "list"
                    tip: root.queueAsList ? "Show as covers" : "Show as a list (reorder, remove)"
                    iconColor: queueModeHover.hovered ? "#ffffff" : root.white(0.45)
                    HoverHandler { id: queueModeHover }
                    onClicked: root.queueAsList = !root.queueAsList
                  }
                }
                ListView {
                  id: coverRow
                  visible: !root.queueAsList && count > 0
                  x: 18
                  width: parent.width - 18
                  height: visible ? 136 : 0
                  orientation: ListView.Horizontal
                  spacing: 12
                  clip: true
                  rightMargin: 18
                  boundsBehavior: Flickable.StopAtBounds
                  model: root.player.queue.filter(function(item) { return !item.current })
                  delegate: Item {
                    id: coverCard
                    required property var modelData
                    width: 92
                    height: 136
                    scale: coverCardArea.pressed ? 0.96 : 1

                    Art {
                      width: 92
                      height: 92
                      radius: 14
                      source: coverCard.modelData.image || ""
                      seed: coverCard.modelData.title
                      opacity: coverCardArea.containsMouse ? 1 : 0.9
                    }
                    Label {
                      y: 100
                      width: parent.width
                      text: coverCard.modelData.title
                      font.pixelSize: 12
                      weight: Font.Medium
                      color: coverCardArea.containsMouse ? "#ffffff" : root.white(0.9)
                    }
                    Label {
                      y: 117
                      width: parent.width
                      text: coverCard.modelData.artist || ""
                      font.pixelSize: 11
                      color: root.white(0.45)
                    }
                    MouseArea {
                      id: coverCardArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.action("jump", [coverCard.modelData.index])
                    }
                    Tip {
                      visible: coverCardArea.containsMouse
                      text: coverCard.modelData.title + (coverCard.modelData.artist ? " — " + coverCard.modelData.artist : "")
                    }
                  }
                }
                Flickable {
                  visible: root.queueAsList
                  x: 8
                  width: parent.width - 16
                  height: visible ? Math.min(queueList.implicitHeight, root.queueRows * 53) : 0
                  contentHeight: queueList.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  interactive: contentHeight > height && root.dragFrom < 0

                  Column {
                    id: queueList
                    width: parent.width
                    spacing: 1

                    Repeater {
                      model: root.player.queue.map(function(item) {
                        return { type: "queue", id: String(item.index), index: item.index, title: item.title,
                                 subtitle: item.artist, length: item.length, image: item.image || "", current: item.current }
                      })
                      delegate: EntryRow {}
                    }
                  }
                }
                Note {
                  visible: root.player.queue.length === 0
                  text: "Queue is empty"
                }
              }
            }
          }

          // ---- Search.
          Column {
            visible: root.page === null && root.tab === "search"
            width: parent.width

            Item {
              width: parent.width
              height: 14 + 40

              TextField {
                id: searchField
                x: 12
                y: 14
                width: parent.width - 24
                height: 40
                leftPadding: 36
                rightPadding: 12
                placeholderText: "Search YouTube Music"
                placeholderTextColor: root.white(0.38)
                color: "#ffffff"
                foreground: "#ffffff"
                accent: root.accent
                font.family: root.sansFont
                font.pixelSize: 13
                background: Rectangle {
                  radius: 12
                  color: root.white(0.06)
                  border.width: 1
                  border.color: searchField.activeFocus ? root.white(0.18) : root.white(0.08)
                }
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

                Icon {
                  x: 13
                  anchors.verticalCenter: parent.verticalCenter
                  name: "search"
                  size: 14
                  stroke: 2.2
                  color: root.white(0.45)
                }
              }
            }
            Flow {
              x: 12
              topPadding: 10
              width: parent.width - 24
              spacing: 6

              Repeater {
                model: root.filters
                delegate: Chip {
                  required property var modelData
                  text: modelData.label
                  selected: root.searchFilter === modelData.value
                  onClicked: root.setFilter(modelData.value)
                }
              }
            }
            Note {
              visible: root.searchActive && (root.searching || root.searchError !== "" || root.searchSections.length === 0)
              text: root.searching ? "Searching…" : (root.searchError !== "" ? root.searchError : "No results for “" + root.searchQuery.trim() + "”")
            }
            Item { width: 1; height: 10 }
            Sections {
              x: 8
              width: parent.width - 16
              visible: root.searchActive
              sections: root.searchSections
            }
            Item { width: 1; height: 10 }
          }

          // ---- Library.
          Column {
            visible: root.page === null && root.tab === "library"
            width: parent.width

            Note {
              visible: !root.player.loggedIn
              bottomPadding: 12
              text: "Log in to see your playlists, albums and artists."
            }
            Item {
              visible: !root.player.loggedIn
              width: parent.width
              height: 32 + 24

              Pill {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Log in"
                icon: "account"
                primary: true
                onClicked: root.setTab("settings")
              }
            }
            Note {
              visible: root.player.loggedIn && (root.libraryLoading || root.libraryError !== "")
              text: root.libraryLoading ? "Loading…" : root.libraryError
            }
            Item { width: 1; height: 10 }
            Sections {
              x: 8
              width: parent.width - 16
              visible: root.player.loggedIn
              sections: root.librarySections
            }
            Item { width: 1; height: 10 }
          }

          // ---- Home.
          Column {
            visible: root.page === null && root.tab === "home"
            width: parent.width

            Note {
              visible: root.homeLoading || root.homeError !== ""
              text: root.homeLoading ? "Loading…" : root.homeError
            }
            Item { width: 1; height: 10 }
            Sections {
              x: 8
              width: parent.width - 16
              sections: root.homeSections
            }
            Item { width: 1; height: 10 }
          }

          // ---- Settings: the YouTube Music account.
          Column {
            visible: root.page === null && root.tab === "settings"
            x: 18
            width: parent.width - 36
            topPadding: 18
            bottomPadding: 20
            spacing: 10

            // ---- Sleep timer.
            Item {
              width: parent.width
              height: sleepHeader.implicitHeight

              SectionHeader { id: sleepHeader; text: "Sleep timer" }
              Mono {
                anchors.right: parent.right
                anchors.baseline: sleepHeader.baseline
                text: !root.player.sleep ? "" : (root.player.sleep.mode === "end" ? "Stops after this song" : "Pauses in " + root.sleepLabel)
                color: root.accent
              }
            }
            Flow {
              width: parent.width
              spacing: 6

              Repeater {
                model: root.sleepOptions
                delegate: Rectangle {
                  id: sleepOption
                  required property var modelData
                  readonly property bool active: root.sleepSelected(modelData.value)
                  width: sleepOptionLabel.implicitWidth + 24
                  height: 32
                  radius: 16
                  color: active ? root.accent : root.white(0.04)
                  border.width: 1
                  border.color: active ? root.accent : (sleepOptionArea.containsMouse ? root.white(0.3) : root.white(0.1))

                  Label {
                    id: sleepOptionLabel
                    anchors.centerIn: parent
                    text: sleepOption.modelData.label
                    font.pixelSize: 12
                    weight: Font.Medium
                    color: sleepOption.active ? "#111111" : root.white(0.8)
                  }
                  MouseArea {
                    id: sleepOptionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.action("sleep", [sleepOption.modelData.value])
                  }
                }
              }
            }

            // ---- Equalizer.
            Item { width: 1; height: 10 }
            SectionHeader { text: "Equalizer" }
            Grid {
              id: eqGrid
              width: parent.width
              columns: 3
              spacing: 6

              Repeater {
                model: root.eqPresets
                delegate: Rectangle {
                  id: preset
                  required property var modelData
                  readonly property bool active: root.player.eq === modelData.value
                  width: (eqGrid.width - eqGrid.spacing * 2) / 3
                  height: 10 + 24 + 8 + presetLabel.implicitHeight + 10
                  radius: 12
                  color: active ? root.white(0.1) : root.white(0.03)
                  border.width: 1
                  border.color: active ? root.accent : (presetArea.containsMouse ? root.white(0.3) : root.white(0.08))

                  Row {
                    id: presetBars
                    x: 10
                    y: 10
                    width: parent.width - 20
                    height: 24
                    spacing: 3

                    Repeater {
                      model: preset.modelData.gains
                      delegate: Rectangle {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: (presetBars.width - presetBars.spacing * 4) / 5
                        height: presetBars.height * (30 + modelData * 10) / 100
                        radius: 2
                        color: preset.active ? root.accent : root.white(0.35)
                      }
                    }
                  }
                  Label {
                    id: presetLabel
                    x: 10
                    anchors.top: presetBars.bottom
                    anchors.topMargin: 8
                    text: preset.modelData.label
                    font.pixelSize: 12
                    weight: Font.Medium
                    color: preset.active ? "#ffffff" : root.white(0.75)
                  }
                  MouseArea {
                    id: presetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.action("eq", [preset.modelData.value])
                  }
                }
              }
            }

            // ---- Volume boost.
            Item { width: 1; height: 10 }
            SectionHeader { text: "Volume" }
            Rectangle {
              width: parent.width
              height: boostText.implicitHeight + 20
              radius: 12
              color: boostArea.containsMouse ? root.white(0.07) : root.white(0.04)
              border.width: 1
              border.color: root.white(0.08)

              Column {
                id: boostText
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24 - 36 - 12
                spacing: 2

                Label { text: "Volume boost"; weight: Font.Medium }
                Label {
                  width: parent.width
                  text: "Allow up to 150%. May distort loud tracks."
                  font.pixelSize: 12
                  color: root.white(0.45)
                }
              }
              Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 20
                radius: 10
                color: root.player.boost ? root.accent : root.white(0.15)

                Rectangle {
                  x: root.player.boost ? 18 : 2
                  y: 2
                  width: 16
                  height: 16
                  radius: 8
                  color: "#ffffff"

                  Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
              }
              MouseArea {
                id: boostArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.action("boost")
              }
            }

            // ---- Interface: the same player full-screen in a terminal (bin/ytm-tui).
            Item { width: 1; height: 10 }
            SectionHeader { text: "Interface" }
            Rectangle {
              width: parent.width
              height: 52
              radius: 12
              color: tuiArea.containsMouse ? root.white(0.08) : root.white(0.04)
              border.width: 1
              border.color: root.white(0.08)

              Rectangle {
                id: tuiBadge
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.4)
                border.width: 1
                border.color: root.white(0.1)

                Label {
                  anchors.centerIn: parent
                  text: ">_"
                  font.family: root.monoFont
                  font.pixelSize: 12
                  color: root.accent
                }
              }
              Column {
                anchors.left: tuiBadge.right
                anchors.leftMargin: 12
                anchors.right: tuiChevron.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Label { text: "Open in TUI"; weight: Font.Medium }
                Label {
                  text: "Keyboard-driven terminal view"
                  font.pixelSize: 12
                  color: root.white(0.45)
                }
              }
              Icon {
                id: tuiChevron
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron"
                size: 14
                color: root.white(0.4)
              }
              MouseArea {
                id: tuiArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openTui()
              }
            }

            // ---- Memory: the service and mpv (the popup itself lives in the shell).
            Item { width: 1; height: 10 }
            SectionHeader { text: "Memory" }
            Rectangle {
              width: parent.width
              height: 62
              radius: 12
              color: root.white(0.04)
              border.width: 1
              border.color: root.white(0.08)

              Row {
                anchors.fill: parent
                anchors.margins: 12

                Repeater {
                  model: [
                    { label: "Player service", value: root.stats ? root.stats.service : null },
                    { label: "mpv", value: root.stats ? root.stats.mpv : null },
                    { label: "Total", value: root.stats ? root.stats.total : null }
                  ]
                  delegate: Column {
                    required property var modelData
                    required property int index
                    width: (parent.width) / 3
                    spacing: 3

                    Mono {
                      text: modelData.value === null ? "—"
                        : (modelData.value > 0 ? Math.round(modelData.value) + " MB" : "off")
                      font.pixelSize: 15
                      color: index === 2 ? root.accent : root.ink
                    }
                    Label {
                      text: modelData.label
                      font.pixelSize: 11
                      color: root.white(0.45)
                    }
                  }
                }
              }
              Tip {
                visible: memoryHover.hovered
                text: "Resident memory. mpv starts with the first song and holds the audio buffers; the popup runs inside the Omarchy shell."
              }
              HoverHandler { id: memoryHover }
            }

            // ---- The YouTube Music account.
            Item { width: 1; height: 10 }
            SectionHeader { text: "Account" }

            // Logged in.
            Item {
              visible: root.account.loggedIn
              width: parent.width
              height: 44

              Art {
                id: accountPhoto
                width: 44
                height: 44
                radius: 22
                source: root.account.photo || ""
                seed: root.account.name || ""
              }
              Column {
                anchors.left: accountPhoto.right
                anchors.leftMargin: 12
                anchors.right: logoutButton.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Label {
                  width: parent.width
                  text: root.account.name || "Logged in"
                  weight: Font.Medium
                }
                Label {
                  width: parent.width
                  visible: text !== ""
                  text: root.account.handle || ""
                  font.pixelSize: 12
                  color: root.white(0.45)
                }
              }
              Pill {
                id: logoutButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Log out"
                icon: "logout"
                onClicked: root.logout()
              }
            }

            // Not logged in: sign in to Google in a browser window, or paste
            // request headers from the browser.
            Label {
              visible: !root.account.loggedIn
              width: parent.width
              wrapMode: Text.Wrap
              elide: Text.ElideNone
              lineHeight: 1.2
              font.pixelSize: 12
              color: root.white(0.7)
              text: root.signingIn
                ? "Finish signing in in the window that opened. It closes by itself once you're in."
                : "Log in to like songs and see Saved and a personal For you. Search and playback work without it."
            }
            Row {
              visible: !root.account.loggedIn
              spacing: 8
              Pill {
                text: root.signingIn ? "Waiting for Google…" : "Sign in with Google"
                icon: "account"
                primary: true
                onClicked: if (!root.signingIn) root.signin()
              }
              Pill {
                text: root.showHeaderLogin ? "Hide headers" : "Paste headers"
                onClicked: root.showHeaderLogin = !root.showHeaderLogin
              }
            }
            Label {
              visible: !root.account.loggedIn && root.showHeaderLogin
              width: parent.width
              wrapMode: Text.Wrap
              elide: Text.ElideNone
              lineHeight: 1.2
              font.pixelSize: 12
              color: root.white(0.7)
              text: "1. Open music.youtube.com in your browser, signed in.\n"
                + "2. Open the developer tools (F12) → Network, and reload the page.\n"
                + "3. Find a POST request to “browse”, right-click → Copy → Copy request headers.\n"
                + "4. Paste them below and press Log in."
            }
            Rectangle {
              visible: !root.account.loggedIn && root.showHeaderLogin
              width: parent.width
              height: 110
              radius: 12
              color: root.white(0.06)
              border.width: 1
              border.color: headersEdit.activeFocus ? root.white(0.18) : root.white(0.08)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: headersEdit.forceActiveFocus()
              }
              Flickable {
                id: headersScroll
                anchors.fill: parent
                anchors.margins: 10
                contentWidth: width
                contentHeight: headersEdit.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                  id: headersEdit
                  width: headersScroll.width
                  wrapMode: TextEdit.WrapAnywhere
                  selectByMouse: true
                  textFormat: TextEdit.PlainText
                  color: "#ffffff"
                  selectionColor: root.white(0.25)
                  font.family: root.monoFont
                  font.pixelSize: 11
                  Keys.onEscapePressed: function(event) {
                    root.close()
                    event.accepted = true
                  }
                }
              }
              Label {
                anchors.fill: headersScroll
                visible: headersEdit.text === ""
                text: "Paste request headers here"
                color: root.white(0.38)
              }
            }
            Pill {
              visible: !root.account.loggedIn && root.showHeaderLogin
              text: root.loginBusy ? "Checking…" : "Log in"
              icon: "account"
              primary: true
              onClicked: root.login()
            }
            Label {
              visible: !root.account.loggedIn && root.loginError !== ""
              width: parent.width
              wrapMode: Text.Wrap
              elide: Text.ElideNone
              text: root.loginError
              font.pixelSize: 12
              color: root.accent
            }
            Label {
              visible: !root.account.loggedIn
              width: parent.width
              wrapMode: Text.Wrap
              elide: Text.ElideNone
              font.pixelSize: 11
              color: root.white(0.4)
              text: "Your login cookie is saved only on this computer, in ~/.config/ytm-bar, readable by you alone. Signing out of Google in the sign-in window ends it."
            }
          }
        }
      }
    }
  }
}
