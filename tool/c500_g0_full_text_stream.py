#!/usr/bin/env python3
"""G0ai: full 164K-page SHA-pinned MuPDF UTF-8 coverage, not award authority."""
import hashlib
import os
import pathlib
import re
import resource
import shutil
import subprocess
import sys
import tempfile
from c500_g0_decoded_text_window_audit import audit

SOURCES = (
    ("115-05-06", "G0_OLD_PDF", 119769589,
     "1efe4dcc5af410c9b5cfaf3ca605c2b8aea1e9259a4f16ebd8f8b9ea7110d0fe", 77000),
    ("115-07-08", "G0_NEW_PDF", 135200798,
     "f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571", 87000),
)
WINDOW = 512
VM_BYTES = 3 * 1024**3
FILE_BYTES = 256 * 1024

def verify_source(path, expected_bytes, expected_sha):
    if path.is_symlink() or not path.is_file() or path.stat().st_size != expected_bytes:
        raise ValueError("G0AI_SOURCE_MISSING_SYMLINK_OR_SIZE")
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != expected_sha:
        raise ValueError("G0AI_SOURCE_SHA_MISMATCH")

def limits():
    resource.setrlimit(resource.RLIMIT_AS, (VM_BYTES, VM_BYTES))
    resource.setrlimit(resource.RLIMIT_FSIZE, (FILE_BYTES, FILE_BYTES))

def scan_period(period, source, pages, engine="mutool"):
    if pages < 1 or pages > 87000 or source.is_symlink() or not source.is_file():
        raise ValueError("G0AI_PERIOD_ARGUMENT_INVALID")
    manifest = hashlib.sha256()
    totals = dict(windows=0, utf8_pages=0, candidate_pages=0, candidates=0,
                  increases=0, decreases=0, equals=0)
    with tempfile.TemporaryDirectory(prefix="c500_g0ai_") as work:
        root = pathlib.Path(work)
        for start in range(1, pages + 1, WINDOW):
            count = min(WINDOW, pages - start + 1)
            end = start + count - 1
            out = root / "window"
            out.mkdir()
            try:
                args = [engine, "draw", "-F", "txt", "-o",
                        str(out / "page-%d.txt"), str(source), f"{start}-{end}"]
                try:
                    result = subprocess.run(args, stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL, timeout=180,
                                            preexec_fn=limits, check=False)
                except subprocess.TimeoutExpired as exc:
                    raise ValueError(f"G0AI_ENGINE_TIMEOUT period={period} start={start}") from exc
                if result.returncode:
                    raise ValueError(f"G0AI_ENGINE_FAILED period={period} start={start} rc={result.returncode}")
                try:
                    summary = audit(out, start, count)
                except (ValueError, OSError) as exc:
                    kind = str(exc).split(" ", 1)[0]
                    raise ValueError(f"G0AI_TEXT_AUDIT_FAILED period={period} start={start} kind={kind}") from exc
                def number(key):
                    match = re.search(r"\b" + re.escape(key) + r"=([0-9]+)\b", summary)
                    if match is None:
                        raise ValueError("G0AI_SUMMARY_MALFORMED")
                    return int(match.group(1))
                if number("pages") != count or number("utf8_pages") != count:
                    raise ValueError("G0AI_SUMMARY_PAGE_COUNT_MISMATCH")
                match = re.search(r"text_manifest_sha256=([0-9a-f]{64})", summary)
                if match is None:
                    raise ValueError("G0AI_MANIFEST_MISSING")
                manifest.update(f"{start}:{count}:{match.group(1)}\n".encode("ascii"))
                totals["windows"] += 1
                totals["utf8_pages"] += count
                totals["candidate_pages"] += number("pages_with_eight_digit_candidates")
                totals["candidates"] += number("eight_digit_candidates")
                for key in ("increases", "decreases", "equals"):
                    totals[key] += number(key)
            finally:
                shutil.rmtree(out)
    if totals["utf8_pages"] != pages or totals["windows"] != (pages + WINDOW - 1) // WINDOW:
        raise ValueError("G0AI_GLOBAL_PAGE_COVERAGE_MISMATCH")
    rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    return (f"G0AI_FULL_TEXT period={period} pages={pages} windows={totals['windows']} "
            f"utf8_pages={totals['utf8_pages']} candidate_pages={totals['candidate_pages']} "
            f"eight_digit_lexical_candidates={totals['candidates']} "
            f"window_increases={totals['increases']} window_decreases={totals['decreases']} "
            f"window_equals={totals['equals']} peak_child_rss_kib={rss} "
            f"manifest_sha256={manifest.hexdigest()} "
            "UTF8_BYTES=VALIDATED UNICODE_SEMANTICS=UNPROVEN "
            "AWARD_RECORDS=UNVERIFIED GLOBAL_SORTING=UNPROVEN GLOBAL_NOT_WIN=HOLD")

def main():
    try:
        paths = []
        for period, variable, size, digest, pages in SOURCES:
            raw = os.environ.get(variable)
            if not raw:
                raise ValueError(f"G0AI_SOURCE_UNAVAILABLE period={period}")
            path = pathlib.Path(raw)
            verify_source(path, size, digest)
            paths.append((period, path, size, digest, pages))
        if paths[0][1].resolve() == paths[1][1].resolve():
            raise ValueError("G0AI_SOURCE_PATH_ALIAS")
        print("G0AI_SOURCE_PIN_PASS both_official_periods=true", flush=True)
        for period, path, size, digest, pages in paths:
            result = scan_period(period, path, pages)
            verify_source(path, size, digest)
            print(result, flush=True)
        print("G0AI_FULL_TEXT_COVERAGE=PASS_164000_PAGES_UTF8_LEXICAL_ONLY "
              "ANDROID_FEASIBILITY=HOLD GLOBAL_NOT_WIN=HOLD", flush=True)
        return 0
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        message = str(exc)
        if not message.startswith("G0AI_"):
            message = "G0AI_INTERNAL_OR_IO_FAILURE"
        print(message[:200], file=sys.stderr)
        print("G0AI_FULL_TEXT_COVERAGE=HOLD GLOBAL_NOT_WIN=HOLD", file=sys.stderr)
        return 49

if __name__ == "__main__":
    sys.exit(main())
