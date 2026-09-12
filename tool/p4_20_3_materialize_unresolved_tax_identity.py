#!/usr/bin/env python3
"""Materialize FIA seller identity when only legal subtype remains unresolved."""

from __future__ import annotations
import argparse
import hashlib
import json
import re
import tempfile
from pathlib import Path

SELLER_RE = re.compile(r"^\d{8}$")
SOURCE_DATASET = "MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY"
EXPECTED_REASON = "gcis_legal_enrichment_missing"
INPUT_KEYS = frozenset({"seller_identifier","legal_name","organization_type","reason"})
OUTPUT_KEYS = frozenset({"record_type","seller_identifier","entity_type","legal_name","registration_status","parent_seller_identifier","source_dataset"})

def _line(record: dict[str, object]) -> bytes:
    return (json.dumps(record,ensure_ascii=False,sort_keys=True,separators=(",",":"))+"\n").encode("utf-8")

def materialize(unresolved_path: Path, output_dir: Path) -> dict[str, object]:
    output_dir.mkdir(parents=True,exist_ok=True)
    output_path=output_dir/"unknown_entities.ndjson"
    previous=""
    input_count=0
    input_sha=hashlib.sha256()
    output_sha=hashlib.sha256()
    with unresolved_path.open("rb") as source, output_path.open("wb") as out:
        for line_number,raw in enumerate(source,1):
            if not raw.strip():
                continue
            input_sha.update(raw)
            record=json.loads(raw)
            if not isinstance(record,dict) or frozenset(record)!=INPUT_KEYS:
                raise ValueError(f"INPUT_SURFACE_MISMATCH:{line_number}")
            seller=str(record["seller_identifier"]).strip()
            legal_name=str(record["legal_name"]).strip()
            reason=str(record["reason"]).strip()
            if not SELLER_RE.fullmatch(seller):
                raise ValueError(f"INVALID_SELLER_IDENTIFIER:{line_number}")
            if previous and seller<=previous:
                raise ValueError(f"INPUT_NOT_SORTED_OR_DUPLICATE:{line_number}")
            if not legal_name:
                raise ValueError(f"LEGAL_NAME_REQUIRED:{line_number}")
            if reason!=EXPECTED_REASON:
                raise ValueError(f"UNSUPPORTED_UNRESOLVED_REASON:{seller}:{reason}")
            previous=seller
            input_count+=1
            entity={"record_type":"entity","seller_identifier":seller,"entity_type":"unknown","legal_name":legal_name,"registration_status":"active_tax_registration","parent_seller_identifier":"","source_dataset":SOURCE_DATASET}
            if frozenset(entity)!=OUTPUT_KEYS:
                raise AssertionError("INTERNAL_OUTPUT_SURFACE_MISMATCH")
            encoded=_line(entity)
            out.write(encoded)
            output_sha.update(encoded)
    result={"schema_version":1,"gate":"P4.20.3-D-fia-unresolved-tax-identity-materialization","input_unresolved_count":input_count,"unknown_entity_count":input_count,"input_unresolved_payload_sha256":input_sha.hexdigest(),"unknown_entity_payload_sha256":output_sha.hexdigest(),"entity_type":"unknown","identity_authority":SOURCE_DATASET,"legal_subtype_inference_used":False,"merchant_name_inference_used":False,"responsible_person_payload_emitted":False,"mobile_per_invoice_network_lookup":False,"classification_refinement_required":input_count>0,"final_mobile_registry":False}
    (output_dir/"unknown_identity_manifest.json").write_text(json.dumps(result,ensure_ascii=False,sort_keys=True,separators=(",",":"))+"\n",encoding="utf-8")
    print("P4_20_3_UNRESOLVED_TAX_IDENTITY_MATERIALIZATION=PASS")
    print(json.dumps(result,ensure_ascii=False,sort_keys=True))
    return result

def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root=Path(temp)
        source=root/"unresolved.ndjson"
        source.write_bytes(_line({"seller_identifier":"11111111","legal_name":"甲有限合夥","organization_type":"有限合夥","reason":EXPECTED_REASON})+_line({"seller_identifier":"22222222","legal_name":"乙合作社","organization_type":"合作社","reason":EXPECTED_REASON}))
        result=materialize(source,root/"out")
        assert result["unknown_entity_count"]==2
        rows=[json.loads(line) for line in (root/"out"/"unknown_entities.ndjson").read_text(encoding="utf-8").splitlines()]
        assert [row["entity_type"] for row in rows]==["unknown","unknown"]
        assert result["legal_subtype_inference_used"] is False
    print("P4_20_3_UNRESOLVED_TAX_IDENTITY_SELFTEST=PASS")

def main() -> None:
    parser=argparse.ArgumentParser()
    parser.add_argument("unresolved",nargs="?",type=Path)
    parser.add_argument("output_dir",nargs="?",type=Path)
    parser.add_argument("--self-test",action="store_true")
    args=parser.parse_args()
    if args.self_test:
        self_test(); return
    if args.unresolved is None or args.output_dir is None:
        parser.error("unresolved and output_dir are required unless --self-test is used")
    materialize(args.unresolved,args.output_dir)

if __name__=="__main__":
    main()
