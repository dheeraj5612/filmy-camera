"""Offline source, parsing and shipping-catalog regression tests."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import normalize_catalog as catalog

ROOT = Path(__file__).resolve().parents[2]

class RecipeNormalizationTests(unittest.TestCase):
    def setUp(self):
        self.records = json.loads((ROOT / 'FilmyCamera/Resources/RecipeCatalog.json').read_text(encoding='utf-8'))['records']
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
        lock = json.loads((ROOT / 'scripts/recipes/catalog-lock.json').read_text(encoding='utf-8'))
        report = json.loads((ROOT / 'docs/recipe-catalog-audit.json').read_text(encoding='utf-8'))
        self.assertEqual(hashlib.sha256(payload).hexdigest(), lock['catalogSHA256'])
        self.assertEqual(len(self.records), report['accepted'])
        self.assertEqual(len(self.records), lock['sourcedRecipes'])
        self.assertEqual(sum(report['publisherCounts'].values()), len(self.records))
        self.assertNotIn('calibrated', report['calibration'].split(';')[0].lower().replace('not calibrated', ''))

    def test_lock_and_audit_quarantine_arithmetic(self):
        lock = json.loads((ROOT / 'scripts/recipes/catalog-lock.json').read_text(encoding='utf-8'))
        report = json.loads((ROOT / 'docs/recipe-catalog-audit.json').read_text(encoding='utf-8'))
        self.assertEqual(report['candidates'], report['accepted'] + len(report['rejected']))
        self.assertEqual(len(report['rejected']), len({x['url'] for x in report['rejected']}))
        self.assertEqual(lock['totalLooks'], lock['sourcedRecipes'] + lock['originalLooks'] + lock['cameraFoundations'])
        self.assertEqual(lock['mappingVersion'], catalog.MAPPING_VERSION)
        self.assertEqual(report['mappingVersion'], catalog.MAPPING_VERSION)
        self.assertEqual({r['source']['mappingVersion'] for r in self.records}, {catalog.MAPPING_VERSION})
        self.assertRegex(lock['stagingSHA256'], r'^[0-9a-f]{64}$')

    def test_full_build_reproduces_shipped_names_order_and_limitations(self):
        result, report = catalog.build({'records': [self.raw(r) for r in self.records]})
        self.assertEqual(report['rejected'], [])
        self.assertEqual(report['accepted'], len(self.records))
        self.assertEqual(len(result['records']), len(self.records))
        self.assertEqual([r['id'] for r in result['records']], [r['id'] for r in self.records])

        def facts(record):
            source = dict(record['source'])
            source.pop('cameraScope')
            return dict(id=record['id'], name=record['name'], controls=record['controls'], source=source)
        self.assertEqual([facts(r) for r in result['records']], [facts(r) for r in self.records])

    def test_camera_scope_generation_order_is_total(self):
        raw = self.raw(self.gold)
        raw['indexes'] = ['x-trans-iv-a', 'x-trans-ii-a', 'x-trans-v-a', 'x-trans-i-a']
        self.assertEqual(catalog.normalize(raw)['source']['cameraScope'], 'X-Trans I / V / II / IV source index')
        raw['indexes'] = ['x-trans-iv-a', 'x-trans-v-a']
        self.assertEqual(catalog.normalize(raw)['source']['cameraScope'], 'X-Trans V / IV source index')

    def test_untrusted_sources_and_out_of_range_settings_are_rejected(self):
        for url in ['https://film.recipes.evil.com/2026/07/19/x/', 'http://film.recipes/2026/07/19/x/',
                    'https://film.recipes@evil.com/x']:
            with self.subTest(url=url):
                raw = self.raw(self.gold)
                raw['url'] = url
                with self.assertRaisesRegex(ValueError, 'Source not allowlisted'):
                    catalog.normalize(raw)
        cases = [('White Balance', '1000K, +2 Red & -5 Blue', 'Kelvin outside supported bounds'),
                 ('White Balance', '12000K, +2 Red & -5 Blue', 'Kelvin outside supported bounds'),
                 ('Dynamic Range', 'DR300', 'Ambiguous dynamic range'),
                 ('D-Range Priority', 'Strong', 'Dynamic Range Priority'),
                 ('Highlight', '3', 'Contradictory highlight entries'),
                 ('Grain Effect', 'Weak, Medium', 'Unsupported grain size'),
                 ('Grain Effect', 'Weak, Small, Large', 'Unsupported grain size')]
        for key, value, message in cases:
            with self.subTest(key=key, value=value):
                raw = self.raw(self.gold)
                raw['settings'][key] = value
                with self.assertRaisesRegex(ValueError, message):
                    catalog.normalize(raw)

    def test_conflicting_grain_size_sources_are_rejected(self):
        raw = self.raw(self.gold)
        raw['settings']['Grain Effect'] = 'Weak, Large'
        raw['settings']['Grain Size'] = 'Small'
        with self.assertRaisesRegex(ValueError, 'Contradictory grain size'):
            catalog.normalize(raw)
        raw['settings']['Grain Size'] = 'large'
        self.assertEqual(catalog.normalize(raw)['controls']['grainSize'], 1)
        raw['settings']['Grain Effect'] = 'Weak'
        self.assertEqual(catalog.normalize(raw)['controls']['grainSize'], 1)

    def test_main_refuses_to_overwrite_outputs_when_nothing_is_accepted(self):
        raw = self.raw(self.gold)
        raw['url'] = 'https://example.com/x'
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            staging, output, report = tmp / 'staging.json', tmp / 'catalog.json', tmp / 'report.json'
            staging.write_text(json.dumps({'records': [raw]}), encoding='utf-8')
            output.write_text('keep-catalog', encoding='utf-8')
            report.write_text('keep-report', encoding='utf-8')
            with self.assertRaises(SystemExit) as raised:
                catalog.main([str(staging), '--output', str(output), '--report', str(report)])
            self.assertIn('No records accepted', str(raised.exception.code))
            self.assertEqual(output.read_text(encoding='utf-8'), 'keep-catalog')
            self.assertEqual(report.read_text(encoding='utf-8'), 'keep-report')
            self.assertEqual(sorted(p.name for p in tmp.iterdir()), ['catalog.json', 'report.json', 'staging.json'])

    def test_main_writes_catalog_and_report_without_temp_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            staging, output, report = tmp / 'staging.json', tmp / 'out' / 'catalog.json', tmp / 'out' / 'report.json'
            staging.write_text(json.dumps({'records': [self.raw(self.gold)]}), encoding='utf-8')
            with contextlib.redirect_stdout(io.StringIO()):
                catalog.main([str(staging), '--output', str(output), '--report', str(report)])
            written = json.loads(output.read_text(encoding='utf-8'))
            self.assertEqual([r['id'] for r in written['records']], [self.gold['id']])
            self.assertEqual(json.loads(report.read_text(encoding='utf-8'))['accepted'], 1)
            self.assertEqual(sorted(p.name for p in output.parent.iterdir()), ['catalog.json', 'report.json'])
            self.assertEqual(output.read_bytes(), (json.dumps(written, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))

if __name__ == '__main__':
    unittest.main()
