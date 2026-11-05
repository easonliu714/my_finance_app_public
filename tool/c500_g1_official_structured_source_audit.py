#!/usr/bin/env python3
"""Read-only bounded official C500-G1 publication-scope audit; NOT award authority."""
import hashlib
from html.parser import HTMLParser
import json
import sys
from urllib.request import HTTPRedirectHandler, Request, build_opener, urlopen

SPEC = "https://www.einvoice.nat.gov.tw/portal/ods/openapi.json"
INDEX = "https://invoice.etax.nat.gov.tw/cloudListNumber.html"
MAX_BYTES = 2000000

class AuditError(Exception):
    pass

# Fail closed before an HTTP redirect can send a second request to any host.
# Checking the final URL after urlopen follows redirects is insufficient.
class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise AuditError("HTTP_REDIRECT_REJECTED")

def fetch(url, opener=None):
    if url not in (SPEC, INDEX):
        raise AuditError("UNAPPROVED_URL")
    if opener is None:
        opener = build_opener(NoRedirect()).open
    try:
        with opener(Request(url, headers={"User-Agent":"C500-G1-readonly/1.0"}), timeout=25) as r:
            if r.geturl() != url or r.status != 200:
                raise AuditError("HTTP_OR_REDIRECT_REJECTED")
            data = r.read(MAX_BYTES + 1)
    except AuditError:
        raise
    except Exception as exc:
        raise AuditError("FETCH_" + type(exc).__name__) from exc
    if not data or len(data) > MAX_BYTES:
        raise AuditError("EMPTY_OR_OVERSIZE")
    return data

def fields(schema, defs, seen=None):
    if not isinstance(schema, dict):
        return set()
    seen = set() if seen is None else seen
    ref = schema.get("$ref")
    if ref:
        prefix = "#/components/schemas/"
        if not isinstance(ref, str) or not ref.startswith(prefix):
            return set()
        name = ref[len(prefix):]
        return set() if name in seen else fields(defs.get(name), defs, seen | {name})
    result = set()
    props = schema.get("properties", {})
    if isinstance(props, dict):
        result.update(str(k).lower() for k in props)
        for v in props.values():
            result.update(fields(v, defs, seen))
    result.update(fields(schema.get("items"), defs, seen))
    for key in ("allOf", "oneOf", "anyOf"):
        seq = schema.get(key, [])
        if isinstance(seq, list):
            for child in seq:
                result.update(fields(child, defs, seen))
    return result

def audit_spec(data):
    try:
        doc = json.loads(data.decode("utf-8-sig"))
    except (ValueError, UnicodeError) as exc:
        raise AuditError("INVALID_JSON") from exc
    if not isinstance(doc, dict) or not str(doc.get("openapi","")).startswith("3."):
        raise AuditError("INVALID_OPENAPI_VERSION")
    paths = doc.get("paths")
    defs = doc.get("components",{}).get("schemas",{})
    if not isinstance(paths, dict) or not isinstance(defs, dict):
        raise AuditError("MISSING_PATHS_OR_SCHEMAS")
    total, prize, candidate = 0, [], []
    for path, methods in sorted(paths.items()):
        op = methods.get("get") if isinstance(methods, dict) else None
        if not isinstance(op, dict):
            continue
        total += 1
        if not ("prize" in path.lower() or "獎" in str(op.get("tags",[])) or "獎" in str(op.get("summary",""))):
            continue
        prize.append(path)
        resp = op.get("responses",{}).get("200",{})
        media = resp.get("content",{}).get("application/json",{}) if isinstance(resp,dict) else {}
        k = fields(media.get("schema"), defs)
        if (k & {"invoiceno","invoicenumber","invnum","發票號碼","中獎號碼"} and
            k & {"period","invoiceym","awarddatenm","發票歸屬期別","開獎期別"} and
            k & {"prizetier","awardtier","awardname","prizenm","獎別"}):
            candidate.append(path)
    if not total:
        raise AuditError("NO_GET_OPERATIONS")
    return {"get_operations":total,"prize_paths":prize,
            "possible_record_schema_paths":candidate,"record_count_proven":False,
            "tier_completeness_proven":False}

class Anchors(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links=[]
    def handle_starttag(self,tag,attrs):
        if tag.lower()=="a":
            self.links.extend(v for k,v in attrs if k.lower()=="href" and v)

def audit_index(data):
    try:
        html = data.decode("utf-8-sig")
    except UnicodeError as exc:
        raise AuditError("INVALID_INDEX_UTF8") from exc
    parser=Anchors()
    parser.feed(html)
    links=[v.lower().split("?",1)[0].split("#",1)[0] for v in parser.links]
    return {"anchors":len(links),"pdf_links":sum(v.endswith(".pdf") for v in links),
            "csv_json_links":sum(v.endswith((".csv",".json")) for v in links),
            "complete_500_record_source_proven":False}

def audit_pair(spec,index):
    return {"gate":"C500_G1_OFFICIAL_STRUCTURED_SCOPE",
            "openapi":{"url":SPEC,"bytes":len(spec),"sha256":hashlib.sha256(spec).hexdigest(),**audit_spec(spec)},
            "cloud_index":{"url":INDEX,"bytes":len(index),"sha256":hashlib.sha256(index).hexdigest(),**audit_index(index)},
            "decision":"HOLD_PUBLISHED_SCOPE_ONLY","option4_no_go":False,
            "global_not_win":"HOLD","g5_owner_choice":"PENDING",
            "caution":"These two publication surfaces cannot establish absence from all MOF systems."}

def main():
    try:
        result=audit_pair(fetch(SPEC),fetch(INDEX))
    except AuditError as exc:
        print(json.dumps({"gate":"C500_G1_OFFICIAL_STRUCTURED_SCOPE",
                          "decision":"HOLD_SOURCE_UNAVAILABLE","error":str(exc),
                          "global_not_win":"HOLD"}))
        return 42
    print(json.dumps(result,ensure_ascii=False,sort_keys=True))
    return 0

if __name__=="__main__":
    sys.exit(main())
