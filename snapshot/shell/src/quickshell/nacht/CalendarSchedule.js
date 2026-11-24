.pragma library

const minute = 60000;
const preview = 1;
const early = 2;
const started = 3;

function keyFor(event) {
    return JSON.stringify([event.id, event.startMs]);
}

function stageFor(event, now) {
    if (!Number.isFinite(event.startMs) || !Number.isFinite(event.endMs)
            || event.endMs <= event.startMs || now >= event.endMs) {
        return 0;
    }

    const remaining = event.startMs - now;
    if (remaining > 20 * minute || remaining <= -10 * minute) return 0;
    if (remaining > 10 * minute) return preview;
    return remaining > 0 ? early : started;
}

function activeMeetings(events, now, history) {
    const active = [];
    for (const event of events) {
        const stage = stageFor(event, now);
        const key = keyFor(event);
        const previous = history[key];
        if (stage && !(previous && previous.opened)) {
            active.push({ event, key, stage, delivered: previous ? previous.delivered : 0 });
        }
    }
    return active.sort((a, b) => b.stage - a.stage || a.event.startMs - b.event.startMs || a.key.localeCompare(b.key));
}

function updateHistory(history, items, opened, now) {
    const next = {};
    for (const key of Object.keys(history)) {
        if (history[key].at > now - 3 * 24 * 60 * minute) next[key] = history[key];
    }
    for (const item of items) {
        next[item.key] = { delivered: item.stage, opened: opened, at: now };
    }
    return next;
}

function counter(ms) {
    const seconds = Math.max(0, Math.ceil(ms / 1000));
    return String(Math.floor(seconds / 60)).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
}
