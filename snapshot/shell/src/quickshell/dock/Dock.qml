import QtQuick
import Quickshell

Variants {
    id: docks
    property var entrance: null
    model: Quickshell.screens

    delegate: Component {
        Scope {
            id: dockScope
            required property var modelData

            DockExclusionWindow {
                modelData: dockScope.modelData
                dockWindow: dockPanel
            }

            DockWindow {
                id: dockPanel
                modelData: dockScope.modelData
                entrance: docks.entrance
            }
        }
    }
}
