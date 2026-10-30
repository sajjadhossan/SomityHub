# SomityHub deployment and Android preview

## Web deployment

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

## Android APK preview after every push

The workflow `.github/workflows/android-release.yml` runs on every push to `main` and on version tags. It:

1. Generates the Android platform project in the temporary GitHub Actions runner.
2. Installs Flutter dependencies.
3. Runs `flutter analyze` and `flutter test`.
4. Checks the repository Actions Variables `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
5. Builds installable APKs for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
6. Uploads the APKs as a downloadable workflow artifact, retained for 30 days.

To get the latest preview: open **GitHub → Actions → Android APK Preview and Release → latest successful run → Artifacts**. Download and extract the artifact ZIP. Most modern Android phones use the `arm64-v8a` APK.

A version tag such as `v1.0.0` also creates a GitHub Release with the APK files attached. Main-branch previews are not GitHub Releases; they are downloadable from the workflow run's Artifacts section.

The current preview build uses the generated Android project's default debug signing configuration. It is suitable for testing, not production distribution. Production release signing needs a private keystore stored only in GitHub Actions Secrets.

## Free-plan and security notes

- The repository is public, so standard GitHub-hosted runner usage for public repositories is free under GitHub's current Actions policy; artifact availability and retention remain subject to GitHub limits and policies.
- The Android workflow does not require paid Supabase features.
- The Android app uses only the Supabase publishable/anon key. Never store a service-role key, database password, or private signing key in source code or repository variables.
- No deployment or APK build is considered successful until the corresponding GitHub Actions run completes successfully.
