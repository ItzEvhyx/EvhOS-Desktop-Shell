import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.SystemTray
import "../reusables"
import "../"

PanelWindow {
    id: trayMenuWindow

    screen: TrayMenuController.screen

    WlrLayershell.namespace: "traymenu"
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: false
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region {
        Region {
            item: (trayMenuWindow.isVisible || menuContainer.animProgress > 0.001) ? menuContainer : null
        }
        Region {
            item: (trayMenuWindow.isVisible || menuContainer.animProgress > 0.001) && submenuRepeater.count > 0 && submenuRepeater.itemAt(0) ? submenuRepeater.itemAt(0) : null
        }
        Region {
            item: (trayMenuWindow.isVisible || menuContainer.animProgress > 0.001) && submenuRepeater.count > 1 && submenuRepeater.itemAt(1) ? submenuRepeater.itemAt(1) : null
        }
        Region {
            item: (trayMenuWindow.isVisible || menuContainer.animProgress > 0.001) && submenuRepeater.count > 2 && submenuRepeater.itemAt(2) ? submenuRepeater.itemAt(2) : null
        }
        Region {
            item: (trayMenuWindow.isVisible || menuContainer.animProgress > 0.001) && submenuRepeater.count > 3 && submenuRepeater.itemAt(3) ? submenuRepeater.itemAt(3) : null
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function s(val) { return (typeof Scaler !== "undefined") ? Scaler.s(val) : val; }

    function resolveMenuIcon(icon) {
        if (!icon) return "";
        let themed = IconPacks.resolveIcon(icon, "", 32);
        if (themed) return themed;
        let ic = String(icon);
        if (ic.startsWith("file://") || ic.startsWith("http://") || ic.startsWith("https://")) return ic;
        if (ic.startsWith("image://") && !ic.startsWith("image://icon/")) return ic;
        if (ic.startsWith("/")) return "file://" + ic;
        let name = ic.startsWith("image://icon/") ? ic.substring("image://icon/".length) : ic;
        name = name.replace(/\.(png|svg|xpm|ico)$/i, "");
        let candidates = [name];
        if (name.endsWith("-symbolic")) candidates.push(name.substring(0, name.length - "-symbolic".length));
        for (let i = 0; i < candidates.length; i++) {
            let resolved = Quickshell.iconPath(candidates[i], true);
            if (resolved && resolved.length > 0) return resolved.startsWith("/") ? "file://" + resolved : resolved;
        }
        return "";
    }

    property bool isVisible: TrayMenuController.isVisible
    property string activeItemId: TrayMenuController.activeItemId
    property real targetX: TrayMenuController.targetX
    property real targetY: TrayMenuController.targetY
    property bool alignRight: TrayMenuController.alignRight
    property bool alignBottom: TrayMenuController.alignBottom
    property bool isSideBar: TrayMenuController.isSideBar
    readonly property var barGeometry: screen ? BarGeometry.bars[screen.name] : null
    readonly property bool attachedToTopBar: isSolid && !isSideBar && !alignBottom && barGeometry?.position === "top"
    readonly property real topBarEdge: attachedToTopBar ? Math.max(0, barGeometry.notchBottom - 0.5) : 0
    readonly property color menuBackground: Qt.alpha(ThemeBackend.base, barGeometry?.backgroundOpacity ?? 0.78)

    Binding {
        target: TrayMenuController
        property: "topBarAttachment"
        value: trayMenuWindow.attachedToTopBar && menuContainer.height > 1 ? {
            center: menuContainer.x + menuContainer.width / 2,
            halfWidth: menuContainer.width / 2 + menuContainer.dynamicCornerRadius
        } : null
    }

    property int configRevision: 0

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() {
            TrayMenuController.hide();
            trayMenuWindow.configRevision++;
        }
    }

    property string barStyle: {
        let dummy = configRevision;
        if (typeof Config === "undefined" || !Config.rawSettings || !Config.rawSettings.bar) return "modular";
        let s = Config.rawSettings.bar.style;
        if (typeof s === "string") return s;
        if (s && typeof s === "object") {
            if (s.fill || s.mode === "fill") return "fill";
            if (s.solid || s.mode === "solid") return "solid";
        }
        return "modular";
    }

    onBarStyleChanged: {
        TrayMenuController.hide();
    }

    property bool isFill: barStyle === "fill"
    property bool isSolid: barStyle === "solid" || barStyle === "fill"

    property real barHeight: {
        let dummy = configRevision;
        return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.height) ? s(Config.rawSettings.bar.height) : s(40);
    }

    property real cornerRadius: {
        let dummy = configRevision;
        let raw = (typeof ThemeBackend !== "undefined" && ThemeBackend.borderRadius !== undefined && ThemeBackend.borderRadius !== null)
            ? ThemeBackend.borderRadius
            : s(12);
        let threshold = s(32);
        let maxLimit = s(44);
        if (raw <= threshold) {
            return Math.max(0, raw);
        }
        let excess = raw - threshold;
        let range = maxLimit - threshold;
        return threshold + range * (1.0 - Math.exp(-excess / range));
    }

    property real menuMargin: isSolid ? 0 : s(20)

    visible: isVisible || menuContainer.animProgress > 0.001

    function closeMenu() {
        clearSubmenus();
        TrayMenuController.hide();
    }

    property var activeItem: {
        if (!activeItemId && activeItemId !== 0) return null;
        let list = SystemTray.items;
        if (!list) return null;
        let arr = list.values || list;
        if (arr && arr.length !== undefined) {
            for (let i = 0; i < arr.length; i++) {
                let it = arr[i];
                if (it && (String(it.id) === String(activeItemId) || String(i) === String(activeItemId))) {
                    return it;
                }
            }
        }
        if (list.count !== undefined && typeof list.get === "function") {
            for (let j = 0; j < list.count; j++) {
                let it = list.get(j);
                if (it && (String(it.id) === String(activeItemId) || String(j) === String(activeItemId))) {
                    return it;
                }
            }
        }
        let num = parseInt(activeItemId);
        if (!isNaN(num)) {
            if (list.values && list.values[num]) return list.values[num];
            if (list[num]) return list[num];
        }
        return null;
    }

    onActiveItemChanged: {
        clearSubmenus();
        if (!activeItem && isVisible) {
            TrayMenuController.hide();
        }
    }

    onIsVisibleChanged: {
        if (!isVisible) {
            clearSubmenus();
        } else if (!activeItem) {
            TrayMenuController.hide();
        }
    }

    property var activeMenuHandle: activeItem ? activeItem.menu : null

    QsMenuOpener {
        id: menuOpener
        menu: trayMenuWindow.activeMenuHandle
    }

    property real menuWidth: s(236)
    property real itemHeight: s(32)
    property int menuCount: {
        if (!menuOpener.children) return 0;
        if (menuOpener.children.values) return menuOpener.children.values.length;
        if (menuOpener.children.count !== undefined) return menuOpener.children.count;
        if (menuOpener.children.length !== undefined) return menuOpener.children.length;
        return 0;
    }

    property real rawHeight: (menuCount * itemHeight) + s(16)
    property real targetMenuHeight: Math.min(Math.max(s(40), rawHeight),
        attachedToTopBar && height > 0 ? Math.max(0, height - topBarEdge - s(8)) : Infinity)
    property real menuHeight: targetMenuHeight

    Behavior on menuHeight {
        enabled: trayMenuWindow.isVisible && menuContainer.animProgress > 0.95
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    property real clampedX: {
        let w = menuWidth;
        let x = 0;
        if (isSideBar) {
            if (alignRight) {
                let barEdge = (targetX > trayMenuWindow.width / 2) ? targetX : (trayMenuWindow.width - barHeight);
                x = isSolid ? (trayMenuWindow.width - barHeight - w) : (barEdge - w - menuMargin);
            } else {
                let barEdge = (targetX > 0 && targetX < trayMenuWindow.width / 2) ? targetX : barHeight;
                x = isSolid ? barHeight : (barEdge + menuMargin);
            }
        } else {
            x = targetX - (w / 2);
        }
        let edgeBound = (isSolid && !isSideBar) ? (cornerRadius + s(4)) : s(8);
        return Math.max(edgeBound, Math.min(trayMenuWindow.width - w - edgeBound, x));
    }

    property real clampedY: {
        if (attachedToTopBar) return topBarEdge;
        let h = menuHeight;
        let y = 0;
        if (isSideBar) {
            y = targetY - (h / 2);
        } else {
            if (alignBottom) {
                let barEdge = (targetY > trayMenuWindow.height / 2) ? targetY : (trayMenuWindow.height - barHeight);
                y = isSolid ? (trayMenuWindow.height - barHeight - h) : (barEdge - h - menuMargin);
            } else {
                let barEdge = (targetY > 0 && targetY < trayMenuWindow.height / 2) ? targetY : barHeight;
                y = isSolid ? barHeight : (barEdge + menuMargin);
            }
        }
        let edgeBound = (isSolid && isSideBar) ? (cornerRadius + s(4)) : s(8);
        return Math.max(edgeBound, Math.min(trayMenuWindow.height - h - edgeBound, y));
    }

    readonly property bool rootExpandRight: {
        if (isSideBar) {
            return !alignRight;
        }
        return (clampedX + menuWidth / 2) < (trayMenuWindow.width / 2);
    }

    property var submenuStack: []

    function openSubmenu(level, itemData, gx, gy, gw, gh) {
        if (!itemData) return;
        let newStack = submenuStack.slice(0, level);
        newStack.push({
            "menu": itemData,
            "parentX": gx,
            "parentY": gy,
            "parentWidth": gw,
            "parentHeight": gh,
            "level": level
        });
        submenuStack = newStack;
    }

    function closeSubmenusFrom(level) {
        if (submenuStack.length > level) {
            submenuStack = submenuStack.slice(0, level);
        }
    }

    function clearSubmenus() {
        submenuStack = [];
    }

    Item {
        id: rootContainer
        anchors.fill: parent

        Item {
            id: menuContainer

            property real animProgress: trayMenuWindow.isVisible ? 1.0 : 0.0
            Behavior on animProgress {
                NumberAnimation {
                    duration: trayMenuWindow.isVisible ? 280 : 220
                    easing.type: trayMenuWindow.attachedToTopBar ? Easing.InOutCubic : Easing.OutCubic
                }
            }

            readonly property real lowerRadius: trayMenuWindow.attachedToTopBar
                ? Math.min(trayMenuWindow.cornerRadius, Math.max(0, height - 0.5) / 2)
                : trayMenuWindow.cornerRadius
            readonly property real dynamicCornerRadius: trayMenuWindow.isSolid
                ? Math.min(lowerRadius, trayMenuWindow.isSideBar ? width : height) : 0

            x: {
                if (trayMenuWindow.isSolid) {
                    if (trayMenuWindow.isSideBar) {
                        if (trayMenuWindow.alignRight) {
                            return trayMenuWindow.clampedX + (trayMenuWindow.menuWidth - width);
                        }
                        return trayMenuWindow.clampedX;
                    }
                    return trayMenuWindow.clampedX;
                }
                let slideOffset = trayMenuWindow.s(16) * (1.0 - animProgress);
                if (trayMenuWindow.isSideBar) {
                    return trayMenuWindow.alignRight ? (trayMenuWindow.clampedX + slideOffset) : (trayMenuWindow.clampedX - slideOffset);
                }
                return trayMenuWindow.clampedX;
            }

            y: {
                if (trayMenuWindow.isSolid) {
                    if (!trayMenuWindow.isSideBar) {
                        if (trayMenuWindow.alignBottom) {
                            return trayMenuWindow.clampedY + (trayMenuWindow.menuHeight - height);
                        }
                        return trayMenuWindow.clampedY;
                    }
                    return trayMenuWindow.clampedY;
                }
                let slideOffset = trayMenuWindow.s(16) * (1.0 - animProgress);
                if (!trayMenuWindow.isSideBar) {
                    return trayMenuWindow.alignBottom ? (trayMenuWindow.clampedY + slideOffset) : (trayMenuWindow.clampedY - slideOffset);
                }
                return trayMenuWindow.clampedY;
            }

            width: {
                if (trayMenuWindow.isSolid && trayMenuWindow.isSideBar) {
                    return trayMenuWindow.menuWidth * animProgress;
                }
                return trayMenuWindow.menuWidth;
            }

            height: {
                if (trayMenuWindow.isSolid && !trayMenuWindow.isSideBar) {
                    return trayMenuWindow.menuHeight * animProgress;
                }
                return trayMenuWindow.menuHeight;
            }

            opacity: trayMenuWindow.attachedToTopBar ? 1 : animProgress
            scale: !trayMenuWindow.isSolid ? (0.92 + (0.08 * animProgress)) : 1.0

            transformOrigin: {
                if (trayMenuWindow.isSideBar) {
                    return trayMenuWindow.alignRight ? Item.Right : Item.Left;
                }
                return trayMenuWindow.alignBottom ? Item.Bottom : Item.Top;
            }

            GlassFillets {
                id: rootFillets
                card: menuBox
                filletRadius: (trayMenuWindow.isSolid && menuContainer.dynamicCornerRadius > 0.5) ? menuContainer.dynamicCornerRadius : 0
                filletDir: trayMenuWindow.isSideBar
                    ? (trayMenuWindow.alignRight ? Qt.vector2d(1, 0) : Qt.vector2d(-1, 0))
                    : (trayMenuWindow.alignBottom ? Qt.vector2d(0, 1) : Qt.vector2d(0, -1))
            }

            ShaderEffect {
                visible: trayMenuWindow.isSolid && menuContainer.dynamicCornerRadius > 0.5
                x: {
                    if (trayMenuWindow.isSideBar) {
                        return trayMenuWindow.alignRight ? (parent.width - menuContainer.dynamicCornerRadius) : 0;
                    }
                    return -menuContainer.dynamicCornerRadius;
                }
                y: {
                    if (trayMenuWindow.isSideBar) {
                        return -menuContainer.dynamicCornerRadius;
                    }
                    return trayMenuWindow.alignBottom ? (parent.height - menuContainer.dynamicCornerRadius) : 0;
                }
                width: menuContainer.dynamicCornerRadius
                height: menuContainer.dynamicCornerRadius
                property vector2d itemSize: Qt.vector2d(width, height)
                property real cornerIndex: {
                    if (trayMenuWindow.isSideBar) {
                        return trayMenuWindow.alignRight ? 3.0 : 2.0;
                    }
                    return trayMenuWindow.alignBottom ? 3.0 : 1.0;
                }
                property color color: trayMenuWindow.menuBackground
                fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/ui/corner_cutout.frag.qsb"
            }

            ShaderEffect {
                visible: trayMenuWindow.isSolid && menuContainer.dynamicCornerRadius > 0.5
                x: {
                    if (trayMenuWindow.isSideBar) {
                        return trayMenuWindow.alignRight ? (parent.width - menuContainer.dynamicCornerRadius) : 0;
                    }
                    return parent.width;
                }
                y: {
                    if (trayMenuWindow.isSideBar) {
                        return parent.height;
                    }
                    return trayMenuWindow.alignBottom ? (parent.height - menuContainer.dynamicCornerRadius) : 0;
                }
                width: menuContainer.dynamicCornerRadius
                height: menuContainer.dynamicCornerRadius
                property vector2d itemSize: Qt.vector2d(width, height)
                property real cornerIndex: {
                    if (trayMenuWindow.isSideBar) {
                        return trayMenuWindow.alignRight ? 1.0 : 0.0;
                    }
                    return trayMenuWindow.alignBottom ? 2.0 : 0.0;
                }
                property color color: trayMenuWindow.menuBackground
                fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/ui/corner_cutout.frag.qsb"
            }

            // Continue the notch outline over the two shoulders and around the menu.
            Shape {
                visible: trayMenuWindow.attachedToTopBar && menuContainer.height > 1
                x: -menuContainer.dynamicCornerRadius
                y: 0
                width: menuContainer.width + 2 * menuContainer.dynamicCornerRadius
                height: menuContainer.height
                z: 2
                layer.enabled: true
                layer.samples: 4
                ShapePath {
                    strokeWidth: 1
                    strokeColor: Qt.alpha(ThemeBackend.text, 0.28)
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    joinStyle: ShapePath.RoundJoin
                    startX: 0; startY: 0
                    PathQuad { x: menuContainer.dynamicCornerRadius; y: menuContainer.dynamicCornerRadius; controlX: menuContainer.dynamicCornerRadius; controlY: 0 }
                    PathLine { x: menuContainer.dynamicCornerRadius; y: menuContainer.height - menuContainer.lowerRadius - 0.5 }
                    PathQuad { x: menuContainer.dynamicCornerRadius + menuContainer.lowerRadius; y: menuContainer.height - 0.5; controlX: menuContainer.dynamicCornerRadius; controlY: menuContainer.height - 0.5 }
                    PathLine { x: menuContainer.dynamicCornerRadius + menuContainer.width - menuContainer.lowerRadius; y: menuContainer.height - 0.5 }
                    PathQuad { x: menuContainer.dynamicCornerRadius + menuContainer.width; y: menuContainer.height - menuContainer.lowerRadius - 0.5; controlX: menuContainer.dynamicCornerRadius + menuContainer.width; controlY: menuContainer.height - 0.5 }
                    PathLine { x: menuContainer.dynamicCornerRadius + menuContainer.width; y: menuContainer.dynamicCornerRadius }
                    PathQuad { x: menuContainer.width + 2 * menuContainer.dynamicCornerRadius; y: 0; controlX: menuContainer.dynamicCornerRadius + menuContainer.width; controlY: 0 }
                }
            }

            Rectangle {
                id: menuBox
                anchors.fill: parent
                color: trayMenuWindow.menuBackground
                radius: menuContainer.lowerRadius
                border.width: trayMenuWindow.attachedToTopBar ? 0 : 1
                border.color: Qt.alpha(ThemeBackend.text, 0.14)
                readonly property bool flatCorners: trayMenuWindow.isSolid
                topLeftRadius: (flatCorners && (trayMenuWindow.isSideBar ? !trayMenuWindow.alignRight : !trayMenuWindow.alignBottom)) ? 0 : radius
                topRightRadius: (flatCorners && (trayMenuWindow.isSideBar ? trayMenuWindow.alignRight : !trayMenuWindow.alignBottom)) ? 0 : radius
                bottomLeftRadius: (flatCorners && (trayMenuWindow.isSideBar ? !trayMenuWindow.alignRight : trayMenuWindow.alignBottom)) ? 0 : radius
                bottomRightRadius: (flatCorners && (trayMenuWindow.isSideBar ? trayMenuWindow.alignRight : trayMenuWindow.alignBottom)) ? 0 : radius
                clip: true

                WallpaperBlur {
                    z: -1
                    anchors.fill: parent
                    rim: 0
                    topLeftRadius: parent.topLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    bottomRightRadius: parent.bottomRightRadius
                    filletRadius: rootFillets.filletRadius
                    filletDir: rootFillets.filletDir
                }

                HoverHandler {
                    id: menuHoverHandler
                    onHoveredChanged: {
                        TrayMenuController.menuHovered = hovered;
                        if (hovered) {
                            TrayMenuController.cancelHide();
                        } else {
                            TrayMenuController.requestHide();
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                ListView {
                    id: menuList
                    anchors.fill: parent
                    anchors.margins: trayMenuWindow.s(8)
                    model: menuOpener.children
                    clip: true
                    spacing: 0
                    cacheBuffer: 3000
                    interactive: contentHeight > height

                    delegate: Item {
                        id: rootItemDelegate
                        width: menuList.width
                        height: trayMenuWindow.itemHeight
                        property bool isSep: modelData ? modelData.isSeparator : false
                        property bool hasChildren: modelData ? (modelData.hasChildren === true) : false

                        Item {
                            anchors.fill: parent
                            visible: !rootItemDelegate.isSep
                            opacity: (modelData && modelData.enabled) ? 1.0 : 0.4

                            Image {
                                id: itemIcon
                                anchors.left: parent.left
                                anchors.leftMargin: trayMenuWindow.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                width: source !== "" ? trayMenuWindow.s(16) : 0
                                height: trayMenuWindow.s(16)
                                source: modelData ? trayMenuWindow.resolveMenuIcon(modelData.icon) : ""
                                sourceSize: Qt.size(trayMenuWindow.s(16), trayMenuWindow.s(16))
                                fillMode: Image.PreserveAspectFit
                                visible: width > 0 && status === Image.Ready
                            }

                            Text {
                                anchors.left: itemIcon.visible ? itemIcon.right : parent.left
                                anchors.leftMargin: trayMenuWindow.s(8)
                                anchors.right: arrowText.visible ? arrowText.left : parent.right
                                anchors.rightMargin: trayMenuWindow.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData && modelData.text) ? modelData.text : ""
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: trayMenuWindow.s(13)
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                id: arrowText
                                anchors.right: parent.right
                                anchors.rightMargin: trayMenuWindow.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                visible: rootItemDelegate.hasChildren
                                text: trayMenuWindow.rootExpandRight ? "›" : "‹"
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: trayMenuWindow.s(13)
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: modelData ? modelData.enabled : false
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    TrayMenuController.cancelHide();
                                    TrayMenuController.menuHovered = true;
                                    if (rootItemDelegate.hasChildren) {
                                        let pos = rootItemDelegate.mapToItem(rootContainer, 0, 0);
                                        trayMenuWindow.openSubmenu(0, modelData, menuContainer.x, pos.y, menuContainer.width, rootItemDelegate.height);
                                    } else {
                                        trayMenuWindow.closeSubmenusFrom(0);
                                    }
                                }
                                onExited: {
                                    TrayMenuController.requestHide();
                                }
                                onClicked: {
                                    if (modelData && !modelData.hasChildren) {
                                        modelData.triggered();
                                        trayMenuWindow.closeMenu();
                                    } else if (modelData && modelData.hasChildren) {
                                        let pos = rootItemDelegate.mapToItem(rootContainer, 0, 0);
                                        trayMenuWindow.openSubmenu(0, modelData, menuContainer.x, pos.y, menuContainer.width, rootItemDelegate.height);
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width - trayMenuWindow.s(16)
                            height: 1
                            color: ThemeBackend.surface0
                            anchors.centerIn: parent
                            visible: rootItemDelegate.isSep
                        }
                    }
                }
            }
        }

        Repeater {
            id: submenuRepeater
            model: trayMenuWindow.submenuStack.length

            Item {
                id: submenuPopout
                property int stackIndex: index
                property var stackData: (trayMenuWindow.submenuStack && trayMenuWindow.submenuStack.length > index) ? trayMenuWindow.submenuStack[index] : null

                property real parentItemX: stackData ? stackData.parentX : 0
                property real parentItemY: stackData ? stackData.parentY : 0
                property real parentItemWidth: stackData ? stackData.parentWidth : trayMenuWindow.menuWidth
                property real parentItemHeight: stackData ? stackData.parentHeight : trayMenuWindow.itemHeight

                property real subCornerRadius: trayMenuWindow.cornerRadius

                readonly property bool shouldExpandRight: {
                    if (trayMenuWindow.isSideBar) {
                        return !trayMenuWindow.alignRight;
                    }
                    return (parentItemX + parentItemWidth / 2) < (trayMenuWindow.width / 2);
                }

                readonly property bool expandRight: {
                    let w = trayMenuWindow.menuWidth;
                    let rightX = parentItemX + parentItemWidth;
                    let leftX = parentItemX - w;
                    if (shouldExpandRight) {
                        if (rightX + w > trayMenuWindow.width - trayMenuWindow.s(8) && leftX >= trayMenuWindow.s(8)) {
                            return false;
                        }
                        return true;
                    } else {
                        if (leftX < trayMenuWindow.s(8) && rightX + w <= trayMenuWindow.width - trayMenuWindow.s(8)) {
                            return true;
                        }
                        return false;
                    }
                }

                QsMenuOpener {
                    id: subMenuOpener
                    menu: (submenuPopout.stackData && submenuPopout.stackData.menu) ? (submenuPopout.stackData.menu.menu || submenuPopout.stackData.menu) : null
                }

                property int subMenuCount: {
                    if (!subMenuOpener.children) return 0;
                    if (subMenuOpener.children.values) return subMenuOpener.children.values.length;
                    if (subMenuOpener.children.count !== undefined) return subMenuOpener.children.count;
                    if (subMenuOpener.children.length !== undefined) return subMenuOpener.children.length;
                    return 0;
                }

                property real subMenuRawHeight: (subMenuCount * trayMenuWindow.itemHeight) + trayMenuWindow.s(16)
                property real subMenuTargetHeight: Math.max(trayMenuWindow.s(40), subMenuRawHeight)
                property real subMenuHeight: subMenuTargetHeight

                width: trayMenuWindow.menuWidth
                height: subMenuHeight

                property real popoutProgress: (trayMenuWindow.isVisible && menuContainer.animProgress > 0.001) ? 1.0 : 0.0
                Behavior on popoutProgress {
                    NumberAnimation {
                        duration: (trayMenuWindow.isVisible && menuContainer.animProgress > 0.001) ? 220 : 160
                        easing.type: Easing.OutCubic
                    }
                }

                visible: (trayMenuWindow.isVisible || menuContainer.animProgress > 0.001) && popoutProgress > 0.001

                x: {
                    let base = expandRight ? (parentItemX + parentItemWidth) : (parentItemX - width);
                    let slide = trayMenuWindow.s(10) * (1.0 - popoutProgress);
                    return expandRight ? (base - slide) : (base + slide);
                }

                y: {
                    let h = height;
                    let target = parentItemY - trayMenuWindow.s(8);
                    return Math.max(trayMenuWindow.s(8), Math.min(trayMenuWindow.height - h - trayMenuWindow.s(8), target));
                }

                opacity: popoutProgress * menuContainer.animProgress
                scale: 0.94 + (0.06 * popoutProgress)
                transformOrigin: expandRight ? Item.Left : Item.Right

                GlassFillets {
                    id: subFillets
                    card: subMenuBox
                    filletRadius: submenuPopout.subCornerRadius > 0.5 ? submenuPopout.subCornerRadius : 0
                    filletDir: submenuPopout.expandRight ? Qt.vector2d(-1, 0) : Qt.vector2d(1, 0)
                }

                ShaderEffect {
                    visible: submenuPopout.subCornerRadius > 0.5
                    x: submenuPopout.expandRight ? 0 : (parent.width - submenuPopout.subCornerRadius)
                    y: -submenuPopout.subCornerRadius
                    width: submenuPopout.subCornerRadius
                    height: submenuPopout.subCornerRadius
                    property vector2d itemSize: Qt.vector2d(width, height)
                    property real cornerIndex: submenuPopout.expandRight ? 2.0 : 3.0
                    property color color: trayMenuWindow.menuBackground
                    fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/ui/corner_cutout.frag.qsb"
                }

                ShaderEffect {
                    visible: submenuPopout.subCornerRadius > 0.5
                    x: submenuPopout.expandRight ? 0 : (parent.width - submenuPopout.subCornerRadius)
                    y: parent.height
                    width: submenuPopout.subCornerRadius
                    height: submenuPopout.subCornerRadius
                    property vector2d itemSize: Qt.vector2d(width, height)
                    property real cornerIndex: submenuPopout.expandRight ? 0.0 : 1.0
                    property color color: trayMenuWindow.menuBackground
                    fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/ui/corner_cutout.frag.qsb"
                }

                Rectangle {
                    id: subMenuBox
                    anchors.fill: parent
                    color: trayMenuWindow.menuBackground
                    radius: trayMenuWindow.cornerRadius
                    border.width: 1
                    border.color: Qt.alpha(ThemeBackend.text, 0.14)
                    topLeftRadius: submenuPopout.expandRight ? 0 : trayMenuWindow.cornerRadius
                    bottomLeftRadius: submenuPopout.expandRight ? 0 : trayMenuWindow.cornerRadius
                    topRightRadius: !submenuPopout.expandRight ? 0 : trayMenuWindow.cornerRadius
                    bottomRightRadius: !submenuPopout.expandRight ? 0 : trayMenuWindow.cornerRadius
                    clip: true

                    WallpaperBlur {
                        z: -1
                        anchors.fill: parent
                        topLeftRadius: parent.topLeftRadius
                        topRightRadius: parent.topRightRadius
                        bottomLeftRadius: parent.bottomLeftRadius
                        bottomRightRadius: parent.bottomRightRadius
                        filletRadius: subFillets.filletRadius
                        filletDir: subFillets.filletDir
                    }

                    HoverHandler {
                        id: subHoverHandler
                        onHoveredChanged: {
                            TrayMenuController.menuHovered = hovered;
                            if (hovered) {
                                TrayMenuController.cancelHide();
                            } else {
                                TrayMenuController.requestHide();
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                    }

                    ListView {
                        id: subListView
                        anchors.fill: parent
                        anchors.margins: trayMenuWindow.s(8)
                        model: subMenuOpener.children
                        clip: true
                        spacing: 0
                        cacheBuffer: 3000
                        interactive: contentHeight > height

                        delegate: Item {
                            id: subItemDelegate
                            width: subListView.width
                            height: trayMenuWindow.itemHeight
                            property bool isSep: modelData ? modelData.isSeparator : false
                            property bool hasChildren: modelData ? (modelData.hasChildren === true) : false

                            Item {
                                anchors.fill: parent
                                visible: !subItemDelegate.isSep
                                opacity: (modelData && modelData.enabled) ? 1.0 : 0.4

                                Image {
                                    id: subItemIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: trayMenuWindow.s(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: source !== "" ? trayMenuWindow.s(16) : 0
                                    height: trayMenuWindow.s(16)
                                    source: modelData ? trayMenuWindow.resolveMenuIcon(modelData.icon) : ""
                                    sourceSize: Qt.size(trayMenuWindow.s(16), trayMenuWindow.s(16))
                                    fillMode: Image.PreserveAspectFit
                                    visible: width > 0 && status === Image.Ready
                                }

                                Text {
                                    anchors.left: subItemIcon.visible ? subItemIcon.right : parent.left
                                    anchors.leftMargin: trayMenuWindow.s(8)
                                    anchors.right: subArrowText.visible ? subArrowText.left : parent.right
                                    anchors.rightMargin: trayMenuWindow.s(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (modelData && modelData.text) ? modelData.text : ""
                                    color: ThemeBackend.text
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: trayMenuWindow.s(13)
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    id: subArrowText
                                    anchors.right: parent.right
                                    anchors.rightMargin: trayMenuWindow.s(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: subItemDelegate.hasChildren
                                    text: submenuPopout.expandRight ? "›" : "‹"
                                    color: ThemeBackend.subtext0
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: trayMenuWindow.s(13)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: modelData ? modelData.enabled : false
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: {
                                        TrayMenuController.cancelHide();
                                        TrayMenuController.menuHovered = true;
                                        if (subItemDelegate.hasChildren) {
                                            let pos = subItemDelegate.mapToItem(rootContainer, 0, 0);
                                            trayMenuWindow.openSubmenu(submenuPopout.stackIndex + 1, modelData, submenuPopout.x, pos.y, submenuPopout.width, subItemDelegate.height);
                                        } else {
                                            trayMenuWindow.closeSubmenusFrom(submenuPopout.stackIndex + 1);
                                        }
                                    }
                                    onExited: {
                                        TrayMenuController.requestHide();
                                    }
                                    onClicked: {
                                        if (modelData && !modelData.hasChildren) {
                                            modelData.triggered();
                                            trayMenuWindow.closeMenu();
                                        } else if (modelData && modelData.hasChildren) {
                                            let pos = subItemDelegate.mapToItem(rootContainer, 0, 0);
                                            trayMenuWindow.openSubmenu(submenuPopout.stackIndex + 1, modelData, submenuPopout.x, pos.y, submenuPopout.width, subItemDelegate.height);
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width - trayMenuWindow.s(16)
                                height: 1
                                color: ThemeBackend.surface0
                                anchors.centerIn: parent
                                visible: subItemDelegate.isSep
                            }
                        }
                    }
                }
            }
        }
    }
}
