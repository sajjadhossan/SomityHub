# SomityHub — Central Agent Instructions & Handover

This is the authoritative operating guide for ChatGPT and other coding agents working in this repository. Read it before inspecting or changing code. The repository owner may explicitly revise these rules.

## 1. Strict authorized scope
- Work ONLY on the Android application in `apps/mobile/` and files strictly required to build, test, sign, or deliver its Android APK.
- Do not work on Web, Next.js, Vercel, Windows, macOS, Linux desktop, or any other platform.
- Supabase schema, migrations, RPCs, and policies may be changed only when indispensable to the Android feature being implemented, and only narrowly.
- Do not merge pull requests, publish a stable/production release, change app versioning, or alter signing credentials/configuration unless explicitly authorized.
- No unrelated refactors, dependency upgrades, optimizations, UI changes, or architecture changes.

## 2. GitHub Actions workflow policy
Only these two workflows are authorized for automatic Android work:
1. **Android App CI** — `.github/workflows/android-ci.yml`: Flutter analysis and tests only.
2. **Android App Preview and Release** — `.github/workflows/android-release.yml`: builds, signs, verifies, and publishes the one Android APK.
- These are the only workflows that should run automatically for Android branch/PR changes.
- Web and desktop workflows must remain manual-only. Never dispatch them during Android-only work.
- Do not create additional Android build workflows or duplicate pipelines without explicit approval.
- Android build concurrency must cancel superseded runs.
- Review changed files before every push. If a change is outside scope, stop and obtain approval.

## 3. Single Android APK delivery policy
- Produce exactly ONE installable, signed, universal APK containing ARMv7 (`android-arm`) and ARM64 (`android-arm64`) native libraries.
- Canonical filename: `SomityHub-Android.apk`.
- Publish it only as one asset on one GitHub Release. No duplicate copies, multiple ABI APKs, split APKs, AABs, Actions artifact copies, or alternate storage destinations.
- Use the existing permanent release signing configuration in GitHub Actions Secrets. Never publish a debug-signed APK.
- Branch builds are preview-only and may publish one GitHub prerelease. They must never be described as stable.
- EVERY official Android version release must publish exactly one signed universal APK (`SomityHub-Android.apk`) as a normal, non-prerelease GitHub Release. The version-tag path (`v*.*.*`) is the official stable-release path and must remain enabled and functional.
- Do not treat a preview build as an official release. To publish the current code as stable, create/push an authorized version tag and verify the resulting normal GitHub Release; do not merge a PR merely to publish an APK.
- Do not silently overwrite an existing version tag or release. A new official release must use a new version tag. A preview is not a stable production release.
- Before sharing, verify release tag, commit SHA, status, exact asset name, asset count, and file size from GitHub.

## 4. Required Android validation
- Run applicable checks: `flutter pub get`, `flutter analyze`, `flutter test`, and release build when requested.
- Verify APK signature and APK presence before publishing.
- Report exact results. State checks that could not be performed. Never claim a test/build/device check passed without evidence.

## 5. Change-control procedure
1. Read this file; inspect current branch, latest commit, open PR, Android workflow runs, and Releases.
2. Identify the smallest set of files required for the requested Android task.
3. Make only requested changes; preserve unrelated behavior and files.
4. Review diff and changed-file list before committing/pushing.
5. Run Android checks and inspect CI/release logs.
6. Verify resulting GitHub commit and, when requested, the single release asset.
7. Update this handover with verified state and remaining work.

## 6. Current project handover (2026-11-03)

### Repository and active work
- Repository: `sajjadhossan/SomityHub`
- Active branch: `feature/android-cooperative-operations-1-8`
- Verified branch HEAD at handover: `e1c30ddaba793e4a0082b54338785b9004c349d7`
- Open work: draft PR #15, Android loan installment schedules and overdue tracking.
- Base branch: `main`
- PR #15 is not merged. Do not merge without explicit approval.

### Latest Android APK successfully published
- Workflow: **Android App Preview and Release**
- Run: #51 (run ID `41580879891`)
- Commit: `72ccdcfbfcf07deefaeae56709dece1d882491a8`
- Result: success
- Release tag: `android-preview-51`
- Type: prerelease, NOT stable production
- Exactly one release asset: `SomityHub-Android.apk`
- Size: 53,404,865 bytes (about 53.4 MB / 50.9 MiB)
- SHA-256: `7db19acb49a1f750f42934290a420de577f1527e82afdcd61d36929ee2b03306`
- Build targets: ARMv7 + ARM64 (one universal APK)
- GitHub Release: https://github.com/sajjadhossan/SomityHub/releases/tag/android-preview-51
- APK download: https://github.com/sajjadhossan/SomityHub/releases/download/android-preview-51/SomityHub-Android.apk
- Android CI run #128 (run ID `41581846217`) on the current handover commit `869e80f3045d594668a73fdd16b7168ff2cad285`: success (Flutter analyze and tests).
- No stable release was created from this preview. Existing stable release `v0.1.46` was not modified.
- Owner has now explicitly authorized stable APK publishing and set the rule that every official Android version release must publish the single APK as a normal GitHub Release. The current preview remains a prerelease until a new version tag triggers the stable-release workflow.

### Current workflow roles
- `.github/workflows/android-ci.yml`: analysis/tests only; no APK publishing.
- `.github/workflows/android-release.yml`: sole APK build/sign/release pipeline.
- `.github/workflows/web-ci.yml` and `.github/workflows/desktop-release.yml`: manual-only; do not run for Android tasks.

### Next-chat continuation instructions
When the owner says:
“SomityHub repository-এর নির্দেশনা ও handover file পড়ো, তারপর পরবর্তী pending কাজ শুরু করো.”

The next agent must:
1. Read this entire `AGENTS.md` first.
2. Fetch latest branch HEAD, PR #15, workflow runs, and Releases; do not assume this snapshot is current.
3. Confirm the pending Android task with the owner if it is not explicit in the latest request.
4. Continue only Android work under the strict scope above.
5. Do not repeat completed work or re-upload an old APK. Build a new APK only when requested or required by the next authorized task.
6. Update this handover after verified progress, including commit SHA, tests, release/run IDs, and remaining tasks.

## 7. Delivery reporting
Always distinguish:
- code pushed vs. code merged;
- preview prerelease vs. stable production release;
- successful CI checks vs. APK build/sign/release;
- APK built vs. APK independently installed/tested on a physical device.
Never imply physical-device installation testing unless it occurred.
