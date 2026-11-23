pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import ".."

Scope {
    id: recorder

    readonly property bool busy: session.phase !== "idle"
    readonly property int collapseDuration: 290
    readonly property string workerPath: Quickshell.shellDir + "/recording/evhos-record-screen.py"
    readonly property string indicatorMonitor: {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === session.monitor) return session.monitor;
        }
        return screens.length ? screens[0].name : "";
    }
    property int elapsedSeconds: 0
    readonly property string elapsedText: Math.floor(elapsedSeconds / 60) + ":" + String(elapsedSeconds % 60).padStart(2, "0")

    PersistentProperties {
        id: session
        reloadableId: "evhos-screen-recorder"
        property string monitor: ""
        property string phase: "idle"
        property real startedAt: 0
        property string pendingSave: ""
        property bool endedEarly: false
    }

    function notify(title: string, body: string): void {
        const escaped = body.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        Quickshell.execDetached(["notify-send", "-a", "EvhOS Recorder", "-i", "media-record", "--", title, escaped]);
    }

    function updateElapsed(): void {
        elapsedSeconds = session.startedAt ? Math.max(0, Math.floor((Date.now() - session.startedAt) / 1000)) : 0;
    }

    function toggleRecording(): void {
        if (busy) {
            stopRecording();
            return;
        }
        if (worker.running) return;
        const focused = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        const monitor = focused ? focused.name : (screens.length ? screens[0].name : "");
        if (!monitor) {
            notify("Recording Could Not Start", "No display is available to record.");
            return;
        }
        session.monitor = monitor;
        session.startedAt = 0;
        elapsedSeconds = 0;
        session.phase = "starting";
        worker.running = true;
    }

    function stopRecording(): void {
        if (!busy || session.phase === "saving") return;
        session.phase = "saving";
        if (worker.processId) worker.write("stop\n");
    }

    function receive(line: string): void {
        const event = JSON.parse(line);
        if (event.type === "recording") {
            if (session.phase === "starting") {
                session.startedAt = event.startedAt;
                session.phase = "recording";
            }
            return;
        }
        session.phase = "idle";
        if (event.type === "saved") {
            session.endedEarly = event.endedEarly;
            session.pendingSave = event.path;
        } else if (event.type === "error") {
            notify("Recording Failed", event.message);
        }
    }

    IpcHandler {
        target: "evhosRecorder"
        function toggle(): void { recorder.toggleRecording(); }
        function status(): string { return session.phase; }
        function version(): int { return 3; }
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() {
            if (recorder.busy && !worker.running) session.phase = "idle";
        }
    }

    Process {
        id: worker
        command: ["python3", recorder.workerPath, session.monitor]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => recorder.receive(line)
        }
        onStarted: if (session.phase === "saving") write("stop\n")
        onExited: {
            if (recorder.busy) {
                session.phase = "idle";
                recorder.notify("Recording Failed", "The recorder exited before it could finish saving.");
            }
        }
    }

    Timer {
        interval: 250
        repeat: true
        triggeredOnStart: true
        running: session.phase === "recording"
        onTriggered: recorder.updateElapsed()
    }

    Timer {
        interval: recorder.collapseDuration + 30
        running: session.pendingSave !== ""
        onTriggered: {
            const command = ["python3", recorder.workerPath, "--notify-saved", session.pendingSave];
            if (session.endedEarly) command.push("--ended-early");
            Quickshell.execDetached(command);
            session.pendingSave = "";
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: window
                required property var modelData
                screen: modelData

                readonly property bool expanded: recorder.busy && modelData.name === recorder.indicatorMonitor
                readonly property var bar: BarGeometry.bars[modelData.name]
                readonly property bool topBar: !!bar && bar.position === "top"
                readonly property var barStyle: Config.getSetting("bar.style", "modular")
                readonly property bool topNotch: barStyle === "solid" || !!(barStyle && (barStyle.solid || barStyle.mode === "solid"))
                readonly property int rowHeight: topBar ? Math.round(bar.height) : 40
                readonly property int rowInset: 2
                readonly property int pillHeight: rowHeight - 2 * rowInset
                readonly property int labelSize: Math.max(12, Math.round(rowHeight * 0.35))
                readonly property bool recording: session.phase === "recording"
                readonly property bool canStop: session.phase === "recording" || session.phase === "starting"
                property bool surfaceReady: false
                property real reveal: expanded && surfaceReady ? 1 : 0

                onExpandedChanged: surfaceReady = expanded && reveal > 0
                Behavior on reveal {
                    NumberAnimation {
                        duration: window.expanded ? 360 : recorder.collapseDuration
                        easing.type: Easing.InOutCubic
                    }
                }

                color: "transparent"
                visible: expanded || reveal > 0
                implicitWidth: Math.min(modelData.width - 16, Math.max(216, Math.round(rowHeight * 5.4)))
                implicitHeight: pillHeight + 8 + statusCard.height
                anchors { top: true; right: true }
                margins {
                    top: window.rowInset + (window.topBar ? (window.topNotch ? 0 : Math.round(window.bar.y)) : 6)
                    right: 8
                }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "evhos-screen-recorder"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region { item: window.reveal > 0 ? capsule : null }

                // Wait for the layer surface to draw before spending any of the reveal animation.
                Connections {
                    target: capsule.Window.window
                    enabled: window.expanded && !window.surfaceReady
                    function onFrameSwapped() { window.surfaceReady = true; }
                }
                Timer {
                    interval: 150
                    running: window.expanded && !window.surfaceReady
                    onTriggered: window.surfaceReady = true
                }

                Rectangle {
                    id: capsule
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (window.pillHeight - height) / 2
                    readonly property real seedSize: window.pillHeight * 0.44
                    width: seedSize + (parent.width - seedSize) * window.reveal
                    height: seedSize + (window.pillHeight - seedSize) * Math.min(1, window.reveal * 1.6)
                    radius: height / 2
                    opacity: Math.min(1, window.reveal * 3.5)
                    clip: true
                    antialiasing: true
                    color: Qt.alpha(ThemeBackend.base, 0.78)
                    border.width: 1
                    border.color: Qt.alpha(ThemeBackend.text, 0.18)

                    HoverHandler {
                        id: statusHover
                        enabled: window.recording && window.reveal >= 0.98
                        onHoveredChanged: if (!hovered) hoverDelay.elapsed = false
                    }
                    Timer {
                        id: hoverDelay
                        property bool elapsed: false
                        interval: 300
                        running: statusHover.hovered && statusHover.enabled
                        onRunningChanged: if (!statusHover.enabled) elapsed = false
                        onTriggered: elapsed = true
                    }

                    Item {
                        anchors.centerIn: parent
                        width: window.width
                        height: window.pillHeight
                        opacity: Math.max(0, (window.reveal - 0.66) / 0.34)

                        Rectangle {
                            id: light
                            width: Math.max(8, Math.round(window.rowHeight * 0.25))
                            height: width
                            radius: width / 2
                            anchors.left: parent.left
                            anchors.leftMargin: Math.max(13, Math.round(window.rowHeight * 0.4))
                            anchors.verticalCenter: parent.verticalCenter
                            color: window.recording ? "#ff5b68" : Qt.alpha(ThemeBackend.text, 0.45)
                            property bool dimmed: false
                            opacity: window.recording && dimmed ? 0.26 : 1
                            Behavior on opacity { NumberAnimation { duration: 140 } }

                            Timer {
                                interval: 600
                                repeat: true
                                running: window.visible && window.recording
                                onRunningChanged: if (!running) light.dimmed = false
                                onTriggered: light.dimmed = !light.dimmed
                            }
                        }

                        Text {
                            anchors.left: light.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: ThemeBackend.text
                            font.family: "monospace"
                            font.pixelSize: window.labelSize
                            font.weight: Font.DemiBold
                            text: window.recording ? recorder.elapsedText : (session.phase === "starting" ? "Starting…" : "Saving…")
                        }

                        Rectangle {
                            width: Math.max(70, Math.round(window.rowHeight * 1.95))
                            height: parent.height - 4
                            radius: height / 2
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.alpha(ThemeBackend.text, stopArea.pressed ? 0.23 : (stopArea.containsMouse ? 0.16 : 0.08))
                            opacity: window.canStop ? 1 : 0.42
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Stop screen recording"
                            Accessible.onPressAction: if (stopArea.enabled) recorder.stopRecording()

                            Row {
                                anchors.centerIn: parent
                                spacing: 7

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(8, Math.round(window.labelSize * 0.67))
                                    height: width
                                    radius: 1.5
                                    color: ThemeBackend.text
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Stop"
                                    color: ThemeBackend.text
                                    font.family: "monospace"
                                    font.pixelSize: window.labelSize
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                id: stopArea
                                anchors.fill: parent
                                enabled: window.canStop && window.reveal >= 0.8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: recorder.stopRecording()
                            }
                        }
                    }
                }

                Rectangle {
                    id: statusCard
                    anchors.horizontalCenter: capsule.horizontalCenter
                    width: Math.min(window.width, statusText.implicitWidth + 26)
                    height: Math.max(30, statusText.implicitHeight + 12)
                    y: window.pillHeight + 8 - (1 - opacity) * 4
                    opacity: statusHover.enabled && statusHover.hovered && hoverDelay.elapsed ? 1 : 0
                    visible: opacity > 0
                    radius: 10
                    color: Qt.alpha(ThemeBackend.base, 0.9)
                    border.width: 1
                    border.color: Qt.alpha(ThemeBackend.text, 0.16)
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    Text {
                        id: statusText
                        anchors.centerIn: parent
                        text: "Recording is active"
                        color: ThemeBackend.text
                        font.family: "monospace"
                        font.pixelSize: Math.max(11, window.labelSize - 1)
                    }
                }
            }
        }
    }
}
