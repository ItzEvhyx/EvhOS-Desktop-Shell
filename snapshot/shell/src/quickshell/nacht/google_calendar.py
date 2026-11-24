#!/usr/bin/env python3
"""Read the primary Google calendar for Nacht. Credentials remain in Secret Service."""
import argparse
import base64
from datetime import date, datetime, timedelta, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
from time import monotonic, time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, unquote, urlencode, urlsplit
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
REVOKE_URL = "https://oauth2.googleapis.com/revoke"
EVENTS_URL = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
SCOPE = "https://www.googleapis.com/auth/calendar.events.owned.readonly"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "serpantinum/nacht"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "serpantinum/nacht"
CLIENT = CONFIG / "google-client.json"
CACHE = STATE / "calendar.json"
MAX_CACHE_AGE_MS = 3_600_000
MEET_URL = re.compile(r'https://meet\.google\.com/(?:[a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/[\w-]+)(?![\w/-])', re.I)
WEB_URL = re.compile(r'https?://', re.I)


class CalendarError(Exception):
    def __init__(self, message, status="error"):
        super().__init__(message)
        self.status = status


def epoch_ms():
    return int(time() * 1000)


def read_object(path):
    try:
        with path.open() as source:
            value = json.load(source)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write_private(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as temp:
        temporary_path = Path(temp.name)
        try:
            json.dump(value, temp, ensure_ascii=True)
            temp.close()
            temporary_path.replace(path)
        finally:
            temporary_path.unlink(missing_ok=True)


def client_info(path=CLIENT):
    client = read_object(path).get("installed")
    if not isinstance(client, dict) or not isinstance(client.get("client_id"), str) or not client["client_id"].endswith(".apps.googleusercontent.com"):
        raise CalendarError("Choose a Google Desktop app OAuth client JSON.", "needsClient")
    if not isinstance(client.get("client_secret"), str) or not client["client_secret"]:
        raise CalendarError("The Google Desktop app client JSON is incomplete.", "needsClient")
    return {name: client[name] for name in ("client_id", "client_secret")}


def keyring(action, client, payload=None):
    profile = hashlib.sha256(client["client_id"].encode()).hexdigest()
    args = ["secret-tool", action]
    if action == "store":
        args.append("--label=Nacht the Notch · Google Calendar")
    args.extend(["application", "evhos-nacht-calendar", "profile", profile])
    try:
        result = subprocess.run(args, input=payload, capture_output=True, text=True, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CalendarError("The Linux keyring is unavailable. Check Secret Service and try again.") from error
    if result.returncode == 0:
        return result.stdout.strip()
    if action in ("lookup", "clear") and result.returncode == 1 and not result.stderr.strip():
        return ""
    raise CalendarError("Could not access the Linux keyring. Unlock it and try again.")


def request_json(url, form=None, bearer=None):
    headers = {"Accept": "application/json"}
    if bearer:
        headers["Authorization"] = "Bearer " + bearer
    request = Request(url, data=urlencode(form).encode() if form is not None else None, headers=headers)
    try:
        with urlopen(request, timeout=12) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except HTTPError as error:
        try:
            detail = json.loads(error.read())
        except (ValueError, OSError):
            detail = {}
        if isinstance(detail, dict) and detail.get("error") == "invalid_grant":
            raise CalendarError("Google access expired. Reconnect your account.", "reauthorize") from error
        if error.code == 401:
            raise CalendarError("Google could not authorize Calendar access.", "unauthorized") from error
        if error.code == 403:
            raise CalendarError("Google denied Calendar access. Check that the API is enabled and permitted by your Workspace.") from error
        if error.code in (429, 500, 502, 503, 504):
            raise CalendarError("Google Calendar is temporarily unavailable.", "offline") from error
        raise CalendarError(f"Google Calendar request failed (HTTP {error.code}).") from error
    except (URLError, OSError, ValueError) as error:
        raise CalendarError("Could not reach Google Calendar.", "offline") from error


def parse_timestamp(info):
    value = info.get("dateTime")
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=ZoneInfo(info["timeZone"]))
        return int(parsed.timestamp() * 1000)
    except (ValueError, KeyError, ZoneInfoNotFoundError, OverflowError, OSError):
        return None


def clean_text(value, limit):
    return " ".join(value.split())[:limit] if isinstance(value, str) else ""


def https_link(value):
    if not isinstance(value, str) or any(ord(char) < 33 or ord(char) == 127 for char in value) or "\\" in value:
        return ""
    try:
        parts = urlsplit(value)
        if parts.scheme == "https" and parts.hostname and parts.username is None and parts.password is None:
            return value
    except ValueError:
        pass
    return ""


def normalize_event(event):
    if event.get("status") == "cancelled" or event.get("eventType", "default") != "default":
        return None
    start = parse_timestamp(event.get("start") or {})
    end = parse_timestamp(event.get("end") or {})
    identifier = event.get("id")
    if start is None or end is None or end <= start or not isinstance(identifier, str) or not identifier:
        return None
    attendees = event.get("attendees") or []
    if any(person.get("self") and person.get("responseStatus") == "declined" for person in attendees):
        return None

    conference = event.get("conferenceData") or {}
    link = next((uri for point in conference.get("entryPoints", []) if point.get("entryPointType") == "video"
                 and (uri := https_link(point.get("uri")))), "")
    if not link:
        link = https_link(event.get("hangoutLink"))
    if not link:
        for value in (event.get("location"), event.get("description")):
            match = MEET_URL.search(value) if isinstance(value, str) else None
            if match and https_link(match.group()):
                link = match.group()
                break
    provider = clean_text((conference.get("conferenceSolution") or {}).get("name"), 60)
    if link and urlsplit(link).hostname == "meet.google.com":
        provider = "Google Meet"

    location = clean_text(event.get("location"), 150)
    if WEB_URL.search(location) or location.casefold() in {"online", "virtual", "remote", "tbd", "google meet", "zoom", "teams"}:
        location = ""
    guests = any(not person.get("self") and not person.get("resource") for person in attendees)
    is_meeting = bool(link or location or guests)

    return {
        "id": identifier, "startMs": start, "endMs": end,
        "title": clean_text(event.get("summary"), 250) or ("Meeting" if is_meeting else "Calendar event"),
        "location": location, "provider": (provider or "Video meeting") if link else "",
        "joinUrl": link, "eventUrl": calendar_event_url(event), "isMeeting": is_meeting,
    }


def calendar_event_url(event):
    link = https_link(event.get("htmlLink"))
    if not link:
        return ""
    page = urlsplit(link)
    if page.hostname == "calendar.google.com" or (
        page.hostname == "www.google.com" and page.path == "/calendar/event"
    ):
        return link
    return ""


def normalize_agenda_event(event):
    identifier = event.get("id")
    if event.get("status") == "cancelled" or not isinstance(identifier, str) or not identifier:
        return None
    start = event.get("start") or {}
    end = event.get("end") or {}
    if "date" in start and "date" in end:
        try:
            first = date.fromisoformat(start["date"])
            last = date.fromisoformat(end["date"])
        except (TypeError, ValueError):
            return None
        if first >= last:
            return None
        period = {"allDay": True, "startDate": first.isoformat(), "endDate": last.isoformat()}
    else:
        first = parse_timestamp(start)
        last = parse_timestamp(end)
        if first is None or last is None or first >= last:
            return None
        period = {"allDay": False, "startMs": first, "endMs": last}
    return {
        "id": identifier, "title": clean_text(event.get("summary"), 250) or "Calendar event",
        "location": clean_text(event.get("location"), 150),
        "eventUrl": calendar_event_url(event), **period,
    }


def events_between(access, start, end, fields, normalize):
    params = {
        "singleEvents": "true", "showDeleted": "false", "orderBy": "startTime", "maxResults": 250,
        "timeMin": start.isoformat(timespec="seconds"),
        "timeMax": end.isoformat(timespec="seconds"),
        "fields": "nextPageToken,items(" + fields + ")",
    }
    events = []
    seen_pages = set()
    while True:
        page = request_json(EVENTS_URL + "?" + urlencode(params), bearer=access)
        for item in page.get("items", []):
            event = normalize(item)
            if event:
                events.append(event)
        token = page.get("nextPageToken")
        if not token:
            return events
        if token in seen_pages:
            raise CalendarError("Google Calendar returned a duplicate page.")
        seen_pages.add(token)
        params["pageToken"] = token


def fetch_events(access):
    now = datetime.now(timezone.utc)
    return events_between(access, now, now + timedelta(days=2),
                          "id,status,eventType,summary,start,end,attendees(self,resource,responseStatus),location,description,conferenceData,hangoutLink,htmlLink",
                          normalize_event)


def fetch_agenda(access, start, end):
    # All-day bounds are interpreted in the calendar's zone by Google. The grid
    # clips to its own dates after this padded fetch, including across zone changes.
    padding = timedelta(days=2)
    return events_between(access, start - padding, end + padding,
                          "id,status,summary,start,end,location,htmlLink", normalize_agenda_event)


def grant_auth(client):
    state = secrets.token_urlsafe(32)
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    callback = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            parts = urlsplit(self.path)
            values = parse_qs(parts.query)
            if parts.path != "/" or not secrets.compare_digest(values.get("state", [""])[0], state):
                self.send_error(400, "Invalid Nacht callback")
                return
            callback.update(values)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(b"Nacht received the Google response. You can close this tab.")

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        redirect = f"http://127.0.0.1:{server.server_port}/"
        query = urlencode({
            "client_id": client["client_id"], "redirect_uri": redirect, "response_type": "code",
            "scope": SCOPE, "state": state, "code_challenge": challenge, "code_challenge_method": "S256",
            "access_type": "offline", "prompt": "consent select_account",
        })
        try:
            launched = subprocess.run(["gio", "open", AUTH_URL + "?" + query], capture_output=True, timeout=12, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise CalendarError("Could not open the browser for Google sign-in.") from error
        if launched.returncode != 0:
            raise CalendarError("Could not open the browser for Google sign-in.")
        deadline = monotonic() + 180
        server.timeout = 1
        while not callback and monotonic() < deadline:
            server.handle_request()
    if not callback:
        raise CalendarError("Google sign-in timed out. Try connecting again.")
    if not callback.get("code"):
        raise CalendarError("Google sign-in was canceled or blocked by Workspace policy.")
    token = request_json(TOKEN_URL, {
        **client, "code": callback["code"][0], "grant_type": "authorization_code",
        "redirect_uri": redirect, "code_verifier": verifier,
    })
    if not token.get("refresh_token"):
        raise CalendarError("Google did not grant offline access. Try connecting again.")
    return store_token(client, token, token["refresh_token"])


def store_token(client, token, refresh):
    access = token.get("access_token")
    if not isinstance(access, str) or not access:
        raise CalendarError("Google returned an incomplete sign-in response.")
    expiry = epoch_ms() + int(token.get("expires_in", 0)) * 1000
    keyring("store", client, json.dumps({"refresh": token.get("refresh_token") or refresh, "access": access, "expiry": expiry}))
    return access


def access_token(client, force=False):
    raw = keyring("lookup", client)
    stored = json.loads(raw) if raw else {}
    refresh = stored.get("refresh")
    if not refresh:
        raise CalendarError("Connect your Google account to sync events.", "reauthorize")
    if not force and stored.get("expiry", 0) > epoch_ms() + 60_000 and stored.get("access"):
        return stored["access"]
    token = request_json(TOKEN_URL, {**client, "refresh_token": refresh, "grant_type": "refresh_token"})
    return store_token(client, token, refresh)


def state_view(cache, status, message=""):
    synced = cache.get("lastSyncMs", 0)
    return {
        "status": status, "message": message, "authorized": bool(cache.get("authorized")),
        "lastSyncMs": synced,
        "events": cache.get("events", []) if synced and epoch_ms() - synced <= MAX_CACHE_AGE_MS else [],
    }


def fetch_authorized(client, fetch, access=None):
    access = access or access_token(client)
    try:
        return fetch(access)
    except CalendarError as error:
        if error.status != "unauthorized":
            raise
    return fetch(access_token(client, force=True))


def sync(client, cache, access=None):
    try:
        events = fetch_authorized(client, fetch_events, access)
    except CalendarError as error:
        if error.status in ("reauthorize", "unauthorized"):
            write_private(CACHE, {})
            return state_view({}, "reauthorize", "Reconnect your Google account to resume Calendar sync.")
        return state_view(cache, error.status, str(error))

    cache = {"authorized": True, "lastSyncMs": epoch_ms(), "events": events}
    write_private(CACHE, cache)
    return state_view(cache, "connected")


def execute(args):
    cache = read_object(CACHE)
    if args.command == "configure":
        location = urlsplit(args.path)
        if location.scheme and (location.scheme != "file" or location.netloc not in ("", "localhost")):
            raise CalendarError("Choose a local Google Desktop app OAuth client JSON.")
        path = Path(unquote(location.path)) if location.scheme else Path(args.path)
        client = client_info(path)
        if cache.get("authorized") and client_info()["client_id"] != client["client_id"]:
            raise CalendarError("Disconnect the active account before replacing its OAuth client.")
        write_private(CLIENT, {"installed": client})
        return state_view(cache, "connected" if cache.get("authorized") else "disconnected")

    client = client_info()
    if args.command == "status":
        return state_view(cache, "connected" if cache.get("authorized") else "disconnected")
    if args.command == "agenda":
        if not cache.get("authorized"):
            return {"events": []}
        try:
            first = datetime.fromisoformat(args.path)
            end = datetime.fromisoformat(args.end)
        except (TypeError, ValueError) as error:
            raise CalendarError("Could not read the selected calendar month.") from error
        if not first.tzinfo or not end.tzinfo or not timedelta(0) < end - first <= timedelta(days=44):
            raise CalendarError("Could not read the selected calendar month.")
        return {"events": fetch_authorized(client, lambda access: fetch_agenda(access, first, end))}
    if args.command == "connect":
        access = grant_auth(client)
        cache = {"authorized": True}
        write_private(CACHE, cache)
        return sync(client, cache, access)
    if args.command == "disconnect":
        raw = keyring("lookup", client)
        keyring("clear", client)
        CACHE.unlink(missing_ok=True)
        refresh = (json.loads(raw) if raw else {}).get("refresh")
        if refresh:
            try:
                request_json(REVOKE_URL, {"token": refresh})
            except CalendarError:
                return state_view({}, "disconnected", "Disconnected locally. Google could not confirm revocation.")
        return state_view({}, "disconnected")

    return sync(client, cache) if cache.get("authorized") else state_view(cache, "disconnected")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("status", "configure", "connect", "sync", "disconnect", "agenda"))
    parser.add_argument("path", nargs="?")
    parser.add_argument("end", nargs="?")
    args = parser.parse_args()
    if args.command == "configure" and not args.path:
        parser.error("configure requires the desktop client JSON path")
    try:
        result = execute(args)
    except CalendarError as error:
        if args.command in ("configure", "agenda"):
            # These operations have their own result and don't change reminder sync state.
            result = {"operationError": str(error)}
        else:
            result = state_view(read_object(CACHE), error.status, str(error))
    except (OSError, ValueError, TypeError):
        result = {"operationError": "Could not read or save Nacht’s local Calendar configuration."}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
