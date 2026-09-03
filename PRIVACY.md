# Privacy Policy for Braim

**Last updated:** September 3, 2026

Braim ("the App") is developed and published by Kalpesh Nichal ("we," "us,"
"our"). This policy explains what happens to your data when you use Braim.

## Summary

Braim is a local-first notes app. It does not require an account, does not use
analytics or advertising SDKs, and has no backend server that we operate. Your
content stays on your device unless you explicitly export it, share it, or turn
on the optional Google Drive backup, in which case your data is uploaded to your
own Google Drive account and never to us.

## Data We Collect

We do not collect, store, or have access to any of your data. There is no user
account with us and no analytics library in the App. Specifically:

- **Notes, cards, checklists, journal entries, books, and habit trackers** are
  stored only in a local data file on your device.
- **Images** you attach are stored locally, accessed via your device's photo
  picker at your request.
- **Crypt folder authentication** uses your device's built-in biometric or PIN
  lock (via the operating system's local authentication API). We never see or
  store your biometric data or device credentials; the operating system handles
  this entirely.
- **Local backups** you create are saved as archive files on your device. If you
  share one (for example, via email, cloud storage, or another app) using your
  device's native share function, that transfer is between you and the
  destination you pick; we have no visibility into it and no involvement in it.

## Optional Google Drive Backup

Braim includes an optional backup feature that is **off by default** and becomes
active only if you connect a Google account in Settings. When you enable it:

- The App uses **Google Sign-In** to authenticate the Google account you choose,
  and requests a single restricted permission, the `drive.appdata` scope. This
  grants access only to a private, app-specific folder in your own Google Drive.
  It does not grant access to the rest of your Drive, and the folder does not
  appear in your normal Drive view.
- Backup archives, which contain your notes, images, and other app data, are
  uploaded to that private folder in **your own Google Drive account**. The
  upload goes directly from your device to Google's servers under your account.
- We operate no server and receive no copy of this data. It is stored under your
  Google account and is governed by Google's Privacy Policy
  (https://policies.google.com/privacy).
- Once enabled, Braim may also back up automatically when you leave the App, and
  keeps only the most recent backups, deleting older ones automatically.
- You can disconnect at any time in Settings, which stops further backups, and
  you can delete uploaded backups from within the App or from your Google
  account.

## Link and Tweet Previews

When you save a link or a tweet as a card, the App fetches a preview. This
involves direct network requests from your device to third-party services,
initiated by your action:

- **For a general link,** the App requests the page you saved to read its title,
  description, and preview image (Open Graph tags). That website, and any
  content-delivery network it uses, sees a request from your device, the same as
  if you had opened the link in a browser.
- **For a tweet or X post,** the App additionally contacts **Twitter/X's public
  oEmbed endpoint** (`publish.twitter.com`) to fetch the post text, and
  **unavatar.io** to fetch the author's public profile picture from their
  handle. No login or API key is used; the requests carry only the post URL or
  public handle.

These requests go directly from your device to those services. We do not proxy,
log, or store this traffic, and none of it is sent to us.

## Permissions

Braim requests the following device capabilities, used only for the stated
purpose and never transmitted to us:

- **Photos/Media** — to attach images to notes.
- **Storage/Files** — to save backups, export data, and pick files.
- **Biometric/Device Lock** — to protect the Crypt folder.
- **Notifications** — to show local reminders, including the focus (Pomodoro)
  timer. These are generated on your device; no push service is used.
- **Do Not Disturb access** (optional) — if you use the focus timer's Do Not
  Disturb option, to silence interruptions during a session.
- **Network/Internet** — to fetch link and tweet previews, and to perform Google
  Drive backup if you enable it.
- **Share intent** — to let you save shared content (links, text, tweets,
  images) into Braim from other apps.

## Third-Party Services

Braim does not integrate any third-party analytics, advertising, or
crash-reporting SDKs. Outbound network activity is limited to:

1. Fetching link and tweet previews from the linked site, Twitter/X oEmbed, and
   unavatar.io, as described above, and only when you save a card.
2. Uploading and managing your backups in your own Google Drive, via Google
   Sign-In and the Google Drive API, and only if you enable Google Drive backup.

Every one of these is initiated by your own action. None of them send data to a
server operated by us.

## Children's Privacy

Braim does not knowingly collect any information from anyone, including children,
because it collects no information itself. The App is not directed at children
specifically and contains no age-restricted content.

## Data Deletion

Because all app data lives locally on your device, uninstalling the App or
clearing its storage removes all associated data permanently. We hold no copy
and cannot recover it for you. If you used Google Drive backup, you can delete
those backups from within the App (Settings, then Google Drive) or directly from
your Google account.

## Changes to This Policy

We may update this policy if the App's functionality changes (for example, if
cloud sync is added in the future). Any material change will be reflected here
with an updated date, and, if it introduces new data collection, will be
communicated via the app store listing or an in-app notice before it takes
effect.

## Contact

Questions about this policy can be directed to: **yellowisjoyy@gmail.com**
