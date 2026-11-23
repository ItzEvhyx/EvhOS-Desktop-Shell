-- Personal Hyprland settings kept independently of the desktop shell.

-- Screenshot to the clipboard.
hl.unbind("SUPER + SHIFT + S")
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))

-- Keep tiled windows flush with the screen edges while retaining visible focus.
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })
hl.window_rule({
    name = "flush-tiled-windows",
    match = { float = false },
    rounding = 0,
    border_size = 0,
})
hl.config({ decoration = { dim_inactive = true, dim_strength = 0.12 } })

-- Serpantinum controls.
hl.unbind("SUPER + SUPER_L")
hl.bind(
    "SUPER + SUPER_L",
    hl.dsp.exec_cmd("pgrep -f '[s]erpantinumd' >/dev/null && serpantinum msg toggle launcher"),
    { release = true }
)
hl.unbind("SUPER + N")
hl.bind("SUPER + N", hl.dsp.exec_cmd("pgrep -f '[s]erpantinumd' >/dev/null && serpantinum msg toggle system"))
hl.unbind("SUPER + I")
hl.bind("SUPER + I", hl.dsp.exec_cmd("serpantinum settings"))

-- Restore the Serpantinum controls that intentionally replace base-profile
-- bindings. These use the running shell's IPC endpoint rather than another
-- desktop-shell integration.
hl.unbind("SUPER + S")
hl.bind(
    "SUPER + S",
    hl.dsp.exec_cmd('quickshell -p /home/yhvhan/.local/share/serpantinum/src/quickshell/Shell.qml ipc call main handleCommand toggle wallpaper ""')
)
hl.unbind("SUPER + W")
hl.bind(
    "SUPER + W",
    hl.dsp.exec_cmd("quickshell -p /home/yhvhan/.local/share/serpantinum/src/quickshell/Shell.qml ipc call workspaceOverview toggle")
)

-- Navigate workspaces directly with Super+Left/Right. The base profile maps
-- these keys to tiled-window focus, which supersedes this desktop behavior.
hl.unbind("SUPER + left")
hl.unbind("SUPER + right")
hl.bind("SUPER + left", hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + right", hl.dsp.focus({ workspace = "+1" }), { repeating = true })

-- Keep the configured file manager on its dedicated shortcut.
hl.unbind("SUPER + E")
hl.bind("SUPER + E", hl.dsp.exec_cmd("ski"))

-- Use Serpantinum's brightness OSD when its daemon is active.
hl.unbind("XF86MonBrightnessDown")
hl.unbind("XF86MonBrightnessUp")
hl.bind(
    "XF86MonBrightnessDown",
    hl.dsp.exec_cmd("pgrep -f '[s]erpantinumd' >/dev/null && serpantinum brightness lower"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86MonBrightnessUp",
    hl.dsp.exec_cmd("pgrep -f '[s]erpantinumd' >/dev/null && serpantinum brightness raise"),
    { locked = true, repeating = true }
)

-- Blur Serpantinum surfaces without affecting the rest of the desktop.
hl.layer_rule({ name = "serp-glass-bar", match = { namespace = "^qs-custom-bar$" }, blur = true, ignore_alpha = 0.05 })
hl.layer_rule({ name = "serp-glass-dock", match = { namespace = "^qs-dock$" }, blur = true, ignore_alpha = 0.05 })
hl.layer_rule({ name = "serp-glass-widgets", match = { namespace = "^qs-master$" }, blur = true, ignore_alpha = 0.05 })

-- The notification center moves inside its surface.
hl.layer_rule({
    name = "serp-notification-center",
    match = { namespace = "^qs-master-system-panel$" },
    blur = true,
    ignore_alpha = 0.05,
    no_anim = true,
})
hl.layer_rule({ name = "serp-glass-process-desk", match = { namespace = "^evhos-process-desk$" }, blur = true, ignore_alpha = 0.05 })
hl.layer_rule({ name = "serp-glass-tray-menu", match = { namespace = "^traymenu$" }, blur = true, ignore_alpha = 0.05 })
hl.layer_rule({ name = "serp-glass-osd", match = { namespace = "^osd$" }, blur = true, ignore_alpha = 0.05 })
hl.layer_rule({ name = "serp-glass-launcher", match = { namespace = "^qs-applauncher$" }, blur = true, ignore_alpha = 0.05 })

-- Preserve the dedicated floating treatment for HyprMod.
hl.window_rule({
    name = "hyprmod-glass",
    match = { class = "^io\\.github\\.bluemancz\\.hyprmod$" },
    float = true,
    size = "1200 750",
    center = true,
    rounding = 20,
    opacity = "1.0 override",
})

-- Alternative number-row shortcuts retained from the original setup.
hl.bind("ALT + Q", hl.dsp.send_shortcut({ mods = "", key = "1" }))
hl.bind("ALT + W", hl.dsp.send_shortcut({ mods = "", key = "2" }))
hl.bind("SHIFT + Q", hl.dsp.send_shortcut({ mods = "SHIFT", key = "1" }))
hl.bind("SHIFT + W", hl.dsp.send_shortcut({ mods = "SHIFT", key = "2" }))

-- Let the Serpantinum launcher discover Flatpak application entries and icons.
hl.env("XDG_DATA_DIRS", os.getenv("HOME") .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share")
