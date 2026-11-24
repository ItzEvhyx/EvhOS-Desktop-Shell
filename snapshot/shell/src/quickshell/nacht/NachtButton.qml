import QtQuick
import QtQuick.Controls
import "../"

Button {
    id: button
    property bool primary: false
    readonly property bool hoverActive: enabled && hovered
    hoverEnabled: true
    readonly property color accent: "#a68af6"
    leftPadding: Scaler.s(10)
    rightPadding: Scaler.s(10)
    topPadding: Scaler.s(5)
    bottomPadding: Scaler.s(5)
    font.family: ThemeBackend.fontFamily
    font.pixelSize: Scaler.s(13)
    font.weight: Font.DemiBold
    opacity: enabled ? 1 : 0.48
    contentItem: Text {
        text: button.text
        font: button.font
        color: button.primary ? "#191126" : ThemeBackend.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
    }
    background: Rectangle {
        radius: Scaler.s(8)
        color: button.primary ? Qt.lighter(button.accent, button.hoverActive ? 1.16 : 1)
                              : Qt.alpha(ThemeBackend.text, button.hoverActive ? 0.20 : 0.06)
        border.color: button.primary ? "transparent" : Qt.alpha(ThemeBackend.text, 0.35)

        Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }
}
