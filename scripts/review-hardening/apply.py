"""One-use source transfer, removed after applying the reviewed local patch."""
from pathlib import Path
import base64
import hashlib
import lzma
import subprocess

EXPECTED = {
    "FilmyCamera/FilmyCameraApp.swift": "9fe071440bbc64d94dea5e003d015228be267035f193b109918d616cf13f762a",
    "FilmyCamera/Info.plist": "46d3e64debed45d3b81645403347d23e7b48f61c9ba64ef42fdee8a71d29e07f",
    "FilmyCamera/Resources/PrivacyInfo.xcprivacy": "87789e31cce8c58223219f4a7e7ab457587ae22fc540f6024a7ad5ac6a18d4ce",
    "FilmyCamera/Services/CameraService.swift": "5b5702d8adea8b17130350be585a9d2b56b6f780ae80a7227916cd3e6b0722ba",
    "FilmyCamera/Services/PhotoLibraryService.swift": "1eed9cccf2717edc70ede9ee6ed6bad9f581ef8476d7ce51c76293cb945cc280",
    "FilmyCamera/Views/CameraScreen.swift": "7d7e5c45ec9bcb200c90122c4aa54f4c36db1108d588e18000733daa8664b5e9",
    "FilmyCamera/Views/FilteredCameraPreview.swift": "752d5a81c4779f2a893adfd70f6eda69bd694b8ad3b8c657107f8031b4477e42",
    "FilmyCamera/Views/GalleryScreen.swift": "a0c4bbb8825c4ef620ed9cbe79683210f5a0b0e5ea435988bf300453cfc5cf11",
    "FilmyCamera/Views/SettingsView.swift": "5037fe7e8ef10e85d7adaeb64caa0006daefd3344b5f363b3977f637f0866820",
    "FilmyCameraTests/CameraServiceAvailabilityTests.swift": "d99a171dbf335f1a6ab07f0a257f10a6ff35803334f77916a73849b8fae6d08f",
    "FilmyCameraTests/PhotoLibraryMetadataTests.swift": "581f7cf1b3792bcc8e706578d9696918b40a801cc71fd2da0d5f37e11e3e727e",
    "FilmyCameraUITests/FilmyCameraUITests.swift": "a1554969ca29943695683f9877477f228c2f38b93ad972b369cbbcdb5fda7ad3",
    "project.yml": "0750de0c25045aee5d3a48226eda704e60b7852e962f3ef028a262babfbc8079",
    "scripts/testing/suites.json": "6b0ebd2c19197cc26c3a5eccff0fcb7f2a0fa49bdf3fa86c67a7f62f7ecd0113"
}
for name, expected in EXPECTED.items():
    if hashlib.sha256(Path(name).read_bytes()).hexdigest() != expected:
        raise SystemExit(f"Refusing changed source: {name}")
folder = Path(__file__).parent
encoded = "".join((folder / f"payload-{index}.txt").read_text().strip() for index in range(3))
patch = lzma.decompress(base64.b64decode(encoded, validate=True))
if hashlib.sha256(patch).hexdigest() != "73930544ac35026afdb36c68dc2868a7176bfe0b25fc6e6e173f83b4f3fb5289":
    raise SystemExit("Patch checksum mismatch")
subprocess.run(["git", "apply", "--check", "--index", "-"], input=patch, check=True)
subprocess.run(["git", "apply", "--index", "-"], input=patch, check=True)
