"""Pin pure Python libraries; never install platform wheels into the iOS app."""
import hashlib
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = [
 ("dulwich", "https://files.pythonhosted.org/packages/f3/f1/f8abd5626e413c356a70aef0804893895dbc75de770cec87dba72302c577/dulwich-1.2.19-py3-none-any.whl", "efe585c9c2a921a26136dc2fba785faafb16d5eed39ea6d40c5dd1cd8140f0a3"),
 ("urllib3", "https://files.pythonhosted.org/packages/92/9d/c4e665119135114480843e7ab388fa94d8480650450e6f8e26b70d323a4c/urllib3-2.8.0-py3-none-any.whl", "0cf3cae568d36aa9576b28dfb35f11328f1cb974ca7647d9475ebb86c75ac6e3"),
 ("certifi", "https://files.pythonhosted.org/packages/32/d1/a3652fe2c19134d0d15922177821d863cbd7e842d53a21bbe7e8e3a1b5ac/certifi-2026.10.23-py3-none-any.whl", "e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1"),
 ("jedi", "https://files.pythonhosted.org/packages/be/c7/71eb0d51cdcbb63b857c931aa4e9218b078b5d9f8ecd383b234f28fe7b0f/jedi-0.20.1-py2.py3-none-any.whl", "0fb16d86c4a4c73c37ba518c77419975e30fcc620658a8d14fbb5720cdd34142"),
 ("parso", "https://files.pythonhosted.org/packages/99/5d/8268b644392ee874ee82a635cd0df1773de230bde356c38de28e298392cc/parso-0.8.7-py2.py3-none-any.whl", "a8926eb2a1b915486941fdbd31e86a4baf88fe8c210f25f2f35ecec5b574ca1c"),
]

def main():
    cache = ROOT / '.cache'
    target = ROOT / 'Vendor/PythonPackages'
    cache.mkdir(exist_ok=True)
    target.mkdir(parents=True, exist_ok=True)
    for name, url, expected in PACKAGES:
        path = cache / url.rsplit('/', 1)[-1]
        if not path.exists():
            with urllib.request.urlopen(url, timeout=60) as response:
                path.write_bytes(response.read(20 * 1024 * 1024))
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Package checksum mismatch: ' + name)
        with zipfile.ZipFile(path) as wheel:
            for info in wheel.infolist():
                rel = Path(info.filename)
                if rel.is_absolute() or '..' in rel.parts or not info.filename.startswith((name + '/', name + '-')):
                    continue
                if '/tests/' in info.filename or info.filename.endswith(('.pyc', '.so', '.pyd')):
                    continue
                destination = target / rel
                if info.is_dir():
                    destination.mkdir(parents=True, exist_ok=True)
                else:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(wheel.read(info))
        print('Verified pure Python package:', name)

if __name__ == '__main__':
    main()
