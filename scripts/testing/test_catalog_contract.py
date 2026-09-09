"""Make every authored look and its always-on renderer test auditable on Linux."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CatalogContractTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((ROOT / 'scripts/testing/original-look-manifest.json').read_text())
        self.model = (ROOT / 'FilmyCamera/Models/FilmRecipe.swift').read_text()
        self.render_tests = (ROOT / 'FilmyCameraTests/RecipeRenderGalleryTests.swift').read_text().split(
            'final class CatalogRenderAcceptanceTests: XCTestCase {', 1)[1]

    def test_manifest_has_92_unique_stable_original_ids(self):
        ids = self.manifest['ids']
        self.assertEqual(len(ids), 92)
        self.assertEqual(len(set(ids)), 92)
        self.assertEqual(sum(self.manifest['collections'].values()), 92)
        for collection, expected in self.manifest['collections'].items():
            self.assertEqual(sum(x.startswith(collection + '-') for x in ids), expected)

    def test_every_manifest_id_has_exactly_one_authored_definition(self):
        observed = []
        for collection in self.manifest['collections']:
            start = self.model.index('let ' + collection + ': [CreativeLook] = [')
            end = self.model.index('result += ' + collection + '.map', start)
            slugs = re.findall(r'\.init\("([a-z0-9-]+)",', self.model[start:end])
            observed.extend(collection + '-' + slug for slug in slugs)
        self.assertEqual(observed, self.manifest['ids'])

    def test_every_legacy_and_original_look_has_a_concrete_renderer_case(self):
        legacy = self.model.split('static let legacyBuiltIns:', 1)[1].split('extension FilmRecipe', 1)[0]
        legacy_ids = re.findall(r'\bid: "([a-z0-9-]+)"', legacy)
        self.assertEqual(len(legacy_ids), 36)
        cases = re.findall(r'func testRender_\w+\(\) throws \{ try verifyRecipe\("([a-z0-9-]+)"\)', self.render_tests)
        self.assertEqual(len(cases), 128)
        self.assertEqual(cases, legacy_ids + self.manifest['ids'])

    def test_renders_cannot_skip_for_missing_private_fixture(self):
        self.assertNotIn('XCTSkip', self.render_tests)
        self.assertIn('UIImage(named: "LookPreviewCafe")', self.render_tests)
        self.assertIn('FilmRenderer.Quality.preview, .photo', self.render_tests)
        self.assertIn('PhotoOutputEncoder.jpegData', self.render_tests)
        self.assertIn('kCGImagePropertyGPSDictionary', self.render_tests)
        self.assertIn('CatalogRenderAcceptanceTests', (ROOT / 'scripts/testing/suites.json').read_text())

    def test_render_workflow_requires_all_145_cases_without_skips(self):
        workflow = (ROOT / '.github/workflows/catalog-acceptance.yml').read_text()
        self.assertIn('s["passedTests"] == 145', workflow)
        self.assertIn('s["failedTests"] == 0 and s["skippedTests"] == 0', workflow)
        self.assertIn('Catalog result bundle is required', workflow)
        self.assertNotIn('contents: write', workflow)


if __name__ == '__main__':
    unittest.main()
