#!/usr/bin/env python3
"""Fail-closed Owner/PR45 signed-candidate dispatch gate; no signing secrets read."""
import json
import os
import re
import sys

REPO = 'easonliu714/my_finance_app_public'
BRANCH = 'issue-13-invoice-award-official-data'
CONSENT = 'AUTHORIZE_SIGNED_CANDIDATE_ONLY'


def reject(reason):
    print('SIGNED_DISPATCH_AUTHORITY=HOLD_' + reason, file=sys.stderr)
    return 1


def main():
    env = os.environ
    if env.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        return reject('NOT_MANUAL_DISPATCH')
    if env.get('GITHUB_ACTOR') != 'easonliu714':
        return reject('ACTOR_NOT_OWNER')
    if env.get('GITHUB_REPOSITORY') != REPO:
        return reject('REPOSITORY_MISMATCH')
    if env.get('GITHUB_REF') != 'refs/heads/' + BRANCH:
        return reject('BRANCH_MISMATCH')
    if env.get('OWNER_SIGNING_AUTHORIZATION') != CONSENT:
        return reject('EXPLICIT_SIGNING_CONSENT_MISSING')
    sha = env.get('GITHUB_SHA', '')
    if re.fullmatch(r'[0-9a-f]{40}', sha) is None:
        return reject('INVALID_EXACT_SHA')
    try:
        pr = json.load(sys.stdin)
    except (ValueError, UnicodeError):
        return reject('INVALID_PR_RESPONSE')
    if not isinstance(pr, dict):
        return reject('INVALID_PR_RESPONSE')
    head = pr.get('head')
    base = pr.get('base')
    if not isinstance(head, dict) or not isinstance(base, dict):
        return reject('MISSING_PR_REFS')
    head_repo = head.get('repo')
    if not isinstance(head_repo, dict):
        return reject('MISSING_HEAD_REPOSITORY')
    if (pr.get('number') != 45 or pr.get('state') != 'open'
            or pr.get('draft') is not True or pr.get('merged_at') is not None
            or head.get('ref') != BRANCH or head_repo.get('full_name') != REPO
            or base.get('ref') != 'main'):
        return reject('PR45_STATE_OR_SCOPE_MISMATCH')
    if head.get('sha') != sha:
        return reject('PR45_HEAD_MOVED')
    print('SIGNED_DISPATCH_AUTHORITY=PASS_OWNER_CONSENT_EXACT_DRAFT_PR45_ONLY')
    print('SIGNED_APK_AND_OWNER_DEVICE=HOLD_UNTIL_INDEPENDENT_EVIDENCE')
    return 0


if __name__ == '__main__':
    sys.exit(main())
