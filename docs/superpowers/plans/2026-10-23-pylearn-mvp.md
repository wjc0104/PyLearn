# PyLearn iOS 16.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a Runestone-based offline Python learning app and a verified TrollStore IPA.

**Architecture:** SwiftUI and Runestone share one local document store. A serial Objective-C bridge embeds CPython and calls a small Python helper for diagnostics and execution. A macOS workflow builds and validates the package.

**Tech Stack:** SwiftUI, Runestone, TreeSitterPythonRunestone, CPython 3.13, XcodeGen, unittest, XCTest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-23-pylearn-design.md`

## Global Constraints

- Minimum iOS 16.3; arm64 IPA; no private entitlements.
- Offline execution; no backend, login, analytics or AI in the first release.
- Import UTF-8 `.py` files, copy locally and never modify the original.
- Maximum source 512 KiB, console 20,000 characters, execution 10 seconds excluding input waits.
- GitHub owner `wjc0104`; wait for that authentication before repository creation or push.

## Review Focus

- Cancellation during infinite loops, sleep and pending input must restore a runnable interpreter.
- Chinese/emoji text and error positions must preserve Unicode and UTF-16 boundaries.
- Failed import/save must preserve existing scripts and surface the actual error.
- Syntax analysis and completion must not execute user source or produce stale editor results.
- Every embedded Mach-O must support iOS 16.3 and contain the correct device architecture.

### Task 1: Python execution and learning content

**Files:** `PyLearn/Resources/runtime.py`, `PyLearn/Resources/lessons.json`, `tests/test_runtime.py`, `tests/test_lessons.py`.

**Interfaces:** `analyze(source, prefix) -> dict`; `execute(source, write, read, cancelled, timeout=10) -> dict`; `request(payload_json) -> str`.

- [ ] Write unittest cases for syntax errors, non-executing completion, input, Unicode, fresh globals, stop, sleep, timeout, output caps and exception locations.
- [ ] Run `python -m unittest discover -s tests -v`; observe the missing implementation fail.
- [ ] Implement helpers and eight lessons / sixteen independently verifiable solutions.
- [ ] Run the full suite and commit the passing task.

### Task 2: Native bridge, persistence and screens

**Files:** `PyLearn/Runtime/*`, `PyLearn/Editor/*`, `PyLearn/Store.swift`, `PyLearn/ContentView.swift`, `PyLearn/LearningViews.swift`, `PyLearn/PyLearnApp.swift`, `PyLearnTests/*`.

**Interfaces:** `PythonSession.run(source:)`, `.stop()`, `.submitInput(_:)`, `.analyze(source:prefix:completion:)`; `LearningStore` publishes lessons, documents and completed exercise IDs. `CodeEditor` binds text and a UTF-16 selection.

- [ ] Write native tests for import boundaries, persistence restoration and embedded execution before implementing the corresponding units. Run with Xcode when the macOS runner is available; record unavailable checks honestly.
- [ ] Implement the serial bridge, console and cooperative input cancellation.
- [ ] Implement Files import/export, atomic storage, lessons, exercises and editor.
- [ ] Run portable tests, then native tests in the same macOS build used for packaging.

### Task 3: Reproducible IPA build and delivery

**Files:** `project.yml`, `scripts/prepare_dependencies.py`, `scripts/embed_python.sh`, `scripts/build_ipa.sh`, `scripts/inspect_ipa.py`, `.github/workflows/build-ipa.yml`, `tests/test_ipa.py`, `README.md`, `THIRD_PARTY_NOTICES.md`.

**Interfaces:** `inspect_ipa(path) -> dict` rejects corrupt ZIPs, missing CPython, simulator-only binaries and deployment targets newer than 16.3. `prepare_dependencies.py` verifies the pinned Python release SHA256.

- [ ] Write inspector fixtures for valid packages, broken ZIPs, wrong architecture and incompatible deployment targets; watch them fail.
- [ ] Implement dependency preparation, XcodeGen project, simulator tests, signing and packaging.
- [ ] Run the full portable suite and dependency integrity check.
- [ ] After `wjc0104` login is confirmed, create the private repository, push source and run the macOS workflow.
- [ ] Download the successful artifact, inspect ZIP/plist/Mach-O and record SHA256. Do not equate this with a physical-device installation test.

### Final review

- [ ] Request one independent whole-branch review, resolve material findings and rerun relevant tests.
- [ ] Report actual build/test status, artifact location and any remaining device-only checks.
