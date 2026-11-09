"""Fail-closed merged APK permission check for the isolated Cloud500 PDF Lab.

Only reads aapt's actual APK permission dump. No Owner files or credentials.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REQUIRED = frozenset({
    "android.permission.INTERNET",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
})
FORBIDDEN = frozenset({
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
})
_PERMISSION_LINE = re.compile(
    r"^\s*uses-permission(?:-sdk-23)?:\s+name='([^']+)'", re.MULTILINE
)
_REQUIRED_HARDWARE = re.compile(
    r"^\s*uses-feature:\s+name='android\.hardware\.(?:camera(?:\.[^']*)?|microphone)'",
    re.MULTILINE,
)


def validate_permissions(aapt_output: str, aapt_badging: str = "") -> frozenset[str]:
    """Reject missing functional permissions and inherited sensitive permissions."""
    declared = frozenset(_PERMISSION_LINE.findall(aapt_output))
    missing = sorted(REQUIRED - declared)
    forbidden = sorted(FORBIDDEN & declared)
    if missing:
        raise ValueError("LAB_MERGED_PERMISSION_REQUIRED_MISSING=" + ",".join(missing))
    if forbidden:
        raise ValueError("LAB_MERGED_PERMISSION_FORBIDDEN=" + ",".join(forbidden))
    if _REQUIRED_HARDWARE.search(aapt_badging):
        raise ValueError("LAB_UNNEEDED_REQUIRED_HARDWARE_FEATURE")
    return declared


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: issue13_lab_permission_gate.py AAPT_PERMISSION_DUMP AAPT_BADGING_DUMP", file=sys.stderr)
        return 2
    try:
        permissions = validate_permissions(
            Path(argv[1]).read_text(encoding="utf-8"),
            Path(argv[2]).read_text(encoding="utf-8"),
        )
    except (OSError, ValueError) as exc:
        print(f"LAB_MERGED_PERMISSION_MINIMUM_GATE=FAIL {exc}", file=sys.stderr)
        return 1
    print("LAB_MERGED_PERMISSION_MINIMUM_GATE=PASS")
    print("LAB_DECLARED_PERMISSIONS=" + ",".join(sorted(permissions)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
