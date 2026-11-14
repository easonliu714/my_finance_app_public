#!/usr/bin/env bash
# G0z negative regression: forged or swapped official bytes must never invoke renderer.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf fake-old >"$tmp/old.pdf"
printf fake-new >"$tmp/new.pdf"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/mutool" <<'STUB'
#!/usr/bin/env bash
touch "$G0Z_FORGED_RENDER_MARKER"
exit 0
STUB
chmod +x "$tmp/bin/mutool"
export G0Z_FORGED_RENDER_MARKER="$tmp/render-called"
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
script="$root/tool/c500_g0_mutool_spread_page_probe.sh"
if PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then echo 'FAIL G0Z_FORGED_PAIR_ACCEPTED'; exit 1; fi
grep -Fq G0Z_SOURCE_PIN_MISMATCH "$tmp/log"
test ! -e "$G0Z_FORGED_RENDER_MARKER" || { echo 'FAIL G0Z_RENDER_BEFORE_BOTH_PINS'; exit 1; }
if G0_OLD_PDF="$tmp/missing.pdf" PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then echo 'FAIL G0Z_MISSING_SOURCE_ACCEPTED'; exit 1; fi
grep -Fq G0Z_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
test ! -e "$G0Z_FORGED_RENDER_MARKER"
bash -n "$script"
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$script" <<'PY'
from pathlib import Path
import sys
workflow, script = (Path(p).read_text(encoding='utf-8') for p in sys.argv[1:])
assert 'G0z pinned MuPDF middle and last random-page feasibility (NOT G0 PASS)' in workflow
assert 'bash tool/c500_g0_mutool_spread_page_probe.sh' in workflow
assert "steps.gate.outputs.run_lab == 'true'" in workflow
assert 'ulimit -v 3145728' in script and 'ulimit -f 512' in script
assert 'timeout --signal=TERM --kill-after=5s 90s' in script
assert '38500 middle' in script and '77000 last' in script
assert '43500 middle' in script and '87000 last' in script
assert 'NOT_UNICODE_NOT_SORTED_NOT_COMPLETE_NOT_GLOBAL_NOT_WIN' in script
assert 'G0Z_SOURCE_PIN_MISMATCH' in script
print('PASS G0Z_PINNED_SOURCE_FOUR_RANDOM_PAGES_BOUNDED_AND_FORGED_FAIL_CLOSED')
PY
