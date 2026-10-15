# HelpHive

A neighbourhood help board for Android. People post what they need or what they can offer, react, comment, add each other as friends and message.

```
app/      Flutter app (Android only)
server/   Node.js API for Render: comments, messages, notifications (Neon)
supabase/ schema.sql: profiles, posts, reactions, friendships, storage buckets, RLS
```

**Where data lives**

| Data | Where |
|---|---|
| Accounts (email + Google) | Supabase Auth |
| Profiles, posts, post reactions, friendships | Supabase Postgres |
| Avatars, covers, post photos | Supabase Storage (`avatars`, `covers`, `posts`) |
| Comments, replies, comment reactions, messages, message reactions, notifications | Neon Postgres, through the Render server |

The app talks to Supabase directly (protected by row level security) and to the Render server for everything in Neon. The server checks the user's Supabase session token on every request.

## 1. Supabase

1. Create a project. Open **SQL Editor**, paste `supabase/schema.sql`, run it. Safe to re-run.
2. **Authentication > Providers**: Email is on. Keep "Confirm email" on if you want verified emails.
3. **Authentication > Providers > Google**: create an OAuth *Web* client in Google Cloud Console, paste its client ID and secret into Supabase. In Google, add Supabase's callback URL (shown on that page) as an authorized redirect URI.
4. **Authentication > URL Configuration > Redirect URLs**: add `io.helphive.app://login-callback/`
5. **Project Settings > API**: copy the project URL, the anon key and the service role key.

The service role key goes only on Render. Never put it in the app.

## 2. Neon

Create a project, open the SQL editor, run `server/sql/neon.sql`. Copy the **pooled** connection string.

## 3. Render (the API)

1. Push this folder to GitHub.
2. Render > **New > Blueprint**, pick the repo. It reads `render.yaml`.
3. Fill in the environment variables:
   - `DATABASE_URL` Neon pooled connection string
   - `SUPABASE_URL` `https://<ref>.supabase.co`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `SUPABASE_JWT_SECRET` only if your project still uses the legacy HS256 secret
4. Deploy. `https://<service>.onrender.com/health` should answer `{"ok":true}`.

Free instances sleep after idle time. The app pings `/health` on launch, and the first request after a long sleep can take up to a minute.

Local run: copy `server/.env.example` to `.env`, then `cd server && npm ci && node --env-file=.env src/index.js`.

## 4. Build the APK on Codemagic

1. Add the repo in Codemagic and choose the `codemagic.yaml` workflow `helphive-android`.
2. Create an environment variable group named **helphive** with `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `API_URL` (the Render URL).
3. Start the build. It creates the Android project, patches the manifest (internet permission, Google sign-in deep link, no cleartext, no backups, minSdk 23), generates launcher icons from `app/assets/icons/launcher*.png`, runs `flutter analyze`, and builds a release APK as an artifact.

Local build, if you have Flutter:

```
cd app
flutter create --platforms=android --org io.helphive --project-name helphive .   # first time only; keep our lib/ and pubspec.yaml
python3 tool/patch_android.py
flutter pub get && dart run flutter_launcher_icons
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_URL=...
```

For the Play Store you will want your own signing key; add it in Codemagic code signing.

## Icons

Every icon is a PNG in `app/assets/icons/`, drawn by `app/tool/make_icons.py` (needs Pillow). Edit the script and re-run to change them.

## Security notes

- Row level security is on for every table. The app can only read what it needs and only write its own rows. Direct deletes on posts are blocked; deleting goes through the server so Neon rows and photos are cleaned up with it.
- Friend requests and reactions are written by SECURITY DEFINER functions; the server re-reads Supabase before creating a notification, so notifications cannot be forged.
- The server verifies the Supabase JWT (signature, issuer, audience, pinned algorithms), uses parameterised SQL only, validates every body with zod, sets Helmet headers, caps body size, and rate limits per IP and per user.
- The session is stored in Android's keystore-backed secure storage, not plain preferences.
- Storage: images only (jpeg, png, webp), size caps per bucket, writes only inside your own `<user id>/` folder.
- Account deletion removes Neon rows, storage files and the auth user.

## Features

Email and Google sign-in, profile with avatar, cover, bio, location, username; posts (create, edit, delete, photo, category, mark resolved); five reactions; comments with replies, edit, delete and reactions; friends (add, cancel, confirm, decline, remove); two-column people grid with filters; search for people and posts; notifications; direct messages with search, replies, reactions, unsend and seen marks; bottom navigation with badges.
