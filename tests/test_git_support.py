import os,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'Vendor/PythonPackages'),str(ROOT/'PyLearn/Resources')]
import git_support
from unittest.mock import patch
from dulwich import porcelain
class GitTests(unittest.TestCase):
 def test_commit_records_same_size_edit_even_if_file_timestamp_is_preserved(self):
  with tempfile.TemporaryDirectory() as d:
   def call(op,**extra): return git_support.perform(dict(directory=d,operation=op,**extra))
   call('init'); path=Path(d,'main.py');path.write_text('print(1)')
   self.assertEqual(call('commit',message='one')['status'],'success')
   saved=path.stat();path.write_text('print(2)');os.utime(path,ns=(saved.st_atime_ns,saved.st_mtime_ns))
   self.assertEqual(call('commit',message='two')['status'],'success')
   with git_support.Repo(d) as repo:
    item=repo[repo[repo.head()].tree][b'main.py']
    self.assertEqual(repo[item[1]].data,b'print(2)')

 def test_phone_and_computer_can_exchange_edits_and_new_chinese_files(self):
  with tempfile.TemporaryDirectory() as d:
   remote=Path(d,'remote'); pc=Path(d,'computer'); phone=Path(d,'phone')
   porcelain.init(str(remote),bare=True).close(); pc.mkdir()
   def call(path,operation,**extra):
    with patch.object(git_support,'_remote',return_value=str(remote)):
     result=git_support.perform(dict(directory=str(path),operation=operation,remote='https://example.com/repo',**extra))
    self.assertEqual(result['status'],'success',result)
    return result
   call(pc,'init'); Path(pc,'main.py').write_text('print(1)',encoding='utf8')
   call(pc,'commit',message='initial'); call(pc,'push'); call(phone,'clone')
   Path(phone,'main.py').write_text('print(2)',encoding='utf8')
   Path(phone,'中文练习.py').write_text("print('手机新增')",encoding='utf8')
   call(phone,'commit',message='phone edit and new script'); call(phone,'push'); call(pc,'pull')
   self.assertEqual(Path(pc,'main.py').read_text(encoding='utf8'),'print(2)')
   self.assertEqual(Path(pc,'中文练习.py').read_text(encoding='utf8'),"print('手机新增')")
   Path(pc,'中文练习.py').write_text("print('电脑修改')",encoding='utf8')
   call(pc,'commit',message='computer edit'); call(pc,'push'); call(phone,'pull')
   self.assertEqual(Path(phone,'中文练习.py').read_text(encoding='utf8'),"print('电脑修改')")

 def test_pull_tracks_current_branch_instead_of_remote_default(self):
  with tempfile.TemporaryDirectory() as d:
   remote=Path(d,'remote');local=Path(d,'local');remote.mkdir()
   porcelain.init(str(remote)).close()
   def commit(value):
    Path(remote,'main.py').write_text(value);porcelain.add(str(remote));porcelain.commit(str(remote),message=value.encode(),author=b'Test <test@local>',no_verify=True,sign=False)
   commit('base')
   porcelain.branch_create(str(remote),'practice')
   clone=porcelain.clone(str(remote),str(local));clone.close()
   porcelain.branch_create(str(local),'practice',objectish=b'refs/remotes/origin/practice')
   porcelain.checkout(str(local),'practice')
   commit('default-new')
   porcelain.checkout(str(remote),'practice');commit('practice-new')
   with patch.object(git_support,'_remote',return_value=str(remote)):
    result=git_support.perform(dict(directory=str(local),operation='pull',remote='https://example.com/repo'))
   self.assertEqual(result['status'],'success',result)
   self.assertEqual(Path(local,'main.py').read_text(),'practice-new')
 def test_local_git_and_dirty_checkout_protection(self):
  with tempfile.TemporaryDirectory() as d:
   def call(op,**kw):return git_support.perform(dict(directory=d,operation=op,**kw))
   self.assertEqual(call('init')['status'],'success')
   Path(d,'main.py').write_text('print(1)')
   self.assertIn('main.py',call('status')['report'])
   self.assertEqual(call('commit',message='first')['status'],'success')
   self.assertEqual(call('branch',branch='practice')['status'],'success')
   Path(d,'main.py').write_text('print(2)')
   self.assertIn('+print(2)',call('diff')['report'])
   self.assertEqual(call('checkout',branch='practice')['status'],'error')
   self.assertEqual(Path(d,'main.py').read_text(),'print(2)')
 def test_remote_rejects_embedded_credentials_and_non_https(self):
  for remote in ['https://user:secret@github.com/a/b','file:///tmp/repo','http://github.com/a/b']:
   self.assertEqual(git_support.perform(dict(directory='.',operation='clone',remote=remote))['status'],'error')
