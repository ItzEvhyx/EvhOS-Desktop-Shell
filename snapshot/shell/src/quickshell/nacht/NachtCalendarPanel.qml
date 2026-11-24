import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../"

Rectangle {
    id: root
    signal back()
    color: Qt.tint(ThemeBackend.base, Qt.rgba(0, 0, 0, 0.25))
    radius: Scaler.s(20)
    border.color: Qt.alpha(ThemeBackend.text, 0.18)

    onVisibleChanged: {
        if (visible) {
            NachtCalendar.refreshDisplay();
            if (!NachtCalendar.busy) NachtCalendar.run("status");
        }
    }

    function s(px) { return Math.round(Scaler.s(px)); }

    FileDialog {
        id: clientDialog
        title: "Choose your Google Desktop OAuth client JSON"
        nameFilters: ["Google OAuth client JSON (*.json)"]
        onAccepted: NachtCalendar.importClient(selectedFile)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.s(16)
        spacing: root.s(10)

        RowLayout {
            Layout.fillWidth: true
            ToolButton {
                id: backButton
                implicitWidth: root.s(26)
                implicitHeight: root.s(30)
                Accessible.name: "Back"
                onClicked: root.back()

                contentItem: Text {
                    text: "‹"
                    font.family: "Noto Sans"
                    font.pixelSize: root.s(29)
                    color: backButton.hovered ? NachtCalendar.accent : ThemeBackend.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Item {}
            }
            Text {
                Layout.fillWidth: true
                text: "Nacht Calendar"
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: root.s(16)
            }
        }

        Text {
            Layout.fillWidth: true
            text: {
                const state = NachtCalendar.status;
                if (NachtCalendar.operation === "connect") return "Finish Google sign-in in your browser.";
                if (NachtCalendar.busy && NachtCalendar.operation !== "sync") return "Checking Google Calendar…";
                if (NachtCalendar.message) return NachtCalendar.message;
                if (state === "connected" && NachtCalendar.lastSyncMs)
                    return "Last synced " + Qt.formatDateTime(new Date(NachtCalendar.lastSyncMs), "MMM d, h:mm AP");
                if (state === "needsClient") return "Choose a Google Desktop app OAuth client JSON to connect.";
                if (state === "reauthorize") return "Reconnect your account to resume Google Calendar sync.";
                if (state === "loading") return "Checking Google Calendar…";
                return "Connect your Google account to read your primary calendar.";
            }
            color: ThemeBackend.subtext0
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(12)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: root.s(5)
            NachtButton {
                text: "Choose OAuth file"
                visible: !NachtCalendar.authorized
                enabled: !NachtCalendar.busy
                onClicked: clientDialog.open()
            }
            NachtButton {
                text: NachtCalendar.authorized || NachtCalendar.status === "reauthorize" ? "Reconnect" : "Connect"
                primary: true
                visible: NachtCalendar.status !== "needsClient" && NachtCalendar.status !== "loading"
                enabled: !NachtCalendar.busy
                onClicked: NachtCalendar.run("connect")
            }
            NachtButton {
                text: "Disconnect"
                visible: NachtCalendar.authorized || NachtCalendar.status === "reauthorize"
                enabled: !NachtCalendar.busy
                onClicked: NachtCalendar.disconnect()
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.alpha(ThemeBackend.text, 0.12) }
        Text {
            text: "Upcoming"
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.weight: Font.DemiBold
            font.pixelSize: root.s(14)
        }
        Text {
            visible: NachtCalendar.upcoming.length === 0
            Layout.fillWidth: true
            text: NachtCalendar.authorized ? "No more events today." : "Events appear here after you connect."
            wrapMode: Text.WordWrap
            color: ThemeBackend.subtext0
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(12)
        }
        Text {
            visible: !!NachtCalendar.actionError
            Layout.fillWidth: true
            text: NachtCalendar.actionError
            wrapMode: Text.WordWrap
            color: ThemeBackend.red
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(12)
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: root.s(6)
            model: NachtCalendar.upcoming
            delegate: RowLayout {
                required property var modelData
                width: ListView.view.width
                spacing: root.s(6)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.s(2)
                    Text {
                        Layout.fillWidth: true
                        text: modelData.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: ThemeBackend.text
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(13)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: NachtCalendar.formatStart(modelData.startMs) +
                            (modelData.location ? " · " + modelData.location : "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: ThemeBackend.subtext0
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(11)
                    }
                }
                NachtButton {
                    readonly property bool canJoin: modelData.startMs <= NachtCalendar.wallNow && !!modelData.joinUrl
                    visible: canJoin || !!modelData.eventUrl
                    enabled: !NachtCalendar.opening
                    text: canJoin ? "Join meeting" : "Open event"
                    onClicked: NachtCalendar.activate(modelData, !canJoin)
                }
            }
        }
    }
}
