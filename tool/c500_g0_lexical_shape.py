#!/usr/bin/env python3
"""G0aj: bounded, privacy-preserving lexical-position evidence, NOT award semantics."""
import re

TOKEN = re.compile(r"(?<![0-9])[0-9]{8}(?![0-9])")


class LexicalShape:
    def __init__(self):
        self.pages = 0
        self.counts = {}
        self.drop_positions = {}
        self.single_drop_pages = 0
        self.zero_drop_pages = 0
        self.multi_drop_pages = 0
        self.boundary_descents = 0
        self.repeat_positions = {}
        self.prev = None
        # G0ak: strictly lexical candidate-body ordering; never award authority.
        self.header_reference = None
        self.header_mismatches = 0
        self.bad_body_count_pages = 0
        self.body_within_descents = 0
        self.body_boundary_descents = 0
        self.body_equal_pairs = 0
        self.previous_body_tail = None
        self.first_body_anomaly_page = 0

    def observe(self, raw):
        values = [int(v) for v in TOKEN.findall(raw.decode("utf-8", "strict"))]
        self._observe_candidate_body(values)
        if not 1 <= len(values) <= 8192:
            raise ValueError("G0AJ_CANDIDATE_COUNT_OUT_OF_BOUNDS")
        n = len(values)
        if n not in self.counts and len(self.counts) >= 32:
            raise ValueError("G0AJ_COUNT_VARIANTS_BOUND")
        self.counts[n] = self.counts.get(n, 0) + 1
        drops = [i for i in range(1, n) if values[i] < values[i - 1]]
        if not drops:
            self.zero_drop_pages += 1
        elif len(drops) == 1:
            self.single_drop_pages += 1
            idx = drops[0] + 1
            self.drop_positions[idx] = self.drop_positions.get(idx, 0) + 1
        else:
            self.multi_drop_pages += 1
        if self.prev is not None:
            if self.prev[-1] > values[0]:
                self.boundary_descents += 1
            if len(self.prev) == n:
                for idx, (a, b) in enumerate(zip(self.prev, values), start=1):
                    if a == b:
                        self.repeat_positions[idx] = self.repeat_positions.get(idx, 0) + 1
        self.prev = values
        self.pages += 1

    def _mark_body_anomaly(self):
        if not self.first_body_anomaly_page:
            self.first_body_anomaly_page = self.pages + 1

    def _observe_candidate_body(self, values):
        # Only the observed 51-token candidate layout is eligible for this
        # diagnostic. Neither the repeated first token nor the 50-token body
        # is promoted to a verified official award record.
        if len(values) != 51:
            self.bad_body_count_pages += 1
            self._mark_body_anomaly()
            self.previous_body_tail = None
            return
        header, body = values[0], values[1:]
        if self.header_reference is None:
            self.header_reference = header
        elif header != self.header_reference:
            self.header_mismatches += 1
            self._mark_body_anomaly()
        for left, right in zip(body, body[1:]):
            if right < left:
                self.body_within_descents += 1
                self._mark_body_anomaly()
            elif right == left:
                self.body_equal_pairs += 1
                self._mark_body_anomaly()
        if self.previous_body_tail is not None:
            if body[0] < self.previous_body_tail:
                self.body_boundary_descents += 1
                self._mark_body_anomaly()
            elif body[0] == self.previous_body_tail:
                self.body_equal_pairs += 1
                self._mark_body_anomaly()
        self.previous_body_tail = body[-1]

    def summary(self):
        if not self.pages:
            raise ValueError("G0AJ_NO_PAGES")
        # Strict global lexical-only proof; fail closed on ANY anomalous
        # candidate count, header drift, duplicate or order inversion.
        lexical_pass = (self.bad_body_count_pages == 0 and
                        self.header_mismatches == 0 and
                        self.body_within_descents == 0 and
                        self.body_boundary_descents == 0 and
                        self.body_equal_pairs == 0)
        body_status = "STRICT_50_LEXICAL_ONLY" if lexical_pass else "FAIL_CLOSED"
        top_drop = max(self.drop_positions.items(),
                       key=lambda kv: (kv[1], -kv[0]), default=(0, 0))
        top_repeat = max(self.repeat_positions.items(),
                         key=lambda kv: (kv[1], -kv[0]), default=(0, 0))
        return (f"G0AJ_LEXICAL_SHAPE pages={self.pages} "
                f"candidate_count_min={min(self.counts)} candidate_count_max={max(self.counts)} "
                f"count_variants={len(self.counts)} zero_drop_pages={self.zero_drop_pages} "
                f"single_drop_pages={self.single_drop_pages} multi_drop_pages={self.multi_drop_pages} "
                f"dominant_drop_position={top_drop[0]} dominant_drop_pages={top_drop[1]} "
                f"dominant_repeat_position={top_repeat[0]} dominant_repeat_pairs={top_repeat[1]} "
                f"boundary_descents={self.boundary_descents} "
                f"G0AK_BODY_CANDIDATE_ORDER={body_status} "
                f"body_count_invalid_pages={self.bad_body_count_pages} "
                f"header_constant_mismatches={self.header_mismatches} "
                f"body_within_descents={self.body_within_descents} "
                f"body_cross_page_descents={self.body_boundary_descents} "
                f"body_duplicate_pairs={self.body_equal_pairs} "
                f"first_anomaly_page={self.first_body_anomaly_page} "
                "RECORD_GRAMMAR=UNVERIFIED SORTING=UNPROVEN GLOBAL_NOT_WIN=HOLD")
