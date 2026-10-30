-- >>> ytm-bar >>>
-- YouTube Music bar widget: open/close the player
o.bind("SUPER + ALT + M", "YouTube Music player", "omarchy-shell crsstha.ytmusic toggle")
-- Blur behind the see-through player card (its layer is named "ytm-bar" in
-- Panel.qml, so other Omarchy panels aren't blurred). The popup layer covers
-- the whole screen, so ignore_alpha limits the blur to the card itself; no_anim
-- keeps it popping like the other panels.
hl.layer_rule({ match = { namespace = "^ytm-bar$" }, blur = true, ignore_alpha = 0.3, no_anim = true, animation = "none" })
-- "Sign in with Google": a small floating window in the middle of the screen
-- (its class comes from the page it opens on, see SIGNIN_START in bin/ytm-bar).
o.window(".*ytm-bar%20sign-in.*", { float = true, center = true, size = { 480, 680 } })
-- ytm-tui (Settings → Open in TUI): a floating window in the middle of the screen.
o.window("org.omarchy.ytm-tui", { float = true, center = true, size = { 900, 700 } })
-- <<< ytm-bar <<<
