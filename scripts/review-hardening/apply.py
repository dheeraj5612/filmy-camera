"""One-use verified transfer, removed immediately after application."""
from pathlib import Path
import base64, hashlib, lzma, subprocess
EXPECTED = {'.github/workflows/ios-build.yml': 'bdc8efd6bf98294e2d52848ea9adffe7c6d5bb51d652ba75b14c6f4ed3749f6f', '.github/workflows/release-sdk-build.yml': 'b55b5efa850e25c652fff4fba2835e1cd8eb738fed20acca31d1f48a62e81279', 'FilmyCamera/Resources/PrivacyInfo.xcprivacy': '10e30c3a228307f4cf0eecf35997a7551e74924f326189391168e6142ff6a9f6', 'FilmyCamera/Services/PhotoLibraryService.swift': 'da9f6b6c35c35f9f996e40e3e5ad096d0f8dd94c17e99f9501e12d6daf1d8844', 'FilmyCamera/Views/GalleryScreen.swift': 'c30ea538be7b2520f7d3331cfdf5a30abff53af33a1f1de1086bbb7542164d10', 'FilmyCameraTests/PhotoLibraryMetadataTests.swift': '8773ddc7a44856ceda439aa98067b376adb784077117d859ef145777ca5adfed', 'docs/app-store/app-privacy.md': '4f463bd38c4a27e8922fb7f436b273a24b65712f4aa6de50a13445fe45d57f9b', 'docs/app-store/metadata-en-US.md': '98966a54007c2f779f3a2cf011afb144c58f988f6e38115880cc79097a16c180', 'docs/app-store/review-hardening-2026-09-10.md': None, 'docs/release-checklist.md': '9529144f022bcbb5dbe676bcdfe085d0baaef3c1382e400e913b867850f58e82', 'scripts/release/validate-app-review.py': None, 'scripts/release/validate-archive.sh': 'b9789adbacf278b1d9d7d52cdc8cd2e19c0e41f66b09e37fa5087ca0d5ff873b', 'scripts/release/validate-ipa.sh': '968d75f879c41a8971a5ef387d00a611fa883907cfef7fb59bd6e9ce87d8bb1d', 'scripts/release/validate-project.sh': '6ebc0d45b2f12425a7873a9c7f982f2201aece3e7a67da6af6bcce10b386619f', 'scripts/testing/test_app_review.py': None}
for name, expected in EXPECTED.items():
    path = Path(name)
    if expected is None:
        if path.exists():
            raise SystemExit(f"Refusing existing new path: {name}")
    elif hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit(f"Refusing changed source: {name}")
folder = Path(__file__).parent
encoded = "".join((folder / f"payload-{index}.txt").read_text().strip() for index in range(3))
patch = lzma.decompress(base64.b64decode(encoded, validate=True))
if hashlib.sha256(patch).hexdigest() != "902f3a66116bdd724c0199a429546dbd1110aa7e4475c01ab8ccd8e4d7fb7c4f":
    raise SystemExit("Patch checksum mismatch")
subprocess.run(["git", "apply", "--check", "--index", "-"], input=patch, check=True)
subprocess.run(["git", "apply", "--index", "-"], input=patch, check=True)
