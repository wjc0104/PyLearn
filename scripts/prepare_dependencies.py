"""Download the pinned BeeWare runtime, verify its hash, then extract safely."""
import argparse
import hashlib
from pathlib import Path
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://github.com/beeware/Python-Apple-support/releases/download/3.13-b17/Python-3.13-iOS-support.b17.tar.gz'
SHA256 = '5d3617622369c545538cb2959197706d04d945d9fce9135aff4692d35d57c77d'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    cache = ROOT / '.cache/Python-3.13-iOS-support.b17.tar.gz'
    cache.parent.mkdir(exist_ok=True)
    if not cache.exists():
        with urllib.request.urlopen(URL, timeout=120) as response, cache.open('wb') as target:
            while block := response.read(1024 * 1024):
                target.write(block)
    with cache.open('rb') as handle:
        digest = hashlib.file_digest(handle, 'sha256').hexdigest()
    if digest != SHA256:
        raise ValueError('CPython release checksum mismatch; remove the cached archive and retry')
    with tarfile.open(cache) as archive:
        versions = archive.extractfile('VERSIONS').read().decode()
        if 'Min iOS version: 13.0' not in versions:
            raise ValueError('Unexpected CPython deployment target')
        if not args.check_only:
            vendor = ROOT / 'Vendor'
            vendor.mkdir(exist_ok=True)
            archive.extractall(vendor, filter='data')
    print('Verified CPython 3.13-b17: SHA256 ' + digest + '; minimum iOS 13.0')


if __name__ == '__main__':
    main()
