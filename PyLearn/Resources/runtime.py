"""Portable learning helpers. The native bridge calls request() on one queue."""
import ast
import builtins
import contextlib
import io
import importlib.abc
import importlib.machinery
import importlib.util
import json
import keyword
import os
from pathlib import Path
import re
import sys
import time
import tokenize
import traceback
import types
import unittest

_packages = Path(__file__).parent / 'packages'
if _packages.is_dir():
    sys.path.insert(0, str(_packages))

FILENAME = '<学习脚本>'
MAX_SOURCE = 512 * 1024
MAX_OUTPUT = 20000


class _Stopped(BaseException):
    pass


class _TimedOut(BaseException):
    pass


class _OutputLimit(BaseException):
    pass


def _error(exc, filename=FILENAME):
    line = getattr(exc, 'lineno', None)
    if line is None and exc.__traceback__:
        for frame in traceback.extract_tb(exc.__traceback__):
            if frame.filename == filename:
                line = frame.lineno
    kind = type(exc).__name__
    hints = {
        'SyntaxError': '检查冒号、括号、引号是否完整，以及语句写法是否正确。',
        'IndentationError': '检查缩进：同一代码块使用相同数量的空格，通常为四个。',
        'TabError': '请统一使用空格缩进，不要混用制表符和空格。',
        'NameError': '检查变量名拼写，并确认使用前已赋值。',
        'TypeError': '检查参与运算或传给函数的值的类型。',
        'ValueError': '值的格式不符合要求，例如把文字转换成数字。',
        'ZeroDivisionError': '除数不能为零，请先检查除数。',
        'IndexError': '索引超出范围，请检查列表长度；第一个元素的索引是 0。',
        'KeyError': '字典中没有这个键，可以先检查键是否存在。',
        'ModuleNotFoundError': '检查模块名、项目目录和运行入口。支持标准库与项目内模块，未提供任意第三方包安装。',
        'RecursionError': '递归调用过深，请检查终止条件。',
        'FileNotFoundError': '没有找到文件，请检查文件路径。',
    }
    hint = hints.get(kind, '查看错误类型和提示，检查对应代码行。')
    if kind == 'NameError' and getattr(exc, 'name', None):
        hint = f'变量“{exc.name}”还没有定义。请检查拼写，或先给它赋值。'
    return {'kind': kind, 'message': str(exc), 'line': line, 'hint': hint,
            'traceback': ''.join(traceback.format_exception(exc))}


def _compile(source, guard_name=None, filename=FILENAME):
    if len(source.encode('utf-8')) > MAX_SOURCE:
        raise ValueError('脚本不能超过 512 KiB。')
    if guard_name is None:
        return compile(source, filename, 'exec')
    tree = ast.parse(source, filename)

    class Guards(ast.NodeTransformer):
        def generic_visit(self, node):
            node = super().generic_visit(node)
            if isinstance(node, (ast.While, ast.For, ast.AsyncFor, ast.ExceptHandler)):
                call = ast.Expr(ast.Call(ast.Name(guard_name, ast.Load()), [], []))
                node.body.insert(0, ast.copy_location(call, node))
            return node

    # A caught trace exception disables tracing; loop/handler guards remain active.
    return compile(ast.fix_missing_locations(Guards().visit(tree)), filename, 'exec')


def analyze(source, prefix, line=None, column=None, directory=None, path=None):
    error = None
    try:
        _compile(source)
    except (SyntaxError, ValueError) as exc:
        error = _error(exc)
    matches = []
    if prefix:
        names = set(keyword.kwlist) | set(dir(builtins))
        names.update(re.findall(r'[^\W\d]\w*', source, re.UNICODE))
        matches = sorted(n for n in names if n.startswith(prefix) and n != prefix)
    signature = ''
    before = ''
    if line is not None and column is not None:
        lines = source.split('\n')
        if 0 < line <= len(lines):
            before = lines[line - 1][:column].rstrip()
            if not before:
                # A paired closing bracket can make the whole file valid even
                # while the caret is on a blank argument line inside a call.
                cursor_source = '\n'.join(lines[:line - 1] + [lines[line - 1][:column]])
                delimiters = []
                try:
                    for token in tokenize.generate_tokens(io.StringIO(cursor_source).readline):
                        if token.type == tokenize.OP:
                            if token.string in ('(', '[', '{'):
                                delimiters.append(token.string)
                            elif token.string in (')', ']', '}') and delimiters:
                                delimiters.pop()
                except (tokenize.TokenError, IndentationError, SyntaxError):
                    pass
                if delimiters:
                    before = delimiters[-1]
    # Blank statements should indent on Tab, not start global Jedi inference.
    if line is not None and column is not None and (prefix or before):
        try:
            import jedi
            # iOS cannot spawn a Python executable; Script only inspects source.
            script = jedi.Script(source, path=path,
                project=jedi.Project(directory, load_unsafe_extensions=False) if directory else None,
                environment=jedi.InterpreterEnvironment())
            matches = [c.name for c in script.complete(line, column)] or matches
            signature = '\n'.join(s.to_string() for s in script.get_signatures(line, column))
        except Exception:
            pass  # New syntax must remain runnable even before Jedi supports it.
    return {'error': error, 'completions': list(dict.fromkeys(matches))[:30], 'signature': signature}


@contextlib.contextmanager
def project_context(directory, guard_name=None, check=None):
    if not directory:
        yield
        return
    root = Path(directory).resolve(strict=True)
    old_cwd, old_path = Path.cwd(), sys.path[:]
    before = sys.modules.copy()
    missing = object()
    old_guard = getattr(builtins, guard_name, missing) if guard_name else missing
    class Loader(importlib.machinery.SourceFileLoader):
        def source_to_code(self, data, path, *, _optimize=-1):
            return _compile(importlib.util.decode_source(data) if isinstance(data, bytes) else data, guard_name, path)
        def get_code(self, fullname):
            return self.source_to_code(self.get_data(self.path), self.path)
    class Finder(importlib.abc.MetaPathFinder):
        def find_spec(self, fullname, path=None, target=None):
            spec = importlib.machinery.PathFinder.find_spec(fullname, path)
            if spec and spec.origin and spec.origin.endswith('.py') and Path(spec.origin).resolve().is_relative_to(root):
                spec.loader = Loader(fullname, spec.origin)
                return spec
            return None
    finder = Finder()
    try:
        if guard_name:
            setattr(builtins, guard_name, check)
            sys.meta_path.insert(0, finder)
        os.chdir(root)
        sys.path.insert(0, str(root))
        yield
    finally:
        for name, module in list(sys.modules.items()):
            file = getattr(module, '__file__', None)
            if file:
                try:
                    inside = Path(file).resolve().is_relative_to(root)
                except (ValueError, OSError):
                    inside = False
                if inside:
                    sys.modules.pop(name, None)
                    if name in before:
                        sys.modules[name] = before[name]
        sys.path[:] = old_path
        os.chdir(old_cwd)
        if finder in sys.meta_path: sys.meta_path.remove(finder)
        if guard_name:
            if old_guard is missing: delattr(builtins, guard_name)
            else: setattr(builtins, guard_name, old_guard)


def execute(source, write, read, cancelled, timeout=10, directory=None, filename=None):
    started = time.monotonic()
    project_prefix = str(Path(directory).resolve()) + os.sep if directory else None
    paused = 0.0
    waiting = False
    emitted = 0
    old_trace = sys.gettrace()
    original_input = builtins.input
    original_sleep = time.sleep

    def check():
        if cancelled():
            raise _Stopped()
        if not waiting and time.monotonic() - started - paused > timeout:
            raise _TimedOut()

    def trace(frame, event, arg):
        if frame.f_code.co_filename == FILENAME or (project_prefix and frame.f_code.co_filename.startswith(project_prefix)):
            # Opcode events also catch a one-line `while True: pass` loop.
            # Project imports also have AST loop guards; opcode tracing there
            # would make ordinary module functions needlessly slow.
            frame.f_trace_opcodes = frame.f_code.co_filename == FILENAME
            check()
        return trace

    class Writer(io.TextIOBase):
        @property
        def encoding(self):
            return 'utf-8'

        def writable(self):
            return True

        def write(self, value):
            nonlocal emitted
            room = MAX_OUTPUT - emitted
            chunk = value[:room]
            if chunk:
                write(chunk)
                emitted += len(chunk)
            if len(value) > room:
                raise _OutputLimit()
            return len(value)

    def ask(prompt=''):
        nonlocal paused, waiting
        check()
        before = time.monotonic()
        waiting = True
        try:
            answer = read(str(prompt))
        finally:
            paused += time.monotonic() - before
            waiting = False
        if answer is None:
            raise _Stopped()
        check()
        return answer

    def sleep(seconds):
        if seconds < 0:
            raise ValueError('sleep length must be non-negative')
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            check()
            original_sleep(min(.025, max(0, end - time.monotonic())))

    status, error = 'success', None
    try:
        guard_name = '__pylearn_check__'
        while guard_name in source:
            guard_name += '_'
        code = _compile(source, guard_name, filename or FILENAME)
        builtins.input = ask
        time.sleep = sleep
        with project_context(directory, guard_name, check), contextlib.redirect_stdout(Writer()), contextlib.redirect_stderr(Writer()):
            if directory and filename:
                sys.path.insert(0, str(Path(filename).resolve().parent))
            sys.settrace(trace)
            # shortcut: cancellation is cooperative; arbitrary C extensions cannot be force-killed.
            exec(code, {'__name__': '__main__', '__file__': filename or FILENAME, guard_name: check})
    except _Stopped:
        status = 'stopped'
    except _TimedOut:
        status = 'timeout'
    except _OutputLimit:
        status = 'output_limit'
    except SystemExit as exc:
        if exc.code not in (None, 0):
            status, error = 'error', _error(exc, filename or FILENAME)
    except BaseException as exc:
        status, error = 'error', _error(exc, filename or FILENAME)
    finally:
        sys.settrace(old_trace)
        builtins.input = original_input
        time.sleep = original_sleep
    return {'status': status, 'error': error}


def grade(source, module_name, test_source, cancelled=lambda: False):
    if not re.fullmatch(r'[A-Za-z_]\w*', module_name):
        raise ValueError('无效的练习模块名称')
    import tempfile
    with tempfile.TemporaryDirectory() as folder:
        Path(folder, module_name + '.py').write_text(source, encoding='utf8')
        test_path = Path(folder, 'pylearn_checks.py')
        test_path.write_text(test_source, encoding='utf8')
        out = []
        runner = ("import unittest\n"
                  "suite = unittest.TestLoader().discover('.', pattern='pylearn_checks.py')\n"
                  "result = unittest.TextTestRunner(verbosity=2).run(suite)\n"
                  "if result.testsRun == 0: raise ValueError('题目没有有效测试')\n"
                  "if len(result.skipped) == result.testsRun: raise ValueError('所有测试都被跳过')\n"
                  "if not result.wasSuccessful(): raise AssertionError('部分测试没有通过')")
        response = execute(runner, out.append, lambda _: None, cancelled, directory=folder)
        if response['status'] == 'error':
            response['status'] = 'failed'
        response['report'] = ''.join(out)
        return response


def request(payload_json):
    payload = json.loads(payload_json)
    source = payload.get('source', '')
    if payload['action'] == 'analyze':
        result = analyze(source, payload.get('prefix', ''), payload.get('line'), payload.get('column'), payload.get('directory'), payload.get('path'))
    elif payload['action'] == 'run':
        import _learnpy_native as native
        result = execute(source, native.write, native.read, native.cancelled,
                         directory=payload.get('directory'), filename=payload.get('path'))
    elif payload['action'] == 'grade':
        result = grade(source, payload['module'], payload['tests'])
    elif payload['action'] == 'git':
        from git_support import perform
        result = perform(payload)
    else:
        raise ValueError('未知操作')
    return json.dumps(result, ensure_ascii=False)
