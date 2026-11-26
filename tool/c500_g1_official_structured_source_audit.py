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


def json_success_response_fields(op, components):
    """Enumerate bounded 2xx JSON response schemas, including local response refs.

    This is source-discovery evidence only. Unresolved refs are counted as
    unknown, never as evidence that no official award-record API exists.
    """
    responses = op.get("responses", {})
    if not isinstance(responses, dict):
        return set(), 0, 1
    response_defs = components.get("responses", {})
    schema_defs = components.get("schemas", {})
    if not isinstance(response_defs, dict):
        response_defs = {}
    if not isinstance(schema_defs, dict):
        schema_defs = {}
    found, scanned, unresolved = set(), 0, 0
    for status, response in responses.items():
        status = str(status)
        if len(status) != 3 or not status.isdigit() or not status.startswith("2"):
            continue
        visited = set()
        while isinstance(response, dict) and "$ref" in response:
            ref = response["$ref"]
            prefix = "#/components/responses/"
            if not isinstance(ref, str) or not ref.startswith(prefix):
                unresolved += 1
                response = None
                break
            name = ref[len(prefix):]
            if not name or name in visited or name not in response_defs:
                unresolved += 1
                response = None
                break
            visited.add(name)
            response = response_defs[name]
        if not isinstance(response, dict):
            unresolved += 1 if response is not None else 0
            continue
        content = response.get("content", {})
        if not isinstance(content, dict):
            unresolved += 1
            continue
        for media_type, media in content.items():
            if not isinstance(media_type, str) or not isinstance(media, dict):
                continue
            kind = media_type.split(";", 1)[0].strip().lower()
            if kind == "application/json" or (kind.startswith("application/") and kind.endswith("+json")):
                scanned += 1
                found.update(fields(media.get("schema"), schema_defs))
    return found, scanned, unresolved

def audit_spec(data):
    try:
        doc = json.loads(data.decode("utf-8-sig"))
    except (ValueError, UnicodeError) as exc:
        raise AuditError("INVALID_JSON") from exc
    if not isinstance(doc, dict) or not str(doc.get("openapi","")).startswith("3."):
        raise AuditError("INVALID_OPENAPI_VERSION")
    paths = doc.get("paths")
    components = doc.get("components", {})
    if not isinstance(components, dict):
        raise AuditError("MISSING_PATHS_OR_SCHEMAS")
    defs = components.get("schemas", {})
    if not isinstance(paths, dict) or not isinstance(defs, dict):
        raise AuditError("MISSING_PATHS_OR_SCHEMAS")
    total, prize, candidate = 0, [], []
    scanned_json_schemas = unresolved_response_refs = 0
    for path, methods in sorted(paths.items()):
        op = methods.get("get") if isinstance(methods, dict) else None
        if not isinstance(op, dict):
            continue
        total += 1
        # Do not silently exclude an official cloud/award endpoint merely
        # because its route omits the English word "prize".
        hint = path.lower()
        if not (any(word in hint for word in ("prize", "award", "cloud", "500", "獎")) or
                "獎" in str(op.get("tags", [])) or
                "獎" in str(op.get("summary", ""))):
            continue
        prize.append(path)
        k, scanned, unresolved = json_success_response_fields(op, components)
        scanned_json_schemas += scanned
        unresolved_response_refs += unresolved
        if (k & {"invoiceno","invoicenumber","invnum","發票號碼","中獎號碼"} and
            k & {"period","invoiceym","awarddatenm","發票歸屬期別","開獎期別"} and
            k & {"prizetier","awardtier","awardname","prizenm","獎別"}):
            candidate.append(path)
    if not total:
        raise AuditError("NO_GET_OPERATIONS")
    return {"get_operations":total,"prize_paths":prize,
            "possible_record_schema_paths":candidate,
            "json_success_schemas_scanned":scanned_json_schemas,
            "unresolved_response_refs":unresolved_response_refs,
            "record_count_proven":False,"tier_completeness_proven":False}

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
