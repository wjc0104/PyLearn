import importlib.util
import json
from pathlib import Path
import time
import unittest
import subprocess
import sys


RUNTIME_PATH = Path(__file__).parents[1] / 'PyLearn/Resources/runtime.py'


class RuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not RUNTIME_PATH.exists():
            return
        spec = importlib.util.spec_from_file_location('learn_runtime', RUNTIME_PATH)
        cls.runtime = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.runtime)

    def setUp(self):
        self.assertTrue(RUNTIME_PATH.exists(), 'Python runtime has not been implemented')

    def run_source(self, source, inputs=(), cancelled=lambda: False, timeout=10):
        output = []
        answers = iter(inputs)
        prompts = []
        def read(prompt):
            prompts.append(prompt)
            return next(answers, None)
        result = self.runtime.execute(source, output.append, read, cancelled, timeout)
        return result, ''.join(output), prompts

    def test_runs_unicode_and_standard_library(self):
        result, output, _ = self.run_source('import math\nprint("你好🐍", math.isqrt(81))')
        self.assertEqual(result['status'], 'success')
        self.assertEqual(output, '你好🐍 9\n')

    def test_reports_syntax_line_without_running_partial_source(self):
        result, output, _ = self.run_source('print("不应该输出")\nif True\n    pass')
        self.assertEqual(result['status'], 'error')
        self.assertEqual(result['error']['line'], 2)
        self.assertEqual(result['error']['kind'], 'SyntaxError')
        self.assertEqual(output, '')

    def test_reports_user_runtime_error_line(self):
        result, _, _ = self.run_source('x = 0\nprint(5 / x)')
        self.assertEqual(result['error']['line'], 2)
        self.assertEqual(result['error']['kind'], 'ZeroDivisionError')
        self.assertIn('零', result['error']['hint'])

    def test_input_is_interactive_and_preserves_unicode(self):
        result, output, prompts = self.run_source('name = input("名字：")\nprint(name)', ['小明🐍'])
        self.assertEqual(result['status'], 'success')
        self.assertEqual(prompts, ['名字：'])
        self.assertEqual(output, '小明🐍\n')

    def test_cancelled_input_stops_without_turning_into_eof_error(self):
        result, _, _ = self.run_source('input("等待")')
        self.assertEqual(result['status'], 'stopped')

    def test_fresh_globals_after_previous_execution(self):
        self.run_source('secret = 42')
        result, _, _ = self.run_source('print(secret)')
        self.assertEqual(result['error']['kind'], 'NameError')

    def test_cancels_a_tight_loop_and_next_run_works(self):
        calls = 0
        def stop():
            nonlocal calls
            calls += 1
            return calls > 20
        result, _, _ = self.run_source('while True:\n    pass', cancelled=stop)
        self.assertEqual(result['status'], 'stopped')
        self.assertEqual(self.run_source('print(3)')[1], '3\n')

    def test_cancels_sleep_quickly(self):
        start = time.monotonic()
        result, _, _ = self.run_source('import time\ntime.sleep(60)', cancelled=lambda: time.monotonic()-start > .05)
        self.assertEqual(result['status'], 'stopped')
        self.assertLess(time.monotonic()-start, 1)

    def test_timeout_recovers_from_loop(self):
        result, _, _ = self.run_source('while True:\n    pass', timeout=.02)
        self.assertEqual(result['status'], 'timeout')
        self.assertEqual(self.run_source('print("ok")')[1], 'ok\n')

    def test_waiting_for_input_does_not_consume_execution_budget(self):
        def read(prompt):
            time.sleep(.04)
            return '42'
        output = []
        result = self.runtime.execute('print(input())', output.append, read, lambda:False, .02)
        self.assertEqual(result['status'], 'success')
        self.assertEqual(''.join(output), '42\n')

    def test_output_is_bounded(self):
        result, output, _ = self.run_source('print("x" * 100000)')
        self.assertEqual(result['status'], 'output_limit')
        self.assertLessEqual(len(output), 20000)

    def test_analysis_does_not_execute_source(self):
        result = self.runtime.analyze('raise RuntimeError("不能运行")\nmy_name = 1', 'my_')
        self.assertIsNone(result['error'])
        self.assertIn('my_name', result['completions'])

    def test_analysis_reports_indent_error_and_builtin_completion(self):
        result = self.runtime.analyze('if True:\nprint(1)', 'pri')
        self.assertEqual(result['error']['kind'], 'IndentationError')
        self.assertEqual(result['error']['line'], 2)
        self.assertIn('print', result['completions'])

    def test_analysis_handles_empty_source_and_unicode_identifiers(self):
        self.assertIsNone(self.runtime.analyze('', '')['error'])
        self.assertIn('名字', self.runtime.analyze('名字 = 1', '名')['completions'])

    def test_exit_does_not_exit_host(self):
        result, _, _ = self.run_source('raise SystemExit(0)')
        self.assertEqual(result['status'], 'success')

    def test_json_request_boundary(self):
        response = json.loads(self.runtime.request(json.dumps({'action':'analyze','source':'print(1)','prefix':'pri'})))
        self.assertIn('print', response['completions'])

    def test_bare_except_cannot_swallow_stop_and_disable_timeout(self):
        probe = f'''
import importlib.util, json
spec = importlib.util.spec_from_file_location('runtime', {str(RUNTIME_PATH)!r})
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
source = "while True:\\n    try:\\n        while True: pass\\n    except:\\n        pass"
print(json.dumps(runtime.execute(source, lambda _:None, lambda _:None, lambda:False, .02)))
'''
        try:
            result = subprocess.run([sys.executable, '-c', probe], capture_output=True, text=True, timeout=2)
        except subprocess.TimeoutExpired:
            self.fail('An except block swallowed the timeout and left the interpreter running forever')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['status'], 'timeout')


if __name__ == '__main__':
    unittest.main()
