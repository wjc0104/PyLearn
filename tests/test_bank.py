import sys,json,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'Vendor/PythonPackages'),str(ROOT/'PyLearn/Resources')]
import runtime
class BankTests(unittest.TestCase):
 def test_catalog_is_bundled_and_reference_answers_pass(self):
  data=json.loads((ROOT/'catalog/bank.json').read_text(encoding='utf8'))
  self.assertEqual(data['schema'],1)
  self.assertGreaterEqual(len(data['exercises']),100)
  self.assertEqual((ROOT/'catalog/bank.json').read_bytes(),(ROOT/'PyLearn/Resources/bank.json').read_bytes())
  self.assertEqual(len({e['id'] for e in data['exercises']}),len(data['exercises']))
  for item in data['exercises']:
   with self.subTest(id=item['id']):
    self.assertTrue(item['prompt']);self.assertTrue(item['sourceURL'].startswith('https://github.com/exercism/python/'))
    r=runtime.grade(item['solution'],item['module'],item['tests'])
    self.assertEqual(r['status'],'success',r.get('report','')[-1000:])
 def test_no_tests_cannot_be_graded_as_success(self):
  self.assertNotEqual(runtime.grade('x=1','answer','import unittest')['status'],'success')
