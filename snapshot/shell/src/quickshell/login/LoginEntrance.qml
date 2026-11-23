import QtQuick
import Quickshell

Scope {
    id: entrance

    property bool requested: Quickshell.env("EVHOS_LOGIN_ENTRANCE") === "1"
    property bool settingsReady: false
    property bool wallpaperEnabled: true
    property bool dockEnabled: true
    property var screens: Quickshell.screens

    readonly property bool active: requested && !session.finished
    readonly property bool sliding: slide.running
    readonly property real progress: active ? amount : 1
    property real amount: 0
    property var wallpaperScreens: []
    property var barScreens: []
    property var dockScreens: []
    readonly property bool ready: active && settingsReady && screens.length > 0
        && screens.every(screen => barScreens.includes(screen.name)
            && (!wallpaperEnabled || wallpaperScreens.includes(screen.name))
            && (!dockEnabled || dockScreens.includes(screen.name)))

    PersistentProperties {
        id: session
        reloadableId: "evhos-login-entrance"
        property bool finished: false
    }

    function reportReady(surface: string, screenName: string): void {
        if (!active || !screenName || entrance[surface].includes(screenName)) return;
        entrance[surface] = entrance[surface].concat(screenName);
    }

    onReadyChanged: if (ready && !slide.running) slide.start()

    // Release the desktop if a display or wallpaper cannot deliver a frame.
    Timer {
        interval: 1500
        running: entrance.active && !slide.running
        onTriggered: slide.start()
    }

    NumberAnimation {
        id: slide
        target: entrance
        property: "amount"
        from: 0
        to: 1
        duration: 320
        easing.type: Easing.OutCubic
        onFinished: session.finished = true
    }
}
