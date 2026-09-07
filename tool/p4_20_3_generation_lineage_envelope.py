#!/usr/bin/env python3
"""P4.20.3 reusable GCIS generation -> consumer-head lineage envelope.

This is a cheap downstream authority primitive. It never acquires GCIS data and
never rewrites producer evidence. It binds immutable producer-generation evidence
to the exact consumer/release head only after a same-generation reuse gate has
explicitly approved reuse.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

SCHEMA_VERSION = 1
GATE = "P4.20.3-generation-lineage-envelope"


def _canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _require_sha256(value: object, label: str) -> str:
    text = str(value or "")
    if len(text) != 64 or any(ch not in "0123456789abcdef" for ch in text.lower()):
        raise RuntimeError(f"{label}_INVALID")
    return text.lower()


def _load_json(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"{label}_JSON_INVALID") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"{label}_OBJECT_REQUIRED")
    return value


def build_lineage_envelope(
    *,
    consumer_exact_head: str,
    generation_gate_path: Path,
    producer_closure_sha256: str,
    producer_materialization_sha256: str,
) -> dict[str, object]:
    gate = _load_json(generation_gate_path, "GENERATION_GATE")
    gate_sha = _sha256_file(generation_gate_path)

    if gate.get("gate") != "P4.20.3-full-residual-generation-gate":
        raise RuntimeError("GENERATION_GATE_IDENTITY_MISMATCH")
    if gate.get("current_head") != consumer_exact_head:
        raise RuntimeError("GENERATION_GATE_CONSUMER_HEAD_MISMATCH")
    if gate.get("run_expensive") is not False:
        raise RuntimeError("GENERATION_GATE_REUSE_NOT_APPROVED")
    if gate.get("generation_artifact_reuse") is not True:
        raise RuntimeError("GENERATION_GATE_REUSE_NOT_APPROVED")
    reasons = gate.get("reasons")
    if reasons != ["SAME_GENERATION_REUSE_APPROVED"]:
        raise RuntimeError("GENERATION_GATE_REUSE_REASON_MISMATCH")
    if gate.get("validation_subset") is not False:
        raise RuntimeError("GENERATION_GATE_VALIDATION_SUBSET_FORBIDDEN")
    if gate.get("responsible_person_payload_emitted") is not False:
        raise RuntimeError("GENERATION_GATE_RESPONSIBLE_PERSON_FORBIDDEN")
    if gate.get("mobile_per_invoice_network_lookup") is not False:
        raise RuntimeError("GENERATION_GATE_PER_INVOICE_NETWORK_FORBIDDEN")

    producer_head = str(gate.get("prior_success_head") or "")
    if len(producer_head) != 40:
        raise RuntimeError("PRODUCER_HEAD_INVALID")
    producer_run_id = int(gate.get("prior_success_run_id") or 0)
    closure_artifact_id = int(gate.get("prior_closure_artifact_id") or 0)
    materialization_artifact_id = int(
        gate.get("prior_materialization_artifact_id") or 0
    )
    if min(producer_run_id, closure_artifact_id, materialization_artifact_id) <= 0:
        raise RuntimeError("PRODUCER_ARTIFACT_AUTHORITY_INCOMPLETE")

    envelope: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "gate": GATE,
        "producer_head": producer_head,
        "producer_run_id": producer_run_id,
        "producer_closure_artifact_id": closure_artifact_id,
        "producer_closure_sha256": _require_sha256(
            producer_closure_sha256, "PRODUCER_CLOSURE_SHA256"
        ),
        "producer_materialization_artifact_id": materialization_artifact_id,
        "producer_materialization_sha256": _require_sha256(
            producer_materialization_sha256, "PRODUCER_MATERIALIZATION_SHA256"
        ),
        "generation_key": _require_sha256(
            gate.get("generation_key"), "GENERATION_KEY"
        ),
        "source_archive_sha256": _require_sha256(
            gate.get("source_archive_sha256"), "SOURCE_ARCHIVE_SHA256"
        ),
        "source_last_modified": str(gate.get("prior_source_last_modified") or ""),
        "stage_tool_sha256": _require_sha256(
            gate.get("stage_tool_sha256"), "STAGE_TOOL_SHA256"
        ),
        "acquisition_tool_sha256": _require_sha256(
            gate.get("acquisition_tool_sha256"), "ACQUISITION_TOOL_SHA256"
        ),
        "consumer_exact_head": consumer_exact_head,
        "generation_gate_sha256": gate_sha,
        "generation_reuse": True,
        "validation_subset": False,
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
    }
    if not envelope["source_last_modified"]:
        raise RuntimeError("SOURCE_LAST_MODIFIED_MISSING")
    envelope["lineage_envelope_sha256"] = _sha256_bytes(_canonical_bytes(envelope))
    return envelope


def validate_lineage_envelope(
    envelope: dict[str, object], *, consumer_exact_head: str
) -> str:
    supplied = _require_sha256(
        envelope.get("lineage_envelope_sha256"), "LINEAGE_ENVELOPE_SHA256"
    )
    payload = dict(envelope)
    payload.pop("lineage_envelope_sha256", None)
    actual = _sha256_bytes(_canonical_bytes(payload))
    if actual != supplied:
        raise RuntimeError("LINEAGE_ENVELOPE_SHA_MISMATCH")
    if envelope.get("gate") != GATE:
        raise RuntimeError("LINEAGE_ENVELOPE_GATE_MISMATCH")
    if envelope.get("consumer_exact_head") != consumer_exact_head:
        raise RuntimeError("LINEAGE_ENVELOPE_CONSUMER_HEAD_MISMATCH")
    if envelope.get("generation_reuse") is not True:
        raise RuntimeError("LINEAGE_ENVELOPE_REUSE_REQUIRED")
    if envelope.get("validation_subset") is not False:
        raise RuntimeError("LINEAGE_ENVELOPE_VALIDATION_SUBSET_FORBIDDEN")
    if envelope.get("responsible_person_payload_emitted") is not False:
        raise RuntimeError("LINEAGE_ENVELOPE_RESPONSIBLE_PERSON_FORBIDDEN")
    if envelope.get("mobile_per_invoice_network_lookup") is not False:
        raise RuntimeError("LINEAGE_ENVELOPE_PER_INVOICE_NETWORK_FORBIDDEN")
    for field in (
        "generation_key",
        "source_archive_sha256",
        "stage_tool_sha256",
        "acquisition_tool_sha256",
        "generation_gate_sha256",
        "producer_closure_sha256",
        "producer_materialization_sha256",
    ):
        _require_sha256(envelope.get(field), field.upper())
    return supplied


def _fixture_gate(consumer_head: str, producer_head: str) -> dict[str, object]:
    return {
        "schema_version": 1,
        "gate": "P4.20.3-full-residual-generation-gate",
        "current_head": consumer_head,
        "prior_success_head": producer_head,
        "prior_success_run_id": 41,
        "prior_closure_artifact_id": 1001,
        "prior_materialization_artifact_id": 1002,
        "prior_source_last_modified": "Sun, 06 Sep 2026 21:13:30 GMT",
        "source_archive_sha256": "1" * 64,
        "stage_tool_sha256": "2" * 64,
        "acquisition_tool_sha256": "3" * 64,
        "generation_key": "4" * 64,
        "run_expensive": False,
        "generation_artifact_reuse": True,
        "reasons": ["SAME_GENERATION_REUSE_APPROVED"],
        "validation_subset": False,
        "responsible_person_payload_emitted": False,
        "mobile_per_invoice_network_lookup": False,
    }


def self_test() -> None:
    consumer = "b" * 40
    producer = "a" * 40
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        gate_path = root / "generation_gate.json"
        gate = _fixture_gate(consumer, producer)
        gate_path.write_bytes(_canonical_bytes(gate))

        envelope = build_lineage_envelope(
            consumer_exact_head=consumer,
            generation_gate_path=gate_path,
            producer_closure_sha256="5" * 64,
            producer_materialization_sha256="6" * 64,
        )
        assert envelope["producer_head"] == producer
        assert envelope["consumer_exact_head"] == consumer
        validate_lineage_envelope(envelope, consumer_exact_head=consumer)

        # Consumer rebinding without same-head generation-gate evidence must fail.
        try:
            build_lineage_envelope(
                consumer_exact_head="c" * 40,
                generation_gate_path=gate_path,
                producer_closure_sha256="5" * 64,
                producer_materialization_sha256="6" * 64,
            )
            raise AssertionError("EXPECTED_CONSUMER_HEAD_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "GENERATION_GATE_CONSUMER_HEAD_MISMATCH"

        # Source/generation authority mutation changes the gate digest and cannot
        # preserve an already-issued envelope.
        gate["source_archive_sha256"] = "7" * 64
        gate_path.write_bytes(_canonical_bytes(gate))
        mutated = build_lineage_envelope(
            consumer_exact_head=consumer,
            generation_gate_path=gate_path,
            producer_closure_sha256="5" * 64,
            producer_materialization_sha256="6" * 64,
        )
        assert mutated["generation_gate_sha256"] != envelope["generation_gate_sha256"]

        # Producer evidence mutation with stale envelope self-hash must fail.
        bad = dict(envelope)
        bad["producer_closure_sha256"] = "8" * 64
        try:
            validate_lineage_envelope(bad, consumer_exact_head=consumer)
            raise AssertionError("EXPECTED_PRODUCER_MUTATION_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "LINEAGE_ENVELOPE_SHA_MISMATCH"

        # Envelope is explicitly dual-lineage; consumer lineage is mandatory.
        bad = dict(envelope)
        bad.pop("consumer_exact_head")
        payload = dict(bad)
        payload.pop("lineage_envelope_sha256", None)
        bad["lineage_envelope_sha256"] = _sha256_bytes(_canonical_bytes(payload))
        try:
            validate_lineage_envelope(bad, consumer_exact_head=consumer)
            raise AssertionError("EXPECTED_DUAL_LINEAGE_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "LINEAGE_ENVELOPE_CONSUMER_HEAD_MISMATCH"

    print("P4_20_3_GENERATION_LINEAGE_ENVELOPE_SELF_TEST=PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--consumer-exact-head")
    parser.add_argument("--generation-gate", type=Path)
    parser.add_argument("--producer-closure-sha256")
    parser.add_argument("--producer-materialization-sha256")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0
    required = (
        args.consumer_exact_head,
        args.generation_gate,
        args.producer_closure_sha256,
        args.producer_materialization_sha256,
        args.output,
    )
    if any(value in (None, "") for value in required):
        parser.error("lineage envelope production inputs are incomplete")

    envelope = build_lineage_envelope(
        consumer_exact_head=args.consumer_exact_head,
        generation_gate_path=args.generation_gate,
        producer_closure_sha256=args.producer_closure_sha256,
        producer_materialization_sha256=args.producer_materialization_sha256,
    )
    validate_lineage_envelope(envelope, consumer_exact_head=args.consumer_exact_head)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(_canonical_bytes(envelope) + b"\n")
    print(f"P4_20_3_GENERATION_LINEAGE_ENVELOPE_SHA256={envelope['lineage_envelope_sha256']}")
    print("P4_20_3_GENERATION_LINEAGE_ENVELOPE=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
