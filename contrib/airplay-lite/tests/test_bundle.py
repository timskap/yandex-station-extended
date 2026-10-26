import contextlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'bundle.py'
spec = importlib.util.spec_from_file_location('bundle', MODULE)
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        runtime = self.base / 'runtime'
        for folder, names in {
            'bin': ['shairport-sync', 'nqptp', 'avahi-daemon', 'dbus-daemon', 'airplay-buttons'],
            'lib': ['ld-musl-aarch64.so.1'],
        }.items():
            (runtime / folder).mkdir(parents=True)
            for name in names:
                (runtime / folder / name).write_bytes(b'test fixture')
        self.archive = self.base / 'airplay.tar.gz'
        with contextlib.redirect_stdout(io.StringIO()):
            bundle.pack(runtime, self.archive)

    def unpack(self, host='yandexmicro-EXAMPLE123.local.'):
        with contextlib.redirect_stdout(io.StringIO()):
            bundle.unpack(self.archive, self.base / 'out', host)

    def rewrite_archive(self, transform):
        with tarfile.open(self.archive, 'r:gz') as source:
            contents = [(m.name, source.extractfile(m).read()) for m in source.getmembers()]
        with tarfile.open(self.archive, 'w:gz') as target:
            for name, data in transform(contents):
                member = tarfile.TarInfo(name)
                member.size = len(data)
                target.addfile(member, io.BytesIO(data))
        self.archive.with_name(self.archive.name + '.sha256').write_text(
            f'{bundle.digest(self.archive.read_bytes())}  {self.archive.name}\n')

    def test_round_trip_personalizes_and_rehashes(self):
        self.unpack()
        root = self.base / 'out/shairport'
        config = (root / 'etc/avahi-daemon.conf').read_text()
        self.assertIn('host-name=yandexmicro-EXAMPLE123\n', config)
        self.assertNotIn('@MDNS_HOST@', config)
        for row in (root / 'MANIFEST.sha256').read_text().splitlines():
            checksum, name = row.split('  ', 1)
            self.assertEqual(checksum, bundle.digest((root / name).read_bytes()))
        self.assertTrue((root / 'bin/shairport-sync').stat().st_mode & 0o111)

    def test_rejects_corrupt_archive(self):
        with self.archive.open('ab') as stream:
            stream.write(b'corrupted')
        with self.assertRaisesRegex(ValueError, 'Archive SHA256'):
            self.unpack()

    def test_rejects_modified_payload_even_with_updated_archive_checksum(self):
        self.rewrite_archive(lambda rows: [(name, b'altered' if name.endswith('/run.sh') else data) for name, data in rows])
        with self.assertRaisesRegex(ValueError, 'File SHA256'):
            self.unpack()

    def test_rejects_archive_traversal_before_writing(self):
        self.rewrite_archive(lambda rows: rows + [('shairport/../../escaped', b'bad')])
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            self.unpack()
        self.assertFalse((self.base / 'out').exists())
        self.assertFalse((self.base / 'escaped').exists())

    def test_rejects_extra_unlisted_file(self):
        self.rewrite_archive(lambda rows: rows + [('shairport/extra', b'unlisted')])
        with self.assertRaisesRegex(ValueError, 'exactly'):
            self.unpack()

    def test_rejects_shell_characters_in_hostname(self):
        for host in ("host'; reboot; '", 'bad/host', 'host\nnext', '-bad', 'x' * 64):
            with self.subTest(host=host), self.assertRaises(ValueError):
                bundle.hostname(host)


if __name__ == '__main__':
    unittest.main()
