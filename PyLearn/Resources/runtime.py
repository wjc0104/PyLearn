"""Portable learning helpers. The native bridge calls request() on one queue."""
import builtins
import contextlib
import io
import json
import keyword
import re
import sys
import time
import traceback

FILENAME = '<学习脚本>'
MAX_SOURCE = 512 * 1024
MAX_OUTPUT = 20000


class _Stopped(BaseException):
    pass


class _TimedOut(BaseException):
    pass


class _OutputLimit(BaseException):
    pass


def _error(exc):
    line = getattr(exc, 'lineno', None)
    if line is None and exc.__traceback__:
        for frame in traceback.extract_tb(exc.__traceback__):
            if frame.filename == FILENAME:
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
        'ModuleNotFoundError': '未找到这个模块。首版提供标准库，不支持任意第三方包。',
        'RecursionError': '递归调用过深，请检查终止条件。',
        'FileNotFoundError': '没有找到文件，请检查文件路径。',
    }
    return {'kind': kind, 'message': str(exc), 'line': line,
            'hint': hints.get(kind, '查看错误类型和提示，检查对应代码行。')}


def _compile(source):
    if len(source.encode('utf-8')) > MAX_SOURCE:
        raise ValueError('脚本不能超过 512 KiB。')
    return compile(source, FILENAME, 'exec')


def analyze(source, prefix):
    error = None
    try:
        _compile(source)
    except (SyntaxError, ValueError) as exc:
        error = _error(exc)
    names = set(keyword.kwlist) | set(dir(builtins))
    names.update(re.findall(r'[^\W\d]\w*', source, re.UNICODE))
    matches = sorted(n for n in names if prefix and n.startswith(prefix) and n != prefix)
    return {'error': error, 'completions': matches[:8]}


def execute(source, write, read, cancelled, timeout=10):
    started = time.monotonic()
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
        if frame.f_code.co_filename == FILENAME:
            # Opcode events also catch a one-line `while True: pass` loop.
            frame.f_trace_opcodes = True
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
        code = _compile(source)
        builtins.input = ask
        time.sleep = sleep
        with contextlib.redirect_stdout(Writer()), contextlib.redirect_stderr(Writer()):
            sys.settrace(trace)
            # shortcut: cancellation is cooperative; arbitrary C extensions cannot be force-killed.
            exec(code, {'__name__': '__main__', '__file__': FILENAME})
    except _Stopped:
        status = 'stopped'
    except _TimedOut:
        status = 'timeout'
    except _OutputLimit:
        status = 'output_limit'
    except SystemExit as exc:
        if exc.code not in (None, 0):
            status, error = 'error', _error(exc)
    except BaseException as exc:
        status, error = 'error', _error(exc)
    finally:
        sys.settrace(old_trace)
        builtins.input = original_input
        time.sleep = original_sleep
    return {'status': status, 'error': error}


def request(payload_json):
    payload = json.loads(payload_json)
    source = payload.get('source', '')
    if payload['action'] == 'analyze':
        result = analyze(source, payload.get('prefix', ''))
    elif payload['action'] == 'run':
        import _learnpy_native as native
        result = execute(source, native.write, native.read, native.cancelled)
    else:
        raise ValueError('未知操作')
    return json.dumps(result, ensure_ascii=False)
