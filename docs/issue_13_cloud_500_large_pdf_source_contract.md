# Issue #13 — Large cloud-500 PDF source contract

Status: diagnostic/source-characterization scaffold only. This document does not authorize award promotion.

## Scope

This contract exists for the only remaining owner gate: 115-07-08 cloud-500 candidate authority. The owner-tested 4.20.15+473 path fails closed with `PDFBOX_WORKER_OOM` in the isolated worker while the main App survives. The predecessor 115-05-06 cloud-500 path remains owner-CLOSED/PASS.

## Frozen safety boundaries

- MOF public page/PDF is the only award-number authority.
- Candidate universe is exact, local, on-device invoice numbers only.
- No invoice/accounting upload and no remote candidate submission.
- No private AJAX endpoint.
- No giant full-index fallback.
- No `largeHeap`, timeout-only, or blind retry workaround.
- General-award authority, LKG, durable PDF cache/source SHA/provenance and `FORMAL_ACCOUNTING_WRITE=ZERO` remain unchanged.
- Partial/crashed/unknown parsing never promotes cloud authority.

## Required characterization record

For each official artifact, record these values from the exact cached PDF bytes before selecting a parser:

| Field | 115-05-06 | 115-07-08 |
| --- | --- | --- |
| source URL | PENDING_BINARY | PENDING_BINARY |
| SHA-256 | PENDING_BINARY | PENDING_BINARY |
| byte length | ~114.2 MiB owner evidence | ~128.9 MiB owner evidence |
| PDF header/version | PENDING_BINARY | PENDING_BINARY |
| `startxref` offset | PENDING_BINARY | PENDING_BINARY |
| xref topology (table/stream/hybrid/incremental) | PENDING_BINARY | PENDING_BINARY |
| `/ObjStm` count | PENDING_BINARY | PENDING_BINARY |
| stream count | PENDING_BINARY | PENDING_BINARY |
| `/Filter` histogram | PENDING_BINARY | PENDING_BINARY |
| page-tree root/count | PENDING_BINARY | PENDING_BINARY |
| exact candidate token visible in raw bytes | PENDING_BINARY | PENDING_BINARY |
| bounded decoded-stream token recovery | PENDING_BINARY | PENDING_BINARY |

`PENDING_BINARY` is intentional fail-closed evidence. Filename or file-size inference MUST NOT replace any field above.

## Parser admission criteria

A production successor may replace the PDFBox whole-document open only after the exact official binaries establish a deterministic bounded strategy. An admitted strategy must:

1. avoid whole-document COS/object-graph materialization;
2. bound raw reads and each decoded stream/object independently;
3. search only the exact local candidate set;
4. emit source SHA plus byte/object/stream/page evidence for a hit;
5. reject unsupported xref/filter/object-stream topology explicitly;
6. never promote on partial scan, timeout, worker death, malformed structure, or unsupported encoding;
7. expose monotonic diagnostic stages such as `source-open`, `xref-scan`, `object-scan`, `stream-decode`, `candidate-match`, with byte/object/stream/page counters where applicable.

## Deterministic characterization procedure

When the two owner-cached official PDFs are available, characterize them without PDFBox/Pdfium document loading:

1. hash and byte-count the exact files;
2. read fixed-size head/tail windows to identify `%PDF-`, `%%EOF`, and the terminal `startxref` chain;
3. follow xref offsets with bounded random reads and classify table/stream/hybrid/incremental topology;
4. enumerate referenced stream dictionaries without materializing a document model;
5. record filters and declared stream lengths with hard per-object bounds;
6. test exact candidate bytes in raw data; if absent, decode only individually admitted streams with bounded output and test the exact candidate set;
7. retain deterministic evidence sufficient to map a hit to source SHA and byte/object/stream/page provenance.

## Implemented bounded probe scaffold

The branch now includes a production-safe diagnostic probe at
`lib/features/invoice/invoice_award_cloud_pdf_structure_probe.dart` plus focused synthetic topology tests.

The probe:

- uses `RandomAccessFile` fixed-size windows/chunks and never calls PDFBox/Pdfium document open;
- streams SHA-256 while scanning, so exact bytes can be bound to the characterization record;
- validates `%PDF-`, terminal `%%EOF`, terminal `startxref`, and classifies classic xref / xref-stream / hybrid forms;
- reports `/ObjStm`, stream, `/Filter`, `/Pages /Count`, `/Prev`, `/Encrypt`, and exact raw-visible local candidate evidence;
- keeps memory bounded to the configured scan chunk plus overlap window;
- fails closed on missing/invalid `startxref` and unsupported xref topology;
- is diagnostic only and is not wired to cloud-award authority promotion.

Synthetic tests cover classic xref, xref-stream, hybrid xref, invalid `startxref`, and a candidate token split across scan-chunk boundaries. Real official binary characterization is still required before stream decoding or candidate authority can be admitted.

For >120 MiB cloud-500 artifacts, the foreground acquisition path now runs this bounded probe before launching the legacy isolated worker. The UI receives a selectable non-sensitive diagnostic summary containing source SHA/bytes/PDF version/startxref/xref topology/incremental+encryption flags/object-stream and stream counts/filter histogram/page-count markers/raw-visible candidate hit count/window bound. Exact candidate invoice numbers are never included. Probe SHA and byte length must match the already validated cached artifact or the tier fails closed with `CLOUD_AWARD_PDF_STRUCTURE_SOURCE_MISMATCH`.

## Bounded stream-decoder scaffold

A second non-authority primitive is now defined for individually admitted PDF streams:

- hard limit on compressed bytes per stream;
- hard limit on decoded bytes per stream;
- chunked zlib/Flate decoding rather than whole-document parsing;
- only a single `FlateDecode` / `Fl` filter is admitted by the scaffold;
- multi-filter chains and all other filters fail closed until exact official-binary characterization explicitly admits them;
- malformed Flate and decompression expansion beyond the configured bound fail closed;
- this decoder is not connected to award promotion or the >120 MiB worker yet.

Deterministic tests cover raw pass-through, chunked Flate decode, the `Fl` abbreviation, unsupported filters, filter chains, compressed-byte limits, decompression-bomb limits, and malformed data.

## Current blocker

The repository does not contain the owner-cached 115-05-06 / 115-07-08 official PDF binaries. Until at least the failing 115-07-08 exact PDF is supplied, xref/object-stream/filter/token representation is unknown and production parser selection remains HOLD.
