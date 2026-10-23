# PyLearn · Python 学习
面向 **iOS 16.3 及以上 iPhone / iPad** 的原生 Python 学习 App，使用 Runestone 与设备本地 CPython。IPA 通过巨魔商店（TrollStore）安装。

**本项目由 OpenAI Codex 辅助开发与编辑**，包括架构、代码、审查和测试。

## 0.2 功能
- 8 个中文入门章节、16 道入门题，另有 **126 道可更新题库练习**；按中文知识点、关键词和难度检索，包含中文任务说明、原题、参考答案和函数测试。下载后离线可用。
- AI 出题、完整题目翻译：预置 OpenAI、DeepSeek、通义、智谱、硅基流动、Moonshot、Gemini、Claude、Ollama、自定义服务；支持兼容接口、Responses、Claude 和 Gemini 原生格式。可保存多个配置、读取模型列表；密钥保存在 Keychain。
- Runestone 编辑器，语法检查、错误定位、中文提示、复制代码和完整错误信息；更多符号、配对和代码模板。
- Jedi 离线静态补全，包含变量、模块成员和函数参数提示；点选候选或外接键盘 Tab 接受。最新语法以 CPython 检查结果为准，补全不等于完整 PyCharm。
- **CPython 3.15.1** 本地执行，支持 input、停止、控制台就近收起/展开、复制和清空。
- 导入文件夹、多个脚本及文本文件；保留目录和资源，文件树与入口选择，支持项目模块导入和相对路径读取数据。
- Git 初始化、HTTPS 克隆、状态/差异/历史、提交、分支及快进拉取/推送。由 Dulwich 运行，不需要桌面 git 命令。凭据不进入项目或远程 URL。
- 字号、字体、导入 TTF/OTF、浅色/深色/自定义颜色。脚本和项目统一 **长按菜单**，删除需确认。
- 旧版脚本和进度保留，首次迁移备份旧库。无需 App 账号，无广告。

## 安装与测试
**正式版本从 [GitHub Releases](https://github.com/wjc0104/PyLearn/releases) 下载。**
正式发布与测试构建分开；未发布的版本不能视为正式发行版。

[Actions 工作流](https://github.com/wjc0104/PyLearn/actions/workflows/build-ipa.yml)用于开发测试。成功记录的 Artifacts 中下载 PyLearn-iOS16.3-TrollStore，解压取得 IPA，再用巨魔商店安装。测试产物保留 14 天，包含 IPA、SHA256、包检查结果及启用模拟器测试后的截图。

维护者准备好后可手动运行“发布发行版”，默认预发布；常规推送不会自动发行。

## 使用说明
题库首屏自带离线内容；点击右上角刷新或下拉可同步线上目录。搜索针对已收录题库，**不是全网网站爬虫**；没有现成题时，可明确点击 AI 出题补充。AI 需要自配服务、密钥和模型，费用由相应服务商收取，不会因搜索自动计费。完整英文题面可展开，也可以使用自己的服务翻译。

AI 生成题标记为尚未验证，进入题目可运行参考答案校验；通过当前用例不代表覆盖所有情况。只将本次关键词或所选题面发给配置的服务，不自动上传项目。云服务必须 HTTPS；局域网 HTTP 需显式开启，手机与服务器需网络互通，示例 IP 必须改成自己的设备地址。

文件夹导入保存本机副本，最多 1000 个文件 / 50 MiB，忽略缓存和虚拟环境，拒绝符号链接。文本编辑支持 UTF-8、最大 512 KiB；二进制资源保留供脚本读取。长按 .py 文件可设置运行入口。项目删除保留在 App 数据目录 deleted-projects 中。

Git 仅提供基础流程：提交前检查差异，拉取只允许快进，分歧时保留本地代码。未接入 SSH、子模块、LFS、交互式冲突合并或强制推送。

## 构建与验证
本地原生构建需 macOS、Xcode、XcodeGen、Python 3.15；Windows 可运行便携回归和 IPA 检查。
```sh
python3 scripts/prepare_python_packages.py
python3 -m unittest discover -s tests -v
bash scripts/build_ipa.sh
```
构建输出 dist/PyLearn-0.2.0.ipa、verification.json、SHA256SUMS.txt。依赖固定版本并校验 SHA256；IPA 检查 arm64、最低系统与所需资源。

题库更新工具 scripts/sync_exercises.py 从固定上游版本生成目录，启用练习测试并逐题校验参考答案；不通过或不适合设备限制的题目不收录。中文任务说明是辅助摘要，详细约定以完整原题和测试为准。保留来源、作者及 MIT 许可；不把整个上游直接当作已适配。

## 运行范围
提供标准库及 App 自用的补全/Git 组件，不提供任意 pip 安装。常规脚本默认 10 秒执行限制（不计等待输入），输出最多 20,000 字符。协作停止无法安全强制终止任意阻塞的 C 调用。

脚本、测试和 Git 组件处于 App 进程中，不是独立安全沙箱。只运行你信任的代码。不需要 JIT、私有权限或解除系统沙箱。
模拟器和编译验证不能代替物理 iOS 16.3 设备的安装、第三方 API 或真实远程 Git 验证。

## 架构与许可
SwiftUI / Runestone / Tree-sitter / CPython 3.15.1 / Objective-C 桥接；Jedi + Parso 静态补全；Dulwich Git；URLSession 多协议 AI。

[新版设计](docs/superpowers/specs/2026-10-23-pylearn-v2-design.md) · [计划](docs/superpowers/plans/2026-10-23-pylearn-v2.md) · [第三方声明](THIRD_PARTY_NOTICES.md)

原创应用代码的再使用许可尚未选定。第三方组件保持各自许可，许可文本随包分发。
