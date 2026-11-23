import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"
import "NotesFormat.js" as NotesFormat

Item {
    id: root

    property int requestedLayoutTemplate: 1
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property string nerdFont: ThemeBackend.iconFont
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    property bool stateLoaded: false
    property var interceptedShortcuts: isEditing ? ["Return", "Enter", "Left", "Right", "Up", "Down", "Escape"] : (searchInput.activeFocus || selectedCount > 0 ? ["Escape"] : [])
    readonly property bool hasInputFocus: searchInput.activeFocus || (typeof nameInput !== "undefined" && nameInput.hasFocus) || (typeof contentInput !== "undefined" && contentInput.hasFocus)

    function unfocusInputs() {
        searchInput.focus = false;
        if (typeof nameInput !== "undefined" && typeof nameInput.releaseFocus === "function") {
            nameInput.releaseFocus();
        }
        if (typeof contentInput !== "undefined" && typeof contentInput.releaseFocus === "function") {
            contentInput.releaseFocus();
        }
    }

    Shortcut {
        enabled: root.isActiveTab && root.isEditing
        sequence: "Ctrl+S"
        onActivated: root.flushEdits()
    }

    Shortcut {
        enabled: root.isActiveTab && root.isEditing
        sequence: "Escape"
        onActivated: root.saveCurrentNote()
    }

    Shortcut {
        enabled: root.visible && root.isActiveTab && !root.isEditing
        sequence: "Ctrl+F"
        onActivated: searchInput.forceActiveFocus()
    }

    Shortcut {
        enabled: root.visible && root.isActiveTab && !root.isEditing && !searchInput.activeFocus && root.selectedCount > 0
        sequence: "Escape"
        onActivated: root.clearSelection()
    }

    function s(val) {
        return typeof scaleFunc === "function" ? scaleFunc(val) : val;
    }

    property real baseW: s(460)
    property real baseL: s(430)

    property real preferredWidth: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseL + 50 : baseW
    property real preferredExtraLength: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseW : baseL

    property real counterRotation: {
        if (root.safeActiveEdge === "right") return 180;
        if (root.safeActiveEdge === "bottom") return 90;
        if (root.safeActiveEdge === "top") return -90;
        return 0;
    }

    function alpha(color, a) { return Qt.rgba(color.r, color.g, color.b, a); }

    function getStorageDir() {
        return (typeof Caching !== "undefined" && Caching.stateDir ? Caching.stateDir : ((Quickshell.env("HOME") || "") + "/.local/state/serpantinum")) + "/quickactions";
    }

    property var notesList: []
    property var selectedIds: ({})
    property int selectedCount: 0

    property bool isEditing: false
    property string editingNoteId: ""
    property real editingUpdatedAt: 0
    property bool editingNotePinned: false
    property bool isMarkdownPreview: false
    property bool editorLoading: false
    property bool editorDirty: false
    property string saveError: ""

    function resetHistory() {} // Native document owns undo/redo.
    function contentEdited() { scheduleSave(); }

    onIsActiveTabChanged: {
        if (!isActiveTab) {
            if (searchInput) searchInput.focus = false;
            flushEdits();
        }
    }
    Component.onDestruction: flushEdits()

    Timer { id: autosaveTimer; interval: 500; onTriggered: root.flushEdits() }
    function scheduleSave() {
        if (isEditing && !editorLoading) { editorDirty = true; autosaveTimer.restart(); }
    }
    function flushEdits() {
        autosaveTimer.stop();
        if (isEditing && editorDirty) persistCurrentNote();
    }

    readonly property bool areSelectedNotesPinned: {
        let keys = Object.keys(root.selectedIds);
        if (keys.length === 0) return false;
        for (let i = 0; i < root.notesList.length; i++) {
            let n = root.notesList[i];
            if (root.selectedIds[n.id] && !n.pinned) {
                return false;
            }
        }
        return true;
    }

    readonly property string searchQuery: searchInput.text.trim()
    property double todayStart: startOfDay()

    function startOfDay() {
        const day = new Date();
        day.setHours(0, 0, 0, 0);
        return day.getTime();
    }

    readonly property var displayNotesList: {
        const terms = root.searchQuery.toLocaleLowerCase().split(/\s+/).filter(Boolean);
        const weekStart = new Date(root.todayStart);
        weekStart.setDate(weekStart.getDate() - 7);
        const pinned = I18n.t("quickactions.notes.pinned");
        const visibleNotes = [];
        for (const note of root.notesList) {
            if (terms.length) {
                const searchable = ((note.title || "") + " " + (note.content || "")).toLocaleLowerCase();
                if (!terms.every(term => searchable.includes(term))) continue;
            }
            const timestamp = Number(note.updatedAt || note.createdAt) || 0;
            const section = note.pinned ? pinned : timestamp >= root.todayStart ? "Today" : timestamp >= weekStart.getTime() ? "Previous 7 days" : "Earlier";
            visibleNotes.push(Object.assign({}, note, { listTimestamp: timestamp, sectionCategory: section }));
        }
        visibleNotes.sort((a, b) => Number(Boolean(b.pinned)) - Number(Boolean(a.pinned)) || b.listTimestamp - a.listTimestamp);
        return visibleNotes;
    }

    property real expandProgress: 0.0
    property bool isDraggingV: false
    Behavior on expandProgress {
        enabled: !root.isDraggingV
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    onExpandProgressChanged: {
        if (expandProgress <= 0.001 && isEditing && !isDraggingV) {
            flushEdits();
            isEditing = false;
            editingNoteId = "";
        }
    }

    Timer {
        interval: 60000
        running: root.visible && root.isActiveTab && !root.isEditing
        repeat: true
        triggeredOnStart: true
        onTriggered: root.todayStart = root.startOfDay()
    }

    function formatCardDate(timestamp) {
        if (!timestamp) return "";
        const date = new Date(timestamp);
        if (timestamp >= root.todayStart) {
            const format = Config.getSetting("bar.time.format", "HH:mm");
            return Qt.formatTime(date, String(format).includes("hh:") ? "h:mm AP" : "HH:mm");
        }
        const inCurrentYear = date.getFullYear() === new Date(root.todayStart).getFullYear();
        return Qt.formatDate(date, inCurrentYear ? "MMM d" : "MMM d, yyyy");
    }

    function formatPreciseTime(timestamp) {
        return NotesFormat.formatPreciseTime(timestamp);
    }

    FileView {
        id: notesStore
        path: root.getStorageDir() + "/notes.json"
        blockWrites: true
        atomicWrites: true
        onSaved: { root.editorDirty = false; root.saveError = ""; }
        onSaveFailed: error => {
            root.saveError = "Could not save — try Ctrl+S";
            root.editorDirty = true;
            console.warn("Notes could not be saved:", error);
        }
    }

    Process {
        id: loadNotesProc
        command: ["bash", "-c", "mkdir -p -- \"$1\"; if [ -f \"$1/notes.json\" ]; then cat -- \"$1/notes.json\"; else echo '[]'; fi", "notes", root.getStorageDir()]
        stdout: StdioCollector {
            id: loadNotesOut
            onStreamFinished: {
                root.restoreNotes(loadNotesOut.text);
            }
        }
    }

    Component.onCompleted: {
        loadNotesProc.running = true;
    }

    function restoreNotes(rawText) {
        let txt = (rawText || "").trim();
        if (txt !== "") {
            try {
                let data = JSON.parse(txt);
                if (Array.isArray(data)) {
                    root.notesList = data;
                }
            } catch (e) {}
        }
        root.stateLoaded = true;
    }

    function saveNotes() {
        if (!root.stateLoaded) return;
        notesStore.setText(JSON.stringify(root.notesList));
    }

    function isSelected(id) {
        return !!root.selectedIds[id];
    }

    function toggleSelection(id) {
        let copy = Object.assign({}, root.selectedIds);
        if (copy[id]) {
            delete copy[id];
        } else {
            copy[id] = true;
        }
        root.selectedIds = copy;
        root.selectedCount = Object.keys(copy).length;
    }

    function clearSelection() {
        root.selectedIds = ({});
        root.selectedCount = 0;
    }

    function deleteSelectedNotes() {
        let remaining = [];
        for (let i = 0; i < root.notesList.length; i++) {
            let item = root.notesList[i];
            if (!root.selectedIds[item.id]) {
                remaining.push(item);
            }
        }
        root.notesList = remaining;
        root.clearSelection();
        root.saveNotes();
    }

    function togglePinSelectedNotes() {
        let allPinned = root.areSelectedNotesPinned;
        let targetPinned = !allPinned;
        let list = root.notesList.map(n => {
            if (root.selectedIds[n.id]) {
                let copy = Object.assign({}, n);
                copy.pinned = targetPinned;
                return copy;
            }
            return n;
        });
        root.notesList = list;
        root.clearSelection();
        root.saveNotes();
    }

    function createNewNote() {
        root.clearSelection();
        searchInput.focus = false;
        let newId = "note_" + Date.now();
        root.editingNoteId = newId;
        root.editingUpdatedAt = Date.now();
        root.editingNotePinned = false;
        root.editorLoading = true;
        nameInput.text = "";
        contentInput.text = "";
        root.editorLoading = false;
        root.editorDirty = false;
        root.isMarkdownPreview = false;
        root.isEditing = true;
        root.resetHistory();
        root.expandProgress = 1.0;
    }

    function openNote(noteItem) {
        if (root.selectedCount > 0) {
            root.toggleSelection(noteItem.id);
            return;
        }
        root.loadNoteIntoEditor(noteItem);
        root.expandProgress = 1.0;
    }

    function loadNoteIntoEditor(noteItem) {
        searchInput.focus = false;
        root.editingNoteId = noteItem.id;
        root.editingUpdatedAt = noteItem.updatedAt || Date.now();
        root.editingNotePinned = Boolean(noteItem.pinned);
        root.editorLoading = true;
        nameInput.text = noteItem.title || "";
        contentInput.text = root.prepareNoteForEditor(noteItem);
        root.editorLoading = false;
        root.editorDirty = false;
        root.isMarkdownPreview = false;
        root.isEditing = true;
        root.resetHistory();
    }

    function saveCurrentNote() {
        flushEdits();
        if (!root.saveError) root.expandProgress = 0.0;
    }

    function persistCurrentNote() {
        if (!root.isEditing || !root.stateLoaded || !root.editingNoteId) return;
        let t = nameInput.text.trim();
        let c = contentInput.plainText();
        let html = contentInput.html();
        let id = root.editingNoteId;
        let list = root.notesList.slice();
        let idx = list.findIndex(n => n.id === id);
        if (t === "" && c.trim() === "" && idx === -1) {
            root.editorDirty = false;
            return;
        }
        if (t === "") {
            let firstLine = c.trim().split("\n")[0];
            t = firstLine.length > 25 ? firstLine.substring(0, 25) + "..." : firstLine;
            if (!t) t = I18n.t("quickactions.notes.new_note_title");
        }
        let now = Date.now();
        let note = Object.assign({}, idx >= 0 ? list[idx] : {}, {
            id: id, title: t, content: c, pinned: root.editingNotePinned, editorFormat: "richtext-html-v1", contentHtml: html,
            updatedAt: now, createdAt: idx >= 0 ? (list[idx].createdAt || now) : now
        });
        if (idx >= 0) list[idx] = note; else list.unshift(note);
        root.notesList = list;
        root.saveNotes();
        root.editingUpdatedAt = now;
    }

    function prepareNoteForEditor(note) {
        if (note.editorFormat === "richtext-html-v1" && typeof note.contentHtml === "string") return note.contentHtml;
        let content = note.content || "";
        if (note.editorFormat !== "markdown-visual-v1") {
            // Older notes displayed every newline, including single newlines.
            content = content.replace(/\r\n/g, "\n").split("\n").map(line =>
                line.trim() && !/^(\s*#{1,6} |\s*[-*+] |\s*\d+\. |\s*!\[)/.test(line) ? line + "  " : line
            ).join("\n");
        }
        return contentInput.fromMarkdown(content);
    }

    function applyFormat(kind) {
        contentInput.format(kind);
        root.scheduleSave();
    }

    function pasteIntoNote() {
        if (pasteProc.running) return;
        pasteProc.noteId = root.editingNoteId;
        pasteProc.position = contentInput.multilineEditor.selectionStart;
        pasteProc.endPosition = contentInput.multilineEditor.selectionEnd;
        pasteProc.originalText = contentInput.text;
        pasteProc.command = ["python3", Caching.serpantinumDir + "/scripts/notes_paste_image.py", root.getStorageDir()];
        pasteProc.running = true;
    }
    Process {
        id: pasteProc
        property string noteId: ""
        property int position: 0
        property int endPosition: 0
        property string originalText: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.isEditing || pasteProc.noteId !== root.editingNoteId) return;
                let result = text.trim();
                let edit = contentInput.multilineEditor;
                if (result.startsWith("IMAGE:")) {
                    let position = Math.min(pasteProc.position, edit.length);
                    if (contentInput.text !== pasteProc.originalText) position = edit.cursorPosition;
                    let end = contentInput.text === pasteProc.originalText ? pasteProc.endPosition : position;
                    contentInput.insertImage(result.substring(6), position, end);
                    root.scheduleSave();
                } else if (result === "TEXT") {
                    edit.paste();
                } else {
                    console.warn("Could not paste image into note:", result);
                }
            }
        }
    }

    function markdownToHtml(md) {
        return NotesFormat.markdownToHtml(md);
    }

    Item {
        id: orientedRoot
        anchors.centerIn: parent
        width: (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation
        clip: true

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: ThemeBackend.borderRadius

            Item {
                id: mainListView
                anchors.fill: parent
                opacity: Math.max(0.0, 1.0 - root.expandProgress * 1.5)
                visible: opacity > 0.001

                ColumnLayout {
                    id: listControls
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: root.s(13)
                    spacing: root.s(9)

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(32)
                        spacing: root.s(6)

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.selectedCount > 0
                                ? I18n.t("quickactions.notes.selected_count", { count: root.selectedCount })
                                : I18n.t("quickactions.notes.title")
                            color: ThemeBackend.text
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(root.selectedCount > 0 ? 15 : 21)
                            font.weight: Font.DemiBold
                        }

                        ClickButton {
                            visible: root.selectedCount === 0
                            enabled: root.stateLoaded
                            buttonText: I18n.t("quickactions.notes.add_note")
                            buttonIcon: "󰐕"
                            iconFont: root.nerdFont
                            iconFontSize: root.s(14)
                            textFontSize: root.s(12)
                            accentColor: Qt.lighter(ThemeBackend.surface1, 1.10)
                            bgOpacity: ThemeBackend.elementOpacity
                            textColor: ThemeBackend.text
                            cornerRadius: root.s(9)
                            implicitHeight: root.s(32)
                            onClicked: root.createNewNote()
                        }

                        IconButton {
                            visible: root.selectedCount > 0
                            size: root.s(32)
                            cornerRadius: root.s(8)
                            iconFont: root.nerdFont
                            iconFontSize: root.s(15)
                            buttonIcon: "󰐃"
                            textColor: root.areSelectedNotesPinned ? ThemeBackend.mauve : ThemeBackend.subtext0
                            accentColor: ThemeBackend.surface0
                            bgOpacity: ThemeBackend.elementOpacity
                            Accessible.name: I18n.t(root.areSelectedNotesPinned ? "quickactions.notes.unpin" : "quickactions.notes.pin")
                            onClicked: root.togglePinSelectedNotes()
                        }

                        IconButton {
                            visible: root.selectedCount > 0
                            size: root.s(32)
                            cornerRadius: root.s(8)
                            iconFont: root.nerdFont
                            iconFontSize: root.s(15)
                            buttonIcon: "󰆴"
                            textColor: ThemeBackend.red
                            accentColor: root.alpha(ThemeBackend.red, 0.16)
                            bgOpacity: ThemeBackend.elementOpacity
                            Accessible.name: I18n.t("quickactions.notes.delete")
                            onClicked: root.deleteSelectedNotes()
                        }

                        CloseButton {
                            visible: root.selectedCount > 0
                            size: root.s(32)
                            cornerRadius: root.s(8)
                            iconFont: root.nerdFont
                            iconFontSize: root.s(15)
                            textColor: ThemeBackend.subtext0
                            accentColor: ThemeBackend.surface0
                            bgOpacity: ThemeBackend.elementOpacity
                            Accessible.name: I18n.t("quickactions.notes.deselect_all")
                            onClicked: root.clearSelection()
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(36)

                        Basic.TextField {
                            id: searchInput
                            objectName: "notes-search"
                            anchors.fill: parent
                            padding: 0
                            leftPadding: root.s(35)
                            rightPadding: text.length ? root.s(38) : root.s(10)
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: I18n.t("quickactions.notes.search_placeholder")
                            placeholderTextColor: ThemeBackend.subtext0
                            color: ThemeBackend.text
                            selectionColor: ThemeBackend.mauve
                            selectedTextColor: ThemeBackend.base
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(12)
                            selectByMouse: true
                            background: Rectangle {
                                radius: root.s(9)
                                color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
                                border.width: 1
                                border.color: Qt.tint(ThemeBackend.surface0, Qt.alpha(searchInput.activeFocus ? ThemeBackend.mauve : ThemeBackend.text, searchInput.activeFocus ? 0.58 : 0.10))
                                Behavior on border.color { ColorAnimation { duration: 130 } }
                            }
                            onTextChanged: {
                                if (root.selectedCount) root.clearSelection();
                                notesListView.positionViewAtBeginning();
                            }
                            onAccepted: {
                                if (root.displayNotesList.length && !root.selectedCount)
                                    root.openNote(root.displayNotesList[0]);
                            }
                            Keys.onEscapePressed: searchInput.focus = false
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: root.s(11)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰍉"
                            color: searchInput.activeFocus ? ThemeBackend.mauve : ThemeBackend.subtext0
                            font.family: root.nerdFont
                            font.pixelSize: root.s(16)
                        }

                        CloseButton {
                            anchors.right: parent.right
                            anchors.rightMargin: root.s(4)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length > 0
                            size: root.s(28)
                            cornerRadius: root.s(6)
                            iconFont: root.nerdFont
                            iconFontSize: root.s(13)
                            textColor: ThemeBackend.subtext0
                            accentColor: ThemeBackend.surface1
                            bgOpacity: 0.6
                            Accessible.name: "Clear search"
                            onClicked: { searchInput.clear(); searchInput.forceActiveFocus(); }
                        }
                    }
                }

                ListView {
                    id: notesListView
                    objectName: "notes-list"
                    anchors.top: listControls.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.topMargin: root.s(8)
                    anchors.bottomMargin: root.s(8)
                    anchors.leftMargin: root.s(13)
                    anchors.rightMargin: root.s(13)
                    spacing: root.s(6)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.displayNotesList

                    section.property: "sectionCategory"
                    section.criteria: ViewSection.FullString
                    section.delegate: Item {
                        id: groupHeader
                        required property string section
                        width: ListView.view ? ListView.view.width : 0
                        height: root.s(24)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: root.s(5)
                            anchors.verticalCenter: parent.verticalCenter
                            text: groupHeader.section
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.DemiBold
                            font.pixelSize: root.s(11)
                            color: groupHeader.section === I18n.t("quickactions.notes.pinned") ? ThemeBackend.mauve : ThemeBackend.subtext0
                        }
                    }

                    ScrollBar.vertical: ScrollBar {
                        width: root.s(4)
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: root.s(4)
                            radius: root.s(2)
                            color: ThemeBackend.surface2
                        }
                    }

                    delegate: Rectangle {
                        id: noteCard
                        required property var modelData
                        readonly property bool selected: root.isSelected(modelData.id)
                        readonly property string preview: String(modelData.content || "").slice(0, 700).replace(/\s+/g, " ").trim()
                        width: notesListView.width - root.s(6)
                        height: noteCopy.implicitHeight + root.s(18)
                        radius: root.s(10)
                        color: cardGlass.active ? "transparent" : (selected
                            ? Qt.alpha(ThemeBackend.mauve, 0.16)
                            : Qt.alpha(cardPointer.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0, ThemeBackend.elementOpacity))
                        border.width: 1
                        border.color: Qt.tint(ThemeBackend.surface0, Qt.alpha(selected ? ThemeBackend.mauve : ThemeBackend.text, selected ? 0.62 : 0.09))
                        clip: true
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                        Accessible.role: Accessible.Button
                        Accessible.name: noteTitle.text
                        Accessible.onPressAction: root.openNote(noteCard.modelData)

                        GlassFill {
                            id: cardGlass
                            anchors.fill: parent
                            radius: noteCard.radius
                            tintColor: noteCard.selected ? ThemeBackend.mauve : ThemeBackend.surface0
                            tintAmount: noteCard.selected ? 0.24 : 0.3
                            press: cardPointer.pressed ? 0.65 : (cardPointer.containsMouse ? 0.2 : 0)
                            Behavior on press { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        ColumnLayout {
                            id: noteCopy
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: root.s(9)
                            anchors.leftMargin: root.s(11)
                            anchors.rightMargin: root.s(11)
                            spacing: root.s(3)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)

                                Text {
                                    id: noteTitle
                                    text: noteCard.modelData.title || I18n.t("quickactions.notes.new_note_title")
                                    textFormat: Text.PlainText
                                    color: ThemeBackend.text
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(14)
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    visible: noteCard.selected || !!noteCard.modelData.pinned
                                    text: noteCard.selected ? "󰄬" : "󰐃"
                                    color: ThemeBackend.mauve
                                    font.family: root.nerdFont
                                    font.pixelSize: root.s(13)
                                }
                            }

                            Text {
                                visible: noteCard.preview.length > 0
                                Layout.fillWidth: true
                                text: noteCard.preview
                                textFormat: Text.PlainText
                                color: ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(12)
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: text.length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: root.s(2)
                                text: root.formatCardDate(noteCard.modelData.listTimestamp)
                                color: ThemeBackend.subtext1
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(10)
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: cardPointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            property real startY: 0
                            property bool dragging: false
                            property bool held: false

                            function finishDrag() {
                                preventStealing = false;
                                if (!dragging) return;
                                dragging = false;
                                root.isDraggingV = false;
                                root.expandProgress = root.expandProgress > 0.35 ? 1.0 : 0.0;
                                if (root.expandProgress === 0 && root.isEditing && root.editingNoteId === noteCard.modelData.id) {
                                    root.flushEdits();
                                    root.isEditing = false;
                                    root.editingNoteId = "";
                                }
                            }

                            onPressed: mouse => {
                                startY = mouse.y;
                                dragging = false;
                                held = false;
                            }
                            onPositionChanged: mouse => {
                                if (!(pressedButtons & Qt.LeftButton) || held) return;
                                const dy = mouse.y - startY;
                                if (!dragging && dy > root.s(6) && root.selectedCount === 0) {
                                    dragging = true;
                                    root.isDraggingV = true;
                                    preventStealing = true;
                                    root.loadNoteIntoEditor(noteCard.modelData);
                                }
                                if (dragging) root.expandProgress = Math.max(0, Math.min(1, dy / root.s(90)));
                            }
                            onReleased: mouse => {
                                if (dragging) finishDrag();
                                else if (!held && mouse.button === Qt.RightButton) root.toggleSelection(noteCard.modelData.id);
                                else if (!held && containsMouse) root.openNote(noteCard.modelData);
                            }
                            onCanceled: finishDrag()
                            onPressAndHold: mouse => {
                                if (!dragging && mouse.button === Qt.LeftButton) {
                                    held = true;
                                    root.toggleSelection(noteCard.modelData.id);
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: notesListView.count === 0
                    anchors.centerIn: notesListView
                    width: notesListView.width - root.s(24)
                    text: !root.stateLoaded ? "Loading notes…"
                        : root.searchQuery ? "No matching notes" : I18n.t("quickactions.notes.no_notes")
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(12)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }

            Item {
                id: editorView
                anchors.fill: parent
                visible: root.expandProgress > 0.001
                opacity: Math.max(0.0, (root.expandProgress - 0.15) / 0.85)
                scale: 0.96 + 0.04 * root.expandProgress
                transform: Translate { y: root.s(25) * (1.0 - root.expandProgress) }

                Rectangle {
                    id: editorCard
                    anchors.fill: parent
                    anchors.margins: root.s(8)
                    color: editorGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface1, ThemeBackend.elementOpacity)
                    radius: ThemeBackend.borderRadius
                    clip: true

                    GlassFill {
                        id: editorGlass
                        anchors.fill: parent
                        radius: parent.radius
                        tintColor: ThemeBackend.surface1
                        tintAmount: 0.3
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.s(8)
                        spacing: root.s(8)

                        Item {
                            id: editorHeaderBar
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(32)

                            RowLayout {
                                anchors.fill: parent
                                spacing: root.s(8)

                                CloseButton {
                                    id: closeBtn
                                    size: root.s(32)
                                    cornerRadius: root.s(8)
                                    iconFont: root.nerdFont
                                    iconFontSize: root.s(15)
                                    textColor: ThemeBackend.text
                                    accentColor: ThemeBackend.surface2
                                    bgOpacity: ThemeBackend.elementOpacity
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: root.saveCurrentNote()
                                }

                                Item {
                                    id: headerTitleArea
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    ColumnLayout {
                                        id: headerTitleCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0

                                        Text {
                                            text: root.isMarkdownPreview ? "Reading view" : "Notepad"
                                            color: ThemeBackend.text
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: root.s(12.5)
                                            font.bold: true
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: root.saveError || (root.editorDirty ? "Saving…" : "All changes saved")
                                            color: ThemeBackend.subtext0
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: root.s(9.5)
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: headerDragArea
                                        anchors.fill: parent
                                        hoverEnabled: true

                                        property real startY: 0
                                        property bool draggingV: false

                                        onPressed: mouse => {
                                            startY = mouse.y;
                                            draggingV = false;
                                            root.isDraggingV = false;
                                        }

                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            let dy = mouse.y - startY;
                                            if (!draggingV && dy > root.s(6)) {
                                                draggingV = true;
                                                root.isDraggingV = true;
                                                preventStealing = true;
                                            }
                                            if (draggingV) {
                                                let prog = Math.max(0.0, Math.min(1.0, 1.0 - (dy / root.s(90))));
                                                root.expandProgress = prog;
                                            }
                                        }

                                        onReleased: {
                                            preventStealing = false;
                                            if (draggingV) {
                                                root.isDraggingV = false;
                                                draggingV = false;
                                                if (root.expandProgress < 0.65) {
                                                    root.saveCurrentNote();
                                                } else {
                                                    root.expandProgress = 1.0;
                                                }
                                            }
                                        }

                                        onCanceled: {
                                            preventStealing = false;
                                            if (draggingV) {
                                                root.isDraggingV = false;
                                                draggingV = false;
                                                if (root.expandProgress < 0.65) {
                                                    root.saveCurrentNote();
                                                } else {
                                                    root.expandProgress = 1.0;
                                                }
                                            }
                                        }
                                    }
                                }

                                IconButton {
                                    id: pinBtn
                                    size: root.s(32)
                                    cornerRadius: root.s(8)
                                    iconFont: root.nerdFont
                                    iconFontSize: root.s(15)
                                    buttonIcon: "󰐃"
                                    textColor: root.editingNotePinned ? ThemeBackend.mauve : ThemeBackend.subtext0
                                    accentColor: root.editingNotePinned ? root.alpha(ThemeBackend.mauve, 0.2) : ThemeBackend.surface2
                                    bgOpacity: ThemeBackend.elementOpacity
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: { root.editingNotePinned = !root.editingNotePinned; root.scheduleSave(); }
                                }

                                IconButton {
                                    id: readingViewBtn
                                    size: root.s(32)
                                    cornerRadius: root.s(8)
                                    iconFont: root.nerdFont
                                    iconFontSize: root.s(15)
                                    buttonIcon: root.isMarkdownPreview ? "󰈙" : "󰂺"
                                    textColor: root.isMarkdownPreview ? ThemeBackend.mauve : ThemeBackend.subtext0
                                    accentColor: root.isMarkdownPreview ? root.alpha(ThemeBackend.mauve, 0.2) : ThemeBackend.surface2
                                    bgOpacity: ThemeBackend.elementOpacity
                                    Layout.alignment: Qt.AlignVCenter
                                    ToolTip.visible: readingViewBtn.isHoveredOrHighlighted
                                    ToolTip.text: "Reading view"
                                    onClicked: root.isMarkdownPreview = !root.isMarkdownPreview
                                }

                                ClickButton {
                                    id: saveBtn
                                    buttonText: I18n.t("quickactions.notes.save")
                                    buttonIcon: "󰄬"
                                    iconFont: root.nerdFont
                                    iconFontSize: root.s(13)
                                    textFontSize: root.s(12)
                                    accentColor: ThemeBackend.mauve
                                    bgOpacity: ThemeBackend.elementOpacity
                                    textColor: ThemeBackend.base
                                    cornerRadius: root.s(8)
                                    implicitHeight: root.s(32)
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: root.saveCurrentNote()
                                }
                            }
                        }

                        Item {
                            id: noteNameWrapper
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(34)

                            Input {
                                id: nameInput
                                anchors.fill: parent
                                baseColor: ThemeBackend.surface0
                                bgOpacity: ThemeBackend.elementOpacity
                                textColor: ThemeBackend.text
                                placeholderText: I18n.t("quickactions.notes.title_placeholder")
                                cornerRadius: root.s(8)
                                fontPixelSize: root.s(12)
                                leadingIcon: ""
                                showClearButton: true
                                onTextEdited: root.scheduleSave()
                                onCleared: root.scheduleSave()
                                visible: !root.isMarkdownPreview
                            }

                            Rectangle {
                                id: previewTitleBar
                                anchors.fill: parent
                                radius: root.s(8)
                                color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
                                visible: root.isMarkdownPreview

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.s(12)
                                    anchors.rightMargin: root.s(12)
                                    verticalAlignment: Text.AlignVCenter
                                    text: nameInput.text.trim().length > 0 ? nameInput.text.trim() : I18n.t("quickactions.notes.new_note_title")
                                    color: ThemeBackend.text
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(12.5)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(38)
                            color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
                            radius: root.s(8)
                            visible: !root.isMarkdownPreview
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(4)
                                spacing: root.s(2)
                                ComboBox {
                                    id: paragraphStylePicker
                                    objectName: "notepad-heading-picker"
                                    Layout.preferredWidth: Math.max(root.s(130), headingLabelMetrics.width + root.s(40))
                                    Layout.minimumWidth: implicitWidth
                                    Layout.fillHeight: true
                                    focusPolicy: Qt.NoFocus
                                    model: ["Normal", "Heading 1", "Heading 2", "Heading 3"]
                                    currentIndex: contentInput.paragraphStyle.heading || 0
                                    onActivated: index => root.applyFormat(String(index))
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(10)
                                    palette.text: ThemeBackend.text
                                    palette.buttonText: ThemeBackend.text
                                    palette.button: ThemeBackend.surface1
                                    palette.base: ThemeBackend.surface0
                                    palette.window: ThemeBackend.surface0
                                    palette.highlight: ThemeBackend.mauve
                                    ToolTip.visible: hovered
                                    ToolTip.text: "Paragraph style"
                                    TextMetrics {
                                        id: headingLabelMetrics
                                        font: paragraphStylePicker.font
                                        text: "Heading 3"
                                    }
                                    leftPadding: root.s(10)
                                    rightPadding: root.s(28)
                                    contentItem: Text {
                                        text: paragraphStylePicker.displayText
                                        font: paragraphStylePicker.font
                                        color: ThemeBackend.text
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                    indicator: Text {
                                        x: paragraphStylePicker.width - width - root.s(9)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "▾"
                                        color: ThemeBackend.subtext0
                                        font.pixelSize: root.s(11)
                                    }
                                    background: Rectangle {
                                        radius: root.s(5)
                                        color: paragraphStylePicker.hovered || paragraphStylePicker.down
                                            ? ThemeBackend.surface2 : ThemeBackend.surface1
                                    }
                                    delegate: ItemDelegate {
                                        required property var modelData
                                        required property int index
                                        width: paragraphStylePicker.popup.availableWidth
                                        height: root.s(34)
                                        leftPadding: root.s(12)
                                        rightPadding: root.s(12)
                                        highlighted: paragraphStylePicker.highlightedIndex === index
                                        hoverEnabled: true
                                        contentItem: Text {
                                            text: modelData
                                            font: paragraphStylePicker.font
                                            color: parent.highlighted ? ThemeBackend.mauve : ThemeBackend.text
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            radius: root.s(5)
                                            color: parent.highlighted ? Qt.alpha(ThemeBackend.mauve, 0.18)
                                                : parent.hovered ? ThemeBackend.surface1 : "transparent"
                                        }
                                    }
                                    popup: Popup {
                                        y: paragraphStylePicker.height + root.s(5)
                                        width: Math.max(paragraphStylePicker.width, root.s(164), headingLabelMetrics.width + root.s(40))
                                        padding: root.s(5)
                                        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
                                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                                        contentItem: ListView {
                                            clip: true
                                            implicitHeight: contentHeight
                                            model: paragraphStylePicker.popup.visible ? paragraphStylePicker.delegateModel : null
                                            currentIndex: paragraphStylePicker.highlightedIndex
                                            boundsBehavior: Flickable.StopAtBounds
                                        }
                                        background: Rectangle {
                                            radius: root.s(8)
                                            color: ThemeBackend.surface0
                                            border.width: 1
                                            border.color: ThemeBackend.surface2
                                        }
                                    }
                                }
                                Repeater {
                                    model: [
                                        { label: "B", kind: "bold", tip: "Bold · Ctrl+B" },
                                        { label: "I", kind: "italic", tip: "Italic · Ctrl+I" },
                                        { label: "U", kind: "underline", tip: "Underline · Ctrl+U" },
                                        { label: "•", kind: "bullet", tip: "Bulleted list · Ctrl+Shift+L" },
                                        { label: "1.", kind: "number", tip: "Numbered list" }
                                    ]
                                    delegate: Button {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.minimumWidth: root.s(22)
                                        focusPolicy: Qt.NoFocus
                                        readonly property bool formatActive: modelData.kind === "bold" ? contentInput.isBold
                                            : modelData.kind === "italic" ? contentInput.isItalic
                                            : modelData.kind === "underline" ? contentInput.isUnderline
                                            : modelData.kind === "bullet" ? contentInput.paragraphStyle.bullet === true
                                            : modelData.kind === "number" ? contentInput.paragraphStyle.number === true : false
                                        text: modelData.label
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: root.s(12)
                                        font.bold: modelData.kind === "bold"
                                        font.italic: modelData.kind === "italic"
                                        font.underline: modelData.kind === "underline"
                                        ToolTip.visible: hovered
                                        ToolTip.text: modelData.tip
                                        background: Rectangle {
                                            radius: root.s(5)
                                            color: parent.formatActive ? Qt.alpha(ThemeBackend.mauve, 0.24)
                                                : parent.down || parent.hovered ? ThemeBackend.surface1 : "transparent"
                                        }
                                        contentItem: Text {
                                            text: parent.text
                                            font: parent.font
                                            opacity: parent.enabled ? 1 : 0.35
                                            color: parent.formatActive ? ThemeBackend.mauve : ThemeBackend.text
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: root.applyFormat(modelData.kind)
                                    }
                                }
                            }
                        }

                        Item {
                            id: editorContent
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RichNoteEditor {
                                id: contentInput
                                objectName: "rich-note-editor"
                                anchors.fill: parent
                                baseColor: ThemeBackend.surface0
                                bgOpacity: ThemeBackend.elementOpacity
                                textColor: ThemeBackend.text
                                placeholderText: I18n.t("quickactions.notes.content_placeholder")
                                cornerRadius: root.s(8)
                                fontPixelSize: root.s(14)
                                onFormatRequested: kind => root.applyFormat(kind)
                                onPasteRequested: root.pasteIntoNote()
                                onTextEdited: root.contentEdited()
                                visible: !root.isMarkdownPreview
                            }

                            Rectangle {
                                id: previewContainer
                                anchors.fill: parent
                                color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
                                radius: root.s(8)
                                visible: root.isMarkdownPreview

                                Flickable {
                                    id: previewFlickable
                                    anchors.fill: parent
                                    anchors.margins: root.s(10)
                                    contentWidth: width
                                    contentHeight: previewText.height
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true

                                    ScrollBar.vertical: ScrollBar {
                                        active: previewFlickable.moving || previewFlickable.movingVertically
                                        width: root.s(4)
                                        policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle {
                                            implicitWidth: root.s(4)
                                            radius: root.s(2)
                                            color: ThemeBackend.surface2
                                        }
                                    }

                                    Text {
                                        id: previewText
                                        width: previewFlickable.width
                                        visible: root.isMarkdownPreview
                                        textFormat: Text.RichText
                                        text: contentInput.text
                                        color: ThemeBackend.text
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: root.s(12)
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: !root.isMarkdownPreview
                            text: {
                                let content = contentInput.text; // track document edits
                                let plain = contentInput.plainText().trim();
                                return (plain ? plain.split(/\s+/).length : 0) + " words  ·  Rich text  ·  Autosave on";
                            }
                            color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(9)
                            leftPadding: root.s(4)
                        }
                    }
                }
            }
        }
    }
}
