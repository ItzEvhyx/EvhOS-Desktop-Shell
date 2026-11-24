#!/usr/bin/env python3
"""Exercise Nacht's Google event normalization and offline cache behavior."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "nacht_calendar", ROOT / "snapshot/shell/src/quickshell/nacht/google_calendar.py"
)
calendar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(calendar)


def meeting(**fields):
    return {
        "id": "standup",
        "summary": "Team stand-up",
        "start": {"dateTime": "2026-11-23T10:00:00+08:00"},
        "end": {"dateTime": "2026-11-23T10:30:00+08:00"},
        "htmlLink": "https://calendar.google.com/calendar/event?eid=standup",
        **fields,
    }


class NachtCalendarTests(unittest.TestCase):
    def test_reads_video_entry_point_before_pasted_link(self):
        event = meeting(
            description="https://meet.google.com/abc-defg-hij",
            conferenceData={
                "conferenceSolution": {"name": "Video call"},
                "entryPoints": [
                    {"entryPointType": "phone", "uri": "tel:5555555"},
                    {"entryPointType": "video", "uri": "https://example.org/meeting"},
                ],
            },
        )
        result = calendar.normalize_event(event)
        self.assertEqual(result["joinUrl"], "https://example.org/meeting")
        self.assertEqual(result["provider"], "Video call")
        self.assertEqual(result["endMs"] - result["startMs"], 30 * 60_000)

    def test_pasted_meet_and_timezone(self):
        event = meeting(
            start={"dateTime": "2026-11-23T10:00:00", "timeZone": "Asia/Manila"},
            location="Join here: https://meet.google.com/abc-defg-hij",
        )
        result = calendar.normalize_event(event)
        self.assertEqual(result["provider"], "Google Meet")
        self.assertEqual(result["joinUrl"], "https://meet.google.com/abc-defg-hij")
        self.assertEqual(result["location"], "")
        self.assertEqual(result["startMs"], 1_795_399_200_000)

    def test_in_person_event_uses_calendar_url(self):
        result = calendar.normalize_event(meeting(location="Lab 3"))
        self.assertEqual(result["location"], "Lab 3")
        self.assertTrue(result["isMeeting"])
        self.assertEqual(result["joinUrl"], "")
        self.assertTrue(result["eventUrl"].startswith("https://calendar.google.com/"))

    def test_plain_timed_event_can_be_opened_in_calendar(self):
        result = calendar.normalize_event(meeting(summary="test event"))
        self.assertEqual(result["title"], "test event")
        self.assertFalse(result["isMeeting"])
        self.assertEqual(result["joinUrl"], "")
        self.assertEqual(result["eventUrl"], "https://calendar.google.com/calendar/event?eid=standup")

        empty_title = calendar.normalize_event(meeting(summary="", location="Online"))
        self.assertEqual(empty_title["title"], "Calendar event")
        self.assertEqual(empty_title["location"], "")

    def test_google_legacy_calendar_url_can_open_the_event(self):
        link = "https://www.google.com/calendar/event?eid=standup"
        result = calendar.normalize_event(meeting(htmlLink=link))
        self.assertEqual(result["eventUrl"], link)
        redirect = calendar.normalize_event(meeting(htmlLink="https://www.google.com/url?q=https://other.test"))
        self.assertEqual(redirect["eventUrl"], "")

    def test_unsafe_video_link_does_not_hide_the_event(self):
        result = calendar.normalize_event(meeting(hangoutLink="file:///etc/hosts"))
        self.assertEqual(result["joinUrl"], "")
        self.assertTrue(result["eventUrl"])

    def test_excludes_unavailable_or_nonstandard_occurrences(self):
        for fields in (
            {"status": "cancelled"},
            {"eventType": "focusTime"},
            {"attendees": [{"self": True, "responseStatus": "declined"}]},
            {"start": {"date": "2026-11-23"}},
        ):
            with self.subTest(fields=fields):
                self.assertIsNone(calendar.normalize_event(meeting(**fields)))

    def test_removes_unsafe_calendar_action(self):
        result = calendar.normalize_event(meeting(location="Lab 3", htmlLink="https://calendar.google.com@other.test/"))
        self.assertEqual(result["eventUrl"], "")

    def test_paginates_recurring_instances(self):
        pages = [
            {"nextPageToken": "more", "items": [meeting(id="instance-1", location="Lab 3")]},
            {"items": [meeting(id="instance-2", location="Lab 3")]},
        ]
        with patch.object(calendar, "request_json", side_effect=pages) as request:
            result = calendar.fetch_events("unused")
        self.assertEqual([item["id"] for item in result], ["instance-1", "instance-2"])
        self.assertIn("singleEvents=true", request.call_args_list[0].args[0])
        self.assertIn("pageToken=more", request.call_args_list[1].args[0])

    def test_agenda_retains_multiday_all_day_and_special_entries(self):
        all_day = meeting(start={"date": "2026-11-23"}, end={"date": "2026-11-25"},
                          eventType="outOfOffice")
        result = calendar.normalize_agenda_event(all_day)
        self.assertTrue(result["allDay"])
        self.assertEqual(result["startDate"], "2026-11-23")
        self.assertEqual(result["endDate"], "2026-11-25")
        self.assertTrue(result["eventUrl"])
        self.assertIsNone(calendar.normalize_event(all_day))
        self.assertIsNone(calendar.normalize_agenda_event({**all_day, "status": "cancelled"}))

    def test_agenda_includes_events_outside_reminder_eligibility(self):
        declined = meeting(attendees=[{"self": True, "responseStatus": "declined"}])
        result = calendar.normalize_agenda_event(declined)
        self.assertFalse(result["allDay"])
        self.assertEqual(result["endMs"] - result["startMs"], 30 * 60_000)
        self.assertIsNone(calendar.normalize_event(declined))
        self.assertIsNone(calendar.normalize_agenda_event(meeting(end={"date": "2026-11-25"})))

    def test_agenda_fetch_expands_recurrences_over_the_requested_month(self):
        start = calendar.datetime.fromisoformat("2026-10-26T00:00:00+08:00")
        end = calendar.datetime.fromisoformat("2026-12-07T00:00:00+08:00")
        pages = [
            {"nextPageToken": "more", "items": [meeting(id="instance-1")]},
            {"items": [meeting(id="instance-2", start={"date": "2026-11-30"},
                               end={"date": "2026-12-01"})]},
        ]
        with patch.object(calendar, "request_json", side_effect=pages) as request:
            events = calendar.fetch_agenda("unused", start, end)
        self.assertEqual([event["id"] for event in events], ["instance-1", "instance-2"])
        query = calendar.parse_qs(calendar.urlsplit(request.call_args_list[0].args[0]).query)
        self.assertEqual(query["singleEvents"], ["true"])
        self.assertEqual(query["showDeleted"], ["false"])
        self.assertEqual(query["timeMin"], ["2026-10-24T00:00:00+08:00"])
        self.assertEqual(query["timeMax"], ["2026-12-09T00:00:00+08:00"])

    def test_outline_restore_accepts_current_and_older_templates(self):
        scripts = ROOT / "snapshot/home/.config/hypr/scripts"
        script = scripts / "restore-serp-notch-outline.py"
        modern = (scripts / "serpantinum-balanced-topbar.qml").read_text()
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            topbar = home / ".local/share/serpantinum/src/quickshell/bar/TopBar.qml"
            topbar.parent.mkdir(parents=True)
            env = {**os.environ, "HOME": str(home)}
            topbar.write_text(modern)
            self.assertEqual(subprocess.run([script], env=env).returncode, 0)
            self.assertEqual(topbar.read_text(), modern)

            topbar.write_text("import QtQuick.Controls\n    ShaderEffect {\n        id: leftOuterCorner\n")
            self.assertEqual(subprocess.run([script], env=env).returncode, 10)
            self.assertEqual(topbar.read_text().count("id: notchOutline"), 1)
            self.assertEqual(subprocess.run([script], env=env).returncode, 0)

    def test_offline_cache_expires_without_losing_account_state(self):
        now = 1_800_000_000_000
        cache = {"authorized": True, "lastSyncMs": now, "events": [{"id": "cached"}]}
        with patch.object(calendar, "epoch_ms", return_value=now + 3_600_000):
            self.assertEqual(len(calendar.state_view(cache, "offline")["events"]), 1)
        with patch.object(calendar, "epoch_ms", return_value=now + 3_600_001):
            state = calendar.state_view(cache, "offline")
            self.assertTrue(state["authorized"])
            self.assertEqual(state["events"], [])

    def test_revoked_access_drops_cached_meeting_details(self):
        cache = {"authorized": True, "lastSyncMs": calendar.epoch_ms(), "events": [{"id": "cached"}]}
        with (
            patch.object(calendar, "access_token", side_effect=calendar.CalendarError("Expired", "reauthorize")),
            patch.object(calendar, "write_private") as write,
        ):
            result = calendar.sync({}, cache)
        self.assertEqual(result["status"], "reauthorize")
        self.assertFalse(result["authorized"])
        self.assertEqual(result["events"], [])
        write.assert_called_once_with(calendar.CACHE, {})


if __name__ == "__main__":
    unittest.main()
