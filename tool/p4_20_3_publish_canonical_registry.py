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
import json
import tempfile
from pathlib import Path

from p4_20_3_build_canonical_registry import build_canonical_registry


def _unlink_if_exists(path: Path) -> None:
    if path.exists():
        path.unlink()


def _publish_pair(
    candidate_output: Path,
    candidate_summary: Path,
    output_path: Path,
    summary_path: Path,
    *,
    failpoint: str | None = None,
) -> None:
    """Publish candidate payload+summary while preserving the prior LKG pair.

    File replacement cannot make two independent paths atomically visible as a
    pair. This routine therefore uses same-directory backups plus deterministic
    rollback. Any exception before full pair publication restores the exact old
    payload and summary bytes. Production callers never set ``failpoint``; it is
    reserved for focused failure-injection regression coverage.
    """

    if output_path.parent.resolve() != summary_path.parent.resolve():
        raise RuntimeError("PUBLISH_PAIR_DIRECTORY_MISMATCH")
    if not candidate_output.is_file() or not candidate_summary.is_file():
        raise RuntimeError("PUBLISH_CANDIDATE_PAIR_INCOMPLETE")

    output_exists = output_path.exists()
    summary_exists = summary_path.exists()
    if output_exists != summary_exists:
        raise RuntimeError("LAST_KNOWN_GOOD_PAIR_INCOMPLETE")

    backup_output = output_path.with_suffix(output_path.suffix + ".lkg.bak")
    backup_summary = summary_path.with_suffix(summary_path.suffix + ".lkg.bak")
    _unlink_if_exists(backup_output)
    _unlink_if_exists(backup_summary)

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

        candidate_output.replace(output_path)
        if failpoint == "after_payload_publish":
            raise RuntimeError("INJECTED_PUBLISH_FAILURE:after_payload_publish")

        candidate_summary.replace(summary_path)
        if failpoint == "after_summary_publish":
            raise RuntimeError("INJECTED_PUBLISH_FAILURE:after_summary_publish")

        if old_pair:
            backup_output.unlink()
            backup_summary.unlink()
    except Exception:
        # Remove any partially published new generation before restoring LKG.
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
        # If old_pair is true but summary_backed is false, the original summary
        # was never moved and is already the correct LKG summary.

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

    # Candidate paths live under the final pair's filesystem so Path.replace()
    # remains same-filesystem and cannot degrade into a copy/delete operation.
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

        # Require the builder's persisted evidence to match its returned result
        # before publication. This also prevents publishing an absent/truncated
        # summary even if a future builder regression returns success.
        persisted = json.loads(candidate_summary.read_text(encoding="utf-8"))
        if persisted != result:
            raise RuntimeError("CANDIDATE_SUMMARY_RESULT_MISMATCH")
        if candidate_output.stat().st_size != result["canonical_entities_bytes"]:
            raise RuntimeError("CANDIDATE_PAYLOAD_SIZE_MISMATCH")

        _publish_pair(
            candidate_output,
            candidate_summary,
            output_path,
            summary_path,
        )
        return result


def _write_bytes(path: Path, value: bytes) -> None:
    path.write_bytes(value)


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        output = root / "canonical.ndjson"
        summary = root / "summary.json"

        # Failure after the new payload becomes visible must restore both exact
        # old files and clean rollback backups.
        old_payload = b'OLD-PAYLOAD\n'
        old_summary = b'{"generation":"old"}\n'
        _write_bytes(output, old_payload)
        _write_bytes(summary, old_summary)

        candidate_output = root / "candidate.ndjson"
        candidate_summary = root / "candidate.json"
        _write_bytes(candidate_output, b'NEW-PAYLOAD\n')
        _write_bytes(candidate_summary, b'{"generation":"new"}\n')

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
        assert not output.with_suffix(output.suffix + ".lkg.bak").exists()
        assert not summary.with_suffix(summary.suffix + ".lkg.bak").exists()

        # Failure while only the output has been backed up must also restore the
        # exact old pair; the untouched old summary must not be deleted.
        _write_bytes(candidate_output, b'NEW-PAYLOAD-2\n')
        _write_bytes(candidate_summary, b'{"generation":"new2"}\n')
        try:
            _publish_pair(
                candidate_output,
                candidate_summary,
                output,
                summary,
                failpoint="after_output_backup",
            )
            raise AssertionError("EXPECTED_OUTPUT_BACKUP_FAILURE")
        except RuntimeError as exc:
            assert str(exc) == "INJECTED_PUBLISH_FAILURE:after_output_backup"

        assert output.read_bytes() == old_payload
        assert summary.read_bytes() == old_summary

        # A successful publication replaces both members and leaves no backup.
        _write_bytes(candidate_output, b'FINAL-PAYLOAD\n')
        _write_bytes(candidate_summary, b'{"generation":"final"}\n')
        _publish_pair(candidate_output, candidate_summary, output, summary)
        assert output.read_bytes() == b'FINAL-PAYLOAD\n'
        assert summary.read_bytes() == b'{"generation":"final"}\n'
        assert not output.with_suffix(output.suffix + ".lkg.bak").exists()
        assert not summary.with_suffix(summary.suffix + ".lkg.bak").exists()

        # Pre-existing half-generation state is not a valid LKG and must fail
        # closed before candidate publication mutates either final path.
        summary.unlink()
        _write_bytes(candidate_output, b'IGNORED\n')
        _write_bytes(candidate_summary, b'{}\n')
        try:
            _publish_pair(candidate_output, candidate_summary, output, summary)
            raise AssertionError("EXPECTED_INCOMPLETE_LKG_HOLD")
        except RuntimeError as exc:
            assert str(exc) == "LAST_KNOWN_GOOD_PAIR_INCOMPLETE"
        assert output.read_bytes() == b'FINAL-PAYLOAD\n'
        assert not summary.exists()

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
