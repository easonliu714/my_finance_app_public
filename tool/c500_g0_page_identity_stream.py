#!/usr/bin/env python3
"""G0af: streaming qpdf --show-pages page identity custody, not content proof."""
import hashlib
import re
import sys

PAGE = re.compile(r"page ([0-9]+): ([1-9][0-9]*) ([0-9]+) R")
AUX = re.compile(r"\s*(?:content:|[0-9]+ [0-9]+ R)?")

def main() -> int:
    if len(sys.argv) != 2:
        print("G0AF_EXPECTED_COUNT_REQUIRED", file=sys.stderr)
        return 64
    try:
        expected = int(sys.argv[1])
    except ValueError:
        return 64
    if not 1 <= expected <= 87000:
        return 64
    count = 0
    total_bytes = 0
    seen = set()
    digest = hashlib.sha256()
    for raw in sys.stdin.buffer:
        total_bytes += len(raw)
        if len(raw) > 512 or total_bytes > 16 * 1024 * 1024:
            print("G0AF_OUTPUT_LIMIT", file=sys.stderr)
            return 49
        try:
            line = raw.decode("ascii").rstrip("\r\n")
        except UnicodeDecodeError:
            print("G0AF_NONASCII_OUTPUT", file=sys.stderr)
            return 49
        match = PAGE.fullmatch(line)
        if match:
            ordinal, obj, gen = map(int, match.groups())
            identity = (obj, gen)
            if ordinal != count + 1 or count >= expected or identity in seen:
                print("G0AF_ORDINAL_OR_IDENTITY_VIOLATION", file=sys.stderr)
                return 49
            seen.add(identity)
            count += 1
            digest.update(f"{ordinal}:{obj}:{gen}\n".encode("ascii"))
        elif not AUX.fullmatch(line):
            print("G0AF_UNEXPECTED_QPDF_LINE", file=sys.stderr)
            return 49
    if count != expected:
        print("G0AF_INCOMPLETE_PAGE_ENUMERATION", file=sys.stderr)
        return 49
    print(f"G0AF_ENUM count={count} unique_page_refs={len(seen)} identity_sha256={digest.hexdigest()}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
