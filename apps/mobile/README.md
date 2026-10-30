# SomityHub Android app

- Display name: SomityHub
- Android application ID: com.somityhub.app
- Flutter package: somityhub_app
- Initial version: 1.0.0+1

## Local setup

Install Flutter stable and Android SDK, then:

```bash
cd apps/mobile
flutter create --platforms=android --org com.somityhub --project-name app .
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://ifyqpnfagojwjodcqxyz.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

Use only the Supabase publishable key (or legacy anon key). Never use the service-role key in a mobile application.

## GitHub Actions variables

Add repository Actions Variables named SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY at Settings → Secrets and variables → Actions → Variables.

## Versioned APK release

Update version in pubspec.yaml and create a semantic version tag such as v1.0.0. The repository workflow builds ABI-specific APKs and attaches them to a GitHub Release.

Release signing must be configured with a private keystore before production distribution. Never commit a keystore or its passwords.
