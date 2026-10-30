-- >>> ytm-bar >>>
-- YouTube Music bar widget: open/close the player
o.bind("SUPER + ALT + M", "YouTube Music player", "omarchy-shell crsstha.ytmusic toggle")
-- Blur behind the see-through player card. The popup layer covers the whole
-- screen, so ignore_alpha limits the blur to the card itself.
hl.layer_rule({ match = { namespace = "omarchy-keyboard-panel" }, blur = true, ignore_alpha = 0.3 })
-- "Sign in with Google": a small floating window in the middle of the screen
-- (its class comes from the page it opens on, see SIGNIN_START in bin/ytm-bar).
o.window(".*ytm-bar%20sign-in.*", { float = true, center = true, size = { 480, 680 } })
-- <<< ytm-bar <<<
