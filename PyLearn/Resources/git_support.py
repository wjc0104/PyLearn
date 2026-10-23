"""Git operations via pure Python Dulwich; no shell or credential persistence."""
import io
from pathlib import Path
from urllib.parse import urlsplit
from dulwich import porcelain
from dulwich.repo import Repo
from dulwich.client import HTTPUnauthorized, HTTPProxyUnauthorized

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
        if operation == 'commit_push':
            _remote(payload.get('remote', ''))
            committed = perform(dict(payload, operation='commit'))
            if committed['status'] != 'success': return committed
            pushed = perform(dict(payload, operation='push'))
            pushed['report'] = committed['report'] + '\n\n' + pushed['report']
            return pushed
        output = io.BytesIO()
        if operation in ('clone', 'pull', 'push'):
            import certifi, urllib3
            remote = _remote(payload.get('remote', ''))
            options = dict(pool_manager=urllib3.PoolManager(cert_reqs='CERT_REQUIRED', ca_certs=certifi.where(),
                    timeout=urllib3.Timeout(connect=15, read=30), retries=False))
            if payload.get('token'):
                options.update(username=payload.get('username') or 'git', password=payload['token'])
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
            # Explicitly hash tracked files; unchanged size/timestamps can hide rapid edits.
            with Repo(path) as repo:
                # iOS cannot spawn shell hooks, including post-commit despite no_verify.
                repo.hooks.clear()
                repo.get_worktree().stage(list(repo.open_index()), config=repo.get_config_stack())
                porcelain.add(repo)
                try:
                    unchanged = repo.open_index().commit(repo.object_store) == repo[repo.head()].tree
                except KeyError:
                    unchanged = False
                if unchanged:
                    sha = repo.head()
                    report = '没有新的文件修改；当前本地提交：' + sha.decode()[:12]
                else:
                    sha = porcelain.commit(repo, message=payload['message'].encode(), author=author.encode(),
                                           committer=author.encode(), no_verify=True, sign=False)
                    report = '本地提交完成：' + sha.decode()[:12]
                report += '\n尚未推送；推送成功后其他设备才能拉取。'
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
                # Dulwich 1.2.19 v2 can advertise GitHub tips without downloading their objects.
                porcelain.pull(path, remote, refspecs=[remote_ref + b':' + local_ref], protocol_version=0, ff_only=True, force=False, errstream=output, outstream=output, **options)
            else:
                result = porcelain.push(path, remote, refspecs=[local_ref + b':' + remote_ref], force=False, errstream=output, outstream=output, **options)
                if any(result.ref_status.values()): raise ValueError('远程拒绝推送，请先检查权限或拉取最新提交。')
            report = '拉取完成，项目已更新。' if operation == 'pull' else '推送成功，远端已更新；其他设备现在可以拉取。'
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
        if isinstance(exc, porcelain.DivergedBranches):
            message = ('远端已有本机未包含的提交，请先拉取再推送。若拉取仍提示分歧，请在电脑 Git 客户端合并两端提交，再拉取。' if operation == 'push' else
                       '本地与远端提交已分歧，当前拉取仅支持快进。请在电脑 Git 客户端合并两端提交，再拉取。')
            message += '\n已停止同步以保护两端代码，不会强制覆盖。'
        elif isinstance(exc, HTTPUnauthorized):
            message = '账号或访问令牌无效，或没有该仓库权限。请检查已保存凭据；公开仓库克隆可清空令牌后重试。'
        elif isinstance(exc, HTTPProxyUnauthorized):
            message = '网络代理需要认证，请检查设备代理设置后重试。'
        else:
            message = str(exc)
        for secret in (payload.get('token'), payload.get('username')):
            if secret: message = message.replace(secret, '***')
        return {'status':'error', 'report':'Git ' + {'commit':'提交','push':'推送','pull':'拉取','clone':'克隆'}.get(operation, operation) + '失败；本地文件和已有提交已保留。\n' + message[:2000]}
