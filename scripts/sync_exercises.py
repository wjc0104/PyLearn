"""Generate the versioned offline/online bank from a pinned MIT Exercism track."""
import ast, hashlib, json, sys, tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REF='6105f6d9d3ef66ce3d5c8f529d2882af3d76b706'
sys.path[:0]=[str(ROOT/'Vendor/PythonPackages'),str(ROOT/'PyLearn/Resources')]
import runtime
TOPICS={'bools':'布尔值','numbers':'数字 数学','conditionals':'条件判断 if else','comparisons':'比较运算',
'strings':'字符串','string-methods':'字符串方法','lists':'列表','list-methods':'列表方法','loops':'循环 for while',
'sequences':'序列','dicts':'字典','sets':'集合','function-arguments':'函数参数','functions':'函数',
'regular-expressions':'正则表达式','classes':'类 面向对象','tuples':'元组','generators':'生成器',
'iteration':'迭代','recursion':'递归','with-statement':'文件读写 with','raising-and-handling-errors':'异常处理',
'list-comprehensions':'列表推导式','itertools':'迭代工具','class-inheritance':'类继承','decorators':'装饰器',
'operator-overloading':'运算符重载','enums':'枚举','collections':'容器','none':'空值','unpacking-and-multiple-assignment':'解包 多重赋值'}

def main():
    zh=json.loads((ROOT/'catalog/zh.json').read_text(encoding='utf8'))
    archive=ROOT/'.cache/exercism-python.tar.gz'
    if not archive.exists():
        import urllib.request
        with urllib.request.urlopen('https://api.github.com/repos/exercism/python/tarball/'+REF,timeout=90) as response:
            archive.write_bytes(response.read())
    output=[]; rejected=[]
    class EnableTests(ast.NodeTransformer):
        def visit_FunctionDef(self,node):
            node.decorator_list=[d for d in node.decorator_list if not (isinstance(d,ast.Call) and isinstance(d.func,ast.Attribute) and d.func.attr in ('skip','skipIf','skipUnless'))]
            return self.generic_visit(node)
    with tarfile.open(archive) as tar:
        root=tar.getnames()[0]
        if REF[:7] not in root:raise ValueError('Unexpected upstream archive ref')
        def read(path):return tar.extractfile(root+'/'+path).read().decode('utf8')
        config=json.loads(read('config.json'))
        for item in config['exercises']['practice']:
            slug=item['slug']
            if slug not in zh or item.get('status')=='deprecated':continue
            base='exercises/practice/'+slug+'/'
            try:
                meta=json.loads(read(base+'.meta/config.json'))
                files=meta['files']
                if len(files['solution'])!=1 or len(files['test'])!=1 or len(files['example'])!=1:continue
                module=Path(files['solution'][0]).stem
                starter=read(base+files['solution'][0])
                solution=read(base+files['example'][0])
                tests=ast.unparse(EnableTests().visit(ast.parse(read(base+files['test'][0]))))
                original=read(base+'.docs/instructions.md')
                result=runtime.grade(solution,module,tests)
                if result['status']!='success':
                    rejected.append({'id':slug,'reason':result.get('report','')[-500:]});continue
                tags=[TOPICS.get(t,t) for t in item.get('practices',[])] or ['综合练习']
                output.append(dict(id='exercism.'+slug,title=zh[slug]['title'],prompt=zh[slug]['prompt'],
                    original=original,starter=starter,solution=solution,module=module,tests=tests,
                    hint='先阅读函数参数和测试示例，从最简单的输入开始，再处理空值和边界。不要只打印答案，要返回函数结果。',
                    tags=tags,difficulty=item.get('difficulty',1),source='Exercism · MIT',
                    sourceURL='https://github.com/exercism/python/tree/'+REF+'/'+base.rstrip('/'),
                    revision=REF,authors=meta.get('authors',[])+meta.get('contributors',[])))
                print('Verified',slug,flush=True)
            except Exception as exc:rejected.append({'id':slug,'reason':str(exc)})
    document=dict(schema=1,revision=REF,exercises=output)
    text=json.dumps(document,ensure_ascii=False,separators=(',',':'))
    (ROOT/'catalog/bank.json').write_text(text,encoding='utf8')
    (ROOT/'PyLearn/Resources/bank.json').write_text(text,encoding='utf8')
    (ROOT/'catalog/excluded.json').write_text(json.dumps(rejected,ensure_ascii=False,indent=2),encoding='utf8')
    with tarfile.open(archive) as tar:
        license=tar.extractfile(tar.getnames()[0]+'/LICENSE').read().decode()
    (ROOT/'catalog/LICENSE-Exercism.txt').write_text(license,encoding='utf8')
    (ROOT/'PyLearn/Resources/ExercismLicense.txt').write_text(license,encoding='utf8')
    print('Published',len(output),'exercises;',len(rejected),'excluded')
if __name__=='__main__':main()
