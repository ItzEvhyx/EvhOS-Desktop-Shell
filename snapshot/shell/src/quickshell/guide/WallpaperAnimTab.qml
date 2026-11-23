import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as GuideScroll
import "../"
import "../reusables"

GuideTab {
    id: panel

    Flickable {
        GuideScroll.MouseWheelScroll {}
        anchors.fill: parent
        anchors.margins: panel.rootObj.s(8)
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: settingsColumn
            width: parent.width

            SettingsBlob {
                SettingsRow {
                    rootObj: panel.rootObj
                    settingId: "wallpaper_picker_style"
                    searchKeywords: "wallpaper animation rounded carousel card carousel"
                    icon: "󰸉"
                    title: I18n.t("guide.wallpaper_anim.style")
                    description: I18n.t("guide.wallpaper_anim.description")
                }

                GridLayout {
                    id: previews
                    Layout.fillWidth: true
                    Layout.leftMargin: panel.rootObj.s(14)
                    Layout.rightMargin: panel.rootObj.s(14)
                    Layout.bottomMargin: panel.rootObj.s(14)
                    columns: width >= panel.rootObj.s(520) ? 2 : 1
                    columnSpacing: panel.rootObj.s(12)
                    rowSpacing: columnSpacing

                    Repeater {
                        model: ["rounded", "card"]

                        delegate: AbstractButton {
                            id: styleButton
                            required property string modelData

                            readonly property bool selected: Config.dataReady
                                && Config.wallpaperCardCarousel === (modelData === "card")
                            readonly property real inset: panel.rootObj.s(6)
                            readonly property real tileWidth: (previews.width - (previews.columns - 1) * previews.columnSpacing)
                                / previews.columns

                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 0
                            Layout.preferredHeight: Math.max(0, tileWidth - 2 * inset) * 9 / 16
                                + panel.rootObj.s(42)

                            padding: inset
                            enabled: Config.dataReady
                            hoverEnabled: true
                            focusPolicy: Qt.StrongFocus
                            text: I18n.t("guide.wallpaper_anim." + modelData)

                            Accessible.role: Accessible.RadioButton
                            Accessible.name: text
                            Accessible.checkable: true
                            Accessible.checked: selected

                            onClicked: {
                                if (!selected) Config.setSetting("wallpaperPickerStyle", modelData);
                            }

                            background: Rectangle {
                                radius: panel.rootObj.s(13)
                                color: styleButton.selected
                                    ? Qt.alpha(ThemeBackend.mauve, styleButton.hovered ? 0.16 : 0.10)
                                    : Qt.alpha(ThemeBackend.text, styleButton.hovered ? 0.09 : 0.035)
                                border.width: styleButton.visualFocus ? 2 : 1
                                border.color: Qt.alpha(styleButton.selected || styleButton.visualFocus
                                    ? ThemeBackend.mauve : ThemeBackend.text,
                                    styleButton.selected || styleButton.visualFocus ? 0.80 : 0.12)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            contentItem: ColumnLayout {
                                spacing: 0

                                Image {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 0
                                    source: Qt.resolvedUrl("wallpaper-previews/" + styleButton.modelData + ".webp")
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: panel.rootObj.s(30)
                                    Layout.leftMargin: panel.rootObj.s(6)
                                    Layout.rightMargin: panel.rootObj.s(6)
                                    spacing: panel.rootObj.s(8)

                                    Text {
                                        Layout.fillWidth: true
                                        text: styleButton.text
                                        elide: Text.ElideRight
                                        color: ThemeBackend.text
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: panel.rootObj.s(13)
                                        font.bold: styleButton.selected
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: panel.rootObj.s(16)
                                        Layout.preferredHeight: panel.rootObj.s(16)
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: styleButton.selected ? ThemeBackend.mauve : ThemeBackend.overlay0

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: panel.rootObj.s(8)
                                            height: width
                                            radius: width / 2
                                            color: ThemeBackend.mauve
                                            visible: styleButton.selected
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
