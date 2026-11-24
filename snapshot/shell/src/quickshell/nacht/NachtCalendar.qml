pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../"
import "CalendarSchedule.js" as Schedule

Singleton {
    id: root

    property bool locked: false
    readonly property bool blocked: locked || PrivacyMode.active
    readonly property string screenName: (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
        || (Quickshell.screens.length ? Quickshell.screens[0].name : "")
    readonly property var bar: BarGeometry.bars[screenName] || null
    readonly property bool workspaceEmpty: bar !== null && bar.workspaceEmpty === true
    readonly property color accent: "#a68af6"
    readonly property bool hasTopBar: !blocked && bar !== null
        && bar.position === "top" && !bar.fullscreen
    readonly property bool canAttach: hasTopBar && bar.notchBottom > 0
    readonly property bool attached: shown !== null && canAttach
    property real overlayWidth: 0
    readonly property bool eventNear: events.some(event => event.endMs > wallNow
        && event.startMs > wallNow - 600000 && event.startMs <= wallNow + 3600000)
    readonly property int syncInterval: syncBackoff || (eventNear ? 5000 : 15000)
    readonly property bool busy: operation !== ""
    readonly property bool opening: opener.running
    readonly property var upcoming: {
        const endOfDay = new Date(wallNow);
        endOfDay.setHours(24, 0, 0, 0);
        return wallNow - lastSyncMs <= 3600000
            ? events.filter(event => event.endMs > wallNow && event.startMs < endOfDay.getTime()) : [];
    }

    property string status: "loading"
    property string message: ""
    property bool authorized: false
    property double lastSyncMs: 0
    property var events: []
    property var shown: null
    readonly property bool expanded: shown !== null && expandedKey !== ""
    property string actionError: ""

    property string operation: ""
    property string expandedKey: ""
    property bool timedCard: false
    property bool hovered: false
    property string notedKey: ""
    property bool historyReady: false
    property bool waitingForRefresh: false
    property int syncBackoff: 0
    property double wallNow: Date.now()
    readonly property string helperPath: Quickshell.shellDir + "/nacht/google_calendar.py"
    readonly property string historyPath: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/serpantinum/nacht/history.json"

    PersistentProperties {
        id: saved
        reloadableId: "nacht-calendar-v1"
        property var history: ({})
        property string pendingReplay: ""
    }

    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: false
        printErrors: false
        blockWrites: true
        atomicWrites: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data && typeof data === "object" && !Array.isArray(data))
                    saved.history = Object.assign({}, data, saved.history);
            } catch (error) {
                console.warn("Nacht: could not read reminder delivery history.");
            }
            root.historyReady = true;
            root.refreshDisplay();
        }
        onLoadFailed: {
            root.historyReady = true;
            root.refreshDisplay();
        }
        onSaveFailed: console.warn("Nacht: could not save reminder delivery history.")
    }

    Timer {
        interval: 100
        running: root.status === "loading" && !root.busy
        onTriggered: root.run("status")
    }
    Connections {
        target: saved
        function onLoaded() { root.notedKey = saved.pendingReplay }
    }

    onBlockedChanged: {
        if (blocked) {
            expandedKey = "";
            refreshDisplay();
        } else {
            refreshAfterResume();
        }
    }
    onWorkspaceEmptyChanged: {
        if (workspaceEmpty && notedKey && !blocked) refreshDisplay();
    }

    function run(action, argument) {
        if (busy || backend.running) return false;
        if (action !== "sync") message = "";
        operation = action;
        backend.command = ["python3", helperPath, action].concat(argument ? [argument] : []);
        backend.running = true;
        return true;
    }

    function importClient(url) {
        run("configure", String(url));
    }

    function disconnect() {
        run("disconnect");
    }

    function applyResult(result, action) {
        if (result.operationError) {
            message = result.operationError;
            if (status === "loading") status = "error";
            return;
        }
        status = result.status;
        message = result.message || "";
        authorized = result.authorized === true;
        lastSyncMs = result.lastSyncMs || 0;
        events = result.events || [];
        if (action === "disconnect" && status === "disconnected") {
            saved.history = ({});
            updateReplay(false);
            writeHistory();
        }
    }

    function updateReplay(useCurrent) {
        notedKey = useCurrent && shown && !workspaceEmpty ? shown.key : "";
        saved.pendingReplay = notedKey;
    }

    function writeHistory() {
        if (lastSyncMs > 0 || status === "disconnected")
            historyFile.setText(JSON.stringify(saved.history));
    }

    function record(items, opened) {
        if (!items.length) return;
        saved.history = Schedule.updateHistory(saved.history, items, opened, wallNow);
        writeHistory();
    }

    function refreshAfterResume() {
        if (!blocked && authorized)
            waitingForRefresh = run("sync") || operation === "sync";
        refreshDisplay();
    }

    function refreshDisplay() {
        wallNow = Date.now();
        if (blocked || !authorized || !historyReady || wallNow - lastSyncMs > 3600000) {
            expandedKey = "";
            shown = null;
            autoClose.stop();
            return;
        }

        const active = Schedule.activeMeetings(events, wallNow, saved.history);
        if (!waitingForRefresh) {
            const due = active.filter(item => item.stage > item.delivered);
            if (due.length) {
                record(due, false);
                showCard(due[0], true);
                if (notedKey && workspaceEmpty) updateReplay(false);
                return;
            }

            if (notedKey) {
                const replay = active.find(item => item.key === notedKey);
                if (!replay) updateReplay(false);
                else if (workspaceEmpty) {
                    updateReplay(false);
                    showCard(replay, true);
                    return;
                }
            }
        }

        const current = active.find(item => item.key === expandedKey);
        if (!current) {
            expandedKey = "";
            autoClose.stop();
        }
        shown = current || active.find(item => item.stage >= Schedule.early) || null;
    }

    function showCard(item, timed) {
        expandedKey = item.key;
        shown = item;
        actionError = "";
        timedCard = timed;
        if (timed && !hovered) autoClose.restart();
        else autoClose.stop();
    }

    function collapse() {
        timedCard = false;
        expandedKey = "";
        autoClose.stop();
        refreshDisplay();
    }

    function acknowledge() {
        updateReplay(true);
        collapse();
    }

    function expand() {
        if (shown) showCard(shown, false);
    }

    function activate(event, openCalendar) {
        if (opener.running) return;
        actionError = "";
        const join = !openCalendar && !!event.joinUrl;
        const url = join ? event.joinUrl : event.eventUrl;
        if (!url || !/^https:\/\//.test(url)) return;
        opener.event = join ? event : null;
        opener.command = ["gio", "open", url];
        opener.running = true;
    }

    function formatStart(value) {
        return Qt.formatTime(new Date(value), "h:mm AP");
    }

    function timeRange(event) {
        const start = new Date(event.startMs);
        const end = new Date(event.endMs);
        const samePeriod = start.toDateString() === end.toDateString()
            && (start.getHours() < 12) === (end.getHours() < 12);
        const startTime = formatStart(event.startMs);
        return (samePeriod ? startTime.replace(/\s+\S+$/, "") : startTime)
            + " – " + formatStart(event.endMs);
    }

    function countdown(value) {
        return Schedule.counter(value - wallNow);
    }

    Process {
        id: backend
        stdout: StdioCollector { id: response }
        onExited: function(exitCode, _exitStatus) {
            const action = root.operation;
            let synced = false;
            try {
                if (exitCode !== 0) throw new Error("Calendar helper unavailable");
                const result = JSON.parse(response.text);
                root.applyResult(result, action);
                synced = result.status === "connected";
            } catch (error) {
                root.message = "Could not run the Nacht Calendar helper.";
                if (root.status === "loading") root.status = "error";
            }
            if (synced) root.syncBackoff = 0;
            else if (action === "sync" && root.authorized)
                root.syncBackoff = Math.min(120000, Math.max(30000, 2 * root.syncBackoff));
            root.operation = "";
            root.waitingForRefresh = false;
            if ((action === "status" || action === "configure") && root.authorized)
                Qt.callLater(root.refreshAfterResume);
            else root.refreshDisplay();
        }
    }

    Process {
        id: opener
        property var event: null
        onExited: function(exitCode, _exitStatus) {
            if (exitCode === 0 && event && event.joinUrl) {
                root.record([{ key: Schedule.keyFor(event), stage: Schedule.stageFor(event, root.wallNow) }], true);
                if (root.notedKey === Schedule.keyFor(event)) root.updateReplay(false);
                if (root.expandedKey === Schedule.keyFor(event)) root.collapse();
                else root.refreshDisplay();
            } else if (exitCode !== 0) {
                root.actionError = "Could not open the browser. Try again.";
            }
            event = null;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.authorized
        onTriggered: {
            if (Date.now() - root.wallNow > 5000) root.refreshAfterResume();
            else root.refreshDisplay();
        }
    }
    Timer {
        interval: root.syncInterval
        repeat: true
        running: root.authorized && !root.blocked
        onTriggered: root.run("sync")
    }
    Timer {
        id: autoClose
        interval: 6000
        onTriggered: root.collapse()
    }

    function hover(present) {
        hovered = present;
        if (present) autoClose.stop();
        else if (expanded && timedCard && !autoClose.running) autoClose.restart();
    }

    IpcHandler {
        target: "nachtCalendar"
        function status(): string { return root.status; }
        function state(): string {
            return JSON.stringify({
                stage: root.shown ? root.shown.stage : 0, expanded: root.expanded,
                screen: root.screenName, attached: root.attached, pollInterval: root.syncInterval,
                empty: root.workspaceEmpty, authorized: root.authorized, syncing: root.busy,
                countdown: root.shown ? root.countdown(root.shown.event.startMs) : ""
            });
        }
    }
}
