"""Seed only the simulator's Files test directory; not included in the app."""
from pathlib import Path
import sys

root = Path(sys.argv[1]) / 'PyLearnImportFixture'
project = root / 'my-python'
(project / 'modules' / 'deep').mkdir(parents=True, exist_ok=True)
(project / 'main.py').write_text("from modules.helper import value\nfrom pathlib import Path\nprint(value, Path('data.txt').read_text())\n", encoding='utf-8')
(project / 'modules' / 'helper.py').write_text("value = 'folder'\n", encoding='utf-8')
(project / 'modules' / 'deep' / 'value.py').write_text('value = 42\n', encoding='utf-8')
(project / 'data.txt').write_text('import ok', encoding='utf-8')
(root / 'single.py').write_text("print('single import ok')\n", encoding='utf-8')
print('Prepared real Files import fixtures')
