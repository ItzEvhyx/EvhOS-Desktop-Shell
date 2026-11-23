#!/usr/bin/env python3
"""Record a Hyprland output. A line or EOF on stdin requests a graceful stop."""

import argparse
from datetime import datetime
import fcntl
from html import escape
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
from time import monotonic, time
from uuid import uuid4


def report(kind, **details):
    try:
        os.write(sys.stdout.fileno(), (json.dumps({"type": kind, **details}) + "\n").encode())
    except BrokenPipeError:
        return False
    return True


def publish_recording(path, ended_early):
    if report("saved", path=str(path), endedEarly=ended_early):
        return
    # The shell closed or reloaded before the capture was finalized.
    command = [sys.executable, __file__, "--notify-saved", str(path), "--ended-early"]
    try:
        subprocess.Popen(
            command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def notify_saved(path, ended_early):
    title = "Recording Ended Early" if ended_early else "Recording Stopped"
    body = escape(f"Click to play\n{path}", quote=False)
    try:
        result = subprocess.run(
            ["notify-send", "-a", "EvhOS Recorder", "-i", "media-record",
             "--action=default=Play recording", "--", title, body],
            stdout=subprocess.PIPE, text=True,
        )
        if result.returncode == 0 and result.stdout.strip() == "default":
            subprocess.Popen(
                ["xdg-open", str(path)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, start_new_session=True,
            )
        return result.returncode
    except OSError as error:
        print(error, file=sys.stderr)
        return 1


def recordings_folder():
    home = Path.home()
    videos = home / "Videos"
    if shutil.which("xdg-user-dir"):
        result = subprocess.run(["xdg-user-dir", "VIDEOS"], capture_output=True, text=True, timeout=3)
        configured = Path(result.stdout.strip())
        if result.returncode == 0 and configured.is_absolute() and configured != home:
            videos = configured
    return videos / "Recordings"


def playback_source():
    result = subprocess.run(["pactl", "get-default-sink"], capture_output=True, text=True, timeout=4)
    sink = result.stdout.strip()
    if result.returncode != 0 or not sink:
        raise RuntimeError("No system playback device was found. Check that PipeWire audio is running.")
    return f"{sink}.monitor"


def recording_commands(monitor, source, capture_path):
    if shutil.which("gpu-screen-recorder"):
        yield ["gpu-screen-recorder", "-w", monitor, "-f", "30", "-c", "mp4", "-k", "h264",
               "-a", "default_output", "-ac", "aac", "-o", str(capture_path)]
    if shutil.which("wf-recorder"):
        yield ["wf-recorder", "-o", monitor, "-D", "-r", "30", "-c", "libx264", "-p", "preset=ultrafast",
               "-p", "crf=22", "-C", "aac", f"--audio={source}", "-f", str(capture_path)]


class StopRequest:
    def __init__(self, control):
        self.selector = control
        self.requested = False

    def from_signal(self, _signum, _frame):
        self.requested = True

    def wait(self, seconds):
        if not self.requested and self.selector.select(seconds):
            os.read(sys.stdin.fileno(), 4096)
            self.requested = True
        return self.requested


def stop_encoder(encoder):
    encoder.send_signal(signal.SIGINT)
    try:
        encoder.wait(timeout=15)
    except subprocess.TimeoutExpired:
        encoder.kill()
        encoder.wait()


def capture(command, capture_path, stop):
    started = False
    with tempfile.TemporaryFile() as log:
        encoder = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        try:
            deadline = monotonic() + 8
            while encoder.poll() is None:
                if stop.wait(0.2):
                    break
                if not started:
                    if capture_path.is_file():
                        started = True
                        report("recording", startedAt=int(time() * 1000))
                    elif monotonic() >= deadline:
                        break
        finally:
            if encoder.poll() is None:
                stop_encoder(encoder)
        log.seek(max(0, log.seek(0, os.SEEK_END) - 8192))
        diagnostics = log.read().decode(errors="replace").splitlines()
    errors = [line.strip() for line in diagnostics if "error" in line.lower() or "failed" in line.lower()]
    detail = (errors or [f"Encoder exit code {encoder.returncode}."])[-1]
    return started, detail[:250]


def playable_capture(path):
    if not path.is_file():
        return False
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=codec_type:format=duration", "-of", "json", str(path)],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0:
        return False
    metadata = json.loads(result.stdout)
    tracks = {track["codec_type"] for track in metadata.get("streams", []) if "codec_type" in track}
    try:
        duration = float(metadata.get("format", {}).get("duration", 0))
    except ValueError:
        return False
    return {"video", "audio"} <= tracks and duration > 0


def record(monitor, stop):
    if stop.wait(0):
        report("cancelled")
        return
    source = playback_source()
    folder = recordings_folder()
    folder.mkdir(parents=True, exist_ok=True)
    failures = []

    with tempfile.TemporaryDirectory(prefix=".evhos-recording-", dir=folder) as staging:
        partial = Path(staging) / "capture.mp4"
        for command in recording_commands(monitor, source, partial):
            if stop.wait(0):
                report("cancelled")
                return
            try:
                started, detail = capture(command, partial, stop)
            except OSError as error:
                failures.append(str(error))
                continue

            if playable_capture(partial):
                timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
                output = folder / f"Recording-{timestamp}-{uuid4().hex[:8]}.mp4"
                partial.rename(output)
                publish_recording(output, ended_early=not stop.requested)
                return

            if stop.requested:
                if started:
                    raise RuntimeError("The recording ended before a playable MP4 with audio could be saved.")
                report("cancelled")
                return

            failures.append(f"{command[0]}: {detail}")
            partial.unlink(missing_ok=True)
            if started:
                break

    if not failures:
        raise RuntimeError("Install GPU Screen Recorder or wf-recorder to enable recording.")
    raise RuntimeError("A playable recording with system audio could not be saved. " + failures[-1])


def serve(monitor):
    with selectors.PollSelector() as control:
        control.register(sys.stdin, selectors.EVENT_READ)
        stop = StopRequest(control)
        signal.signal(signal.SIGINT, stop.from_signal)
        signal.signal(signal.SIGTERM, stop.from_signal)
        try:
            cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "evhos"
            cache.mkdir(parents=True, exist_ok=True)
            with (cache / "screen-recorder.lock").open("a") as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise RuntimeError("A recording is already running or still being saved.") from None
                record(monitor, stop)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            report("error", message=str(error))
            return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("monitor", nargs="?", help="Hyprland output to capture")
    parser.add_argument("--notify-saved", type=Path, metavar="MP4", help="Show a notification that plays the saved MP4")
    parser.add_argument("--ended-early", action="store_true", help="Mark the saved recording as interrupted")
    args = parser.parse_args()
    if args.notify_saved:
        return notify_saved(args.notify_saved, args.ended_early)
    if not args.monitor:
        parser.error("Specify a Hyprland output to capture.")

    # Quickshell may kill its Process during a reload. The supervisor survives,
    # sees the control pipe close, and gives the encoder time to finish the MP4.
    supervisor = os.fork()
    if supervisor == 0:
        os.setsid()
        return serve(args.monitor)

    def forward(signum, _frame):
        try:
            os.kill(supervisor, signum)
        except ProcessLookupError:
            pass

    signal.signal(signal.SIGINT, forward)
    signal.signal(signal.SIGTERM, forward)
    _, status = os.waitpid(supervisor, 0)
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    raise SystemExit(main())
