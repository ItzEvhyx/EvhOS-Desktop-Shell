#!/usr/bin/env python3
"""Exercise snapshot tag resolution and broken-version fallback without a live desktop."""
import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / 'tools' / 'snapshot-clock.py'
spec = importlib.util.spec_from_file_location('snapshot_clock', SOURCE)
clock = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clock)


class SnapshotClockTest(unittest.TestCase):
    def git(self, root, *args):
        return subprocess.run(['git', '-C', str(root), *args], check=True, text=True, capture_output=True).stdout.strip()

    def test_resolve_and_mark_broken_removes_only_stable_pointer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.git(root, 'init', '--initial-branch=main')
            self.git(root, 'config', 'user.name', 'EvhOS test')
            self.git(root, 'config', 'user.email', 'test@example.invalid')
            (root / 'snapshot.txt').write_text('candidate\n')
            self.git(root, 'add', 'snapshot.txt')
            self.git(root, 'commit', '-m', 'snapshot: test')
            original_root = clock.ROOT
            clock.ROOT = root
            try:
                commit = clock.commit_for('HEAD')
                candidate = 'evhos/snapshot/20261123-120000-test'
                clock.tag(candidate, commit, 'candidate')
                resolved, display = clock.resolve_snapshot('20261123-120000-test')
                self.assertEqual(resolved, commit)
                self.assertEqual(display, candidate)
                clock.tag('evhos/stable/20261123-120000-test', commit, 'stable')
                clock.tag(clock.STABLE_CURRENT, commit, 'current stable')
                with contextlib.redirect_stdout(io.StringIO()):
                    clock.mark_broken(argparse.Namespace(snapshot='20261123-120000-test', reason='test failure', push=False))
                self.assertEqual(clock.commit_for('evhos/broken/20261123-120000-test'), commit)
                self.assertIsNone(clock.maybe_commit(clock.STABLE_CURRENT))
            finally:
                clock.ROOT = original_root

    def test_rollback_plan_does_not_write_a_home(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.git(root, 'init', '--initial-branch=main')
            self.git(root, 'config', 'user.name', 'EvhOS test')
            self.git(root, 'config', 'user.email', 'test@example.invalid')
            (root / 'snapshot.txt').write_text('candidate\n')
            self.git(root, 'add', 'snapshot.txt')
            self.git(root, 'commit', '-m', 'snapshot: test')
            original_root = clock.ROOT
            clock.ROOT = root
            try:
                candidate = 'evhos/snapshot/20261123-120000-test'
                clock.tag(candidate, clock.commit_for('HEAD'), 'candidate')
                target_home = root / 'unwritten-home'
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    clock.rollback(argparse.Namespace(snapshot='20261123-120000-test', home=target_home, apply=False, build_rich_notes=False))
                self.assertIn('PLAN: would restore', output.getvalue())
                self.assertFalse(target_home.exists())
            finally:
                clock.ROOT = original_root


if __name__ == '__main__':
    unittest.main()
