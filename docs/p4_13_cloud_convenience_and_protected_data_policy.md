# P4.13.0 Cloud Convenience and Protected-Data Policy

- Decision date: 2026-06-20
- Issue: #539
- Applies to: cloud invoice, external analysis, future synchronization, local database, backup and restore
- Decision status: architecture and governance baseline

## 1. Product objective

The product should complete as much work as practical inside the app and automate repetitive steps when the user has knowingly enabled that behavior.

The desired experience is:

```text
User grants granular consent
  -> app performs the approved acquisition or handoff
  -> app validates and normalizes data
  -> app reconciles against existing records
  -> app presents conflicts and material decisions
  -> app applies only the actions covered by the selected automation level
  -> app keeps an auditable result and allows revoke / delete / export
```

Convenience is the default optimization target. Data protection and access-control boundaries are release gates, not optional follow-up work.

## 2. Engineering decision gate

The project no longer requires positive written proof of official eligibility before every user-controlled cloud experiment.

A flow may enter design or bounded POC when:

1. no current public source reviewed by the project expressly prohibits the proposed behavior;
2. the behavior uses normal user-visible interaction or a supported platform interface;
3. the user is authorized to access the data and gives informed consent to the app action;
4. the flow does not bypass authentication, authorization, CAPTCHA, anti-bot, rate-limit or other technical controls;
5. the data lifecycle, retention, revoke, delete and security boundaries are defined.

This is a `NO_KNOWN_PUBLIC_PROHIBITION` engineering gate. It is not a legal opinion or a claim that the behavior is officially endorsed.

A lack of discovered prohibition is insufficient when the implementation depends on circumvention, silent collection, unrelated third-party data, or a clearly restricted interface.

## 3. Hard-block matrix

| Behavior | Decision | Reason |
| --- | --- | --- |
| User opens an official page and completes authentication personally | Eligible | User-visible and user-controlled |
| User-triggered WebView / Custom Tab / browser download | Eligible for POC | Must pass host, MIME, lifecycle and consent gates |
| Transient use of a current session cookie for the exact user-triggered official download | Security review required | May be allowed only in memory, one-shot, no log/persistence/backup |
| Automatic import immediately after a validated user-triggered download | Eligible after consent | Must be cancellable, visible and idempotent |
| Scheduled synchronization using an officially supported token flow | Future review | Requires token lifecycle, revocation, rate-limit and retention controls |
| Hidden endpoint reconstructed from browser traffic | Blocked | Unsupported/private interface dependency |
| Authentication, CAPTCHA, anti-bot or authorization bypass | Blocked | Circumvents access controls |
| Storing password or verification code | Blocked | Excessive credential custody |
| Hardcoded shared encryption key | Blocked | Compromise affects all installations |
| Silent collection outside the consented purpose | Blocked | Violates purpose and user-control boundary |
| Automatic formal transaction creation without reconciliation controls | Blocked | Financial-data integrity risk |

## 4. Consent receipt model

Every external-data or automated cloud capability must be representable by an auditable consent receipt.

Minimum fields:

```text
consent_id
policy_version
feature_id
purpose
source_service
approved_data_categories
automation_level
sync_frequency
retention_policy
credential_custody_mode
export_policy
delete_policy
granted_at
last_confirmed_at
revoked_at
```

### Consent requirements

- Granular: unrelated capabilities cannot be bundled into one unavoidable consent.
- Informed: the UI states what is collected, why, where it is stored, how long, and whether it leaves the device.
- Explicit: no preselected opt-in for sensitive collection or background automation.
- Revocable: future access stops after revocation and retained data follows the selected delete/keep policy.
- Versioned: a material scope change requires re-consent.
- Auditable: store the decision and policy version, not credentials or sensitive page content.

### Automation levels

| Level | Behavior |
| --- | --- |
| `manual_handoff` | App opens a supported destination; user returns with a file or result |
| `user_triggered_once` | One visible operation runs after explicit action |
| `assisted_session` | App performs multiple steps inside one foreground session with progress and cancel controls |
| `scheduled_sync` | App runs periodically after separate opt-in; requires token, revocation and failure controls |
| `formal_write` | Financial records may be committed only under existing duplicate/reconciliation policy |

Consent to data collection does not automatically grant `formal_write` authority.

## 5. Data classification and protection

| Class | Examples | Storage rule |
| --- | --- | --- |
| Authentication secret | Password, verification code, CAPTCHA answer | Never persist; never log |
| Session secret | Cookie, authorization header, CSRF token | Ephemeral memory only when strictly required; short lifetime; clear on exit/failure |
| Financial source data | Invoice number, seller, amount, line items, carrier metadata | Encrypted at rest after the production encryption gate; purpose/retention scoped |
| Derived financial data | Reconciliation result, account mapping, duplicate fingerprint | Encrypted at rest; auditable and idempotent |
| Consent/audit metadata | Policy version, scope, timestamps, operation status | Persist without embedding secrets or raw page content |
| Temporary import bytes | CSV or image pending parse | Private cache only; validate; delete after parse/cancel/failure/restart cleanup |
| Readable export | JSON/CSV intended for inspection | Explicitly identify whether plaintext or encrypted; never imply protection that is absent |

## 6. Session and temporary-file lifecycle

For an authenticated one-shot import:

```text
explicit user action
  -> create foreground operation id
  -> obtain only the minimum transient session material
  -> enforce HTTPS and source-host allowlist
  -> receive into private temporary storage
  -> verify redirect host, MIME, extension/signature and size
  -> parse into typed candidates
  -> discard raw bytes
  -> clear cookies/cache/storage/session material
  -> show result, conflicts and cleanup status
```

Mandatory failure behavior:

- cancel when the app leaves the foreground unless the user enabled a separately approved continuation mode;
- delete temporary bytes after timeout, cancellation, parse failure or process-restart cleanup;
- never include secret-bearing URLs, headers or payloads in logs;
- fail closed when source host, redirect, MIME or signature is unexpected.

## 7. Formal financial-write boundary

Maximum automation does not mean uncontrolled writes.

The following may be automated after consent:

- source acquisition;
- parse and normalization;
- duplicate detection;
- reconciliation ranking;
- application of previously confirmed deterministic mappings;
- creation of non-formal candidates or drafts;
- notification that decisions are required.

A formal transaction may be created automatically only after a separate policy stage proves all of the following:

- the user selected an automation rule that explicitly includes formal writes;
- deterministic account/category/merchant resolution is available;
- duplicate and replay checks are atomic;
- ambiguous matches remain blocked;
- every write is auditable and reversible where practical;
- a global kill switch and per-source revoke control exist.

Until then, the current P4.12 review and promotion gates remain active.

## 8. Encryption work split

Local database encryption and backup-file encryption are separate deliverables.

### P4.SEC.1 — encrypted backup envelope POC

Required proof:

- authenticated encryption, not encryption-only;
- password/key derivation parameters stored safely with the envelope;
- no plaintext temporary full-backup file;
- wrong-password and tamper detection;
- explicit recovery warning;
- backward-compatible detection of legacy plaintext backups;
- restore remains preview/validation first.

Recommended envelope fields:

```text
format_version
cipher_suite
kdf
kdf_parameters
salt
nonce
ciphertext
authentication_tag
created_at
app_schema_version
```

### P4.SEC.2 — local database encryption POC

Required proof:

- branch-only SQLCipher-compatible or equivalent experiment;
- Android signed release build opens an encrypted sample database;
- wrong key fails without mutation;
- key is not hardcoded or derived only from an app constant;
- representative account, transaction, invoice and audit data survive open/restart;
- current production database route remains unchanged;
- dependency maintenance, license, native ABI and shrinker risks are recorded.

### Production migration gate

No production database migration until:

- key model and recovery behavior are selected;
- existing plaintext DB migration has transactional copy, integrity checks and rollback;
- kill-during-migration is tested;
- pre/post-encryption backup compatibility is tested;
- signed-device upgrade validation shows no data loss;
- user-facing privacy text matches the real boundary.

## 9. Current issue alignment

### #516 — API eligibility exit gate

Positive written eligibility is no longer a mandatory blocker for all user-controlled workflows.

Keep these conclusions:

- no authentication/access-control bypass;
- no hidden/private endpoint dependency;
- no unsupported background credential replay;
- public restrictions and applicable terms remain hard blocks.

The issue may be closed as superseded by this decision record while official clarification remains useful evidence rather than a universal prerequisite.

### #518 / #538 — in-app authenticated CSV handoff POC

This is the preferred convenience experiment because it can keep login, export, validation and import in one foreground user-controlled session.

Proceed only with:

- explicit user action;
- transient session material;
- official host allowlist;
- private temporary cache;
- direct parser handoff;
- complete cleanup and signed-device evidence.

### #536 / #537 — external-browser fallback

Retain as a fallback and recovery path. Do not treat it as the final product experience until the bounded in-app POC reaches PASS or FAIL.

## 10. Delivery order

1. Merge this policy baseline after CI and owner approval.
2. Execute #538 as the next bounded functional POC.
3. Keep #536 unmerged as fallback while #538 is unresolved.
4. Open P4.SEC.1 encrypted backup envelope POC.
5. Open P4.SEC.2 local database encryption POC.
6. Add production consent settings, retention/delete controls and operation audit before scheduled automation.
7. Reassess formal-write automation only after the preceding controls pass.

## 11. Release acceptance

A cloud convenience feature is not release-ready unless:

- consent scope and automation level are visible;
- the operation can be cancelled and revoked;
- secrets are not persisted or logged;
- retained financial data uses the approved protection boundary;
- temporary files and sessions are cleaned on every path;
- duplicates/replay are prevented;
- failure is visible and recoverable;
- signed-device tests cover upgrade, interruption and cleanup;
- no known public prohibition or explicit platform restriction has been identified for the exact implementation.

## References

- Taiwan Ministry of Justice Laws & Regulations Database — Personal Data Protection Act: `https://law.moj.gov.tw/LawClass/LawAll.aspx?pcode=I0050021`
- Ministry of Finance E-Invoice Platform: `https://www.einvoice.nat.gov.tw/`
- Existing feasibility record: `docs/p4_sec_local_database_encryption_feasibility.md`
- Current P4 exit-gate record: `docs/p4_exit_gate_consumer_cloud_invoice_api_feasibility.md`
