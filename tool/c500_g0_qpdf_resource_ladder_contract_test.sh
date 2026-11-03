#!/usr/bin/env bash
# C500-G0x: fail-closed source identity and bounded workflow control.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf 'forged-old' > "$tmp/old.pdf"
printf 'forged-new' > "$tmp/new.pdf"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/qpdf" <<'EOF'
#!/usr/bin/env bash
touch "$G0X_FORGED_EXECUTION_MARKER"
exit 0
EOF
chmod +x "$tmp/bin/qpdf"
export G0X_FORGED_EXECUTION_MARKER="$tmp/qpdf-was-called"
export G0_OLD_PDF="$tmp/old.pdf"
export G0_NEW_PDF="$tmp/new.pdf"
if PATH="$tmp/bin:$PATH" bash "$root/tool/c500_g0_qpdf_resource_ladder.sh" >"$tmp/out" 2>&1; then
  echo "FAIL G0X_FORGED_SOURCE_ACCEPTED" >&2
  exit 1
fi
grep -Fq 'C500_G0X_HOLD_SOURCE_PIN_MISMATCH' "$tmp/out"
test ! -e "$G0X_FORGED_EXECUTION_MARKER" || { echo "FAIL G0X_QPDF_EXECUTED_BEFORE_PIN" >&2; exit 1; }
# GNU time prints a diagnostic line before peak RSS on a nonzero child exit.
# The previous first-line numeric strip incorrectly read exit status as RSS.
test -x /usr/bin/time
time_rc=0
/usr/bin/time -f '%M' -o "$tmp/nonzero-time" bash -c 'exit 3' >/dev/null 2>&1 || time_rc=$?
[[ "$time_rc" -eq 3 ]]
grep -Fq 'Command exited with non-zero status 3' "$tmp/nonzero-time"
actual_rss="$(grep -E '^[0-9]+$' "$tmp/nonzero-time" | tail -n 1 || true)"
[[ "$actual_rss" =~ ^[0-9]+$ ]] && [[ "$actual_rss" -gt 0 ]]
echo "PASS C500_G0X_GNU_TIME_NONZERO_EXIT_RSS_SEPARATED"

python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$root/tool/c500_g0_qpdf_resource_ladder.sh" <<'PY'
from pathlib import Path
import sys
wf, script = (Path(p).read_text(encoding='utf-8') for p in sys.argv[1:])
assert "G0x pinned dual-PDF qpdf virtual-memory failure threshold (NOT G0 PASS)" in wf
assert "bash tool/c500_g0_qpdf_resource_ladder.sh" in wf
assert "steps.gate.outputs.run_lab == 'true'" in wf
assert "env.G0_OLD_PDF != ''" in wf and "env.G0_NEW_PDF != ''" in wf
assert 'for cap in 1572864 3145728' in script
assert 'for cap in 4194304' in script
assert 'run_probe 115-05-06 "$G0_OLD_PDF" 77000 check "$cap"' in script
assert 'run_probe 115-07-08 "$G0_NEW_PDF" 87000 check "$cap"' in script
assert "grep -E '^[0-9]+$'" in script
assert 'tail -n 1 || true' in script
assert 'head -n 1 "$timing"' not in script
assert 'run_probe 115-05-06' in script and 'run_probe 115-07-08' in script
assert 'ulimit -v "$cap"' in script and 'timeout --signal=TERM' in script
assert 'C500_G0X_RESOURCE_LADDER_COMPLETE=EVIDENCE_ONLY G0_GLOBAL_NOT_WIN=HOLD' in script
print('PASS C500_G0X_PINNED_SOURCE_FAIL_CLOSED_AND_RESOURCE_BOUND_CONTRACT')
PY
