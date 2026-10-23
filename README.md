# HelpHive

A neighbourhood help board for Android, Windows, macOS and Linux. People post what they need or what they can offer, react, comment, add each other as friends and message.

```
app/      Flutter app (Android, Windows, macOS, Linux)
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
4. **Authentication > URL Configuration > Redirect URLs**: add both `io.helphive.app://login-callback/` (Android) and `http://127.0.0.1:47321/login-callback` (Windows, macOS, Linux)
5. **Project Settings > API**: copy the project URL, the anon key and the service role key.

The service role key goes only on Render. Never put it in the app.

## 2. Neon

Create a project, open the SQL editor, run `server/sql/neon.sql`. Copy the **pooled** connection string.

**Updating an existing database** (adding helpful stars to an app that is already running): run `server/sql/neon.sql` again, it is safe to re-run and only adds what is missing (two columns on `comments`, two indexes, and the new `comment_starred` notification type). Then redeploy the server on Render and rebuild the app. No change is needed in Supabase.

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

## 5. Windows, macOS and Linux (no signing key)

None of the desktop builds use a signing key, certificate or developer account.

**Build with GitHub Actions (nothing to install):** push the repo, add the secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_URL`, then run **Actions > HelpHive desktop**. It builds all three on their own runners and attaches `HelpHive-windows.zip`, `HelpHive-macos.zip` and `HelpHive-linux.zip` to the run.

**Build on your own machine** (build each system on that system):

```
cd app
flutter create --platforms=windows,macos,linux --org io.helphive --project-name helphive .   # first time only; keep our lib/ and pubspec.yaml
python3 tool/patch_desktop.py
flutter pub get
flutter run -d windows    # or macos / linux
flutter build windows --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_URL=...
```

Linux needs: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev libjsoncpp-dev`. Windows needs Visual Studio with "Desktop development with C++". macOS needs Xcode.

**Running the unsigned apps**
- Windows: unzip and run `helphive.exe`. SmartScreen may say "unknown publisher": More info > Run anyway.
- macOS: unzip, then right-click `HelpHive.app` > Open the first time (or `xattr -cr HelpHive.app`).
- Linux: unzip and run `./bundle/helphive`.

**How desktop differs from Android**
- Google sign-in opens your browser and returns to a short-lived local page on `127.0.0.1:47321`, because a custom URL scheme cannot be registered without an installer or signature. The redirect URL from step 1 must be in Supabase.
- The session is kept in the app's preferences file (the macOS keychain rejects unsigned apps). Android still uses the keystore-backed store.
- Links in confirmation and reset emails open the project's Site URL in a browser; sign in again in the app afterwards.
- Picking a picture opens a file chooser (no camera), and in a chat Enter sends and Shift+Enter starts a new line.

**Layout follows the window width** (`app/lib/layout.dart`)
- Under 820 px: the phone layout with the floating bottom bar.
- 820 px and up: a side bar replaces the bottom bar (icons only up to 1180 px, with labels and your profile above that). Feed and Alerts sit in a centred 720 px column, People grows from 2 to 4 columns, and Chats show the list and the open conversation side by side once there is room.
- Every pushed page (post, profile, compose, search) opens in a centred panel instead of stretching edge to edge. Resize the window and it adapts live, on Android tablets too.

## Icons

Every icon is a PNG in `app/assets/icons/`, drawn by `app/tool/make_icons.py` (needs Pillow). Edit the script and re-run to change them.

## Security notes

- Row level security is on for every table. The app can only read what it needs and only write its own rows. Direct deletes on posts are blocked; deleting goes through the server so Neon rows and photos are cleaned up with it.
- Friend requests and reactions are written by SECURITY DEFINER functions; the server re-reads Supabase before creating a notification, so notifications cannot be forged.
- The server verifies the Supabase JWT (signature, issuer, audience, pinned algorithms), uses parameterised SQL only, validates every body with zod, sets Helmet headers, caps body size, and rate limits per IP and per user.
- On Android the session is stored in keystore-backed secure storage; on desktop it sits in the app's preferences file.
- Storage: images only (jpeg, png, webp), size caps per bucket, writes only inside your own `<user id>/` folder.
- Account deletion removes Neon rows, storage files and the auth user.

## Features

Email and Google sign-in, helpful stars and badges (see below), profile with avatar, cover, bio, location, username; posts (create, edit, delete, photo, category, mark resolved); five reactions; comments with replies, edit, delete and reactions; friends (add, cancel, confirm, decline, remove); two-column people grid with filters; search for people and posts; notifications; direct messages with search, replies, reactions, unsend and seen marks; bottom navigation with badges.

## Helpful stars, badges and resolved comments

**How it works**
- On their own post, the person who asked (or offered) sees **Mark helpful** under every comment written by someone else. Tapping it gives that comment's author **1 star**. Tap **Unmark** to take it back.
- A starred comment is **highlighted in gold** with a *Helpful answer* tag and is pinned above the other comments. Starring also marks the post **Resolved**.
- Feed cards show the helpful answer under the post, so someone with the same problem can read the fix without opening the thread.
- The helper gets a notification ("marked your comment as helpful and gave you a star").
- A star total is never stored. It is counted from the helper's starred comments, so deleting a comment (or its post, or the account) removes the star with it, and nobody can inflate it. You cannot star your own comment, and only the post's author can star at all (the server checks this against Supabase).

**Badges** (everyone sees them: beside names on posts and comments, on the profile picture, and in the Badges tab)

| Stars | Badge | Quote |
|---|---|---|
| 1 | Fresh Buzz | Every hive starts with a single buzz. |
| 3 | Helping Wing | Small help, big difference. |
| 5 | Worker Bee | Busy wings keep the hive humming. |
| 10 | Honey Maker | Kindness tastes sweetest when shared. |
| 25 | Hive Guardian | Strong hives are built by steady hands. |
| 50 | Nectar Hero | Your help is worth its weight in honey. |
| 100 | Queen Bee | The whole hive thrives because of you. |

Names, quotes and colours live in `app/lib/badges.dart`; the thresholds are mirrored in `server/src/stars.js` (change both together). The medal artwork and its shine (a breathing glow, a glint sweeping across, twinkles) are drawn in code in `app/lib/widgets/badge.dart`, and the animation stops when the phone's "reduce motion" setting is on.

**Profile** has a small nav under the picture: **Profile** (bio, stats, posts), **Badges** (the badge being worn, progress to the next one, and every badge with its quote, locked ones greyed out) and **Resolved** (each comment that was starred, with the post it answered).

**New API routes** (all behind the same sign-in check)

| Route | What it does |
|---|---|
| `PUT /comments/:id/helpful` `{helpful: bool}` | Poster stars / unstars a comment; marks the post resolved |
| `GET /users/:id/stars` | One person's star total and badge |
| `POST /users/stars` `{userIds}` | Star totals for a page of authors |
| `GET /users/:id/resolved?before=` | Starred comments with their posts, newest first |
| `POST /comments/counts` | Now also returns each post's helpful answer |

Comments from the API now carry `helpful` and `user.stars` / `user.badge`.

## Floating bubble, phone notifications and sounds (Android)

- **Floating chat bubble over every app.** Switch it on in Profile > Settings > *Floating chat bubble*. Android asks once for "Display over other apps". The bubble shows the unread count and the latest sender's picture, pops a preview when something arrives, and opens the right chat when tapped. Drag it anywhere; while dragging, an **X** appears at the bottom centre. Drop the bubble on it and it disappears (the setting switches off too).
- **Chat window (like Messenger).** Tap the bubble and a small chat window opens over whatever app you are in: your chat list first, then a conversation with a **back arrow** before the name that takes you back to the list. Type and send from it; messages you read there are marked as read. Tap the bubble again and the window hides. The bubble stays draggable the whole time, and dropping it on the **X** removes it (and closes the window). *Open app* in the header jumps to the same chat in the full app. Tapping a new-message preview opens that chat in the window. The window is drawn natively (`tool/android/BubbleService.kt.tmpl`) and only draws: the background listener fetches the chats and sends what you type (it holds the signed-in session), so the sign-in token is never written anywhere readable. This needs *Alerts when the app is closed* on, like the rest of the bubble; while the window is open the listener checks every second or two.
- **Background listener.** Settings > *Alerts when the app is closed* runs a quiet foreground service (one low-priority "Listening" notification) that keeps checking while the app is in the background or swiped away, then posts to the notification drawer. *Keep alerts running (battery)* asks Android not to put it to sleep; on some phones (Xiaomi, Oppo, Vivo, Huawei) also allow HelpHive to auto-start / run in the background in the phone's own settings.
- **Drawer notifications** carry the sender's picture, the full preview, and for messages **Like** and **Reply** buttons. Icons are the app's own (copied from `assets/icons` into Android resources by `tool/patch_android.py`).
- **Tones**: `assets/sounds/message.wav` for a new message, `alert.wav` for a new notification. Closed or in the background, the notification channel plays them; with the app open, the app plays them.
- The native bubble code is in `tool/android/*.tmpl`; the patch script writes it into the generated Android project. Rebuild on Codemagic as before.
