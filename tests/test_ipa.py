import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).parents[1] / 'scripts/inspect_ipa.py'


def macho(cpu=0x0100000c, platform=2, minimum=(13, 0, 0)):
    version = minimum[0] << 16 | minimum[1] << 8 | minimum[2]
    header = struct.pack('<8I', 0xfeedfacf, cpu, 0, 2, 1, 24, 0, 0)
    return header + struct.pack('<6I', 0x32, 24, platform, version, 0, 0)


class IPATests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), 'IPA validation has not been implemented')
        spec = importlib.util.spec_from_file_location('inspect_ipa', SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'test.ipa'

    def package(self, main=None, framework=None, minimum='16.3', python=True):
        with zipfile.ZipFile(self.path, 'w') as z:
            base = 'Payload/PyLearn.app/'
            z.writestr(base + 'Info.plist', plistlib.dumps({'CFBundleExecutable':'PyLearn', 'MinimumOSVersion':minimum, 'CFBundleIdentifier':'com.wjc0104.pylearn','CFBundleShortVersionString':'0.1.0'}))
            z.writestr(base + 'PyLearn', main if main is not None else macho())
            z.writestr(base + 'runtime.py', '')
            z.writestr(base + 'lessons.json', '[]')
            z.writestr(base + 'bank.json', '{}')
            z.writestr(base + 'packages/jedi/__init__.py', '')
            z.writestr(base + 'packages/dulwich/__init__.py', '')
            if python:
                z.writestr(base + 'Frameworks/Python.framework/Python', framework if framework is not None else macho())
                z.writestr(base + 'python/lib/python3.15/encodings/__init__.py', '')

    def test_accepts_device_ipa_and_reports_hash(self):
        self.package()
        result = self.module.inspect_ipa(self.path)
        self.assertEqual(result['minimum_ios'], '16.3')
        self.assertEqual(len(result['sha256']), 64)
        self.assertEqual(result['macho_count'], 2)

    def test_rejects_simulator_code(self):
        self.package(main=macho(platform=7))
        with self.assertRaisesRegex(ValueError, 'simulator|platform'):
            self.module.inspect_ipa(self.path)

    def test_rejects_framework_requiring_newer_ios(self):
        self.package(framework=macho(minimum=(17, 0, 0)))
        with self.assertRaisesRegex(ValueError, '17|minimum'):
            self.module.inspect_ipa(self.path)

    def test_rejects_wrong_architecture(self):
        self.package(main=macho(cpu=0x01000007))
        with self.assertRaisesRegex(ValueError, 'arm64|architecture'):
            self.module.inspect_ipa(self.path)

    def test_rejects_missing_python_and_newer_app(self):
        self.package(python=False)
        with self.assertRaisesRegex(ValueError, 'Python|missing'):
            self.module.inspect_ipa(self.path)
        self.package(minimum='17.0')
        with self.assertRaisesRegex(ValueError, '17|minimum'):
            self.module.inspect_ipa(self.path)

    def test_rejects_invalid_zip(self):
        self.path.write_bytes(b'not a zip')
        with self.assertRaises((ValueError, zipfile.BadZipFile)):
            self.module.inspect_ipa(self.path)

    def test_rejects_fake_main_even_with_two_real_frameworks(self):
        self.package(main=b'not executable')
        with zipfile.ZipFile(self.path, 'a') as z:
            z.writestr('Payload/PyLearn.app/Frameworks/math.framework/math', macho())
        with self.assertRaisesRegex(ValueError, 'Mach-O|executable'):
            self.module.inspect_ipa(self.path)
