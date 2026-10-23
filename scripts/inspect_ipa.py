"""Validate an arm64 iOS 16.3 IPA without relying on macOS tooling."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys
import zipfile

ARM64 = 0x0100000c


def _version(value):
    return tuple(int(v) for v in value.split('.')) + (0,) * (3 - len(value.split('.')))


def _machos(data):
    if data[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        if count > 64:
            raise ValueError('Invalid fat Mach-O architecture count')
        result = []
        for index in range(count):
            _, _, offset, length, _ = struct.unpack_from('>5I', data, 8 + index * 20)
            result.extend(_machos(data[offset:offset + length]))
        return result
    if data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Unsupported Mach-O architecture or magic')
    _, cpu, _, _, commands, size, _, _ = struct.unpack_from('<8I', data)
    if commands > 4096 or 32 + size > len(data):
        raise ValueError('Invalid Mach-O load commands')
    offset, platform, minimum = 32, None, None
    for _ in range(commands):
        command, length = struct.unpack_from('<2I', data, offset)
        if length < 8 or offset + length > 32 + size:
            raise ValueError('Invalid Mach-O command size')
        if command == 0x32:
            platform, minimum = struct.unpack_from('<2I', data, offset + 8)
        elif command == 0x25:
            platform = 2
            minimum = struct.unpack_from('<I', data, offset + 8)[0]
        offset += length
    if minimum is None:
        raise ValueError('Missing Mach-O minimum OS version')
    return [(cpu, platform, (minimum >> 16, (minimum >> 8) & 255, minimum & 255))]


def inspect_ipa(path):
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError('Corrupt ZIP entry: ' + bad)
        names = archive.namelist()
        infos = [n for n in names if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/') == 2]
        if len(infos) != 1:
            raise ValueError('IPA must contain exactly one app')
        base = infos[0][:-len('Info.plist')]
        info = plistlib.loads(archive.read(infos[0]))
        minimum = info.get('MinimumOSVersion', '')
        if not minimum or _version(minimum) > (16, 3, 0):
            raise ValueError('App minimum iOS is incompatible: ' + minimum)
        executable = info.get('CFBundleExecutable', '')
        if not executable or '/' in executable:
            raise ValueError('Invalid app executable')
        required = [base + executable, base + 'Frameworks/Python.framework/Python',
                    base + 'python/lib/python3.13/encodings/__init__.py', base + 'runtime.py', base + 'lessons.json']
        for name in required:
            if name not in names:
                raise ValueError('Required Python/app resource missing: ' + name)
        checked = 0
        for name in names:
            if not name.startswith(base) or name.endswith('/'):
                continue
            with archive.open(name) as handle:
                magic = handle.read(4)
            if magic not in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                if name in (base + executable, base + 'Frameworks/Python.framework/Python'):
                    raise ValueError('Required executable is not a valid Mach-O: ' + name)
                continue
            slices = _machos(archive.read(name))
            device = [s for s in slices if s[0] == ARM64]
            if not device:
                raise ValueError('Missing arm64 architecture: ' + name)
            for _, platform, version in device:
                if platform != 2:
                    raise ValueError('Non-device/simulator platform: ' + name)
                if version > (16, 3, 0):
                    raise ValueError(f'Binary minimum iOS {version} exceeds 16.3: {name}')
            checked += 1
        if checked < 2:
            raise ValueError('App or Python executable is not a valid Mach-O')
    with path.open('rb') as handle:
        digest = hashlib.file_digest(handle, 'sha256').hexdigest()
    return {'file': path.name, 'bytes': path.stat().st_size,
            'size_mib': round(path.stat().st_size / 1024**2, 2),
            'sha256': digest,
            'bundle_id': info.get('CFBundleIdentifier'), 'version': info.get('CFBundleShortVersionString'),
            'minimum_ios': minimum, 'macho_count': checked}


if __name__ == '__main__':
    print(json.dumps(inspect_ipa(sys.argv[1]), ensure_ascii=False, indent=2))
