#!/usr/bin/env python3
"""B2.11 read-only DGPA 116 resource listing/publication cross-check.

The dataset's *global* metadata timestamp and DGPA calendar announcement
are NOT proof of a per-resource revision or authority to install a package.
"""
from html.parser import HTMLParser
import re
import ssl
import sys
import urllib.request
from urllib.parse import parse_qsl, urljoin, urlsplit

DATASET_URL = 'https://data.gov.tw/dataset/14718'
CALENDAR_URL = 'https://www.dgpa.gov.tw/en/informationlist?uid=353'
CSV_URL = ('https://www.dgpa.gov.tw/FileConversion?filename=dgpa%2Ffiles%2F202607%2F'
           'f538b1ff-ba60-4c63-9477-10db8e6612d1.csv&name=116%E5%B9%B4%E4%B8%AD'
           '%E8%8F%AF%E6%B0%91%E5%9C%8B%E6%94%BF%E5%BA%9C%E8%A1%8C%E6%94%BF'
           '%E6%A9%9F%E9%97%9C%E8%BE%A6%E5%85%AC%E6%97%A5%E6%9B%86%E8%A1%A8_utf8bom.csv&nfix=')
MAX_HTML_BYTES = 1024 * 1024
TARGET_LABEL = '116年中華民國政府行政機關辦公日曆表'
DATASET_METADATA_TIME = '2026-07-15 11:29'
DGPA_CALENDAR_LISTING = '115.07.07 2027 Work Calendar'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Official HTML redirect rejected')


class Tokens(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tokens = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self._skip += 1
        if tag == 'a' and not self._skip:
            href = dict(attrs).get('href')
            if href:
                self.tokens.append(('href', href))

    def handle_endtag(self, tag):
        if tag in ('script', 'style') and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if not self._skip:
            stripped = re.sub(r'\s+', '', data)
            if stripped:
                self.tokens.append(('text', stripped))


def same_official_csv_resource(href):
    # Accept only harmless serialization differences (protocol-relative URL,
    # query encoding/order). Never broaden the official host/path/source pin.
    candidate = urlsplit(urljoin(DATASET_URL, href))
    pinned = urlsplit(CSV_URL)
    return ((candidate.scheme, candidate.netloc, candidate.path) ==
            (pinned.scheme, pinned.netloc, pinned.path) and
            sorted(parse_qsl(candidate.query, keep_blank_values=True)) ==
            sorted(parse_qsl(pinned.query, keep_blank_values=True)) and
            not candidate.fragment)


def verify_dataset_html(raw):
    parser = Tokens()
    parser.feed(raw.decode('utf-8-sig', errors='strict'))
    tokens = parser.tokens
    # A resource label follows its own CSV link; the label is not necessarily
    # part of the anchor. Reject duplicate/mismatched or Google-calendar links.
    # The public portal splits a single resource label across HTML nodes.
    # Associate the *concatenated* text between consecutive links with the
    # preceding href; a per-node substring check can miss genuine resources.
    segments = []
    last_href = None
    text_after_href = []
    for kind, value in tokens:
        if kind == 'href':
            if last_href is not None:
                segments.append((last_href, ''.join(text_after_href)))
            last_href = value
            text_after_href = []
        elif last_href is not None:
            text_after_href.append(value)
    if last_href is not None:
        segments.append((last_href, ''.join(text_after_href)))
    matches = [href for href, label in segments
               if TARGET_LABEL in label and
               not re.search(r'google', label, flags=re.IGNORECASE)]
    if len(matches) != 1 or not same_official_csv_resource(matches[0]):
        raise ValueError('DGPA 116 resource identity unresolved: matches=%d href=%r' %
                         (len(matches), matches[0] if matches else None))
    text = ''.join(value for kind, value in tokens if kind == 'text')
    if '詮釋資料更新時間' + DATASET_METADATA_TIME.replace(' ', '') not in text:
        raise ValueError('Government dataset metadata timestamp drift')
    if '行政院人事行政總處' not in text:
        raise ValueError('Dataset publisher missing')
    return True


def verify_calendar_html(raw):
    parser = Tokens()
    parser.feed(raw.decode('utf-8-sig', errors='strict'))
    text = ''.join(value for kind, value in parser.tokens if kind == 'text')
    if DGPA_CALENDAR_LISTING.replace(' ', '') not in text:
        raise ValueError('DGPA 2027 calendar listing/date missing or changed')
    return True


def fetch_html(url):
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl.create_default_context()),
        NoRedirect(),
    )
    req = urllib.request.Request(url, headers={
        'User-Agent': 'my-finance-app-b2-publication-lab/1.0',
        'Accept': 'text/html',
    })
    with opener.open(req, timeout=35) as response:
        if response.status != 200 or response.geturl() != url:
            raise ValueError('Official HTML response origin/status mismatch')
        if response.headers.get('Content-Length') and int(response.headers['Content-Length']) > MAX_HTML_BYTES:
            raise ValueError('Official HTML declared size over cap')
        raw = response.read(MAX_HTML_BYTES + 1)
    if not raw or len(raw) > MAX_HTML_BYTES:
        raise ValueError('Official HTML size over cap or empty')
    return raw


def main():
    print('B2_PUBLICATION_LAB=START SOURCE_METADATA_NOT_RESOURCE_REVISION', flush=True)
    verify_dataset_html(fetch_html(DATASET_URL))
    print('B2_DATASET_116_EXACT_CSV_LINK_AND_GLOBAL_METADATA=PASS', flush=True)
    verify_calendar_html(fetch_html(CALENDAR_URL))
    print('B2_DGPA_2027_CALENDAR_LISTING=PASS', flush=True)
    print('B2_PUBLICATION_CROSSCHECK=PASS_READ_ONLY_NO_RESOURCE_REVISION_NO_INSTALL', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('B2_PUBLICATION_CROSSCHECK=HOLD FIRST_FAILURE=' + repr(exc),
              file=sys.stderr, flush=True)
        raise SystemExit(49)
