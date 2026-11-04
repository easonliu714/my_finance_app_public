#!/usr/bin/env bash
# G0ai actual full-window scanner positive and negative synthetic contracts.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/mutool" <<'PY'
#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
assert args[:3] == ['draw', '-F', 'txt']
pattern = args[args.index('-o') + 1]
start, end = map(int, args[-1].split('-'))
for page in range(start, end + 1):
    if os.environ.get('G0AI_TEST_MISSING') == '1' and page == 513:
        continue
    text = f'頁 {page}\n{page:08d}\n\f'
    if os.environ.get('G0AI_TEST_CONTROL') == '1' and page == 513:
        text = '12345678\x01'
    pathlib.Path(pattern.replace('%d', str(page))).write_text(text, encoding='utf-8')
PY
chmod +x "$tmp/bin/mutool"
printf 'synthetic-not-official' > "$tmp/mock.pdf"
PYTHONPATH="$root/tool" PATH="$tmp/bin:$PATH" python3 - "$tmp/mock.pdf" <<'PY'
import hashlib, os, pathlib, sys
from c500_g0_full_text_stream import scan_period, verify_source
source = pathlib.Path(sys.argv[1])
sha = hashlib.sha256(source.read_bytes()).hexdigest()
verify_source(source, source.stat().st_size, sha)
try:
    verify_source(source, source.stat().st_size, '0' * 64)
    raise AssertionError('forged SHA accepted')
except ValueError as exc:
    assert str(exc) == 'G0AI_SOURCE_SHA_MISMATCH'
result = scan_period('SYNTHETIC', source, 513)
assert 'pages=513 windows=2 utf8_pages=513 candidate_pages=513' in result, result
assert 'GLOBAL_NOT_WIN=HOLD' in result
for env, expected in [('G0AI_TEST_MISSING', 'G0AI_TEXT_AUDIT_FAILED'),
                      ('G0AI_TEST_CONTROL', 'G0AI_TEXT_AUDIT_FAILED')]:
    os.environ[env] = '1'
    try:
        scan_period('SYNTHETIC', source, 513)
        raise AssertionError(env + ' accepted')
    except ValueError as exc:
        assert expected in str(exc), str(exc)
    finally:
        del os.environ[env]
print('PASS G0AI_FULL_WINDOW_512_PLUS_FINAL_ONE_POSITIVE_NEGATIVE')
PY
python3 -m py_compile "$root/tool/c500_g0_full_text_stream.py"
