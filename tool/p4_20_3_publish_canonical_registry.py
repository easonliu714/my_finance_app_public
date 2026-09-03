#!/usr/bin/env python3
"""P4.20.3 Gate E transactional canonical registry publisher.

Builds the nationwide canonical registry into generation-local candidate paths,
then publishes payload + summary as a rollback-safe pair. Existing validated
last-known-good files are never handed to the builder as mutable outputs.

This wrapper is the production publication entrypoint for Gate E. The underlying
canonical builder remains responsible for seller-only uniqueness, entity-type
preservation, branch-parent closure, canonical entity count, and payload SHA.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

from p4_20_3_build_canonical_registry import build_canonical_registry


def _unlink_if_exists(path: Path) -> None:
    if path.exists():
        path.unlink()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_published_pair(output_path: Path, summary_path: Path) -> None:
    """Validate that payload + summary are one complete committed generation."""

    if not output_path.is_file() or not summary_path.is_file():
        raise RuntimeError("PUBLISHED_PAIR_INCOMPLETE")
    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("PUBLISHED_SUMMARY_INVALID") from exc

    expected_bytes = summary.get("canonical_entities_bytes")
    expected_sha = summary.get("canonical_entities_sha256")
    if type(expected_bytes) is not int or expected_bytes < 0:
        raise RuntimeError("PUBLISHED_SUMMARY_BYTES_INVALID")
    if not isinstance(expected_sha, str) or len(expected_sha) != 64:
        raise RuntimeError("PUBLISHED_SUMMARY_SHA256_INVALID")
    try:
        int(expected_sha, 16)
    except ValueError as exc:
        raise RuntimeError("PUBLISHED_SUMMARY_SHA256_INVALID") from exc

    if output_path.stat().st_size != expected_bytes:
        raise RuntimeError("PUBLISHED_PAYLOAD_SIZE_MISMATCH")
    if _sha256_file(output_path) != expected_sha.lower():
        raise RuntimeError("PUBLISHED_PAYLOAD_SHA256_MISMATCH")


def _recover_publish_state(output_path: Path, summary_path: Path) -> None:
    """Recover an interrupted prior publication before any new mutation.

    The publication protocol intentionally keeps prior-generation backups until
    both new members are visible. A hard process kill or power loss can therefore
    leave one of several durable intermediate states. Recovery is deterministic:
    restore the old LKG when publication is incomplete; retain a fully validated
    new generation when both final members are present; fail closed for states
    that cannot be proven to come from this protocol.
    """

    backup_output = output_path.with_suffix(output_path.suffix + ".lkg.bak")
    backup_summary = summary_path.with_suffix(summary_path.suffix + ".lkg.bak")

    output_exists = output_path.exists()
    summary_exists = summary_path.exists()
    backup_output_exists = backup_output.exists()
    backup_summary_exists = backup_summary.exists()

    # Clean state: either a complete final pair or no prior generation at all.
    if not backup_output_exists and not backup_summary_exists:
        if output_exists != summary_exists:
            raise RuntimeError("LAST_KNOWN_GOOD_PAIR_INCOMPLETE")
        return

    # Both final members are visible. If they form a cryptographically coherent
    # generation, publication committed before the crash and backups are stale.
    if output_exists and summary_exists:
        try:
            _validate_published_pair(output_path, summary_path)
        except RuntimeError:
            if backup_output_exists and backup_summary_exists:
                _unlink_if_exists(output_path)
                _unlink_if_exists(summary_path)
                backup_output.replace(output_path)
                backup_summary.replace(summary_path)
                _validate_published_pair(output_path, summary_path)
                return
            raise RuntimeError("AMBIGUOUS_PUBLISH_STATE_INVALID_FINAL_PAIR")
        _unlink_if_exists(backup_output)
        _unlink_if_exists(backup_summary)
        return

    # Crash after backing up only payload: summary is still the old final member.
    if (
        not output_exists
        and summary_exists
        and backup_output_exists
        and not backup_summary_exists
    ):
        backup_output.replace(output_path)
        _validate_published_pair(output_path, summary_path)
        return

    # Crash after both old members were backed up, before publishing candidate.
    if (
        not output_exists
        and not summary_exists
        and backup_output_exists
        and backup_summary_exists
    ):
        backup_output.replace(output_path)
        backup_summary.replace(summary_path)
        _validate_published_pair(output_path, summary_path)
        return

    # Crash after candidate payload became visible but before candidate summary.
    # The complete prior LKG pair remains in backups, so discard the uncommitted
    # candidate payload and restore the old pair byte-for-byte.
    if (
        output_exists
        and not summary_exists
        and backup_output_exists
        and backup_summary_exists
    ):
        _unlink_if_exists(output_path)
        backup_output.replace(output_path)
        backup_summary.replace(summary_path)
        _validate_published_pair(output_path, summary_path)
        return

    raise RuntimeError("AMBIGUOUS_PUBLISH_RECOVERY_STATE")


def _publish_pair(
    candidate_output: Path,
    candidate_summary: Path,
    output_path: Path,
    summary_path: Path,
    *,
    failpoint: str | None = None,
) -> None:
    """Publish candidate payload+summary while preserving the prior LKG pair."""

    if output_path.parent.resolve() != summary_path.parent.resolve():
        raise RuntimeError("PUBLISH_PAIR_DIRECTORY_MISMATCH")
    if not candidate_output.is_file() or not candidate_summary.is_file():
        raise RuntimeError("PUBLISH_CANDIDATE_PAIR_INCOMPLETE")

    # Never destroy durable crash-recovery evidence from an interrupted prior
    # process. Recover it first, then begin a new publication from a clean state.
    _recover_publish_state(output_path, summary_path)

    output_exists = output_path.exists()
    summary_exists = summary_path.exists()
    if output_exists != summary_exists:
        raise RuntimeError("LAST_KNOWN_GOOD_PAIR_INCOMPLETE")

    backup_output = output_path.with_suffix(output_path.suffix + ".lkg.bak")
    backup_summary = summary_path.with_suffix(summary_path.suffix + ".lkg.bak")
    if backup_output.exists() or backup_summary.exists():
        raise RuntimeError("PUBLISH_RECOVERY_BACKUP_NOT_CLEAN")

    old_pair = output_exists and summary_exists
    output_backed = False
    summary_backed = False

    try:
        if old_pair:
            output_path.replace(backup_output)
            output_backed = True
            if failpoint == "after_output_backup":
                raise RuntimeError("INJECTED_PUBLISH_FAILURE:after_output_backup")

            summary_path.replace(backup_summary)
            summary_backed = True
            if failpoint == "after_summary_backup":
                raise RuntimeError("INJECTED_PUBLISH_FAILURE:after_summary_backup")

        candidate_output.replace(output_path)
        if failpoint == "after_payload_publish":
            raise RuntimeError("INJECTED_PUBLISH_FAILURE:after_payload_publish")

        candidate_summary.replace(summary_path)
        if failpoint == "after_summary_publish":
            raise RuntimeError("INJECTED_PUBLISH_FAILURE:after_summary_publish")

        _validate_published_pair(output_path, summary_path)
        if old_pair:
            backup_output.unlink()
            backup_summary.unlink()
    except Exception:
        # Ordinary Python exceptions are rolled back immediately. Hard crashes
        # bypass this block; _recover_publish_state handles those on next start.
        if output_backed:
            _unlink_if_exists(output_path)
            backup_output.replace(output_path)
        elif not old_pair:
            _unlink_if_exists(output_path)

        if summary_backed:
            _unlink_if_exists(summary_path)
            backup_summary.replace(summary_path)
        elif not old_pair:
            _unlink_if_exists(summary_path)

        _unlink_if_exists(backup_output)
        _unlink_if_exists(backup_summary)
        raise


def build_and_publish(
    ready_path: Path,
    enriched_path: Path,
    output_path: Path,
    summary_path: Path,
) -> dict[str, object]:
    """Build into an isolated generation and rollback-safely publish the pair."""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.parent.resolve() != summary_path.parent.resolve():
        raise RuntimeError("PUBLISH_PAIR_DIRECTORY_MISMATCH")

    # Recover any interrupted prior transaction before spending time building a
    # new nationwide candidate. This also guarantees old LKG availability to the
    # handset while a new generation is prepared.
    _recover_publish_state(output_path, summary_path)

    with tempfile.TemporaryDirectory(
        prefix=".p4_20_3_registry_generation_", dir=output_path.parent
    ) as temp_dir:
        generation = Path(temp_dir)
        candidate_output = generation / "canonical.ndjson"
        candidate_summary = generation / "summary.json"

        result = build_canonical_registry(
            ready_path,
            enriched_path,
            candidate_output,
            candidate_summary,
        )

        persisted = json.loads(candidate_summary.read_text(encoding="utf-8"))
        if persisted != result:
            raise RuntimeError("CANDIDATE_SUMMARY_RESULT_MISMATCH")
        if candidate_output.stat().st_size != result["canonical_entities_bytes"]:
            raise RuntimeError("CANDIDATE_PAYLOAD_SIZE_MISMATCH")
        _validate_published_pair(candidate_output, candidate_summary)

        _publish_pair(
            candidate_output,
            candidate_summary,
            output_path,
            summary_path,
        )
        return result


def _write_generation(output: Path, summary: Path, payload: bytes) -> None:
    output.write_bytes(payload)
    summary.write_text(
        json.dumps(
            {
                "canonical_entities_bytes": len(payload),
                "canonical_entities_sha256": hashlib.sha256(payload).hexdigest(),
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        output = root / "canonical.ndjson"
        summary = root / "summary.json"
        backup_output = output.with_suffix(output.suffix + ".lkg.bak")
        backup_summary = summary.with_suffix(summary.suffix + ".lkg.bak")

        old_payload = b'OLD-PAYLOAD\n'
        new_payload = b'NEW-PAYLOAD\n'
        _write_generation(output, summary, old_payload)
        old_summary = summary.read_bytes()

        # Ordinary exception after candidate payload publication restores LKG.
        candidate_output = root / "candidate.ndjson"
        candidate_summary = root / "candidate.json"
        _write_generation(candidate_output, candidate_summary, new_payload)
        try:
            _publish_pair(
                candidate_output,
                candidate_summary,
                output,
                summary,
                failpoint="after_payload_publish",
            )
            raise AssertionError("EXPECTED_TRANSACTIONAL_PUBLISH_FAILURE")
        except RuntimeError as exc:
            assert str(exc) == "INJECTED_PUBLISH_FAILURE:after_payload_publish"
        assert output.read_bytes() == old_payload
        assert summary.read_bytes() == old_summary
        assert not backup_output.exists() and not backup_summary.exists()

        # Fresh-process recovery: crash after only the old payload was backed up.
        output.replace(backup_output)
        _recover_publish_state(output, summary)
        assert output.read_bytes() == old_payload
        assert summary.read_bytes() == old_summary
        assert not backup_output.exists()

        # Fresh-process recovery: crash after both old members were backed up.
        output.replace(backup_output)
        summary.replace(backup_summary)
        _recover_publish_state(output, summary)
        assert output.read_bytes() == old_payload
        assert summary.read_bytes() == old_summary
        assert not backup_output.exists() and not backup_summary.exists()

        # Fresh-process recovery: uncommitted new payload visible, old LKG backed.
        output.replace(backup_output)
        summary.replace(backup_summary)
        output.write_bytes(new_payload)
        _recover_publish_state(output, summary)
        assert output.read_bytes() == old_payload
        assert summary.read_bytes() == old_summary
        assert not backup_output.exists() and not backup_summary.exists()

        # Fresh-process recovery: both new final members are complete, crash only
        # prevented backup cleanup. Valid new generation wins deterministically.
        output.replace(backup_output)
        summary.replace(backup_summary)
        _write_generation(output, summary, new_payload)
        new_summary = summary.read_bytes()
        _recover_publish_state(output, summary)
        assert output.read_bytes() == new_payload
        assert summary.read_bytes() == new_summary
        assert not backup_output.exists() and not backup_summary.exists()

        # Corrupt mixed final pair with a complete backup must restore old LKG.
        output.replace(backup_output)
        summary.replace(backup_summary)
        output.write_bytes(b'CORRUPT\n')
        summary.write_bytes(new_summary)
        _recover_publish_state(output, summary)
        assert output.read_bytes() == new_payload
        assert summary.read_bytes() == new_summary
        assert not backup_output.exists() and not backup_summary.exists()

        # Ambiguous state without a complete recoverable pair must fail closed.
        output.unlink()
        summary.unlink()
        backup_output.write_bytes(old_payload)
        try:
            _recover_publish_state(output, summary)
            raise AssertionError("EXPECTED_AMBIGUOUS_RECOVERY_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "AMBIGUOUS_PUBLISH_RECOVERY_STATE"
        assert backup_output.read_bytes() == old_payload
        assert not output.exists() and not summary.exists()

    print("P4_20_3_CANONICAL_TRANSACTIONAL_PUBLISH_SELFTEST=PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ready", nargs="?", type=Path)
    parser.add_argument("enriched", nargs="?", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("summary", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if None in (args.ready, args.enriched, args.output, args.summary):
        parser.error(
            "ready, enriched, output and summary are required unless --self-test is used"
        )

    result = build_and_publish(
        args.ready,
        args.enriched,
        args.output,
        args.summary,
    )
    print("P4_20_3_CANONICAL_TRANSACTIONAL_PUBLISH=PASS")
    print(f"CANONICAL_ENTITY_COUNT={result['canonical_entity_count']}")
    print(f"CANONICAL_ENTITIES_SHA256={result['canonical_entities_sha256']}")


if __name__ == "__main__":
    main()
