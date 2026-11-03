import unittest
from tool.b2_official_calendar_publication_lab import (
    CSV_URL, DATASET_METADATA_TIME, DGPA_CALENDAR_LISTING,
    verify_calendar_html, verify_dataset_html, same_official_csv_resource,
)


def dataset(href=CSV_URL, label='116年中華民國政府行政機關辦公日曆表',
            metadata=DATASET_METADATA_TIME):
    return (f'<html><a href="{href}"> CSV </a>檢視資料{label}'
            f'<p>提供機關 行政院人事行政總處</p>'
            f'<p>詮釋資料更新時間 {metadata}</p></html>').encode()


class PublicationCustodyTests(unittest.TestCase):
    def test_exact_official_resource_and_distinct_global_metadata(self):
        self.assertTrue(verify_dataset_html(dataset()))
        self.assertTrue(verify_calendar_html(
            f'<a> {DGPA_CALENDAR_LISTING} </a>'.encode()))

    def test_official_resource_label_split_across_markup_nodes(self):
        raw = dataset().replace('116年中華民國政府行政機關辦公日曆表'.encode(),
                                '116年<span>中華民國政府</span>行政機關辦公日曆表'.encode())
        self.assertTrue(verify_dataset_html(raw))

    def test_html_protocol_relative_and_entity_escaped_link_identity(self):
        self.assertTrue(same_official_csv_resource(CSV_URL.replace('https:', '', 1)))
        self.assertTrue(verify_dataset_html(dataset(CSV_URL.replace('https:', '', 1))))
        self.assertTrue(verify_dataset_html(dataset(CSV_URL.replace('&nfix=', '&amp;nfix='))))

    def test_forged_and_google_resources_fail_closed(self):
        for href, label in (
            ('https://www.dgpa.gov.tw.attacker.example/f.csv', '116年中華民國政府行政機關辦公日曆表'),
            ('https://www.dgpa.gov.tw/FileConversion?filename=wrong.csv', '116年中華民國政府行政機關辦公日曆表'),
            (CSV_URL, '116年中華民國政府行政機關辦公日曆表_Google行事曆專用'),
        ):
            with self.subTest(href=href, label=label):
                with self.assertRaises(ValueError):
                    verify_dataset_html(dataset(href, label))

    def test_missing_duplicate_and_metadata_drift_fail_closed(self):
        for html in (dataset(metadata='2026-07-16 11:29'),
                     dataset() + dataset(),
                     dataset().replace('行政院人事行政總處'.encode(), b'unknown')):
            with self.assertRaises(ValueError):
                verify_dataset_html(html)
        with self.assertRaises(ValueError):
            verify_calendar_html(b'2026 Work Calendar')


if __name__ == '__main__':
    unittest.main()
