# Privacy Policy for Braim

**Last updated:** September 28, 2026

Braim ("the App") is developed and published by Kalpesh Nichal, an individual
developer based in India ("we," "us," "our"). This policy explains what happens
to your data when you use Braim.

## Summary

Braim is a local-first notes app. It does not require an account, does not use
analytics, advertising or crash-reporting SDKs, and has no backend server that
we operate. We never receive your content. The App does connect to other
websites when you save or view links, as described under
[Link, Tweet and YouTube Previews](#link-tweet-and-youtube-previews).

## Data We Collect

We do not collect, store, or have access to any of your data. There is no user
account with us and no analytics library in the App. Specifically:

- **Notes, cards, checklists, journal entries, books, and habit trackers** are
  stored only in a local database on your device.
- **Images** you attach are copied into the App's private storage on your
  device. They come from your device's photo picker or camera, only when you
  choose to add one.
- **Crypt folder authentication** uses your device's built-in biometric or PIN
  lock (via the operating system's local authentication API). We never see or
  store your biometric data or device credentials; the operating system handles
  this entirely. Crypt restricts access inside the App; it does not encrypt its
  contents.
- **Clipboard.** When you tap the button to add a link, the App reads your
  clipboard once to pre-fill the link field if it holds a web address. The text
  stays on your device and is only saved if you confirm it.
- **Backups you export** are saved as zip files where you choose. If you share
  one (for example, via email, cloud storage, or another app) using your
  device's share sheet, that transfer is between you and the destination you
  pick; we have no visibility into it and no involvement in it. Backup files are
  not encrypted and include Crypt items.

## Backups

**Braim's automatic backup** runs only on your device. When enabled in
Settings, it writes a backup zip to the App's own folder on your device on a
schedule you choose, keeping the most recent copies and deleting older ones.
Braim never uploads these files anywhere.

**Android's system backup** is separate from Braim and controlled by your
device. If you have turned on backup to your Google account in Android's
settings, Android may include Braim's data (your notes and attached images,
Crypt items included) in that backup and restore it to a new phone. Google
handles that backup under its own terms and privacy policy; it does not pass
through us and we cannot access it. Braim excludes its own backup zips from this
cloud copy. You can turn Android backup off in your device settings.

## Link, Tweet and YouTube Previews

When you save a link or tweet as a card, or paste a link into a note, the App
fetches a preview. This means direct network requests from your device to
third-party services. Like any website visit, each of those services sees your
device's IP address and the request itself:

- **For a general link,** the App requests the page to read its title,
  description and preview image (Open Graph tags). When you save a card it may
  also keep the article's text so you can read it in reader mode, stored only on
  your device. That website, and any content-delivery network it uses, sees a
  request from your device, the same as if you had opened the link in a
  browser.
- **For a tweet or X post,** the App additionally contacts **X's public oEmbed
  endpoint** (`publish.twitter.com`) to fetch the post text, and **unavatar.io**
  to fetch the author's public profile picture from their handle. No login or
  API key is used; the requests carry only the post URL or public handle.
- **For a YouTube link,** the App asks YouTube's public oEmbed endpoint
  (`youtube.com/oembed`) for the video's title and channel name, and loads the
  thumbnail from `ytimg.com`. No login or API key is used; the requests carry
  only the public video URL.

**Preview images** (article images, video thumbnails and profile pictures) are
loaded from those hosts each time a card or link is displayed, so those hosts
receive a request whenever you view the card, not only when you save it.

These requests go directly from your device to those services. We do not proxy,
log, or store this traffic, and none of it is sent to us. Each service handles
the request under its own privacy policy.

**Links you tap** (including map, search and translate shortcuts) open in your
browser or the relevant app, under that site's own privacy policy.

## Permissions

Braim requests the following device capabilities, used only for the stated
purpose and never transmitted to us:

- **Photos and camera** — to attach images to notes, only when you choose to.
- **Files** — to save and restore backups and to import or export notes,
  through the system file picker and save dialog. Braim does not request broad
  storage access.
- **Biometric/Device Lock** — to protect the Crypt folder.
- **Notifications** — to show reminders and the focus timer. These are generated
  on your device; no push service is used.
- **Alarms and reminders, and run at startup** — to deliver reminders at the
  time you set and to reschedule them after your phone restarts.
- **Do Not Disturb access** (optional) — if you use the focus timer's Do Not
  Disturb option, to silence interruptions during a session. Braim only switches
  the filter on and off; it reads nothing.
- **Network/Internet** — to fetch the previews described above.
- **Share intent** — to let you save shared content (links, text, Markdown files
  and images) into Braim from other apps.

## Third-Party Services

Braim does not integrate any third-party analytics, advertising, or
crash-reporting SDKs. Its only outbound network activity is the preview traffic
described above: the linked website itself, X oEmbed, unavatar.io, and YouTube
(its oEmbed endpoint and thumbnail host). None of it sends data to a server operated
by us.

## Children's Privacy

Braim does not knowingly collect any information from anyone, including
children, because it collects no information itself. The App is not directed at
children and contains no age-restricted content.

## Data Deletion and Your Rights

All app data lives on your device. Deleting items in the App (they stay in
Recently Deleted for thirty days unless you empty it), using Settings › Clear
all data, uninstalling the App, or clearing its storage removes it. We hold
no copy, so there is nothing for us to access, correct, export or delete on
request, and we cannot recover lost data for you. Copies you made yourself
(exported backups, files you shared, or Android's system backup) are under your
control and must be deleted where they are stored.

## Changes to This Policy

We may update this policy if the App's functionality changes (for example, if
cloud sync is added in the future). Any material change will be reflected here
with an updated date, and, if it introduces new data collection, will be
communicated via the app store listing or an in-app notice before it takes
effect.

## Contact

Questions about this policy can be directed to: **yellowisjoyy@gmail.com**
