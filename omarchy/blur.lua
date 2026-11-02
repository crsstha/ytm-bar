-- Hyprland's blur, which Omarchy turns off by default and the card needs. App
-- windows stay unblurred, so only the card changes. install.sh adds this only
-- if blur was off; your own looknfeel.lua loads later and still wins.
hl.config({ decoration = { blur = { enabled = true, size = 12, passes = 3 } } })
o.window(".*", { no_blur = true })
