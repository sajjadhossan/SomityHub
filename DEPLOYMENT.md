# SomityHub deployment and Android release

## Web deployment (Vercel)

The repository is configured for the Next.js framework through `vercel.json`.

1. In Vercel, choose **Add New → Project** and import `sajjadhossan/SomityHub`.
2. Keep the project root directory as the repository root.
3. Confirm Framework Preset is **Next.js**. Build command is `npm run build`; install command is `npm install`.
4. In Project Settings → Environment Variables, add:
   - `NEXT_PUBLIC_SUPABASE_URL` = the existing Supabase project URL
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` = the project's publishable key (or legacy anon key)
5. Apply the variables to the intended environment and redeploy.
6. In Supabase Authentication → URL Configuration, set the Site URL to the deployed URL and add the deployed URL plus the local development URL to Redirect URLs.

Only the publishable/anon key belongs in browser configuration. Never add a Supabase service-role key, database password, or other secret to a `NEXT_PUBLIC_` variable or this public repository.

The GitHub Actions workflow `.github/workflows/web-ci.yml` verifies that dependencies install and the Next.js production build succeeds. It does not deploy to Vercel. Automatic deployment occurs only after the repository is imported and the Git integration is enabled in Vercel.

**Free-plan restriction:** Vercel Hobby is limited to personal, non-commercial use. SomityHub is intended for cooperative/committee operations, so confirm that the intended use qualifies before using Hobby. Do not upgrade or add billing without the owner's explicit approval.

## Android APK version releases

The workflow `.github/workflows/android-release.yml` is prepared to build three ABI-specific APKs and attach them to a GitHub Release when a semantic version tag is pushed, for example `v1.0.0`.

Expected Flutter project location: `apps/mobile/` (must contain `pubspec.yaml` and the Android Gradle project). The current repository contains the Next.js web application only; the Flutter mobile application has not yet been added. Therefore the APK workflow intentionally stops with a clear preflight error until that app exists.

After the Flutter app is added and tested:

1. Update the Flutter app version in `apps/mobile/pubspec.yaml` (for example `version: 1.0.0+1`).
2. Push the app code to `main`.
3. Create and push a version tag, for example:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
4. GitHub Actions builds APKs for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
5. The workflow creates a GitHub Release for the tag and attaches the versioned APK files. Older releases and APKs remain available under **Releases**.

The workflow currently uses the Flutter Android project's default release signing configuration. Before public production distribution, configure a private upload/release keystore and the matching Gradle signing setup. Keep keystore files and passwords in GitHub Actions Secrets only; never commit them or send them in chat.

## Current limitations

- No APK can be built until the Flutter mobile source project exists.
- No Vercel project has been imported and no environment variables have been entered by this repository change.
- GitHub Actions workflows must run successfully before either build process can be considered verified.
- The repository is public; do not store credentials or private signing materials in it.
