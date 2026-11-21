#!/usr/bin/env python3
"""G0ag: fail-closed full qpdf page-to-content-reference custody; not PDF text proof."""
import hashlib
import re
import sys
PAGE = re.compile(rb"page ([1-9][0-9]*): ([1-9][0-9]*) ([0-9]+) R\r?\n?")
CONTENT = re.compile(rb"[ \t]*content:[ \t]*\r?\n?")
REF = re.compile(rb"[ \t]+([1-9][0-9]*) ([0-9]+) R[ \t]*\r?\n?")
def main():
    if len(sys.argv) != 2:
        return 64
    try: expected = int(sys.argv[1])
    except ValueError: return 64
    if not 1 <= expected <= 87000: return 64
    count = 0
    size = 0
    refs_count = 0
    pages, contents = set(), set()
    digest = hashlib.sha256()
    current = None
    page_contents = []
    in_content = False
    def finish():
        nonlocal refs_count
        if current is None: return True
        if not in_content or not page_contents:
            print("G0AG_MISSING_CONTENT_REFERENCE", file=sys.stderr)
            return False
        refs_count += len(page_contents)
        ordinal, obj, gen = current
        encoded = ",".join(f"{o}:{g}" for o, g in page_contents)
        digest.update(f"{ordinal}:{obj}:{gen}|{encoded}\n".encode("ascii"))
        return True
    for raw in sys.stdin.buffer:
        size += len(raw)
        if len(raw) > 512 or size > 32 * 1024 * 1024:
            print("G0AG_OUTPUT_BOUND", file=sys.stderr); return 49
        if not raw.strip(): continue
        match = PAGE.fullmatch(raw)
        if match:
            if not finish(): return 49
            ordinal, obj, gen = map(int, match.groups())
            if ordinal != count + 1 or count >= expected or (obj, gen) in pages:
                print("G0AG_PAGE_ORDER_OR_DUPLICATE", file=sys.stderr); return 49
            pages.add((obj, gen))
            count += 1
            current = (ordinal, obj, gen)
            page_contents = []
            in_content = False
        elif CONTENT.fullmatch(raw):
            if current is None or in_content:
                print("G0AG_CONTENT_SECTION_ORDER", file=sys.stderr); return 49
            in_content = True
        else:
            match = REF.fullmatch(raw)
            if not match or current is None or not in_content:
                print("G0AG_UNEXPECTED_QPDF_OUTPUT", file=sys.stderr); return 49
            identity = tuple(map(int, match.groups()))
            if identity in contents or identity in pages or len(page_contents) >= 16:
                print("G0AG_CONTENT_DUPLICATE_OR_BOUND", file=sys.stderr); return 49
            contents.add(identity)
            page_contents.append(identity)
    if not finish(): return 49
    if count != expected or refs_count < expected or len(contents) != refs_count or pages.intersection(contents):
        print("G0AG_INCOMPLETE_CONTENT_GRAPH", file=sys.stderr); return 49
    print(f"G0AG_GRAPH pages={count} page_refs={len(pages)} content_refs={refs_count} graph_sha256={digest.hexdigest()}")
    return 0
if __name__ == "__main__":
    sys.exit(main())
