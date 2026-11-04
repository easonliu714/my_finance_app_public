#!/usr/bin/env bash
# G0ac fail-closed: forged source must not execute either engine.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
printf forged-old > "$tmp/old.pdf"; printf forged-new > "$tmp/new.pdf"; mkdir -p "$tmp/bin"
for engine in qpdf mutool; do
cat > "$tmp/bin/$engine" <<'MOCK'
#!/usr/bin/env bash
touch "$G0AC_FORGED_EXECUTION_MARKER"
exit 0
MOCK
chmod +x "$tmp/bin/$engine"
done
export G0AC_FORGED_EXECUTION_MARKER="$tmp/engine-called"
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
if PATH="$tmp/bin:$PATH" bash "$root/tool/c500_g0_object_boundary_probe.sh" >"$tmp/out" 2>&1; then echo G0AC_FORGED_ACCEPTED >&2; exit 1; fi
grep -Fq G0AC_SOURCE_PIN_MISMATCH "$tmp/out"
test ! -e "$G0AC_FORGED_EXECUTION_MARKER" || { echo G0AC_ENGINE_BEFORE_PIN >&2; exit 1; }
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$root/tool/c500_g0_object_boundary_probe.sh" <<'PY'
from pathlib import Path
import sys
wf,script=(Path(x).read_text() for x in sys.argv[1:])
assert 'G0ac pinned first qpdf error object and MuPDF bounded recovery' in wf
assert 'bash tool/c500_g0_object_boundary_probe.sh' in wf
assert 'bash tool/c500_g0_object_boundary_contract_test.sh' in wf
assert "steps.gate.outputs.run_lab == 'true'" in wf
assert "env.G0_OLD_PDF != ''" in wf and "env.G0_NEW_PDF != ''" in wf
for x in ('4187016','4730783','ulimit -v 3145728','ulimit -f 8192','timeout --signal=TERM --kill-after=5s 45s','G0AC_FIRST_ERROR_OBJECT_EXPERIMENT=EVIDENCE_ONLY GLOBAL_NOT_WIN=HOLD'): assert x in script,x
print('PASS G0AC_PINNED_NEGATIVE_AND_RESOURCE_CONTRACT')
PY
