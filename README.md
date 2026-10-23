# PyLearn · Python 学习

An offline, native Python learning app for **iPhone/iPad on iOS 16.3 or later**, using Runestone and CPython. The IPA is intended for installation with TrollStore.

## First release

- 8 Chinese lessons and 16 exercises with runnable examples, hints and reference answers.
- Native Runestone editor with Python highlighting, line numbers, indentation, undo/redo and a coding symbol bar.
- Syntax checks and error-line highlighting with Chinese explanations.
- Basic keyword, built-in and local-name completion without executing source.
- Local single-file Python execution, console output, interactive `input()` and cooperative stopping.
- Import UTF-8 `.py` files up to 512 KiB from Files; keep a local copy, auto-save, export or delete with confirmation.
- All scripts and progress stay on the device; no accounts, ads, analytics or server required.

## Build

The **Build IPA** workflow runs portable tests, builds an arm64 app, validates the IPA, runs native/simulator UI tests and uploads the IPA, verification JSON and UI captures. It requires no Apple signing certificate. TrollStore performs its own installation signing.

Locally on macOS, install Xcode, XcodeGen and Python 3.12+, then run:

```sh
python3 -m unittest discover -s tests -v
bash scripts/build_ipa.sh
```

Output: `dist/PyLearn-0.1.0.ipa`, `dist/verification.json`, `dist/SHA256SUMS.txt`.

On Windows, only the portable tests and IPA inspector run; native compilation and simulator tests require macOS/Xcode. A successful build does not prove installation on the user's physical iOS 16.3 device.

## Scope and execution limits

The first release includes the Python standard library, with the normal limitations of CPython on iOS. It does not include arbitrary package installation, NumPy/pandas, an AI assistant, a breakpoint debugger or multi-file projects.

Each execution gets fresh globals, a default 10-second cooperative time limit (excluding input waits), and a 20,000-character console output limit. Python loops, input waits and the wrapped `time.sleep` can be stopped. Arbitrary blocking C extensions cannot safely be forcibly terminated inside the app process. Python's interpreter is **not a security sandbox**: run only scripts you trust. No private entitlements or unsandboxing are requested.

Scripts are saved atomically in `Documents/PyLearn/library.json`. If existing storage cannot be decoded, writing is paused to avoid overwriting it. Imported files are never modified. Completion is basic name completion, rather than a full language server or AI-generated code.

## Architecture

See [design](docs/superpowers/specs/2026-10-23-pylearn-design.md) and [implementation plan](docs/superpowers/plans/2026-10-23-pylearn-mvp.md). Development's primary local directory is `C:\Users\wm14\Desktop\PyLearn`; the earlier workspace remains a backup.

Third-party licenses and attribution are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and bundled with the app. The user authorized making this repository public for GitHub-hosted builds. A license for reuse of the original application code has not been selected; third-party components retain their own licenses.
