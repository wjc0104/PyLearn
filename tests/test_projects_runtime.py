import importlib.util
from pathlib import Path
import sys, tempfile, unittest, json
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Vendor/PythonPackages'))
sys.path.insert(0,str(ROOT/'PyLearn/Resources'))
import runtime

class ProjectRuntimeTests(unittest.TestCase):
    def test_blank_or_completed_line_keeps_tab_for_indentation(self):
        for source, line, column in [('', 1, 0), ('print(1)\n    ', 2, 4)]:
            result = runtime.analyze(source, '', line, column)
            self.assertEqual(result['completions'], [], 'Whitespace must not launch global completion and make Tab insert abs')
            self.assertEqual(result['signature'], '')

    def test_empty_member_prefix_and_open_call_still_receive_help(self):
        member = runtime.analyze("value = 'abc'\nvalue.", '', 2, 6)
        self.assertIn('capitalize', member['completions'])
        call = runtime.analyze('print(', '', 1, 6)
        self.assertIn('print', call['signature'])
        named = 'def greet(name="world"): pass\ngreet(name='
        self.assertIn('greet', runtime.analyze(named, '', 2, 11)['signature'])
        # The source can compile even while the caret sits inside a call.
        self.assertIn('print', runtime.analyze('print(1)', '', 1, 6)['signature'])

    def test_nested_entry_imports_sibling_module(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'tools').mkdir()
            (root/'tools/helper.py').write_text('value=42')
            out=[]
            r=runtime.execute('import helper\nprint(helper.value)',out.append,lambda _:None,lambda:False,directory=folder,filename=str(root/'tools/main.py'))
            self.assertEqual(r['status'],'success',r)
            self.assertEqual(''.join(out),'42\n')

    def test_project_imports_resources_and_restores_environment(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)
            (p/'utils.py').write_text("def greet(): return '你好'",encoding='utf8')
            (p/'data.json').write_text('{"n":42}',encoding='utf8')
            old=Path.cwd(); out=[]
            r=runtime.execute("import utils,json\nwith open('data.json') as f: data=json.load(f)\nprint(utils.greet(),data['n'])",out.append,lambda _:None,lambda:False,directory=folder)
            self.assertEqual(r['status'],'success',r)
            self.assertEqual(''.join(out),'你好 42\n')
            self.assertEqual(Path.cwd(),old)
            self.assertNotIn('utils',sys.modules)

    def test_jedi_attribute_completion_does_not_execute_user_code(self):
        r=runtime.analyze("raise RuntimeError('do not execute')\nvalue = 'abc'\nvalue.up",'up',line=3,column=8)
        self.assertIn('upper',r['completions'])

    def test_function_tests_grade_more_than_one_input(self):
        tests="import unittest\nfrom answer import twice\nclass T(unittest.TestCase):\n def test_values(self):\n  self.assertEqual(twice(2),4)\n  self.assertEqual(twice(9),18)"
        self.assertEqual(runtime.grade('def twice(n): return n*2','answer',tests)['status'],'success')
        self.assertEqual(runtime.grade('def twice(n): return 4','answer',tests)['status'],'failed')

    def test_error_keeps_copyable_trace_and_chinese_hint(self):
        r=runtime.execute("print(missing)",lambda _:None,lambda _:None,lambda:False)
        self.assertIn('missing',r['error']['hint'])
        self.assertIn('NameError',r['error']['traceback'])

if __name__=='__main__':unittest.main()
