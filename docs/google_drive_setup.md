# Google Drive backup — one-time OAuth setup

Braim's automated backup uploads a zip (data + images) into Google Drive's
hidden **app data folder** (`drive.appdata` scope). That folder is private to
Braim, never shows up in the user's Drive UI, and only ever holds Braim's own
files.

**No Firebase is involved.** Everything is configured in the **Google Cloud
Console**. You do this once, paste one client ID into the app, and it's done.

You will create:

1. A Google Cloud project
2. The **Google Drive API**, enabled
3. An **OAuth consent screen** (kept in *Testing*, with yourself as a test user)
4. Two OAuth client IDs:
   - **Android** — identifies the app by package name + signing certificate
   - **Web application** — its ID is pasted into the app (used to sign in)

Total time: ~15 minutes.

---

## 1. Create / pick a Cloud project

1. Go to <https://console.cloud.google.com/>.
2. Top bar → project picker → **New Project**. Name it e.g. `Braim`. Create,
   then make sure it's selected.

## 2. Enable the Drive API

1. **APIs & Services → Library**.
2. Search **Google Drive API** → open it → **Enable**.

## 3. Configure the OAuth consent screen

1. **APIs & Services → OAuth consent screen**.
2. User type: **External** → Create.
3. App name: `Braim`. User support email: your email. Developer contact: your
   email. Save and continue.
4. **Scopes** → *Add or remove scopes* → filter for `drive.appdata` and tick:
   `.../auth/drive.appdata` — *"See, create, and delete its own configuration
   data in your Google Drive"*. Update → Save and continue.
5. **Test users** → *Add users* → add your own Google account (the one on your
   Pixel). Save and continue.
6. Leave the publishing status as **Testing**. That's all you need for personal
   use — you (as a test user) can sign in indefinitely.

> When you first connect, Google shows a *"Google hasn't verified this app"*
> screen. Click **Advanced → Go to Braim (unsafe)** — that warning is expected
> for an unverified personal app and is safe for your own account.

## 4. Get your app's SHA-1 signing fingerprint(s)

The Android OAuth client is matched by **package name + SHA-1 certificate**, so
Google needs the SHA-1 of whatever keystore signs the app you install.

From the project root, the easiest way to print them all:

```bash
cd android && ./gradlew signingReport
```

(on Windows PowerShell: `cd android; .\gradlew signingReport`)

- The **debug** variant's `SHA1:` is what `flutter run` uses — add this so your
  day-to-day debug builds work.
- If you've set up release signing (`android/key.properties` +
  `upload-keystore.jks`), the **release** variant's `SHA1:` is there too — add
  it as well.

You can also get the debug one directly:

```bash
keytool -list -v -alias androiddebugkey -storepass android -keypass android \
  -keystore "$HOME/.android/debug.keystore"
```

> If you later publish on Google Play, Play App Signing re-signs the app with a
> *different* certificate. Add that SHA-1 too (Play Console → your app →
> *Setup → App signing*), or Drive sign-in will fail on the Play build only.

## 5. Create the Android OAuth client

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. Application type: **Android**.
3. Name: `Braim Android`.
4. Package name: `com.solo.braim`.
5. SHA-1: paste the **debug** SHA-1 from step 4. (Add another Android client, or
   edit later, for the release/Play SHA-1s.)
6. Create.

## 6. Create the Web application OAuth client

1. **Create credentials → OAuth client ID** again.
2. Application type: **Web application**.
3. Name: `Braim Web`. No redirect URIs needed.
4. Create. **Copy the Client ID** — it looks like
   `1234567890-abcdef.apps.googleusercontent.com`.

This Web client ID is what the app uses to authenticate the account (the Android
plugin requires it). You don't paste any secret into the app — only this ID.

## 7. Put the Web client ID into Braim

Two options — pick one:

**A. Build-time flag (nothing committed):**

```bash
flutter run --dart-define=BRAIM_GDRIVE_CLIENT_ID=1234567890-abcdef.apps.googleusercontent.com
```

Add the same `--dart-define` to your `flutter build apk` command for release
builds.

**B. Hardcode it** in `lib/services/drive_backup_service.dart`:

```dart
const String kGoogleServerClientId = String.fromEnvironment(
  'BRAIM_GDRIVE_CLIENT_ID',
  defaultValue: '1234567890-abcdef.apps.googleusercontent.com', // ← paste here
);
```

Until a value is present, Settings → Google Drive shows *"Drive backup not set
up"* and the rest of the app is unaffected.

## 8. minSdk (only if the build complains)

`google_sign_in` 7.x uses Android's Credential Manager, which needs
`minSdkVersion 23`. Braim inherits Flutter's default; if a build fails asking
for a higher minSdk, set it explicitly in `android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    minSdk = 23
}
```

## 9. Try it

1. Run the app on your Pixel (with the `--dart-define`, if you chose option A).
2. **Settings → Google Drive → Connect Google Drive**.
3. Pick your account, accept the Drive-appdata consent (click through the
   "unverified app" warning for your own account).
4. It's now connected. **Back up to Drive now** uploads immediately; leave the
   **Automatic backup** switch on and Braim also backs up (silently) each time
   you leave the app — throttled, and skipped when nothing changed.
5. **Restore from Drive** lists your uploaded backups (newest first) to restore
   any of them.

Only the newest 5 backups are kept; older ones are pruned automatically.

---

### How it works, briefly

- `lib/services/drive_backup_service.dart` — Google sign-in + Drive v3 REST
  (upload / list / download / delete) against the `appDataFolder`, using the
  access token from `google_sign_in`. No `googleapis` dependency.
- `AppState.backupToDrive()` / `restoreFromDrive()` / `maybeAutoBackup()` —
  wraps the existing `BackupService` zip, tracks the connected account and last
  backup time (persisted), and self-throttles the automatic backup.
- Settings → Google Drive — connect, toggle auto-backup, back up now, restore,
  disconnect.
