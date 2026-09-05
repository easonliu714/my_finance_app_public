#!/usr/bin/env python3
"""P4.20.3 Gate D/E bridge: package legal-enrichment output deterministically.

Consumes the privacy-reduced output directory produced by
p4_20_3_reconcile_legal_enrichment.py and emits a deterministic gzip corpus plus
an integrity/provenance manifest. This is not the final mobile registry: global
ready+enriched parent-child closure and canonical materialization still follow.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import tempfile
from pathlib import Path

ENTITY_KEYS = {
    "record_type",
    "seller_identifier",
    "entity_type",
    "legal_name",
    "registration_status",
    "parent_seller_identifier",
    "source_dataset",
}
ALLOWED_ENTITY_TYPES = {"company", "business", "branch"}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _deterministic_gzip(source: Path, target: Path) -> None:
    with source.open("rb") as src, target.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as dst:
            for chunk in iter(lambda: src.read(1024 * 1024), b""):
                dst.write(chunk)


def _count_and_validate_entities(path: Path) -> int:
    count = 0
    previous = ""
    with path.open("r", encoding="utf-8") as stream:
        for line_number, raw in enumerate(stream, 1):
            if not raw.strip():
                continue
            row = json.loads(raw)
            if not isinstance(row, dict) or set(row) != ENTITY_KEYS:
                raise ValueError(f"ENRICHED_PAYLOAD_SURFACE_MISMATCH:{line_number}")
            seller = str(row["seller_identifier"])
            if len(seller) != 8 or not seller.isdigit():
                raise ValueError(f"INVALID_SELLER_IDENTIFIER:{line_number}")
            if previous and seller < previous:
                raise ValueError(f"ENRICHED_INPUT_NOT_SORTED:{line_number}")
            previous = seller
            entity_type = str(row["entity_type"])
            if entity_type not in ALLOWED_ENTITY_TYPES:
                raise ValueError(f"UNSUPPORTED_ENTITY_TYPE:{line_number}:{entity_type}")
            parent = str(row["parent_seller_identifier"] or "")
            if entity_type == "branch":
                if len(parent) != 8 or not parent.isdigit() or parent == seller:
                    raise ValueError(f"INVALID_BRANCH_PARENT:{line_number}")
            elif parent:
                raise ValueError(f"NON_BRANCH_HAS_PARENT:{line_number}")
            count += 1
    return count


def package(
    reconciliation_dir: Path,
    output_dir: Path,
    *,
    exact_head: str,
    staging_manifest_sha256: str,
    gcis_closure_manifest_sha256: str,
) -> dict[str, object]:
    source = reconciliation_dir / "enriched_entities.ndjson"
    summary_path = reconciliation_dir / "reconciliation_summary.json"
    if not source.is_file() or not summary_path.is_file():
        raise ValueError("RECONCILIATION_OUTPUT_MISSING")
    if len(exact_head) != 40 or any(c not in "0123456789abcdef" for c in exact_head.lower()):
        raise ValueError("EXACT_HEAD_INVALID")
    for label, value in (
        ("STAGING_MANIFEST_SHA256_INVALID", staging_manifest_sha256),
        ("GCIS_CLOSURE_MANIFEST_SHA256_INVALID", gcis_closure_manifest_sha256),
    ):
        if len(value) != 64 or any(c not in "0123456789abcdef" for c in value.lower()):
            raise ValueError(label)

    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if summary.get("responsible_person_payload_emitted") is not False:
        raise ValueError("RESPONSIBLE_PERSON_BOUNDARY_NOT_CLOSED")
    if summary.get("merchant_name_inference_used") is not False:
        raise ValueError("MERCHANT_NAME_INFERENCE_BOUNDARY_NOT_CLOSED")
    if summary.get("final_mobile_registry") is not False:
        raise ValueError("RECONCILIATION_MUST_NOT_CLAIM_FINAL_REGISTRY")

    count = _count_and_validate_entities(source)
    if count != int(summary.get("enriched_entity_count", -1)):
        raise ValueError("ENRICHED_ENTITY_COUNT_MISMATCH")
    raw_sha = _sha256(source)
    if raw_sha != str(summary.get("enriched_entity_payload_sha256", "")):
        raise ValueError("ENRICHED_ENTITY_SHA256_MISMATCH")

    output_dir.mkdir(parents=True, exist_ok=True)
    target = output_dir / "enriched_entities.ndjson.gz"
    _deterministic_gzip(source, target)
    manifest = {
        "schema_version": 1,
        "gate": "P4.20.3-D-real-legal-enrichment-materialization",
        "exact_head": exact_head.lower(),
        "validation_subset": False,
        "final_mobile_registry": False,
        "responsible_person_payload_emitted": False,
        "merchant_name_inference_used": False,
        "normal_invoice_per_record_network_lookup": False,
        "staging_handoff_manifest_sha256": staging_manifest_sha256.lower(),
        "gcis_full_residual_closure_manifest_sha256": gcis_closure_manifest_sha256.lower(),
        "queue_seller_count": int(summary["queue_seller_count"]),
        "enriched_entity_count": count,
        "unresolved_seller_count": int(summary["unresolved_seller_count"]),
        "hold_seller_count": int(summary["hold_seller_count"]),
        "enriched_entities_sha256": raw_sha,
        "enriched_entities_bytes": source.stat().st_size,
        "enriched_entities_gzip_sha256": _sha256(target),
        "enriched_entities_gzip_bytes": target.stat().st_size,
        "compression": "gzip-mtime-0",
        "coverage_claim": "legal_enrichment_materialization_only_not_final_mobile_registry",
    }
    if manifest["enriched_entity_count"] + manifest["unresolved_seller_count"] + manifest["hold_seller_count"] != manifest["queue_seller_count"]:
        raise ValueError("RECONCILIATION_PARTITION_MISMATCH")
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    (output_dir / "reconciliation_manifest.json").write_bytes(manifest_bytes)
    print("P4_20_3_LEGAL_ENRICHMENT_DETERMINISTIC_PACKAGE=PASS")
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return manifest


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        recon = root / "recon"
        out1 = root / "out1"
        out2 = root / "out2"
        recon.mkdir()
        entity = {
            "record_type": "entity",
            "seller_identifier": "31655572",
            "entity_type": "branch",
            "legal_name": "富達零售股份有限公司晶技門市",
            "registration_status": "核准設立",
            "parent_seller_identifier": "22853565",
            "source_dataset": "FIA+GCIS",
        }
        raw = (json.dumps(entity, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        (recon / "enriched_entities.ndjson").write_bytes(raw)
        (recon / "reconciliation_summary.json").write_text(json.dumps({
            "queue_seller_count": 1,
            "enriched_entity_count": 1,
            "unresolved_seller_count": 0,
            "hold_seller_count": 0,
            "enriched_entity_payload_sha256": hashlib.sha256(raw).hexdigest(),
            "responsible_person_payload_emitted": False,
            "merchant_name_inference_used": False,
            "final_mobile_registry": False,
        }), encoding="utf-8")
        kwargs = dict(
            exact_head="a" * 40,
            staging_manifest_sha256="b" * 64,
            gcis_closure_manifest_sha256="c" * 64,
        )
        m1 = package(recon, out1, **kwargs)
        m2 = package(recon, out2, **kwargs)
        assert (out1 / "enriched_entities.ndjson.gz").read_bytes() == (out2 / "enriched_entities.ndjson.gz").read_bytes()
        assert (out1 / "reconciliation_manifest.json").read_bytes() == (out2 / "reconciliation_manifest.json").read_bytes()
        assert m1 == m2
        assert m1["validation_subset"] is False
        assert m1["responsible_person_payload_emitted"] is False
        assert m1["normal_invoice_per_record_network_lookup"] is False
        assert m1["final_mobile_registry"] is False
    print("P4_20_3_LEGAL_ENRICHMENT_PACKAGE_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reconciliation_dir", nargs="?", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--exact-head", default="")
    parser.add_argument("--staging-manifest-sha256", default="")
    parser.add_argument("--gcis-closure-manifest-sha256", default="")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.reconciliation_dir is None or args.output_dir is None:
        parser.error("reconciliation_dir and output_dir are required unless --self-test is used")
    package(
        args.reconciliation_dir,
        args.output_dir,
        exact_head=args.exact_head,
        staging_manifest_sha256=args.staging_manifest_sha256,
        gcis_closure_manifest_sha256=args.gcis_closure_manifest_sha256,
    )


if __name__ == "__main__":
    main()
