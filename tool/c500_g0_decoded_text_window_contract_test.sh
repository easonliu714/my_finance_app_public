#!/usr/bin/env bash
# G0ah strict negative source and UTF-8/lexical page coverage contracts.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
python3 - "$root/tool/c500_g0_decoded_text_window_audit.py" "$tmp" <<'PY'
import pathlib, subprocess, sys
parser, root = sys.argv[1:]
root = pathlib.Path(root)
folder = root / 'pages'; folder.mkdir()
for n in range(1, 513):
    (folder / f'page-{n}.txt').write_text(f'頁面 {n}\n0000{n:04d}\n', encoding='utf-8')
def check(ok, expected=None):
    p = subprocess.run([sys.executable, parser, str(folder), '1', '512'], capture_output=True, text=True)
    assert (p.returncode == 0) == ok, (p.returncode, p.stderr)
    if expected: assert expected in (p.stdout if ok else p.stderr), (p.stdout, p.stderr)
check(True, 'G0AH_TEXT_WINDOW pages=512 utf8_pages=512')
check(True, 'order=NONDECREASING_LEXICAL_ONLY')
target = folder / 'page-3.txt'
original = target.read_bytes()
target.write_bytes(b'\xff\x00')
check(False, 'G0AH_INVALID_UTF8')
target.write_bytes(b'12345678\xef\xbf\xbd')
check(False, 'kind=REPLACEMENT codepoint=U+FFFD page=3')
target.write_bytes(b'12345678\x01')
check(False, 'kind=CONTROL codepoint=U+0001 page=3')
target.write_bytes(b'12345678\x0c12345678')
check(False, 'kind=CONTROL codepoint=U+000C page=3')
target.write_bytes(b'12345678\x0c\x0c\n')
check(False, 'kind=CONTROL codepoint=U+000C page=3')
target.write_bytes(b'12345678\x0c\n')
check(True, 'terminal_formfeed_pages=1')
target.write_bytes(original)
target.unlink()
check(False, 'G0AH_PAGE_GAP_OR_EXTRA')
target.write_bytes(original)
(folder / 'page-513.txt').write_text('12345678', encoding='utf-8')
check(False, 'G0AH_PAGE_GAP_OR_EXTRA')
(folder / 'page-513.txt').unlink()
target.unlink(); target.symlink_to(folder / 'page-4.txt')
check(False, 'G0AH_PAGE_SET_OR_SYMLINK')
target.unlink(); target.write_bytes(original)
for n in range(1, 513): (folder / f'page-{n}.txt').write_text('no award number', encoding='utf-8')
check(False, 'G0AH_NO_EIGHT_DIGIT_LEXICAL_CANDIDATES')
print('PASS G0AH_UTF8_LEXICAL_WINDOW_POSITIVE_NEGATIVE_512_PAGES')
PY
printf forged-old >"$tmp/old.pdf"; printf forged-new >"$tmp/new.pdf"
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\ntouch "$G0AH_RENDER_MARKER"\n' >"$tmp/bin/mutool"
chmod +x "$tmp/bin/mutool"
export G0AH_RENDER_MARKER="$tmp/engine-called" G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
script="$root/tool/c500_g0_decoded_text_window_probe.sh"
if PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then exit 1; fi
grep -Fq G0AH_SOURCE_PIN_MISMATCH "$tmp/log"
test ! -e "$G0AH_RENDER_MARKER"
if G0_OLD_PDF="$tmp/missing.pdf" bash "$script" >"$tmp/log" 2>&1; then exit 1; fi
grep -Fq G0AH_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
ln -s "$tmp/old.pdf" "$tmp/link.pdf"
if G0_OLD_PDF="$tmp/link.pdf" bash "$script" >"$tmp/log" 2>&1; then exit 1; fi
grep -Fq G0AH_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
test ! -e "$G0AH_RENDER_MARKER"
bash -n "$script"
# Regression: execute the REAL probe function under nounset with a synthetic
# 512-page renderer. Source-pin negative cases above remain unchanged.
cat >"$tmp/bin/mutool" <<'PY'
#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
assert args[:3] == ['draw', '-F', 'txt']
pattern = args[args.index('-o') + 1]
first, last = map(int, args[-1].split('-'))
assert last - first + 1 == 512
for page in range(first, last + 1):
    body = f'頁面 {page}\n{page:08d}\n'
    if os.environ.get('G0AH_SYNTHETIC_BAD_CONTROL') == '1' and page == first + 2:
        body += '\f12345678'
    pathlib.Path(pattern.replace('%d', str(page))).write_text(body, encoding='utf-8')
PY
chmod +x "$tmp/bin/mutool"
(
  root="$root"
  tmp="$tmp"
  source <(sed -n '/^probe() {/,/^}/p' "$script")
  PATH="$tmp/bin:$PATH" probe SYNTHETIC "$tmp/old.pdf" 1 first >"$tmp/probe-positive"
)
grep -Fq 'G0AH_CASE period=SYNTHETIC segment=first pages=1-512' "$tmp/probe-positive"
grep -Fq 'G0AH_TEXT_WINDOW pages=512 utf8_pages=512' "$tmp/probe-positive"
(
  root="$root"; tmp="$tmp"
  source <(sed -n '/^probe() {/,/^}/p' "$script")
  if G0AH_SYNTHETIC_BAD_CONTROL=1 PATH="$tmp/bin:$PATH" probe SYNTHETIC "$tmp/old.pdf" 1 first >"$tmp/probe-negative"; then exit 1; fi
)
grep -Fq 'G0AH_REPLACEMENT_OR_CONTROL kind=CONTROL codepoint=U+000C page=3' "$tmp/probe-negative"
echo 'PASS G0AH_ACTUAL_PROBE_NOUNSET_512_PAGE_SYNTHETIC_REPLAY'
python3 -m py_compile "$root/tool/c500_g0_decoded_text_window_audit.py"
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" <<'PY'
from pathlib import Path
import sys
workflow=Path(sys.argv[1]).read_text()
for token in ('G0ah pinned MuPDF decoded UTF8 3072-page lexical quality',
              'bash tool/c500_g0_decoded_text_window_probe.sh',
              'bash tool/c500_g0_decoded_text_window_contract_test.sh',
              "steps.gate.outputs.run_lab == 'true'"):
    assert token in workflow, token
print('PASS G0AH_SOURCE_WORKFLOW_CONTRACT')
PY
