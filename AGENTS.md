# SomityHub Android-Only Execution Rules

These rules govern automated and agent-assisted work in this repository unless the repository owner explicitly changes the scope.

## Authorized scope
- Work only on the Android application in `apps/mobile/` and files strictly required to build, test, sign, or deliver its Android APK.
- Supabase schema, migrations, RPCs, and policies may be changed only when indispensable to the Android application's functionality. Keep those changes limited to the Android feature being implemented.
- Android validation may include Flutter analysis, Flutter tests, Android APK builds, and Android-only GitHub Actions artifacts.

## Prohibited scope
- Do not implement, modify, build, test, package, publish, or upload Web, Next.js, Vercel, Windows, macOS, Linux desktop, or any other non-Android application.
- Do not create or publish desktop installers, web deployments, desktop previews, or non-Android release assets.
- Do not modify non-Android application source, dependencies, configuration, deployment settings, or release processes as part of Android tasks.
- Do not merge pull requests, publish production releases, or change app versioning/signing unless explicitly requested.

## GitHub and CI delivery rules
- Push only changes required for the authorized Android task and indispensable Android backend changes.
- Android CI may run automatically for Android changes and may upload only Android APK artifacts.
- Web and desktop workflows must remain manual-only unless the repository owner explicitly authorizes those platforms.
- Never manually dispatch Web or Desktop workflows during Android-only work.
- Before reporting delivery, verify the exact commit SHA, Android test/build result, APK artifact name, and artifact association with that commit.
- Never provide a stale APK as the latest build. State clearly whether the artifact is a debug/preview APK or a signed release APK.

## Change control and verification
- Make the smallest change that satisfies the requested Android task. Preserve unrelated behavior and files.
- Do not refactor unrelated code or modify unrelated workflows.
- Review the changed-file list before every push. If any changed file is outside the authorized scope, stop and obtain explicit authorization.
- Run the relevant Android checks. Report any checks that could not be run and do not claim they passed.


## Single-APK delivery policy
- For each Android CI run, produce and publish exactly one installable APK for the Android app.
- Use the canonical filename `SomityHub-Android.apk` and the single artifact name `SomityHub-Android-APK`.
- Upload only that one APK file. Do not upload duplicate copies, alternate filenames, APK variants, split APKs, AABs, or unrelated build outputs unless the repository owner explicitly requests a different Android distribution format.
- Do not mirror the same APK to multiple servers, storage providers, or release destinations. Use the single configured GitHub Actions artifact destination.
- When sharing a build, share only the APK artifact from the latest successful Android CI run for the current branch/commit. Do not send multiple run artifacts or stale builds as separate alternatives.
- Keep Android build concurrency configured to cancel superseded runs so an older in-progress build does not compete with the newest build.


## GitHub Release delivery (single universal APK)
- Publish Android install builds only through one GitHub Release asset named `SomityHub-Android.apk`.
- Build exactly one universal APK containing both `android-arm` (ARMv7/32-bit) and `android-arm64` (ARM64/64-bit) native libraries. Do not build or publish per-ABI APK variants, split APKs, AABs, or duplicate APK copies.
- Do not upload APKs as separate Actions artifacts or mirror them to another server. Android CI is for analysis/tests; the Android release workflow is the only APK delivery path.
- A non-tag build may create one prerelease with one APK. A version tag build may create one normal release with one APK. Do not move or overwrite the existing `latest` tag/release automatically.
- Preserve permanent release signing. Never use a debug-signed APK as a production release.
