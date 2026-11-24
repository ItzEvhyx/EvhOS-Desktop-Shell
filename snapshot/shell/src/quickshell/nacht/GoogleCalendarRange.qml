import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Scope {
    id: root

    property bool calendarVisible: false
    property date firstDay
    readonly property string rangeKey: Number.isFinite(firstDay.getTime()) ? dayKey(firstDay) : ""
    readonly property bool connected: NachtCalendar.authorized && NachtCalendar.operation !== "connect"
        && NachtCalendar.operation !== "disconnect"
    readonly property bool loading: connected && rangeKey !== "" && loadedKey !== rangeKey && message === ""
    property string message: ""

    property var days: ({})
    property string loadedKey: ""
    property int accountRevision: 0

    onCalendarVisibleChanged: if (calendarVisible) Qt.callLater(refresh)
    onRangeKeyChanged: {
        message = "";
        Qt.callLater(refresh);
    }
    onConnectedChanged: {
        accountRevision++;
        days = ({});
        loadedKey = "";
        message = "";
        if (connected) Qt.callLater(refresh);
    }

    function dayKey(day) {
        return day.getFullYear() + "-" + String(day.getMonth() + 1).padStart(2, "0")
            + "-" + String(day.getDate()).padStart(2, "0");
    }

    function dayAt(offset) {
        return new Date(firstDay.getFullYear(), firstDay.getMonth(), firstDay.getDate() + offset);
    }

    function eventsFor(key) {
        return connected && loadedKey === rangeKey ? days[key] || [] : [];
    }

    function refresh() {
        if (!calendarVisible || !connected || !rangeKey || fetcher.running) return;
        fetcher.requestKey = rangeKey;
        fetcher.accountRevision = accountRevision;
        fetcher.command = ["python3", NachtCalendar.helperPath, "agenda",
            firstDay.toISOString(), dayAt(42).toISOString()];
        fetcher.running = true;
    }

    function publish(events) {
        const grouped = {};
        for (let index = 0; index < 42; index++) {
            const day = dayAt(index);
            const key = dayKey(day);
            const start = day.getTime();
            const end = dayAt(index + 1).getTime();
            const matching = events.filter(event => event.allDay
                ? event.startDate <= key && event.endDate > key
                : event.startMs < end && event.endMs > start);
            if (matching.length) {
                matching.sort((a, b) => Number(b.allDay) - Number(a.allDay)
                    || (a.startMs || 0) - (b.startMs || 0) || a.title.localeCompare(b.title));
                grouped[key] = matching;
            }
        }
        days = grouped;
        loadedKey = rangeKey;
        message = "";
    }

    Process {
        id: fetcher
        property string requestKey: ""
        property int accountRevision: 0
        stdout: StdioCollector { id: response }

        onExited: function(exitCode, _exitStatus) {
            if (!root.connected) return;
            if (accountRevision !== root.accountRevision || requestKey !== root.rangeKey) {
                Qt.callLater(root.refresh);
                return;
            }
            try {
                if (exitCode !== 0) throw new Error("Calendar helper exited");
                const data = JSON.parse(response.text);
                if (!Array.isArray(data.events)) {
                    root.message = data.operationError || "Could not refresh Google Calendar.";
                    return;
                }
                root.publish(data.events);
            } catch (error) {
                root.message = "Could not refresh Google Calendar.";
            }
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.calendarVisible && root.connected
        onTriggered: root.refresh()
    }
}
