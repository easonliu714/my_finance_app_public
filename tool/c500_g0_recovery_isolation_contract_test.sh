#!/usr/bin/env bash
# G0ad negative contract: forged PDF bytes never reach the qpdf engine.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
printf forged-old > "$tmp/old.pdf"; printf forged-new > "$tmp/new.pdf"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/qpdf" <<'MOCK'
#!/usr/bin/env bash
touch "$G0AD_FORGED_ENGINE_MARKER"
exit 0
MOCK
chmod +x "$tmp/bin/qpdf"
export G0AD_FORGED_ENGINE_MARKER="$tmp/engine-called"
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
if PATH="$tmp/bin:$PATH" bash "$root/tool/c500_g0_recovery_isolation.sh" >"$tmp/out" 2>&1; then
  echo G0AD_FORGED_SOURCE_ACCEPTED >&2; exit 1
fi
grep -Fq G0AD_SOURCE_PIN_MISMATCH "$tmp/out"
test ! -e "$G0AD_FORGED_ENGINE_MARKER" || { echo G0AD_ENGINE_CALLED_BEFORE_PIN >&2; exit 1; }
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$root/tool/c500_g0_recovery_isolation.sh" <<'PY'
from pathlib import Path
import sys
wf, script = (Path(x).read_text(encoding='utf-8') for x in sys.argv[1:])
for token in ('G0ad pinned qpdf recovery-disabled vs default full-check isolation',
              'bash tool/c500_g0_recovery_isolation.sh',
              'bash tool/c500_g0_recovery_isolation_contract_test.sh',
              "steps.gate.outputs.run_lab == 'true'", "env.G0_OLD_PDF != ''", "env.G0_NEW_PDF != ''"):
    assert token in wf, token
for token in ('--suppress-recovery --check', 'ulimit -v 3145728', 'ulimit -f 1024',
              'timeout --signal=TERM --kill-after=5s 65s',
              'ALLOCATION_FAILURE_PERSISTS_WITHOUT_RECOVERY',
              'G0AD_RECOVERY_ISOLATION=EVIDENCE_ONLY'):
    assert token in script, token
print('PASS G0AD_PINNED_SOURCE_FAIL_CLOSED_RECOVERY_ISOLATION_CONTRACT')
PY
