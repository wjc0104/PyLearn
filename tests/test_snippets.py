import json
from pathlib import Path
import unittest

class SnippetTests(unittest.TestCase):
    def test_templates_are_valid_python_and_cover_common_tasks(self):
        path = Path(__file__).resolve().parents[1] / 'PyLearn/Resources/snippets.json'
        self.assertTrue(path.exists(), 'Editor templates have not been added')
        snippets = json.loads(path.read_text(encoding='utf8'))
        self.assertGreaterEqual(len(snippets), 25)
        self.assertEqual(len({s['id'] for s in snippets}), len(snippets))
        self.assertGreaterEqual(len({s['category'] for s in snippets}), 5)
        for snippet in snippets:
            with self.subTest(id=snippet['id']):
                compile(snippet['source'], snippet['id'] + '.py', 'exec')
