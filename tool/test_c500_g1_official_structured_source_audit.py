"""Synthetic G1 authority contracts; never real-source evidence."""
import json
import unittest
from unittest.mock import patch
from urllib.request import Request
from tool.c500_g1_official_structured_source_audit import (
    SPEC, MAX_BYTES, AuditError, NoRedirect, audit_spec, audit_index, audit_pair, fetch, fields)

def fixture(names):
    return json.dumps({"openapi":"3.0.1","paths":{"/api/v1/PrizeStatic":{
        "get":{"tags":["中獎落點統計"],"responses":{"200":{"content":{
            "application/json":{"schema":{"type":"array","items":{
                "type":"object","properties":{n:{} for n in names}}}}}}}}}},
        "components":{"schemas":{}}}).encode()

class Response:
    def __init__(self, data, url=SPEC, status=200):
        self.data,self.url,self.status=data,url,status
    def __enter__(self): return self
    def __exit__(self,*args): return False
    def geturl(self): return self.url
    def read(self,n): return self.data[:n]

class Tests(unittest.TestCase):
    def test_aggregate_is_not_record(self):
        self.assertEqual(audit_spec(fixture(["awardDateNm","prizeNm","prizeCnt"]))["possible_record_schema_paths"],[])
    def test_candidate_never_auto_passes(self):
        result=audit_pair(fixture(["invoiceNo","period","prizeTier"]),b'<a href="x.pdf">x</a>')
        self.assertEqual(len(result["openapi"]["possible_record_schema_paths"]),1)
        self.assertFalse(result["option4_no_go"])
        self.assertFalse(result["openapi"]["record_count_proven"])
        self.assertEqual(result["global_not_win"],"HOLD")
    def test_pdf_only_index(self):
        self.assertEqual(audit_index(b'<a href="x.pdf">x</a>')["csv_json_links"],0)
    def test_csv_is_not_completeness(self):
        self.assertFalse(audit_pair(fixture([]),b'<a href="x.csv">x</a>')["cloud_index"]["complete_500_record_source_proven"])
    def test_url_allowlist(self):
        with self.assertRaisesRegex(AuditError,"UNAPPROVED"):
            fetch("https://evil.test",opener=lambda *a,**k:self.fail("network"))
    def test_redirect(self):
        with self.assertRaisesRegex(AuditError,"REDIRECT"):
            fetch(SPEC,opener=lambda *a,**k:Response(b"{}",url="https://evil.test"))
    def test_default_opener_uses_no_redirect_handler(self):
        # Verify the real default path, not only a fake injected opener.
        with patch("tool.c500_g1_official_structured_source_audit.build_opener") as builder:
            builder.return_value.open.return_value = Response(b"{}", url=SPEC)
            self.assertEqual(fetch(SPEC), b"{}")
            self.assertIsInstance(builder.call_args.args[0], NoRedirect)

    def test_redirect_rejected_before_any_follow_up_request(self):
        # Exercise the actual urllib redirect handler for both same-origin and foreign targets.
        handler = NoRedirect()
        for code in (301, 302, 303, 307, 308):
            for target in (SPEC + "?next=1", "https://evil.test/collect"):
                with self.subTest(code=code, target=target):
                    with self.assertRaisesRegex(AuditError, "HTTP_REDIRECT_REJECTED"):
                        handler.http_error_302(
                            Request(SPEC), None, code, "Redirect",
                            {"location": target})

    def test_oversize(self):
        with self.assertRaisesRegex(AuditError,"OVERSIZE"):
            fetch(SPEC,opener=lambda *a,**k:Response(b"x"*(MAX_BYTES+1)))
    def test_http_status(self):
        with self.assertRaisesRegex(AuditError,"HTTP"):
            fetch(SPEC,opener=lambda *a,**k:Response(b"{}",status=403))
    def test_bad_json_and_version(self):
        for value in (b"{bad",b'{"openapi":"2.0","paths":{}}'):
            with self.assertRaises(AuditError): audit_spec(value)
    def test_empty_ops(self):
        with self.assertRaisesRegex(AuditError,"NO_GET"):
            audit_spec(b'{"openapi":"3.0.1","paths":{}}')
    def test_external_ref(self):
        self.assertEqual(fields({"$ref":"https://evil.test"},{}),set())
    def test_recursive_ref(self):
        self.assertEqual(fields({"$ref":"#/components/schemas/A"},{"A":{"$ref":"#/components/schemas/A"}}),set())

if __name__=="__main__": unittest.main()
