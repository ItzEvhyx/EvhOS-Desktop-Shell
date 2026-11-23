#!/usr/bin/env python3
"""Keep the wide Serpantinum media panel centered after shell updates."""
from pathlib import Path
import sys

main_path = Path.home() / ".local/share/serpantinum/src/quickshell/Main.qml"
legacy_anchor = '''            // Align the music panel with the bar media control.
            let mediaAnchor = OsdController.mediaPanelAnchor;
            if ((bp === "top" || bp === "bottom") && mediaAnchor
                    && mediaAnchor.screen === masterWindow.screen) {
                let minX = Math.max(0, mediaAnchor.minX);
                let maxX = Math.min(scrW, mediaAnchor.maxX);
                if (maxX - minX < result.w) { minX = 0; maxX = scrW; }
                result.rx = Math.round(Math.max(minX, Math.min(maxX - result.w, mediaAnchor.centerX - result.w / 2)));
            }

'''
center_marker = "        // Keep the wide music panel centered with the weather/calendar container.\n"

try:
    original = main_path.read_text()
    updated = original.replace(legacy_anchor, "")
    updated = updated.replace(
        "        // Match the wide weather/calendar panel, centered beyond the topbar.\n",
        "        // Keep the wide music panel centered with the weather/calendar container.\n",
    )
    if center_marker not in updated or updated.count('if (name === "music")') != 1:
        raise ValueError("music panel layout changed; review centering")
    if updated != original:
        main_path.write_text(updated)
    sys.exit(10 if updated != original else 0)
except (OSError, ValueError) as exc:
    print(f"Serpantinum media centering: {exc}", file=sys.stderr)
    sys.exit(1)
