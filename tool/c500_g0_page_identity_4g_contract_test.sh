#!/usr/bin/env bash
# G0af: enforce fail-closed source custody and page identity negative tests.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
parser="$root/tool/c500_g0_page_identity_stream.py"
printf 'page 1: 7 0 R\n  content:\n    8 0 R\npage 2: 9 0 R\n' |
  python3 "$parser" 2 >"$tmp/out"
grep -Eq '^G0AF_ENUM count=2 unique_page_refs=2 identity_sha256=[0-9a-f]{64}$' "$tmp/out"
reject() {
  if printf '%b' "$1" | python3 "$parser" 2 >"$tmp/out" 2>"$tmp/err"; then
    echo G0AF_FORGED_ENUMERATION_ACCEPTED >&2; exit 1
  fi
}
reject 'page 1: 7 0 R\npage 3: 9 0 R\n'
reject 'page 1: 7 0 R\npage 2: 7 0 R\n'
reject 'page 2: 7 0 R\npage 1: 9 0 R\n'
reject 'page 1: 0 0 R\npage 2: 9 0 R\n'
reject 'page 1: 7 0 R\n'
reject 'page 1: 7 0 R\npage 2: 9 0 R\npage 3: 10 0 R\n'
reject 'page 1: 7 0 R\nINJECTED PAGE TEXT\npage 2: 9 0 R\n'
printf forged-old >"$tmp/old.pdf"; printf forged-new >"$tmp/new.pdf"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/qpdf" <<'MOCK'
#!/usr/bin/env bash
touch "$G0AF_FORGED_ENGINE_MARKER"
exit 0
MOCK
chmod +x "$tmp/bin/qpdf"
export G0AF_FORGED_ENGINE_MARKER="$tmp/engine-called"
export G0_OLD_PDF="$tmp/old.pdf" G0_NEW_PDF="$tmp/new.pdf"
script="$root/tool/c500_g0_page_identity_4g_probe.sh"
if PATH="$tmp/bin:$PATH" bash "$script" >"$tmp/log" 2>&1; then exit 1; fi
grep -Fq G0AF_SOURCE_PIN_MISMATCH "$tmp/log"
test ! -e "$G0AF_FORGED_ENGINE_MARKER"
if G0_OLD_PDF="$tmp/missing" bash "$script" >"$tmp/log" 2>&1; then exit 1; fi
grep -Fq G0AF_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
ln -s "$tmp/old.pdf" "$tmp/link"
if G0_OLD_PDF="$tmp/link" bash "$script" >"$tmp/log" 2>&1; then exit 1; fi
grep -Fq G0AF_SOURCE_MISSING_OR_SYMLINK "$tmp/log"
test ! -e "$G0AF_FORGED_ENGINE_MARKER"
bash -n "$script"
python3 -m py_compile "$parser"
python3 - "$root/.github/workflows/c500_g0_source_lab.yml" "$script" <<'PY'
from pathlib import Path
import sys
workflow, script = (Path(p).read_text() for p in sys.argv[1:])
for token in ('G0af pinned 4-GiB qpdf full page reference identity',
              'bash tool/c500_g0_page_identity_4g_probe.sh',
              'bash tool/c500_g0_page_identity_4g_contract_test.sh',
              "steps.gate.outputs.run_lab == 'true'"):
    assert token in workflow, token
for token in ('ulimit -v 4194304', 'qpdf --show-pages', 'GLOBAL_NOT_WIN=HOLD'):
    assert token in script, token
print('PASS G0AF_PINNED_PAGE_IDENTITY_4G_AND_FAIL_CLOSED_CONTRACT')
PY
