"""Git operations via pure Python Dulwich; no shell or credential persistence."""
import io
from pathlib import Path
from urllib.parse import urlsplit
from dulwich import porcelain
from dulwich.repo import Repo

def _remote(value):
    parsed = urlsplit(value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError('远程地址必须为不含账号密码的 HTTPS URL。')
    return value

def _clean(path):
    status = porcelain.status(path)
    return not (any(status.staged.values()) or status.unstaged or status.untracked)

def perform(payload):
    path = str(Path(payload['directory']).resolve())
    operation = payload.get('operation', 'status')
    try:
        output = io.BytesIO()
        if operation in ('clone', 'pull', 'push'):
            import certifi, urllib3
            remote = _remote(payload.get('remote', ''))
            options = dict(username=payload.get('username') or 'git', password=payload.get('token') or '',
                pool_manager=urllib3.PoolManager(cert_reqs='CERT_REQUIRED', ca_certs=certifi.where(),
                    timeout=urllib3.Timeout(connect=15, read=30), retries=False))
        if operation == 'init':
            porcelain.init(path).close()
            report = '已创建本地 Git 仓库。'
        elif operation == 'clone':
            if Path(path).exists() and any(Path(path).iterdir()):
                raise ValueError('克隆目标必须是空文件夹。')
            porcelain.clone(remote, path, depth=1, errstream=output, **options).close()
            report = '克隆完成。'
        elif operation == 'commit':
            if not payload.get('message', '').strip():
                raise ValueError('请填写提交说明。')
            author = payload.get('author', 'PyLearn <pylearn@local>')
            if '\n' in author or '\r' in author:
                raise ValueError('作者格式无效。')
            porcelain.add(path)
            sha = porcelain.commit(path, message=payload['message'].encode(), author=author.encode(),
                                   committer=author.encode(), no_verify=True, sign=False)
            report = '提交完成：' + sha.decode()[:12]
        elif operation == 'diff':
            porcelain.diff(path, outstream=output)
            report = output.getvalue().decode('utf8', 'replace') or '没有未暂存的差异。'
        elif operation == 'log':
            text = io.StringIO()
            porcelain.log(path, outstream=text, max_entries=30, oneline=True)
            report = text.getvalue()
        elif operation == 'branch':
            porcelain.branch_create(path, payload['branch'])
            report = '分支已创建：' + payload['branch']
        elif operation == 'checkout':
            if not _clean(path): raise ValueError('请先提交修改，再切换分支。')
            porcelain.checkout(path, payload['branch'])
            report = '已切换分支。'
        elif operation in ('pull','push'):
            with Repo(path) as repo:
                refs, _ = repo.refs.follow(b'HEAD')
                local_ref = refs[-1]
                if not local_ref.startswith(b'refs/heads/'):
                    raise ValueError('当前为分离 HEAD，请先切换到分支。')
                try:
                    remote_ref = repo.get_config_stack().get((b'branch', local_ref[len(b'refs/heads/'):]), b'merge')
                except KeyError:
                    remote_ref = local_ref
            if operation == 'pull' and not _clean(path):
                raise ValueError('请先提交本地修改；拉取不会覆盖你的代码。')
            if operation == 'pull':
                porcelain.pull(path, remote, refspecs=[remote_ref + b':' + local_ref], ff_only=True, force=False, errstream=output, outstream=output, **options)
            else:
                result = porcelain.push(path, remote, refspecs=[local_ref + b':' + remote_ref], force=False, errstream=output, outstream=output, **options)
                if any(result.ref_status.values()): raise ValueError('远程拒绝推送，请先检查权限或拉取最新提交。')
            report = '同步完成。'
        elif operation == 'status':
            s = porcelain.status(path, untracked_files='all')
            lines = []
            for state, paths in s.staged.items():
                lines.extend('已暂存 ' + state + '  ' + p.decode('utf8','replace') for p in paths)
            lines.extend('已修改  ' + p.decode('utf8','replace') for p in s.unstaged)
            lines.extend('未跟踪  ' + (p.decode('utf8','replace') if isinstance(p, bytes) else p) for p in s.untracked)
            report = '\n'.join(lines) or '工作区干净。'
        else:
            raise ValueError('未知 Git 操作。')
        branches = []
        try:
            branches = [x.decode('utf8', 'replace') for x in porcelain.branch_list(path)]
        except Exception:
            pass
        return {'status':'success', 'report':report[:20000], 'branches':branches}
    except Exception as exc:
        message = str(exc)
        for secret in (payload.get('token'), payload.get('username')):
            if secret: message = message.replace(secret, '***')
        return {'status':'error', 'report':'Git 操作失败；本地修改已保留。\n' + message[:2000]}
