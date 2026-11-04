#!/usr/bin/env python3
"""G0ah: isolated MuPDF decoded UTF-8 text window audit, never award authority."""
import hashlib
import pathlib
import re
import sys

TOKEN = re.compile(r"(?<![0-9])[0-9]{8}(?![0-9])")


def audit(directory: pathlib.Path, start: int, count: int) -> str:
    if not directory.is_dir() or directory.is_symlink() or count != 512 or start < 1:
        raise ValueError("G0AH_WINDOW_ARGUMENT_INVALID")
    files = list(directory.iterdir())
    if len(files) != count:
        raise ValueError("G0AH_PAGE_GAP_OR_EXTRA")
    if any(p.is_symlink() or not p.is_file() for p in files):
        raise ValueError("G0AH_PAGE_SET_OR_SYMLINK")
    expected_names = {f"page-{page}.txt" for page in range(start, start + count)}
    if {p.name for p in files} != expected_names:
        raise ValueError("G0AH_PAGE_GAP_OR_EXTRA")
    manifest = hashlib.sha256()
    total_bytes = 0
    token_count = 0
    pages_with_tokens = 0
    page_terminators = 0
    increases = decreases = equals = 0
    last = None
    for page in range(start, start + count):
        raw = (directory / f"page-{page}.txt").read_bytes()
        if not 0 < len(raw) <= 262144:
            raise ValueError("G0AH_EMPTY_OR_OVERSIZE_PAGE")
        total_bytes += len(raw)
        if total_bytes > 134217728:
            raise ValueError("G0AH_TOTAL_OUTPUT_BOUND")
        try:
            decoded = raw.decode("utf-8", errors="strict")
        except UnicodeDecodeError as exc:
            raise ValueError("G0AH_INVALID_UTF8") from exc
        # MuPDF may append one structural form feed at the end of a page.
        # Reject embedded/repeated controls and U+FFFD; hash original bytes.
        if decoded.endswith("\f\r\n"):
            text = decoded[:-3]
            page_terminators += 1
        elif decoded.endswith("\f\n"):
            text = decoded[:-2]
            page_terminators += 1
        elif decoded.endswith("\f"):
            text = decoded[:-1]
            page_terminators += 1
        else:
            text = decoded
        bad = next((c for c in text if c == "\ufffd" or
                    (ord(c) < 32 and c not in "\n\r\t")), None)
        if bad is not None:
            kind = "REPLACEMENT" if bad == "\ufffd" else "CONTROL"
            raise ValueError(f"G0AH_REPLACEMENT_OR_CONTROL kind={kind} "
                             f"codepoint=U+{ord(bad):04X} page={page}")
        candidates = TOKEN.findall(text)
        if len(candidates) > 8192:
            raise ValueError("G0AH_TOKEN_COUNT_BOUND")
        if candidates:
            pages_with_tokens += 1
        token_count += len(candidates)
        for candidate in candidates:
            value = int(candidate)
            if last is not None:
                increases += value > last
                decreases += value < last
                equals += value == last
            last = value
        manifest.update(f"{page}:{len(raw)}:{hashlib.sha256(raw).hexdigest()}\n".encode("ascii"))
    if token_count == 0:
        raise ValueError("G0AH_NO_EIGHT_DIGIT_LEXICAL_CANDIDATES")
    ordering = "MIXED_OR_HEADER_CONTAMINATION"
    if not decreases:
        ordering = "NONDECREASING_LEXICAL_ONLY"
    elif not increases:
        ordering = "NONINCREASING_LEXICAL_ONLY"
    return (f"G0AH_TEXT_WINDOW pages={count} utf8_pages={count} "
            f"pages_with_eight_digit_candidates={pages_with_tokens} "
            f"eight_digit_candidates={token_count} increases={increases} "
            f"decreases={decreases} equals={equals} order={ordering} "
            f"bytes={total_bytes} terminal_formfeed_pages={page_terminators} "
            f"text_manifest_sha256={manifest.hexdigest()} "
            "UNICODE_SEMANTICS=UNPROVEN AWARD_RECORDS=UNVERIFIED GLOBAL_NOT_WIN=HOLD")


def main() -> int:
    if len(sys.argv) != 4:
        print("G0AH_ARGUMENT_COUNT", file=sys.stderr)
        return 64
    try:
        result = audit(pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]))
    except (ValueError, OSError) as exc:
        code = str(exc)
        if not code.startswith("G0AH_"):
            code = "G0AH_FILE_IO_FAILURE"
        print(code, file=sys.stderr)
        return 49
    print(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
