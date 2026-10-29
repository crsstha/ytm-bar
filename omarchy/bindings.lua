-- >>> ytm-bar >>>
-- YouTube Music bar widget: open/close the player
o.bind("SUPER + ALT + M", "YouTube Music player", "omarchy-shell crsstha.ytmusic toggle")
-- Keep the YouTube Music window on a hidden workspace; the bar is the UI.
-- Right-click the widget (ytm-bar window) to show or hide it.
o.window("^com\\.github\\.th-ch\\.youtube-music$", { workspace = "special:music silent" })
-- Blur behind the see-through player card. The popup layer covers the whole
-- screen, so ignore_alpha limits the blur to the card itself.
hl.layer_rule({ match = { namespace = "omarchy-keyboard-panel" }, blur = true, ignore_alpha = 0.3 })
-- <<< ytm-bar <<<
