#!/usr/bin/env bash
# G0g workflow control regression: no official bytes or credentials required.
# Ensure qpdf failure cannot suppress a pinned, isolated Android experiment.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" <<'PY'
from pathlib import Path
import re
import sys

workflow = Path(sys.argv[1]).read_text(encoding='utf-8')
def step(name):
    match = re.search(
        r'^      - name: ' + re.escape(name) +
        r'\n(?P<body>.*?)(?=^      - name: |\Z)',
        workflow, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        raise SystemExit('FAIL G0G_WORKFLOW_STEP_MISSING: ' + name)
    return match.group('body')

source = step('Attempt BOTH exact MOF PDFs with bounded stream and structure probe')
assert 'G0C_OFFICIAL_PAIR_PINNED_AND_MOUNTED_EPHEMERALLY' in source
assert 'G0_OLD_PDF' in source and 'G0_NEW_PDF' in source
assert 'source[\'sha256\'] != digest' in source
qpdf = step('G0k bounded independent qpdf structural crosscheck (NOT Android proof)')
assert 'continue-on-error: true' not in qpdf
assert 'bash tool/c500_g0_qpdf_preflight.sh' in qpdf
xref = step('G0l pinned official XRef-stream bounded access (NOT page proof)')
assert '!cancelled()' in xref
common = ("!cancelled()", "steps.gate.outputs.run_lab == 'true'",
          "env.G0_OLD_PDF != ''", "env.G0_NEW_PDF != ''")
for name, step_id, required_predecessor in (
    ('Setup Java 17 for G0d Android renderer lab', 'g0d_java', None),
    ('Prepare isolated Android test host', 'g0d_host', "steps.g0d_java.outcome == 'success'"),
    ('G0g Android API35 official pair three-engine OOM and crash attribution lab', None, "steps.g0d_host.outcome == 'success'"),
):
    body = step(name)
    condition = re.search(r'^        if: (.+)$', body, flags=re.MULTILINE)
    assert condition, 'G0G_IF_MISSING: ' + name
    for term in common:
        assert term in condition.group(1), 'G0G_FAIL_OPEN_OR_SKIPPED: ' + name + ': ' + term
    if step_id:
        assert ('id: ' + step_id) in body
    if required_predecessor:
        assert required_predecessor in condition.group(1)
    assert 'success()' not in condition.group(1)
assert '[G0-SOURCE-LAB]' in step('Gate one-shot PR diagnostic or explicit manual dispatch')
assert 'bash tool/c500_g0_workflow_gate_contract_test.sh' in step(
    'G0g per-case crash isolation and OOM/abort contract (synthetic mock)')
print('PASS C500_G0G_QPDF_FAILURE_INDEPENDENT_PINNED_ANDROID_EXECUTION_GATES')
PY
