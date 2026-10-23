# PyLearn · Python 学习

面向 **iOS 16.3 及以上 iPhone / iPad** 的原生 Python 学习 App，采用 Runestone 编辑器和 CPython 解释器，在设备上离线学习、编辑并运行 Python 脚本。IPA 面向已安装巨魔商店（TrollStore）的设备。

**本项目使用 OpenAI Codex 辅助开发与编辑**，包括架构梳理、代码编写、修改、审查与测试。

## 首版功能

- 8 个中文入门章节、16 道练习，提供可运行示例、提示和参考答案。
- Runestone 原生代码编辑器，支持 Python 语法高亮、行号、缩进、撤销、重做和编程符号栏。
- 语法检查、错误行高亮和常见错误的中文解释。
- 关键字、内置名称和当前代码名称的基础补全；分析时不会执行用户代码。
- 本地单文件运行，支持控制台输出、交互式 `input()` 输入及协作停止。
- 从「文件」App 导入 UTF-8 编码的 `.py` 文件，最大 512 KiB；导入时保存副本，不修改原文件。
- 代码自动保存、`.py` 导出，以及带确认的删除操作。
- 脚本和学习进度保存在设备本地，无需登录，无广告、统计服务或运行服务器。

## 下载与安装

1. 打开仓库的 [Actions 工作流](https://github.com/wjc0104/PyLearn/actions/workflows/build-ipa.yml)。
2. 选择一次绿色成功的 **Build IPA** 运行记录。
3. 在 **Artifacts** 中下载 **PyLearn-iOS16.3-TrollStore**。
4. 解压下载的 ZIP，得到 `PyLearn-0.1.0.ipa`，再通过巨魔商店安装。

工作流产物保留 14 天。产物同时包含包检查记录、SHA256 校验文件和模拟器界面截图；不会自动发布 Release。

## 构建与验证

工作流会运行 Python 回归测试，构建 arm64 安装包，检查包结构及最低系统版本，再运行原生单元测试和模拟器界面测试。构建不需要 Apple 开发者签名证书；巨魔商店会在安装时处理签名。

本地构建需要 **macOS、完整 Xcode、XcodeGen 和 Python 3.12 及以上版本**：

```sh
python3 -m unittest discover -s tests -v
bash scripts/build_ipa.sh
```

生成文件：

- `dist/PyLearn-0.1.0.ipa`：安装包。
- `dist/verification.json`：包大小、版本、最低系统版本和二进制检查结果。
- `dist/SHA256SUMS.txt`：SHA256 校验值。

Windows 可以运行 Python 测试和 IPA 检查器，原生编译与模拟器测试需要 macOS。**编译或模拟器测试通过，不代表已经在物理 iOS 16.3 设备上验证安装与运行。**

## 首版范围与运行限制

首版提供 Python 标准库，受 CPython 在 iOS 上的平台限制影响。暂不包含任意第三方包安装、NumPy / pandas、AI 助手、断点调试器或多文件项目。

每次运行使用新的全局变量字典，默认运行时间限制为 10 秒，不计算等待用户输入的时间；控制台最多输出 20,000 个字符。普通 Python 循环、输入等待和封装后的 `time.sleep` 支持协作停止。任意阻塞的 C 扩展调用无法在 App 进程内安全地强制终止，某些情况可能需要重新打开 App。

Python 解释器不提供独立的安全沙箱，请只运行可信脚本。本项目不申请私有权限、JIT 或解除系统沙箱限制。

脚本以原子写入方式保存在 `Documents/PyLearn/library.json`。如果原有记录无法读取，App 会暂停写入，避免覆盖原文件。代码补全属于基础名称补全，不是完整语言服务器，也不会生成 AI 代码。

## 技术架构与许可

- **SwiftUI**：课程、练习、文件列表和控制台界面。
- **Runestone + Tree-sitter**：原生编辑与 Python 语法高亮。
- **CPython 3.13 + Python Apple Support**：设备本地 Python 运行环境。
- **Objective-C 桥接层**：串行执行、输入输出和取消控制。

详细内容见[架构设计](docs/superpowers/specs/2026-10-23-pylearn-design.md)与[实施计划](docs/superpowers/plans/2026-10-23-pylearn-mvp.md)。

第三方组件的来源和许可见[第三方声明](THIRD_PARTY_NOTICES.md)，完整许可文本随 App 一起打包。仓库已由作者授权公开，用于 GitHub 托管构建；原创应用代码的再使用许可尚未选定，第三方组件仍遵循各自的许可证。
