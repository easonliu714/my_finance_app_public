#!/usr/bin/env python3
"""Read-only source-bound L0 crosswalk; not a production integration PASS."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

G = "packages/flutter_pdf_text/android/build.gradle"
M = "packages/flutter_pdf_text/android/src/main/AndroidManifest.xml"
K = "packages/flutter_pdf_text/android/src/main/kotlin/me/movenext/flutter_pdf_text/"
W = ".github/workflows/issue_13_cloud500_pdf_diagnostic_lab.yml"
D = "docs/issue_13_cloud500_pdf_diagnostic_lab.md"
P = ("pubspec.yaml", G, M, K+"PdfiumCandidateWorkerService.kt",
     K+"PlatformPdfProbeService.kt", K+"PlatformPdfCandidateWorkerService.kt",
     K+"PdfTextPlugin.kt", ".github/workflows/flutter_android_ci.yml", W, D)
SIGNER = "51c7fc93ef3d2a04bcd993e6e716b37949efdb74be9af7f48689cfc7ff5c3c53"
APP_ID = "com.easonliu.cloud500diag"


def git(*args):
    p = subprocess.run(["git", *args], text=True, capture_output=True)
    if p.returncode:
        raise ValueError("git read failed: " + " ".join(args))
    return p.stdout.strip()


def read(ref):
    result = {}
    for path in P:
        p = subprocess.run(["git", "show", ref+":"+path], text=True, capture_output=True)
        result[path] = p.stdout if p.returncode == 0 else None
    return result


def required(files, path, side):
    value = files.get(path)
    if value is None:
        raise ValueError(side + " missing required source " + path)
    return value


def field(pattern, content, label):
    m = re.search(pattern, content, re.MULTILINE)
    if not m:
        raise ValueError("missing L0 field " + label)
    return m.group(1)


def facts(files, side):
    pub = required(files, "pubspec.yaml", side)
    gradle = required(files, G, side)
    manifest = required(files, M, side)
    required(files, K+"PdfiumCandidateWorkerService.kt", side)
    return {
        "version": field(r"^version:\s*(\S+)", pub, side+" version"),
        "pdfium": field(r"pdfiumandroid:([0-9.]+)", gradle, side+" pdfium"),
        "pdfbox": field(r"pdfbox-android:([0-9.]+)", gradle, side+" pdfbox"),
        "compile_sdk": int(field(r"compileSdkVersion\s+(\d+)", gradle, side+" compileSdk")),
        "min_sdk": int(field(r"minSdkVersion\s+(\d+)", gradle, side+" minSdk")),
        "ipc": sorted(set(re.findall(r'android:process="([^"]+)"', manifest))),
    }


def crosswalk(lab, prod, lab_head, prod_head):
    lf, pf = facts(lab, "lab"), facts(prod, "production")
    workflow = required(lab, W, "lab")
    doc = required(lab, D, "lab")
    platform = required(lab, K+"PlatformPdfProbeService.kt", "lab")
    if 'applicationId = "'+APP_ID+'"' not in workflow:
        raise ValueError("Lab applicationId mismatch")
    if "LAB_SIGNER_SHA256="+SIGNER not in workflow or SIGNER not in doc:
        raise ValueError("Lab diagnostic signer mismatch")
    if "android.graphics.pdf.PdfRenderer" not in platform:
        raise ValueError("Lab PdfRenderer missing")
    if ":platform_pdf_probe" not in lf["ipc"]:
        raise ValueError("Lab isolated platform process missing")
    if ":platform_pdf_probe" in pf["ipc"]:
        raise ValueError("Production unexpectedly includes Lab-only process")
    hashes = {
        path: {
            side: hashlib.sha256(files[path].encode("utf-8")).hexdigest()
            if files.get(path) is not None else None
            for side, files in (("lab", lab), ("production", prod))
        } for path in P
    }
    return {
        "gate": "L0_CROSSWALK_CAPTURED_NOT_INTEGRATION_PASS",
        "lab_head": lab_head, "production_head": prod_head,
        "lab_application_id": APP_ID, "production_application_id": "UNVERIFIED_GENERATED_HOST",
        "lab_diagnostic_signer_sha256": SIGNER, "production_signer": "NOT_USED",
        "lab": lf, "production": pf,
        "version_equal": lf["version"] == pf["version"],
        "pdfium_equal": lf["pdfium"] == pf["pdfium"],
        "pdfbox_equal": lf["pdfbox"] == pf["pdfbox"],
        "file_sha256": hashes,
        "official_pdf_revalidated": False,
        "android_runtime_revalidated": False,
        "production_integration": "HOLD", "owner_device": "HOLD",
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--lab-ref", required=True)
    p.add_argument("--production-ref", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    report = crosswalk(read(a.lab_ref), read(a.production_ref),
                       git("rev-parse", "--verify", a.lab_ref+"^{commit}"),
                       git("rev-parse", "--verify", a.production_ref+"^{commit}"))
    Path(a.output).write_text(json.dumps(report, indent=2, sort_keys=True)+"\n", encoding="utf-8")
    print("LAB_L0_CROSSWALK_CAPTURED=PASS")
    print("LAB_L0_PRODUCTION_INTEGRATION=HOLD")
    print("LAB_L0_PRODUCTION_HEAD="+report["production_head"])


if __name__ == "__main__":
    main()
