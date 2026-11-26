"""Prevent analyzer dependency lockfile drift from a floating Flutter SDK."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANALYZE = ROOT / '.github/workflows/issue_13_analyze_evidence.yml'
ANDROID = ROOT / '.github/workflows/flutter_android_ci.yml'


def flutter_versions(path: Path) -> list[str]:
    return re.findall(
        r"(?m)^\s*flutter-version:\s*['\"]([^'\"]+)['\"]\s*$",
        path.read_text(encoding='utf-8'),
    )


class AnalyzeToolchainTest(unittest.TestCase):
    def test_analyzer_pinned_to_all_android_ci_sdk_versions(self):
        android_versions = flutter_versions(ANDROID)
        analyze_versions = flutter_versions(ANALYZE)
        self.assertGreaterEqual(len(android_versions), 2)
        self.assertEqual(len(set(android_versions)), 1)
        self.assertEqual(analyze_versions, [android_versions[0]])

    def test_lockfile_enforcement_is_not_bypassed(self):
        workflow = ANALYZE.read_text(encoding='utf-8')
        self.assertIn('flutter pub get --enforce-lockfile', workflow)
        self.assertIn('git diff --exit-code -- pubspec.lock', workflow)
        self.assertIn('set -euo pipefail', workflow)
        self.assertNotIn('flutter pub get --no-enforce-lockfile', workflow)

    def test_analyzer_remains_a_failing_gate(self):
        workflow = ANALYZE.read_text(encoding='utf-8')
        self.assertIn('flutter analyze 2>&1 | tee flutter-analyze.log', workflow)
        self.assertIn('set -o pipefail', workflow)
        self.assertIn('if-no-files-found: error', workflow)


if __name__ == '__main__':
    unittest.main()
