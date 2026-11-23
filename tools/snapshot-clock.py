#!/usr/bin/env python3
"""Create, classify, publish, and restore dated EvhOS desktop snapshots.

Snapshots are ordinary Git commits with durable tags. This keeps the history
auditable and restores the exact files that were captured without checking out
an older revision in the user's active repository.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT_PREFIX = "evhos/snapshot/"
STABLE_PREFIX = "evhos/stable/"
BROKEN_PREFIX = "evhos/broken/"
STABLE_CURRENT = "evhos/stable/current"


def git(*args: str, capture: bool = False) -> str:
    """Run git in this repository and return stdout when requested."""
    result = subprocess.run(
        ["git", "-C", str(ROOT), *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def command(*args: str, cwd: Path | None = None) -> None:
    subprocess.run(args, check=True, cwd=cwd or ROOT)


def ensure_repository() -> None:
    top_level = Path(git("rev-parse", "--show-toplevel", capture=True)).resolve()
    if top_level != ROOT.resolve():
        raise SystemExit(f"Run this tool from the EvhOS repository at {ROOT}.")


def clean_worktree() -> None:
    status = git("status", "--porcelain", "--untracked-files=normal", capture=True)
    if status:
        raise SystemExit(
            "Refusing to capture a mixed working tree. Commit, stash, or remove these changes first:\n"
            + status
        )


def maybe_commit(ref: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        text=True,
        capture_output=True,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def commit_for(ref: str) -> str:
    commit = maybe_commit(ref)
    if not commit:
        raise SystemExit(f"Cannot resolve snapshot or commit: {ref}")
    return commit


def tag_names(prefix: str) -> list[str]:
    output = git(
        "for-each-ref",
        "--sort=creatordate",
        "--format=%(refname:strip=2)",
        f"refs/tags/{prefix}",
        capture=True,
    )
    return [name for name in output.splitlines() if name]


def snapshot_tags() -> list[str]:
    return tag_names(SNAPSHOT_PREFIX)


def resolve_snapshot(value: str) -> tuple[str, str]:
    """Return a commit and a helpful display name for a stable/snapshot ref."""
    if value in {"latest-stable", "stable"}:
        value = STABLE_CURRENT
        if not maybe_commit(value):
            raise SystemExit(
                "No stable snapshot is marked yet. Capture a candidate, test it in a live session, "
                "then run `python3 tools/snapshot-clock.py mark-stable <snapshot> --confirmed`."
            )
    if value.startswith(SNAPSHOT_PREFIX) or value.startswith(STABLE_PREFIX) or value.startswith(BROKEN_PREFIX):
        return commit_for(value), value
    direct = maybe_commit(value)
    if direct:
        return direct, value
    matches = [tag for tag in snapshot_tags() if tag.removeprefix(SNAPSHOT_PREFIX).startswith(value)]
    if len(matches) == 1:
        return commit_for(matches[0]), matches[0]
    if len(matches) > 1:
        raise SystemExit("Snapshot name is ambiguous; choose one of:\n" + "\n".join(matches))
    raise SystemExit(f"No snapshot matches {value!r}. Run `python3 tools/snapshot-clock.py list`.")


def label_slug(label: str) -> str:
    slug = re.sub(r"[^a-z0-9._-]+", "-", label.lower()).strip("-.")[:48]
    if not slug:
        raise SystemExit("Snapshot label must contain a letter or number.")
    return slug


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


def ref_exists(name: str) -> bool:
    return maybe_commit(name) is not None


def tag(name: str, target: str, message: str, force: bool = False) -> None:
    args = ["tag"]
    if force:
        args.append("--force")
    args.extend(["--annotate", name, target, "--message", message])
    git(*args)


def sync() -> None:
    """Push the current branch and every EvhOS status tag to origin."""
    branch = git("branch", "--show-current", capture=True)
    if not branch:
        raise SystemExit("Cannot publish from a detached HEAD.")
    git("push", "origin", branch)
    for name in tag_names("evhos/"):
        args = ["push"]
        if name == STABLE_CURRENT:
            args.append("--force")
        args.extend(["origin", f"refs/tags/{name}:refs/tags/{name}"])
        git(*args)


def verify_snapshot(commit: str) -> None:
    """Run the full suite from an isolated worktree at the requested commit."""
    with tempfile.TemporaryDirectory(prefix="evhos-snapshot-check-") as temporary:
        worktree = Path(temporary) / "repository"
        git("worktree", "add", "--detach", str(worktree), commit)
        try:
            command(sys.executable, str(worktree / "tools/run-checks.py"), cwd=worktree)
        finally:
            git("worktree", "remove", "--force", str(worktree))


def capture(args: argparse.Namespace) -> None:
    clean_worktree()
    command(sys.executable, str(ROOT / "tools/capture-live.py"), "--apply")
    command(sys.executable, str(ROOT / "tools/run-checks.py"))
    command("git", "-C", str(ROOT), "add", "snapshot")
    pending = git("diff", "--cached", "--name-only", capture=True)
    if not pending:
        raise SystemExit("No desktop changes were captured; no snapshot was created.")
    label = label_slug(args.label)
    stamp = timestamp()
    git("commit", "--message", f"snapshot: {args.label} [{stamp}]")
    commit = commit_for("HEAD")
    snapshot = SNAPSHOT_PREFIX + f"{stamp}-{label}"
    tag(snapshot, commit, f"Candidate EvhOS snapshot: {args.label}\n\nCreated: {stamp} UTC")
    print(f"Created candidate snapshot {snapshot} at {commit[:12]}.")
    print("Log in and use the desktop before promoting it to stable.")
    if args.push:
        sync()


def stable_tags() -> list[str]:
    return [name for name in tag_names(STABLE_PREFIX) if name != STABLE_CURRENT]


def broken_commits() -> set[str]:
    return {commit_for(name) for name in tag_names(BROKEN_PREFIX)}


def promote(args: argparse.Namespace) -> None:
    if not args.confirmed:
        raise SystemExit(
            "Refusing to mark stable without --confirmed. First log in, check the bar, launcher, "
            "wallpaper, audio, network, lock screen, and monitor layout."
        )
    commit, display = resolve_snapshot(args.snapshot)
    verify_snapshot(commit)
    suffix = display.removeprefix(SNAPSHOT_PREFIX).replace("/", "-")
    historical = STABLE_PREFIX + suffix
    if not ref_exists(historical):
        tag(historical, commit, f"Stable EvhOS snapshot promoted from {display}")
    tag(STABLE_CURRENT, commit, f"Current stable EvhOS snapshot: {display}", force=True)
    print(f"Marked {display} as stable. Roll back with: python3 tools/snapshot-clock.py rollback --apply")
    if args.push:
        sync()


def mark_broken(args: argparse.Namespace) -> None:
    commit, display = resolve_snapshot(args.snapshot)
    reason = args.reason.strip()
    if not reason:
        raise SystemExit("Provide a short failure reason with --reason.")
    suffix = display.removeprefix(SNAPSHOT_PREFIX).replace("/", "-")
    broken = BROKEN_PREFIX + suffix
    tag(broken, commit, f"Broken EvhOS snapshot: {display}\n\nReason: {reason}", force=True)
    current = maybe_commit(STABLE_CURRENT)
    if current == commit:
        bad = broken_commits()
        earlier = [name for name in stable_tags() if commit_for(name) not in bad]
        if earlier:
            replacement = earlier[-1]
            tag(STABLE_CURRENT, commit_for(replacement), f"Current stable EvhOS snapshot: {replacement}", force=True)
            print(f"The current stable pointer moved back to {replacement}.")
        else:
            git("tag", "--delete", STABLE_CURRENT, capture=True)
            print("No known-good stable snapshot remains; the current stable pointer was removed.")
    print(f"Marked {display} as broken: {reason}")
    if args.push:
        sync()


def list_snapshots(_: argparse.Namespace) -> None:
    tags = snapshot_tags()
    if not tags:
        print("No snapshots yet. Create one with: python3 tools/snapshot-clock.py capture \"description\"")
        return
    stable = {commit_for(name) for name in stable_tags()}
    broken = broken_commits()
    current = maybe_commit(STABLE_CURRENT)
    print("SNAPSHOT\tCOMMIT\tSTATUS\tSUBJECT")
    for name in tags:
        commit = commit_for(name)
        if commit in broken:
            status = "broken"
        elif commit in stable or commit == current:
            status = "stable"
        else:
            status = "candidate"
        subject = git("log", "-1", "--format=%s", commit, capture=True)
        print(f"{name.removeprefix(SNAPSHOT_PREFIX)}\t{commit[:12]}\t{status}\t{subject}")
    if current:
        print(f"\nLATEST STABLE: {current[:12]} ({STABLE_CURRENT})")


def rollback(args: argparse.Namespace) -> None:
    commit, display = resolve_snapshot(args.snapshot)
    home = args.home.expanduser().resolve()
    if not args.apply:
        print(f"PLAN: would restore {display} ({commit[:12]}) into {home}.")
        print("No files changed. Re-run with --apply after reviewing the snapshot list.")
        return
    with tempfile.TemporaryDirectory(prefix="evhos-rollback-") as temporary:
        worktree = Path(temporary) / "repository"
        git("worktree", "add", "--detach", str(worktree), commit)
        try:
            command_args = [sys.executable, str(worktree / "restore.py"), "--home", str(home), "--apply"]
            if args.build_rich_notes:
                command_args.append("--build-rich-notes")
            command(*command_args, cwd=worktree)
        finally:
            git("worktree", "remove", "--force", str(worktree))
    print(f"Restored {display}. Replaced files were backed up under {home}/.local/state/evhos-backups/.")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)

    create = commands.add_parser("capture", help="capture the live desktop, test it, commit it, and tag it as a candidate")
    create.add_argument("label", help="short snapshot description")
    create.add_argument("--push", action="store_true", help="push the commit and EvhOS tags to origin")
    create.set_defaults(handler=capture)

    promote_parser = commands.add_parser("mark-stable", help="verify a candidate and make it the rollback default")
    promote_parser.add_argument("snapshot", help="candidate tag, unique prefix, commit, or latest-stable")
    promote_parser.add_argument("--confirmed", action="store_true", help="confirm that the snapshot worked in a live session")
    promote_parser.add_argument("--push", action="store_true", help="push the updated status tags to origin")
    promote_parser.set_defaults(handler=promote)

    broken = commands.add_parser("mark-broken", help="record a failed snapshot and fall back to the prior stable one")
    broken.add_argument("snapshot", help="candidate tag, unique prefix, or commit")
    broken.add_argument("--reason", required=True, help="brief explanation of the failure")
    broken.add_argument("--push", action="store_true", help="push the updated status tags to origin")
    broken.set_defaults(handler=mark_broken)

    show = commands.add_parser("list", help="show candidates, stable snapshots, and known-broken snapshots")
    show.set_defaults(handler=list_snapshots)

    restore = commands.add_parser("rollback", help="restore latest-stable or a named snapshot from an isolated worktree")
    restore.add_argument("snapshot", nargs="?", default="latest-stable", help="defaults to latest-stable")
    restore.add_argument("--home", type=Path, default=Path.home(), help="target home; useful for disposable testing")
    restore.add_argument("--apply", action="store_true", help="perform the restore; omitted means preview only")
    restore.add_argument("--build-rich-notes", action="store_true", help="also rebuild the rich-notes plugin")
    restore.set_defaults(handler=rollback)

    publish = commands.add_parser("sync", help="push the current branch and all EvhOS snapshot tags")
    publish.set_defaults(handler=lambda _: sync())
    return result


def main() -> None:
    args = parser().parse_args()
    ensure_repository()
    args.handler(args)


if __name__ == "__main__":
    main()
