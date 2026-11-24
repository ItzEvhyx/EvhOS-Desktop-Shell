import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: root

    readonly property bool wantsReminder: NachtCalendar.screenName !== ""
        && NachtCalendar.shown !== null && !NachtCalendar.blocked
    property var meeting: null
    property bool meetingExpanded: false
    readonly property var event: meeting ? meeting.event : null
    readonly property bool twentyMinuteReminder: meeting !== null && meeting.stage === 1
    readonly property bool canJoinEarly: meeting !== null && meeting.stage === 2 && !!meeting.event.joinUrl
    readonly property bool started: meeting !== null && meeting.stage === 3
    readonly property bool expanded: !started && meetingExpanded
    readonly property bool attached: NachtCalendar.canAttach
    readonly property real anchorY: attached ? Math.max(0, Math.round(NachtCalendar.bar.notchBottom - 1)) : 0
    // Reserve the slide's travel inside the layer. The input region stays on the card.
    readonly property int anchorHeadroom: NachtCalendar.hasTopBar
        ? Math.ceil(NachtCalendar.bar.notchBottomLimit) : 0
    readonly property real centerX: attached
        ? Math.max(0, Math.min(width, NachtCalendar.bar.notchCenterX))
        : width / 2
    readonly property real availableWidth: attached
        ? Math.min(NachtCalendar.bar.width, 2 * Math.min(centerX, width - centerX))
        : width
    readonly property string typeface: "Noto Sans"
    property string counter: "00:00"
    property real entranceProgress: 0
    readonly property int retractDuration: 260
    readonly property int neededHeight: Math.max(1, Math.ceil(card.targetSize.height))
    property int surfaceHeight: 1

    onNeededHeightChanged: {
        settleHeight.stop();
        if (!visible || entranceProgress < 1 || neededHeight >= surfaceHeight) {
            surfaceHeight = neededHeight;
        } else {
            settleHeight.restart();
        }
    }

    screen: Quickshell.screens.find(candidate => candidate.name === NachtCalendar.screenName) || null
    visible: NachtCalendar.screenName !== "" && meeting !== null && !NachtCalendar.blocked
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    WlrLayershell.namespace: "evhos-nacht-calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true }
    implicitHeight: surfaceHeight + anchorHeadroom
    color: "transparent"
    mask: Region { item: root.wantsReminder ? card : null }
    onVisibleChanged: {
        settleHeight.stop();
        surfaceHeight = neededHeight;
        if (!visible) NachtCalendar.hover(false);
    }

    Connections {
        target: NachtCalendar
        function onShownChanged() { Qt.callLater(root.syncReminder); }
        function onExpandedChanged() { Qt.callLater(root.syncReminder); }
        function onWallNowChanged() { Qt.callLater(root.syncReminder); }
        function onScreenNameChanged() { Qt.callLater(root.syncReminder); }
        function onBlockedChanged() { root.syncReminder(); }
    }
    Component.onCompleted: Qt.callLater(syncReminder)

    function syncReminder() {
        if (NachtCalendar.blocked || NachtCalendar.screenName === "") {
            reveal.stop();
            entranceProgress = 0;
            meeting = null;
            return;
        }

        if (wantsReminder) {
            const opening = meeting === null || (reveal.running && reveal.to === 0);
            meeting = NachtCalendar.shown;
            meetingExpanded = NachtCalendar.expanded;
            counter = NachtCalendar.countdown(meeting.event.startMs);
            if (opening) animateReveal(1);
        } else if (meeting !== null && (!reveal.running || reveal.to !== 0)) {
            // Retain the rendered state while the card folds back up.
            settleHeight.stop();
            NachtCalendar.hover(false);
            animateReveal(0);
        }
    }

    function animateReveal(destination) {
        reveal.stop();
        if (entranceProgress === destination) {
            if (destination === 0) meeting = null;
            return;
        }
        reveal.from = entranceProgress;
        reveal.to = destination;
        reveal.duration = Math.max(1, Math.round(280 * Math.abs(destination - entranceProgress)));
        reveal.start();
    }

    // Shrink the Wayland surface once the card has finished scaling down.
    Timer {
        id: settleHeight
        interval: root.retractDuration + 24
        onTriggered: root.surfaceHeight = root.neededHeight
    }

    NumberAnimation {
        id: reveal
        target: root
        property: "entranceProgress"
        easing.type: Easing.InOutCubic
        onFinished: {
            if (to === 0) root.meeting = null;
            else root.surfaceHeight = root.neededHeight;
        }
    }

    Binding {
        target: NachtCalendar
        property: "overlayWidth"
        value: root.visible && card.outlineVisible ? card.width : 0
    }

    function scale(pixels) { return Math.round(Scaler.s(pixels)); }

    Item {
        id: card
        y: root.anchorY
        x: root.centerX - width / 2
        width: Math.max(1, Math.min(root.availableWidth, fullSize.width))
        height: fullHeight * root.entranceProgress
        clip: true

        readonly property real verticalInset: root.scale(7)
        readonly property real compactHeight: compact.implicitHeight + 2 * verticalInset
        readonly property real detailsHeight: details.implicitHeight + 2 * verticalInset
        readonly property size targetSize: Qt.size(preferredWidth,
            root.started ? startedRow.implicitHeight + 2 * verticalInset
                : root.expanded ? detailsHeight : compactHeight)
        property size fullSize: targetSize
        readonly property real fullHeight: fullSize.height
        readonly property real expansion: Math.max(0, Math.min(1,
            (fullHeight - compactHeight) / Math.max(1, detailsHeight - compactHeight)))
        readonly property real preferredWidth: {
            if (root.expanded) return root.scale(640);
            const content = root.started ? startedRow.implicitWidth : compact.implicitWidth;
            return Math.min(root.scale(510), content + 2 * inset + root.scale(8));
        }
        readonly property real shoulderWidth: root.scale(21)
        readonly property real shoulderHeight: Math.min(root.scale(14), height / 2)
        readonly property real radius: Math.min(root.scale(24), Math.max(0, height - shoulderHeight - root.scale(3)))
        readonly property real inset: root.scale(33)
        readonly property real edge: root.scale(1)
        readonly property bool outlineVisible: height > 2 * edge
        Behavior on fullSize {
            enabled: root.entranceProgress === 1
            PropertyAnimation {
                duration: root.expanded ? 190 : root.retractDuration
                easing.type: root.expanded ? Easing.OutCubic : Easing.InOutCubic
            }
        }

        Shape {
            anchors.fill: parent
            visible: card.outlineVisible
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Qt.tint(ThemeBackend.base, Qt.rgba(0, 0, 0, 0.30))
                strokeColor: NachtCalendar.accent
                strokeWidth: root.scale(2)
                capStyle: ShapePath.FlatCap
                joinStyle: ShapePath.RoundJoin
                startX: card.edge
                startY: 0

                PathQuad {
                    x: card.shoulderWidth; y: card.shoulderHeight
                    controlX: card.shoulderWidth; controlY: 0
                }
                PathLine { x: card.shoulderWidth; y: card.height - card.radius }
                PathQuad {
                    x: card.shoulderWidth + card.radius; y: card.height - card.edge
                    controlX: card.shoulderWidth; controlY: card.height - card.edge
                }
                PathLine { x: card.width - card.shoulderWidth - card.radius; y: card.height - card.edge }
                PathQuad {
                    x: card.width - card.shoulderWidth; y: card.height - card.radius
                    controlX: card.width - card.shoulderWidth; controlY: card.height - card.edge
                }
                PathLine { x: card.width - card.shoulderWidth; y: card.shoulderHeight }
                PathQuad {
                    x: card.width - card.edge; y: 0
                    controlX: card.width - card.shoulderWidth; controlY: 0
                }
            }
        }

        HoverHandler {
            enabled: root.wantsReminder
            onHoveredChanged: if (root.wantsReminder) NachtCalendar.hover(hovered)
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.wantsReminder && !root.started && !root.expanded
            cursorShape: Qt.PointingHandCursor
            onClicked: NachtCalendar.expand()
            Accessible.role: Accessible.Button
            Accessible.name: root.event ? "Meeting ahead: " + root.event.title : "Meeting ahead"
            Accessible.onPressAction: NachtCalendar.expand()
        }

        Item {
            id: contentViewport
            anchors.top: parent.top
            width: parent.width
            height: Math.max(0, card.height - (root.entranceProgress < 1 ? root.scale(8) : 0))
            clip: true
        }

        RowLayout {
            id: compact
            parent: contentViewport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.inset
            anchors.rightMargin: card.inset
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: (card.compactHeight - parent.height) / 2
            spacing: root.scale(19)
            opacity: 1 - Math.min(1, card.expansion / 0.3)
            visible: root.event !== null && !root.started && !root.twentyMinuteReminder && opacity > 0

            Text {
                text: "Meeting ahead:"
                color: ThemeBackend.text
                font.family: root.typeface
                font.pixelSize: root.scale(15)
            }
            Text {
                font.family: root.typeface
                textFormat: Text.PlainText
                color: ThemeBackend.text
                Layout.fillWidth: true
                Layout.preferredWidth: Math.min(implicitWidth, root.scale(250))
                Layout.minimumWidth: 0
                text: root.event ? root.event.title : ""
                font.pixelSize: root.scale(17)
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Text {
                font.family: root.typeface
                textFormat: Text.PlainText
                font.pixelSize: root.scale(15)
                text: root.counter
                color: NachtCalendar.accent
                font.features: ({ tnum: 1 })
                font.weight: Font.DemiBold
            }
        }

        RowLayout {
            id: details
            parent: contentViewport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.inset
            anchors.rightMargin: card.inset
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: (card.detailsHeight - parent.height) / 2
            spacing: root.scale(18)
            opacity: Math.max(0, Math.min(1, (card.expansion - 0.32) / 0.55))
            visible: root.event !== null && !root.started && opacity > 0
            enabled: root.wantsReminder && root.expanded && opacity >= 0.8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.scale(7)

                Text {
                    font.family: root.typeface
                    textFormat: Text.PlainText
                    color: ThemeBackend.text
                    Layout.fillWidth: true
                    text: root.event ? root.event.title : ""
                    font.pixelSize: root.scale(24)
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    font.family: root.typeface
                    textFormat: Text.PlainText
                    font.pixelSize: root.scale(15)
                    Layout.fillWidth: true
                    text: NachtCalendar.actionError || (root.event ? NachtCalendar.timeRange(root.event) : "")
                    color: NachtCalendar.actionError ? ThemeBackend.red : ThemeBackend.subtext0
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                Layout.fillWidth: false
                spacing: root.scale(8)

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: root.twentyMinuteReminder ? Text.AlignRight : Text.AlignHCenter
                    font.family: root.typeface
                    font.pixelSize: root.scale(15)
                    font.features: ({ tnum: 1 })
                    font.weight: Font.DemiBold
                    color: NachtCalendar.accent
                    text: "Starting in: " + root.counter
                }
                RowLayout {
                    Layout.alignment: root.twentyMinuteReminder ? Qt.AlignRight : Qt.AlignHCenter
                    spacing: root.scale(9)

                    NachtButton {
                        primary: true
                        leftPadding: Scaler.s(root.twentyMinuteReminder ? 19 : 10)
                        rightPadding: leftPadding
                        visible: root.canJoinEarly || (root.event !== null && !!root.event.eventUrl)
                        enabled: !NachtCalendar.opening
                        opacity: NachtCalendar.opening ? 0.48 : 1
                        text: root.canJoinEarly ? "Join early" : "Open event"
                        font.family: root.typeface
                        onClicked: NachtCalendar.activate(root.event, !root.canJoinEarly)
                    }
                    NachtButton {
                        leftPadding: Scaler.s(root.twentyMinuteReminder ? 19 : 10)
                        rightPadding: leftPadding
                        text: "Dismiss"
                        opacity: 1
                        font.family: root.typeface
                        onClicked: NachtCalendar.acknowledge()
                    }
                }
            }
        }

        RowLayout {
            id: startedRow
            parent: contentViewport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.inset
            anchors.rightMargin: card.inset
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: (card.fullHeight - parent.height) / 2
            spacing: root.scale(19)
            visible: root.event !== null && root.started

            Text {
                font.family: root.typeface
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: NachtCalendar.actionError || (root.event && root.event.isMeeting === false
                    ? "Event has started" : "Meeting has started")
                color: NachtCalendar.actionError ? ThemeBackend.red : ThemeBackend.text
                font.pixelSize: root.scale(17)
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            NachtButton {
                primary: true
                visible: root.event !== null && !!(root.event.joinUrl || root.event.eventUrl)
                enabled: root.wantsReminder && !NachtCalendar.opening
                opacity: NachtCalendar.opening ? 0.48 : 1
                text: root.event && root.event.joinUrl ? "Join meeting" : "Open event"
                font.family: root.typeface
                onClicked: NachtCalendar.activate(root.event)
            }
        }
    }
}
