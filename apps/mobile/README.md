# SomityHub apps

Flutter app packages:

- Android application ID: `com.somityhub.app`
- Desktop app name: SomityHub
- Flutter package: `somityhub_app`

## Desktop builds on every push

The GitHub Actions workflow `.github/workflows/desktop-release.yml` builds Windows x64, macOS Intel, and macOS Apple Silicon packages on pushes, pull requests, and manual runs.

- Pull request and branch builds are available in the run's **Artifacts** section for 30 days.
- Pushes to `main` and version tags also publish desktop downloads on GitHub Releases.
- The `desktop-latest` release contains stable filenames: `SomityHub-Windows-x64.zip`, `SomityHub-macOS-Intel.zip`, and `SomityHub-macOS-Apple-Silicon.zip`.
- Extract the Windows ZIP and run `app.exe`.
- Extract a Mac ZIP and open `SomityHub.app`. These Mac builds are unsigned; on first launch, Control-click the app and choose **Open**.

Every workflow run uses a higher build number. To create a named release, push a version tag such as `v1.2.3`.

## Android APK builds and in-place updates

The Android workflow builds a universal APK and architecture-specific APKs. The in-app **Check for updates** action downloads the universal APK from the `latest` release.

Android installs this as an update over the existing app and keeps its app data when all three values stay compatible:

1. Application ID remains `com.somityhub.app`.
2. The new APK uses the same permanent signing key as the installed APK.
3. The Android version code increases (GitHub Actions uses the run number).

The current workflow requires a permanent release keystore. Configure these GitHub Actions repository secrets before an Android release:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded release keystore
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Keep the same keystore for every later APK. Do not commit it to this repository. Older preview APKs built with temporary CI debug keys may not accept a differently signed update; install a permanent-key signed baseline before using in-place upgrades.

The Android and desktop workflows also require these GitHub Actions repository variables:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY` (a publishable/anon key only; never use a service-role key)

## Local setup

Install Flutter stable and the platform tooling, then:

```sh
cd apps/mobile
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```
