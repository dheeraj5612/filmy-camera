"""Offline source, parsing and shipping-catalog regression tests."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
import normalize_catalog as catalog

ROOT = Path(__file__).resolve().parents[2]

class RecipeNormalizationTests(unittest.TestCase):
    def setUp(self):
        self.records = json.loads((ROOT / 'FilmyCamera/Resources/RecipeCatalog.json').read_text())['records']
        self.gold = next(r for r in self.records if '/2026/07/19/kodak-gold-ii-' in r['source']['url'])

    def raw(self, record):
        source = record['source']
        return dict(name=source['originalName'], url=source['url'], settings=copy.deepcopy(source['settings']),
                    sourceSHA256=source['sourceSHA256'], retrievedOn=source['retrievedOn'], indexes=[])

    def test_every_shipped_record_reproduces_its_controls_from_retained_source_facts(self):
        self.assertGreaterEqual(len(self.records), 500)
        self.assertEqual(len({r['id'] for r in self.records}), len(self.records))
        self.assertEqual(len({r['name'] for r in self.records}), len(self.records))
        self.assertEqual(len({r['source']['url'] for r in self.records}), len(self.records))
        for record in self.records:
            with self.subTest(recipe=record['name']):
                rebuilt = catalog.normalize(self.raw(record))
                self.assertEqual(rebuilt['controls'], record['controls'])
                self.assertEqual(rebuilt['id'], record['id'])
                self.assertEqual(len(record['source']['sourceSHA256']), 64)

    def test_abbreviated_color_chrome_is_preserved_and_missing_color_table_is_rejected(self):
        self.assertEqual(self.gold['controls']['colorChrome'], 1)
        raw = self.raw(self.gold)
        del raw['settings']['Col. Chr. Effect']
        with self.assertRaisesRegex(ValueError, 'Incomplete abbreviated table'):
            catalog.normalize(raw)

    def test_monochrome_axes_and_half_steps_are_preserved_without_color_chrome(self):
        emerald = next(r for r in self.records if '/2022/08/01/emerald-mono-' in r['source']['url'])
        c = catalog.normalize(self.raw(emerald))['controls']
        self.assertEqual((c['highlight'], c['shadow']), (-0.5, 0.5))
        self.assertEqual((c['monochromaticWarmCool'], c['monochromaticGreenMagenta']), (4, 8))
        self.assertEqual(c['colorChrome'], 0)
        self.assertEqual(c['filmBase'], 'acrosGreen')

    def test_unknown_controls_and_custom_white_balance_are_not_silently_guessed(self):
        raw = self.raw(self.gold)
        raw['settings']['Future sensor control'] = 'Strong'
        with self.assertRaisesRegex(ValueError, 'Unknown setting key'):
            catalog.normalize(raw)
        raw = self.raw(self.gold)
        raw['settings']['White Balance'] = 'Custom 1, +4 Red & -5 Blue'
        with self.assertRaisesRegex(ValueError, 'Unsupported white balance mode'):
            catalog.normalize(raw)

    def test_ambiguous_generation_ranges_and_unmapped_toning_are_rejected(self):
        for key, value in [('Col. Chr. Blue', 'Weak; Strong on X-Trans V'), ('Toning', '-9')]:
            raw = self.raw(self.gold)
            raw['settings'][key] = value
            with self.assertRaises(ValueError):
                catalog.normalize(raw)

    def test_unicode_minus_kelvin_and_bounds(self):
        self.assertEqual(catalog.scalar('−1', 'H', -2, 4), -1)
        self.assertEqual(catalog.scalar('‑0.5', 'H', -2, 4), -0.5)
        self.assertEqual(catalog.white_balance('6500K, +2 Red & -5 Blue', None, [])[:2], ('colorTemperature', 6500))
        for value in ['nan', 'Infinity', '5', '1 to 2', '1 (or 2)']:
            with self.assertRaises(ValueError):
                catalog.scalar(value, 'H', -2, 4)

    def test_duplicate_source_urls_are_quarantined_and_ids_ignore_fetch_date(self):
        raw = self.raw(self.gold)
        result, report = catalog.build({'records': [raw, copy.deepcopy(raw)]})
        self.assertEqual(len(result['records']), 1)
        self.assertEqual(len(report['rejected']), 1)
        expected = catalog.normalize(raw)['id']
        raw['retrievedOn'] = '2030-01-01'
        self.assertEqual(catalog.normalize(raw)['id'], expected)

    def test_catalog_integrity_lock_and_audit_counts(self):
        payload = (ROOT / 'FilmyCamera/Resources/RecipeCatalog.json').read_bytes()
        lock = json.loads((ROOT / 'scripts/recipes/catalog-lock.json').read_text())
        report = json.loads((ROOT / 'docs/recipe-catalog-audit.json').read_text())
        self.assertEqual(hashlib.sha256(payload).hexdigest(), lock['catalogSHA256'])
        self.assertEqual(len(self.records), report['accepted'])
        self.assertEqual(len(self.records), lock['sourcedRecipes'])
        self.assertEqual(sum(report['publisherCounts'].values()), len(self.records))
        self.assertNotIn('calibrated', report['calibration'].split(';')[0].lower().replace('not calibrated', ''))

if __name__ == '__main__':
    unittest.main()
