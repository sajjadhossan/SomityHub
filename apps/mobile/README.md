# SomityHub Android app

- Display name: SomityHub
- Android application ID: com.somityhub.app
- Flutter package: somityhub_app
- Initial version: 1.0.0+1

## Preview APKs after every GitHub push

The GitHub Actions workflow `.github/workflows/android-release.yml` runs on every push to `main`. It installs Flutter, runs static analysis and widget tests, then builds installable release APKs for supported Android CPU architectures.

After a successful run:

1. Open the repository on GitHub.
2. Select **Actions**.
3. Open the latest **Android APK Preview and Release** run.
4. Under **Artifacts**, download the `SomityHub-APK-preview-...` ZIP.
5. Extract the ZIP and install the APK matching your phone:
   - Most modern Android phones: `arm64-v8a.apk`
   - Older 32-bit ARM phones: `armeabi-v7a.apk`
   - Android emulator / x86_64 devices: `x86_64.apk`

The artifact is retained for 30 days. A failed build will not publish an APK; inspect the failed workflow logs instead.

## Supabase GitHub Actions variables

At repository **Settings → Secrets and variables → Actions → Variables**, configure:

- `SUPABASE_URL` = the existing Supabase project URL
- `SUPABASE_PUBLISHABLE_KEY` = the Supabase publishable key (legacy anon key is also accepted)

Only a publishable/anon key is allowed in the app. Never use a service-role key or database password in a mobile app, repository variable, or source file.

## Local setup

Install Flutter stable and Android SDK, then:

```bash
cd apps/mobile
flutter create --platforms=android --org com.somityhub --project-name app .
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

## Versioned GitHub Releases

Push a semantic version tag such as `v1.0.0`. The same workflow builds the APKs, uploads them as an Actions artifact, and attaches them to a GitHub Release.

The preview APKs use the generated Android project's default debug signing configuration for convenient testing. They are for preview/testing, not production Play Store distribution. Configure a private release keystore and keep it in GitHub Actions Secrets before production distribution. Never commit a keystore or its passwords.
