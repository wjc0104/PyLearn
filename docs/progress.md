# Execution ledger: PyLearn iOS 16.3 MVP

Plan: `docs/superpowers/plans/2026-10-23-pylearn-mvp.md`

- User approved Runestone, requested a TrollStore IPA, `.py` import, and implementation using suitable architecture/code skills.
- GitHub login confirmed via `gh api user`: wjc0104, ID 171414851. Created private `wjc0104/PyLearn`.
- Primary local project copied to `C:\Users\wm14\Desktop\PyLearn` at user request; the original workspace is a backup.
- Task 1 complete: runtime tests were observed failing before implementation; 17 portable tests passed including 8 lessons / 16 exercise solutions.
- Task 2 in progress: native bridge, files, SwiftUI screens and Runestone integration written. Native tests await the macOS workflow.
- Task 3 in progress: IPA inspector tests were observed failing before implementation; six additional inspector tests now pass.
- GitHub blocked the first private build before allocating a runner, citing payments/spending limits. User explicitly authorized making PyLearn public; visibility changed and the macOS runner started successfully.
- Independent review found three substantive issues: caught trace exceptions could disable cancellation, output was not flushed before an input prompt, and malformed required executables could pass IPA validation. Portable regressions for the cancellation and executable checks were observed failing before fixes; native input-flush coverage was added to simulator tests.
- Final: fixed cancellation swallowing and fake executable validation — targeted regressions RED to GREEN, full portable suite 25/25. Native output-flush fix awaits simulator execution.
- Run 39925878068 completed every build, native-test, attachment-export and artifact-upload step successfully. The cancel request arrived at the end of the job and marked the overall run cancelled; do not present it as a green workflow run. Downloaded IPA: 21,147,814 bytes (20.17 MiB), SHA256 b54c7de2b9491f6eaf79fff128e408aeefab43d330b291c82935feb9ca30dc82; local inspection accepted all 70 Mach-O binaries for arm64/iOS <=16.3. Four simulator captures were exported and reviewed.
- User clarified Actions artifacts are for testing; final distribution must use GitHub Releases. Added a manually triggered release workflow (pre-release by default), kept normal pushes from publishing, and corrected the Chinese README. No release has been published.
- Native workflow now streams test progress, avoids parallel simulator clones and exports a test-result summary. Diagnostics explicitly include the scoped hidden .build test outputs. A clean workflow run is required after these CI changes.
- Ruling: use private repository and working name PyLearn — protect source until naming/publication preferences are specified; renaming is reversible.
- Ruling: use native CPython 3.13 with cooperative cancellation — preserves offline execution on iOS 16.3; arbitrary blocking C extensions remain a documented limit.
- Ruling: use inline execution with one independent whole-branch review — user requested continued development without further planning gates.
