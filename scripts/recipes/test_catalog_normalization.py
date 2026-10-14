"""Offline source, parsing and shipping-catalog regression tests."""
import contextlib
import copy
import hashlib
import io
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
import normalize_catalog as catalog

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/design'))
import collect_public_settings as collect
HAS_BS4 = importlib.util.find_spec('bs4') is not None
HAS_PIL = importlib.util.find_spec('PIL') is not None

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

    def test_invalid_hash_date_and_name_length_are_quarantined(self):
        bad = [('retrievedOn', None), ('retrievedOn', '2026-9-1'), ('retrievedOn', float('nan')),
               ('sourceSHA256', None), ('sourceSHA256', 'abc'), ('sourceSHA256', 'z' * 64),
               ('name', '\u6f22' * 90)]
        for field, value in bad:
            with self.subTest(field=field, value=repr(value)):
                raw = self.raw(self.gold)
                raw[field] = value
                result, report = catalog.build({'records': [raw]})
                self.assertEqual(len(result['records']), 0)
                self.assertEqual(len(report['rejected']), 1)

    def test_name_length_boundary_is_224_bytes(self):
        for size, accepted in ((224, 1), (225, 0)):
            with self.subTest(size=size):
                raw = self.raw(self.gold)
                raw['name'] = 'a' * size
                result, report = catalog.build({'records': [raw]})
                self.assertEqual((len(result['records']), len(report['rejected'])), (accepted, 1 - accepted))

    def test_main_rejects_nan_without_touching_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            staging, output, report = tmp / 'staging.json', tmp / 'catalog.json', tmp / 'report.json'
            staging.write_text('{"candidateCount": NaN, "records": [' + json.dumps(self.raw(self.gold)) + ']}', encoding='utf-8')
            output.write_text('keep-catalog', encoding='utf-8')
            report.write_text('keep-report', encoding='utf-8')
            with contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(ValueError):
                    catalog.main([str(staging), '--output', str(output), '--report', str(report)])
            self.assertEqual(output.read_text(encoding='utf-8'), 'keep-catalog')
            self.assertEqual(report.read_text(encoding='utf-8'), 'keep-report')
            self.assertEqual(sorted(p.name for p in tmp.iterdir()), ['catalog.json', 'report.json', 'staging.json'])

    def test_conflicting_duplicate_setting_is_rejected(self):
        raw = self.raw(self.gold)
        raw['settings']['Highlight (conflicting duplicate 1)'] = '-2'
        result, report = catalog.build({'records': [raw]})
        self.assertEqual((len(result['records']), len(report['rejected'])), (0, 1))

    def test_main_refuses_incomplete_staging_and_default_paths_are_anchored(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            staging, output, report = tmp / 'staging.json', tmp / 'catalog.json', tmp / 'report.json'
            staging.write_text(json.dumps({'records': [self.raw(self.gold)], 'complete': False}), encoding='utf-8')
            output.write_text('keep-catalog', encoding='utf-8')
            with self.assertRaises(SystemExit) as raised:
                catalog.main([str(staging), '--output', str(output), '--report', str(report)])
            self.assertIn('incomplete', str(raised.exception.code))
            self.assertEqual(output.read_text(encoding='utf-8'), 'keep-catalog')
            self.assertFalse(report.exists())
            with contextlib.redirect_stdout(io.StringIO()):
                catalog.main([str(staging), '--output', str(output), '--report', str(report), '--allow-incomplete'])
            self.assertEqual(json.loads(report.read_text(encoding='utf-8'))['accepted'], 1)
            previous = Path.cwd()
            os.chdir(tmp)
            try:
                args = catalog.make_parser().parse_args(['x'])
            finally:
                os.chdir(previous)
            self.assertEqual(args.output, ROOT / 'FilmyCamera/Resources/RecipeCatalog.json')
            self.assertEqual(args.report, ROOT / 'docs/recipe-catalog-audit.json')
            self.assertTrue(args.output.is_absolute() and args.report.is_absolute())

class CollectorTests(unittest.TestCase):
    def test_put_setting_keeps_conflicting_repeats_under_numbered_keys(self):
        settings = {}
        collect.put_setting(settings, 'Highlight', '+1')
        collect.put_setting(settings, 'Highlight', '+1')
        self.assertEqual(settings, {'Highlight': '+1'})
        collect.put_setting(settings, 'Highlight', '-2')
        collect.put_setting(settings, 'Highlight', '0')
        self.assertEqual(settings['Highlight (conflicting duplicate 1)'], '-2')
        self.assertEqual(settings['Highlight (conflicting duplicate 2)'], '0')
        self.assertEqual(settings['Highlight'], '+1')

    def test_same_host_https_redirect_is_followed(self):
        handler = collect._AllowlistRedirects()
        req = urllib.request.Request('https://fujixweekly.com/a')
        followed = handler.redirect_request(req, None, 302, 'Found', {}, 'https://fujixweekly.com/b')
        self.assertEqual(followed.full_url, 'https://fujixweekly.com/b')

    def test_redirects_leaving_the_https_allowlist_are_refused(self):
        handler = collect._AllowlistRedirects()
        for target in ('https://evil.example/', 'http://fujixweekly.com/x', 'https://www.fujixweekly.com/x'):
            with self.subTest(target=target):
                with self.assertRaises(ValueError):
                    handler.redirect_request(None, None, 302, 'Found', {}, target)

    @unittest.skipUnless(HAS_BS4, 'bs4 missing')
    def test_conflicting_duplicate_settings_are_kept_for_quarantine(self):
        from bs4 import BeautifulSoup
        rows = ''.join(f'<tr><td>{k}</td><td>{v}</td></tr>' for k, v in (
            ('Film Simulation', 'Classic Chrome'), ('Dynamic Range', 'DR200'), ('Highlight', '+1'),
            ('Shadow', '-1'), ('Color', '+2'), ('Highlight', '-2'), ('Shadow', '-1')))
        blocks = collect.setting_blocks(BeautifulSoup(f'<table>{rows}</table>', 'html.parser'))
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0]['Highlight'], '+1')
        self.assertEqual(blocks[0]['Highlight (conflicting duplicate 1)'], '-2')
        self.assertEqual(sum(1 for k in blocks[0] if k.startswith('Shadow')), 1)
        paragraph = ('<p>Classic Chrome Dynamic Range: DR200, Highlight: +1, Shadow: -1, Color: +2, '
                     'White Balance: 5500K, White Balance: Auto</p>')
        blocks = collect.setting_blocks(BeautifulSoup(paragraph, 'html.parser'))
        self.assertEqual(blocks[0]['White Balance (conflicting duplicate 1)'], 'Auto')
        labelled = ('<p>X-T3 recipe Film Simulation: Classic Chrome Dynamic Range: DR200 Highlight: +1 '
                    'Shadow: -1 Color: +2 White Balance: Auto</p>')
        blocks = collect.setting_blocks(BeautifulSoup(labelled, 'html.parser'))
        self.assertEqual(blocks[0]['Film Simulation'], 'Classic Chrome')
        self.assertFalse(any('(conflicting duplicate' in k for k in blocks[0]))
        self.assertEqual(list(blocks[0])[0], 'Film Simulation')
        repeated = labelled.replace('White Balance: Auto', 'White Balance: Auto Film Simulation: Velvia')
        blocks = collect.setting_blocks(BeautifulSoup(repeated, 'html.parser'))
        self.assertEqual(list(blocks[0])[0], 'Film Simulation')
        self.assertEqual(blocks[0]['Film Simulation'], 'Classic Chrome')
        self.assertEqual(blocks[0]['Film Simulation (conflicting duplicate 1)'], 'Velvia')
        mixed = ('<table>' + ''.join(f'<tr><td>{k}</td><td>{v}</td></tr>' for k, v in (
            ('Film Simulation', 'Classic Chrome'), ('Film Simulation', 'Velvia'), ('Highlight', '+1'),
            ('Shadow', '-1'), ('Color', '+2'))) + '</table>'
            '<p>Classic Chrome Dynamic Range: DR200, Highlight: +1, Shadow: -1, Color: +2, White Balance: Auto</p>')
        blocks = collect.setting_blocks(BeautifulSoup(mixed, 'html.parser'))
        self.assertEqual(len(blocks), 1)
        self.assertIn('Dynamic Range', blocks[0])

    @unittest.skipUnless(HAS_BS4, 'bs4 missing')
    def test_main_exits_nonzero_without_overwriting_when_every_fetch_fails(self):
        class Failing:
            def __init__(self, delay):
                pass
            def get(self, url, robots=False):
                raise urllib.error.URLError('offline')
        original = collect.Fetcher
        collect.Fetcher = Failing
        self.addCleanup(setattr, collect, 'Fetcher', original)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'o.json'
            output.write_text('keep', encoding='utf-8')
            with self.assertRaises(SystemExit) as raised:
                collect.main(['--output', str(output)])
            self.assertIn('No candidate pages found', str(raised.exception.code))
            self.assertEqual(output.read_text(encoding='utf-8'), 'keep')
            with contextlib.redirect_stderr(io.StringIO()) as err:
                with self.assertRaises(SystemExit):
                    collect.main(['--output', str(output)])
            self.assertIn('offline', err.getvalue())

    @unittest.skipUnless(HAS_BS4, 'bs4 missing')
    def test_limit_truncated_crawl_is_marked_incomplete(self):
        index = '<div class="entry-content">' + ''.join(
            f'<a href="https://fujixweekly.com/2026/01/0{n}/r{n}/">Recipe {n}</a>' for n in (1, 2)) + '</div>'
        class Stub:
            def __init__(self, delay):
                pass
            def get(self, url, robots=False):
                if '/20' in url:
                    raise ValueError('Article content missing')
                return index.encode()
        original = collect.Fetcher
        collect.Fetcher = Stub
        self.addCleanup(setattr, collect, 'Fetcher', original)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'o.json'
            with contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit):
                    collect.main(['--output', str(output), '--limit', '1'])
            data = json.loads(output.read_text(encoding='utf-8'))
            self.assertIs(data['complete'], False)
            self.assertEqual(data['candidateCount'], 2)
            with contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit):
                    collect.main(['--output', str(output), '--limit', '5'])
            self.assertIs(json.loads(output.read_text(encoding='utf-8'))['complete'], True)

    @unittest.skipUnless(HAS_BS4, 'bs4 missing')
    def test_index_fetch_failure_marks_crawl_incomplete(self):
        index = '<div class="entry-content">' + ''.join(
            f'<a href="https://fujixweekly.com/2026/01/0{n}/r{n}/">Recipe {n}</a>' for n in (1, 2)) + '</div>'
        failing = 'https://film.recipes/blog/film-recipes-index-a-z/'
        class Stub:
            def __init__(self, delay):
                pass
            def get(self, url, robots=False):
                if url == failing:
                    raise urllib.error.URLError('timed out')
                if '/20' in url:
                    raise ValueError('Article content missing')
                return index.encode()
        original = collect.Fetcher
        collect.Fetcher = Stub
        self.addCleanup(setattr, collect, 'Fetcher', original)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'o.json'
            errors = io.StringIO()
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(errors):
                with self.assertRaises(SystemExit):
                    collect.main(['--output', str(output), '--limit', '5'])
            self.assertIn('marked incomplete', errors.getvalue())
            data = json.loads(output.read_text(encoding='utf-8'))
            self.assertIs(data['complete'], False)
            self.assertEqual(data['candidateCount'], 2)
            self.assertIn(failing, [f['url'] for f in data['failures']])

class IdentityRenderTests(unittest.TestCase):
    @unittest.skipUnless(HAS_PIL, 'Pillow missing')
    def test_icon_profile_is_reproducible(self):
        import time
        import render_identity
        import render_g7_identity
        for module in (render_identity, render_g7_identity):
            with self.subTest(module=module.__name__):
                first = module.srgb_profile()
                time.sleep(1.1)
                self.assertEqual(first, module.srgb_profile())
                self.assertEqual(first[24:36], bytes(12))

if __name__ == '__main__':
    unittest.main()
