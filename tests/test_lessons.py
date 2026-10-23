import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).parents[1]


class LessonTests(unittest.TestCase):
    def test_all_examples_run_and_solutions_produce_expected_output(self):
        path = ROOT / 'PyLearn/Resources/lessons.json'
        self.assertTrue(path.exists(), 'Learning content has not been implemented')
        lessons = json.loads(path.read_text(encoding='utf-8'))
        spec = importlib.util.spec_from_file_location('runtime', ROOT / 'PyLearn/Resources/runtime.py')
        runtime = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runtime)
        self.assertEqual(len(lessons), 8)
        ids = []
        for lesson in lessons:
            output = []
            self.assertEqual(runtime.execute(lesson['example'], output.append, lambda _: '', lambda: False)['status'], 'success')
            self.assertEqual(len(lesson['exercises']), 2)
            for exercise in lesson['exercises']:
                with self.subTest(exercise=exercise['id']):
                    ids.append(exercise['id'])
                    output = []
                    result = runtime.execute(exercise['solution'], output.append, lambda _: '', lambda: False)
                    self.assertEqual(result['status'], 'success')
                    self.assertEqual(''.join(output).strip(), exercise['expected'].strip())
        self.assertEqual(len(ids), len(set(ids)))
