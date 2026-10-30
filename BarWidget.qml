import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "crsstha.ytmusic"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function action(name) {
    if (panelLoader.item && panelLoader.item.action) panelLoader.item.action(name)
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: panelLoader.item && panelLoader.item.label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  readonly property bool showWave: panelLoader.item ? panelLoader.item.showWave === true && !button.vertical : false
  readonly property bool playing: panelLoader.item ? panelLoader.item.playing === true : false

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : ""
    // With a song loaded, draw the wave + title (below) in place of the label.
    labelVisible: !root.showWave
    // The pill fits the title. It lives in the bar's right section (see
    // install.sh): there a width change only moves its own left edge, while in
    // the centred middle section it would re-centre the clock.
    fixedWidth: root.showWave ? waveRow.implicitWidth + 18 + scaledHorizontalMargin * 2 : -1

    // The design's pill: a soft glass capsule around the wave and title.
    Rectangle {
      visible: root.showWave
      anchors.centerIn: waveRow
      anchors.horizontalCenterOffset: 1
      width: waveRow.implicitWidth + 18
      height: Math.min(button.height - 4, waveTitle.implicitHeight + 8)
      radius: height / 2
      color: Qt.rgba(1, 1, 1, 0.07)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.08)
    }

    Row {
      id: waveRow
      visible: root.showWave
      anchors.centerIn: parent
      spacing: Style.spaceReal(8)

      Item {
        id: wave
        readonly property int bars: 4
        readonly property real barWidth: Math.max(2, Style.spaceReal(2))
        readonly property real gap: Math.max(1.5, Style.spaceReal(1.5))
        readonly property real maxHeight: Math.round(waveTitle.font.pixelSize * 0.9)
        readonly property real minHeight: Math.max(2, Math.round(maxHeight * 0.18))
        property real phase: 0

        width: bars * barWidth + (bars - 1) * gap
        height: maxHeight
        anchors.verticalCenter: parent.verticalCenter

        // Each bar is a sine offset from its neighbour, so the bars ripple like a wave.
        Repeater {
          model: wave.bars
          delegate: Rectangle {
            required property int index
            readonly property real level: root.playing
              ? 0.5 + 0.5 * Math.sin(wave.phase + index * 0.9) * (0.65 + 0.35 * Math.sin(wave.phase * 0.37 + index * 1.7))
              : 0
            x: index * (wave.barWidth + wave.gap)
            width: wave.barWidth
            height: wave.minHeight + (wave.maxHeight - wave.minHeight) * level
            anchors.verticalCenter: parent.verticalCenter
            radius: width / 2
            // Amber while playing, like the design; the plain bar colour when paused.
            color: root.playing && panelLoader.item ? panelLoader.item.accent : button.foreground

            Behavior on height {
              enabled: !root.playing
              NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
          }
        }

        Timer {
          interval: 50
          running: root.playing && root.visible
          repeat: true
          onTriggered: wave.phase += 0.35
        }
      }

      Text {
        id: waveTitle
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: panelLoader.item ? panelLoader.item.waveTitle : ""
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }
    // Dimmed unless something is playing (paused, or the player is stopped).
    dimmed: panelLoader.item ? panelLoader.item.dimmed === true : false
    tooltipText: panelLoader.item ? panelLoader.item.tooltip : ""

    onPressed: function(b) {
      if (!root.bar || !panelLoader.item) return
      if (b === Qt.RightButton) root.open()  // straight to the search box
      else if (b === Qt.MiddleButton) root.action("toggle")
      else root.togglePanel()
    }
    onWheelMoved: function(delta) {
      if (delta > 0) root.action("previous")
      else if (delta < 0) root.action("next")
    }
  }
}
