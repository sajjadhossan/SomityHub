# SomitiPro

Bangla-first cooperative management web application.

## Current implementation
- Email/password registration and login using Supabase Auth
- Registration metadata: display name and preferred language
- Profile creation through the existing Supabase Auth database trigger
- Password reset email and password update
- Browser session persistence
- Browser uses only the Supabase publishable key (or legacy anon key); no service-role key

## Requirements
- Node.js 20.9+
- Supabase project

## Local setup
1. Copy `.env.example` to `.env.local`.
2. Set `NEXT_PUBLIC_SUPABASE_URL`.
3. Set `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` to the project's publishable key (legacy anon key is also accepted).
4. Run `npm install`, then `npm run dev`.

## Supabase Auth URL configuration
Set Site URL to the deployed app URL. Add the deployed URL and local development URL (for example `http://localhost:3000`) to Redirect URLs.

If email confirmation is enabled, users must confirm their email before receiving a persistent authenticated session.

## Security
Never commit the service-role key, database password, or other secret keys. The GitHub repository is public. Only a publishable key / legacy anon key belongs in the browser, protected by RLS and server-side authorization.

## Scope
This is the initial authentication slice, not the complete product. Committee onboarding, member management, financial workflows, receipts, QR verification, backup automation, and platform administration remain to be implemented and tested.
