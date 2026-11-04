#!/usr/bin/env bash
# G0aa: forged/missing/symlink source must fail before renderer; source never faked.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf forged-old > "$tmp/old.pdf"
printf forged-new > "$tmp/new.pdf"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/mutool" <<'STUB'
#!/usr/bin/env bash
touch "$G0AA_RENDER_MARKER"
exit 0
STUB
chmod +x "$tmp/bin/mutool"
export G0AA_RENDER_MARKER="$tmp/render-called"
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
script="$root/tool/c500_g0_mutool_vm_recovery_probe.sh"
if PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then
  echo 'FAIL G0AA_FORGED_PAIR_ACCEPTED'; exit 1
fi
grep -Fq G0AA_SOURCE_PIN_MISMATCH "$tmp/log"
test ! -e "$G0AA_RENDER_MARKER" || { echo 'FAIL G0AA_RENDER_BEFORE_PINS'; exit 1; }
if G0_OLD_PDF="$tmp/missing.pdf" PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then
  echo 'FAIL G0AA_MISSING_SOURCE_ACCEPTED'; exit 1
fi
grep -Fq G0AA_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
ln -s "$tmp/old.pdf" "$tmp/symlink.pdf"
if G0_OLD_PDF="$tmp/symlink.pdf" PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then
  echo 'FAIL G0AA_SYMLINK_SOURCE_ACCEPTED'; exit 1
fi
grep -Fq G0AA_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
test ! -e "$G0AA_RENDER_MARKER"
bash -n "$script"
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$script" <<'PY'
from pathlib import Path
import sys
workflow, script = (Path(p).read_text(encoding='utf-8') for p in sys.argv[1:])
assert 'G0aa pinned MuPDF controlled VM failure and stable recovery (NOT G0 PASS)' in workflow
assert 'bash tool/c500_g0_mutool_vm_recovery_probe.sh' in workflow
assert "steps.gate.outputs.run_lab == 'true'" in workflow
assert 'bash tool/c500_g0_mutool_vm_recovery_contract_test.sh' in workflow
assert 'ulimit -v "$cap"' in script and 'ulimit -f 512' in script
assert 'timeout --signal=TERM --kill-after=5s 90s' in script
assert 'low_256m 262144' in script and 'recovery_a_3g 3145728' in script
assert 'recovery_b_3g 3145728' in script
assert 'case_recovery 115-05-06 "$G0_OLD_PDF" 38500' in script
assert 'case_recovery 115-07-08 "$G0_NEW_PDF" 43500' in script
assert 'G0AA_RESOURCE_RECOVERY=HOLD GLOBAL_NOT_WIN=HOLD' in script
assert 'NOT_ATTRIBUTED_TO_PDFBOX_OR_PDFIUM' in script
print('PASS G0AA_PINNED_CONTROLLED_VM_FAILURE_RECOVERY_AND_FORGED_FAIL_CLOSED')
PY
