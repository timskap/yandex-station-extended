#!/usr/bin/env python3
"""Create and verify the portable AirPlay Lite bundle (standard library only)."""
import argparse
import gzip
import hashlib
import io
import math
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import tarfile
import tempfile
import wave

HERE = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def manifest(root):
    files = sorted(p for p in root.rglob('*') if p.is_file() and p.name != 'MANIFEST.sha256')
    (root / 'MANIFEST.sha256').write_text(''.join(
        f'{digest(p.read_bytes())}  {p.relative_to(root).as_posix()}\n' for p in files))


def hostname(value):
    value = value.removesuffix('.local.').removesuffix('.local')
    if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', value):
        raise ValueError('mDNS host must be one DNS label, without spaces or shell characters')
    return value


def pack(runtime, output):
    with tempfile.TemporaryDirectory(prefix='airplay-bundle-') as tmp:
        stage = Path(tmp)
        root = stage / 'shairport'
        shutil.copytree(HERE / 'device', root)
        for name in ('bin', 'lib'):
            shutil.copytree(runtime / name, root / name)
        for name in ('shairport-sync', 'nqptp', 'avahi-daemon', 'dbus-daemon', 'airplay-buttons'):
            if not (root / 'bin' / name).is_file():
                raise ValueError(f'Missing binary: {name}')
        if not (root / 'lib/ld-musl-aarch64.so.1').is_file():
            raise ValueError('Missing ARM64 musl loader')
        with wave.open(str(root / 'button.wav'), 'wb') as wav:
            wav.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
            wav.writeframes(b''.join(struct.pack('<hh', *[int(
                1000 * math.sin(math.pi * i / 3360) ** 2
                * math.sin(2 * math.pi * 1100 * i / 48000))] * 2) for i in range(3360)))
        manifest(root)
        shutil.copy2(HERE / 'S99zairplay', stage / 'S99zairplay')
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open('wb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode='w') as tar:
                for path in sorted(stage.rglob('*')):
                    if not path.is_file():
                        continue
                    data = path.read_bytes()
                    name = path.relative_to(stage).as_posix()
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    info.mode = 0o755 if path.suffix == '.sh' or '/bin/' in name or '/lib/' in name or path.name == 'S99zairplay' else 0o644
                    tar.addfile(info, io.BytesIO(data))
        output.with_name(output.name + '.sha256').write_text(
            f'{digest(output.read_bytes())}  {output.name}\n')
        print(f'{output}: {output.stat().st_size:,} bytes')


def unpack(archive, output, mdns_host):
    host = hostname(mdns_host)
    expected = archive.with_name(archive.name + '.sha256').read_text().split()[0]
    if digest(archive.read_bytes()) != expected:
        raise ValueError('Archive SHA256 mismatch')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output directory must be empty')
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        names = set()
        for member in members:
            path = PurePosixPath(member.name)
            if (not member.isfile() or path.is_absolute() or '..' in path.parts
                    or str(path) != member.name or member.name in names
                    or not (member.name == 'S99zairplay' or member.name.startswith('shairport/'))):
                raise ValueError(f'Unsafe or duplicate archive entry: {member.name}')
            names.add(member.name)
        if sum(m.size for m in members) > 64 * 1024 * 1024:
            raise ValueError('Bundle exceeds the expected 64 MiB limit')
        for member in members:
            path = output / member.name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(tar.extractfile(member).read())
            path.chmod(member.mode & 0o777)
    root = output / 'shairport'
    listed = set()
    for line in (root / 'MANIFEST.sha256').read_text().splitlines():
        checksum, name = line.split('  ', 1)
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or name in listed:
            raise ValueError('Invalid manifest path')
        listed.add(name)
        if digest((root / name).read_bytes()) != checksum:
            raise ValueError(f'File SHA256 mismatch: {name}')
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.name != 'MANIFEST.sha256'}
    if actual != listed:
        raise ValueError('Manifest does not cover exactly the payload files')
    config = root / 'etc/avahi-daemon.conf'
    original = config.read_text()
    if original.count('@MDNS_HOST@') != 1:
        raise ValueError('Expected one mDNS hostname placeholder')
    config.write_text(original.replace('@MDNS_HOST@', host))
    manifest(root)
    print('Archive and file checksums verified; mDNS hostname configured.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('pack')
    build.add_argument('--runtime', type=Path, required=True)
    build.add_argument('--output', type=Path, required=True)
    extract = commands.add_parser('unpack')
    extract.add_argument('--archive', type=Path, required=True)
    extract.add_argument('--output', type=Path, required=True)
    extract.add_argument('--mdns-host', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            pack(args.runtime, args.output)
        else:
            unpack(args.archive, args.output, args.mdns_host)
    except (ValueError, OSError, tarfile.TarError, IndexError) as exc:
        parser.exit(1, f'Error: {exc}\n')


if __name__ == '__main__':
    main()
