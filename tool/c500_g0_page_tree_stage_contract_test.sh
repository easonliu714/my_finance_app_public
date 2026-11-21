#!/usr/bin/env bash
# G0ae: forged/missing/symlinked source must never reach qpdf.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
printf forged-old > "$tmp/old.pdf"; printf forged-new > "$tmp/new.pdf"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/qpdf" <<'MOCK'
#!/usr/bin/env bash
touch "$G0AE_FORGED_ENGINE_MARKER"
exit 0
MOCK
chmod +x "$tmp/bin/qpdf"
export G0AE_FORGED_ENGINE_MARKER="$tmp/engine-called"
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
script="$root/tool/c500_g0_page_tree_stage_probe.sh"
if PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then echo G0AE_FORGED_SOURCE_ACCEPTED >&2; exit 1; fi
grep -Fq G0AE_SOURCE_PIN_MISMATCH "$tmp/log"
test ! -e "$G0AE_FORGED_ENGINE_MARKER"
if G0_OLD_PDF="$tmp/missing.pdf" PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then exit 1; fi
grep -Fq G0AE_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
ln -s "$tmp/old.pdf" "$tmp/link.pdf"
if G0_OLD_PDF="$tmp/link.pdf" PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then exit 1; fi
grep -Fq G0AE_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
test ! -e "$G0AE_FORGED_ENGINE_MARKER"
bash -n "$script"
# Streaming page ordinal classifier: zero, gap, and reorder are all rejected.
awk_program='/^page [0-9]+:/ { n=$2; sub(/:$/, "", n); if (n != count+1) bad=1; count++ } END { if (bad || count==0) { print "INVALID"; exit 49 }; print count }'
test "$(printf 'page 1: 1 0 R\npage 2: 2 0 R\n' | awk "$awk_program")" = 2
if printf 'page 1: 1 0 R\npage 3: 3 0 R\n' | awk "$awk_program" >"$tmp/ord"; then exit 1; fi
grep -Fq INVALID "$tmp/ord"
if printf 'header only\n' | awk "$awk_program" >"$tmp/ord"; then exit 1; fi
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$script" <<'PY'
from pathlib import Path
import sys
workflow, script = (Path(p).read_text(encoding='utf-8') for p in sys.argv[1:])
for token in ('G0ae pinned qpdf root-count vs page-dictionary enumeration',
              'bash tool/c500_g0_page_tree_stage_probe.sh',
              'bash tool/c500_g0_page_tree_stage_contract_test.sh',
              "steps.gate.outputs.run_lab == 'true'"):
    assert token in workflow, token
for token in ('--show-npages', '--show-pages', 'ulimit -v 3145728',
              'timeout --signal=TERM --kill-after=5s 100s',
              'PAGE_TREE_ENUMERATION_ALLOCATION_BOUNDARY',
              'GLOBAL_NOT_WIN=HOLD'):
    assert token in script, token
print('PASS G0AE_PINNED_PAGE_TREE_STAGE_AND_FAIL_CLOSED_CONTRACT')
PY
