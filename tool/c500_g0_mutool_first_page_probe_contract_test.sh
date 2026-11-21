#!/usr/bin/env bash
# G0y: forged source cannot invoke independent renderer; bounds remain explicit.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf fake-old >"$tmp/old.pdf"
printf fake-new >"$tmp/new.pdf"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/mutool" <<'EOF'
#!/usr/bin/env bash
touch "$G0Y_FORGED_EXEC_MARKER"
exit 0
EOF
chmod +x "$tmp/bin/mutool"
export G0Y_FORGED_EXEC_MARKER="$tmp/render-called"
export G0_OLD_PDF="$tmp/old.pdf"
export G0_NEW_PDF="$tmp/new.pdf"
if PATH="$tmp/bin:$PATH" bash "$root/tool/c500_g0_mutool_first_page_probe.sh" >"$tmp/log" 2>&1; then echo "FAIL G0Y_FORGED_SOURCE_ACCEPTED"; exit 1; fi
grep -Fq G0Y_SOURCE_PIN_MISMATCH "$tmp/log"
test ! -e "$G0Y_FORGED_EXEC_MARKER" || { echo "FAIL G0Y_RENDER_BEFORE_PIN"; exit 1; }
bash -n "$root/tool/c500_g0_mutool_first_page_probe.sh"
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$root/tool/c500_g0_mutool_first_page_probe.sh" <<'PY'
from pathlib import Path
import sys
workflow, script = (Path(p).read_text(encoding='utf-8') for p in sys.argv[1:])
assert 'sudo apt-get install -y -qq qpdf mupdf-tools' in workflow
assert 'G0y independent pinned MuPDF first-page engine feasibility (NOT G0 PASS)' in workflow
assert 'bash tool/c500_g0_mutool_first_page_probe.sh' in workflow
assert "steps.gate.outputs.run_lab == 'true'" in workflow
assert 'ulimit -v 3145728' in script and 'ulimit -f 512' in script
assert 'timeout --signal=TERM --kill-after=5s 90s' in script
assert 'mutool draw -F txt -o "$out" "$file" 1' in script
assert 'NOT_UNICODE_NOT_SORTED_NOT_GLOBAL_NOT_WIN' in script
print('PASS G0Y_PINNED_SOURCE_INDEPENDENT_ENGINE_BOUNDED_CONTRACT')
PY
