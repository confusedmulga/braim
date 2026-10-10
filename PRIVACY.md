# Privacy Policy for Braim

**Last updated:** October 10, 2026

Braim ("the App") is developed and published by Kalpesh Nichal, an individual
developer based in India ("we," "us," "our"). This policy explains what happens
to your data when you use Braim.

## Summary

Braim is a local-first notes app. It does not require an account, does not use
analytics, advertising or crash-reporting SDKs, and has no backend server that
we operate. We never receive your content. The App does connect to other
websites when you save or view links, as described under
[Link, Tweet and YouTube Previews](#link-tweet-and-youtube-previews). If you
turn on [Braim Web](#braim-web), your phone shows your library to your own
browser on your local network.

## What We Never Do

- We never sell, rent or share your data, because we never have it.
- There are no ads, no tracking across apps or websites, no analytics and no
  crash reports.
- The App is free and takes no payments, so it handles no payment details.

## Data We Collect

We do not operate any server, so your notes, library and everything else you
keep in Braim are never sent to us, and we cannot access them. There is no user
account with us and no analytics library in the App. Some features make your
device contact other services directly, as described below; that traffic does
not pass through us either. Specifically:

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

## Braim Web

Braim Web lets you open your library in a browser on your own computer. It is
**off by default** and runs only while you have it switched on in Settings.

- **Your phone is the server.** The pages go from your phone to your browser
  over your local network (the same Wi-Fi, or your phone's hotspot). Nothing is
  sent to us or to any other server, and no internet service is involved.
- **Only browsers you pair can see it.** A browser must enter the six-digit
  code shown on your phone before it can open anything. Each linked browser
  keeps a random sign-in token in a cookie; your phone stores only a hash of
  it, with the browser's name (for example, "Chrome on Windows") and when it
  was linked and last used, so you can tell your linked browsers apart. This
  record stays on your phone and is left out of Android's system backup. You can log any of
  them out from Settings at any time, and a browser unused for thirty days is
  logged out by itself.
- **The Crypt is never served.** Crypt notes, sparks and images are not
  available to the browser and do not appear in its search.
- **The connection is not encrypted.** Braim Web uses plain HTTP on your local
  network, so someone else on the same network could read the pages as they
  pass. Use it on networks you trust, such as your home Wi-Fi or your phone's
  own hotspot, and not on public Wi-Fi.
- **It turns itself off** after thirty minutes without use, when you tap
  **Turn off** in its notification, or when you close Braim.

Changes you make in the browser are saved into the App on your phone, exactly
as if you had made them there.

## Link, Tweet and YouTube Previews

When you save a link or tweet as a card, or paste a link into a note, the App
fetches a preview. This means direct network requests from your device to
third-party services. Like any website visit, each of those services sees your
device's IP address and the request itself:

- **For a general link,** the App requests the page to read its title,
  description and preview image (Open Graph tags). When you save a card it may
  also keep the article's text so you can read it in reader mode, stored only on
  your device. Reader mode uses only what the page serves publicly without
  signing in, and does not keep the text of an article the publisher marks
  as subscriber-only; that card keeps just its preview. That website, and
  any content-delivery network it uses, sees a
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
- **Network/Internet** — to fetch the previews described above, and, when you
  turn on Braim Web, to serve your library to your own browser on your local
  network.
- **Share intent** — to let you save shared content (links, text, Markdown files
  and images) into Braim from other apps.

## Third-Party Services

Braim does not integrate any third-party analytics, advertising, or
crash-reporting SDKs. Its only outbound network activity is the preview traffic
described above: the linked website itself, X oEmbed, unavatar.io, and YouTube
(its oEmbed endpoint and thumbnail host). None of it sends data to a server operated
by us. Braim Web, when you turn it on, answers only browsers on your local
network that you have paired.

## Security

Your library is stored in the App's private storage, which Android's app sandbox
keeps away from other apps, and which your phone's own encryption protects when
it is locked. Braim adds no encryption of its own: the Crypt folder restricts
access inside the App but does not encrypt, and exported backups are plain zip
files. Braim Web pages travel unencrypted on your local network, as described
under [Braim Web](#braim-web). No method of storage or transmission is
completely secure, so keep your phone locked and your backups somewhere safe.

## Children's Privacy

Braim is not designed or marketed for children. We do not knowingly collect
information from anyone, including children, and the App sends nothing to us.
A child's notes, like anyone's, stay on the device they were written on.

## Data Deletion and Your Rights

Privacy laws such as India's Digital Personal Data Protection Act, 2023 and the
EU's General Data Protection Regulation give you rights over personal data a
company holds about you. Because we run no server, we receive and hold none of
your data, so there is nothing of yours for us to disclose, correct or erase. The third-party services listed above handle the
requests your device sends them, and you can exercise your rights with them
directly.

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
