#!/usr/bin/env bash
# G0ab: no renderer may see forged, absent or symlinked official source.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf forged-old > "$tmp/old.pdf"
printf forged-new > "$tmp/new.pdf"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/mutool" <<'STUB'
#!/usr/bin/env bash
touch "$G0AB_RENDER_MARKER"
exit 0
STUB
chmod +x "$tmp/bin/mutool"
export G0AB_RENDER_MARKER="$tmp/render-called"
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
script="$root/tool/c500_g0_mutool_window_replay_probe.sh"
if PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then echo FAIL_FORGED_ACCEPTED; exit 1; fi
grep -Fq G0AB_SOURCE_PIN_MISMATCH "$tmp/log"
test ! -e "$G0AB_RENDER_MARKER"
if G0_OLD_PDF="$tmp/missing.pdf" PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then echo FAIL_MISSING_ACCEPTED; exit 1; fi
grep -Fq G0AB_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
ln -s "$tmp/old.pdf" "$tmp/link.pdf"
if G0_OLD_PDF="$tmp/link.pdf" PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then echo FAIL_SYMLINK_ACCEPTED; exit 1; fi
grep -Fq G0AB_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
test ! -e "$G0AB_RENDER_MARKER"
bash -n "$script"
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$script" <<'PY'
from pathlib import Path
import sys
workflow, script = (Path(p).read_text(encoding='utf-8') for p in sys.argv[1:])
assert 'G0ab pinned MuPDF 64-page contiguous window replay (NOT G0 PASS)' in workflow
assert 'bash tool/c500_g0_mutool_window_replay_probe.sh' in workflow
assert 'bash tool/c500_g0_mutool_window_replay_contract_test.sh' in workflow
assert "steps.gate.outputs.run_lab == 'true'" in workflow
assert 'ulimit -v 3145728' in script and 'ulimit -f 512' in script
assert 'timeout --signal=TERM --kill-after=5s 120s' in script
assert 'count == 64 && total <= 16777216' in script
assert 'CASE_SHA' in script and 'first_sha' in script
assert 'GLOBAL_NOT_WIN=HOLD' in script
print('PASS G0AB_FORGED_SOURCE_FAIL_CLOSED_AND_BOUNDED_WINDOW_REPLAY_CONTRACT')
PY
