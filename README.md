# Zuruf

Zuruf is a walkie-talkie for Apple Watch: hold a button, say something, and it plays on the other person's wrist a moment later, over Wi-Fi or cellular at any distance. It replaces Apple's Walkie-Talkie app for a small group of people. An iPhone app shows the same conversations as threads, with a transcript of every clip made on the phone, and serves people without a watch; the watch app needs no iPhone. Each group runs its own small server, so clips pass through nothing but that server and Apple's push service, which carries only a short alert.

Messages are stored and forwarded rather than streamed. A device records a clip and uploads it, the server sends a push to everyone it is addressed to, and each watch downloads the clip and plays it as the notification arrives. Clips can go to one person or to a group, the sender sees who has played them, and the server deletes them after a set number of days.

Zuruf is invite-only. An account comes from a single-use invite code that the server's operator creates, so an app build is useless without an invitation to a server. Push notifications reach only an app signed by the developer account that holds the APNs key.

This repository holds the watch and iPhone apps, in `watch/`, and the server, in `server/`.

## The watch app

The watch app is SwiftUI with a notification service extension. Joining takes the server's address, an invite code and a display name. From then on the app lists the people and groups on the server, the latest conversation first; choosing one opens a talk button that records while it is held and sends on release, keeping a clip on the watch and retrying until the server accepts it. When the watch gets a notification itself, because its owner has no phone, a notification service extension downloads the clip before it appears; one passed on from the phone fetches the clip when it plays. The notification plays the clip as soon as it shows, unless Play automatically is turned off in Settings or the watch is on silent, in which case the notification's Play button plays it. The notification's Reply button opens the talk button for the sender or the group. Lowering the wrist dismisses the notification and stops the clip there, and because a clip that plays on its own does not count as played, it stays unplayed in the inbox until it is played from there or from the Play button. The inbox keeps recent clips for replay, with a reply to the sender or the group, and shows who has played each clip you sent. Swiping an unplayed clip marks it as read, which counts as playing it, so the sender sees it among those who have played it. Swiping also deletes a clip from the inbox; the sender keeps it in their sent list until it expires, and the server deletes its audio once everyone it was sent to has deleted it. Sending a clip to a person or group marks what they sent you as played, since it answers it. A received clip opened from the inbox has a row of emoji to react with; each person keeps one reaction per clip, choosing another replaces it and choosing it again takes it back, and reacting counts as playing the clip. The inbox shows the reactions on clips you sent and received.

A complication, also offered in the Smart Stack, shows the person or group you last sent a clip to, and tapping it opens the talk button for them. A second one, Talk to, opens the talk button for one person or group chosen when it is added to a face, and is offered once for each of them, so a face can hold one for each person you talk to most; its circular size shows their initials.

## The iPhone app

The iPhone app lists the same people and groups in one list, the latest conversation first, and each one opens a conversation: received clips on one side with the sender, a Play button and an unplayed dot, sent clips on the other with who has played them, and a hold-to-talk button at the bottom where a messaging app would have a text field. There is no way to type a message. Every clip in a conversation, sent or received, is transcribed on the phone with Apple's speech recognition in the phone's language, and the transcript is kept only on that phone and its paired watch. While the server has words to recognize, transcribing uses Apple's dictation model, which favors those words and the names of the people and groups on the server over words that sound like them; without any, it uses Apple's newer speech model, which favors none. Swiping a received clip marks it as read or deletes it, as on the watch. Long-pressing a received clip opens a row of emoji to react with, working as on the watch, and every reaction in the conversation, from anyone in it, hangs off the corner of its clip. A reaction sends the clip's sender a quiet notification, with no sound and no clip to play; tapping it opens that conversation on the phone and the inbox on the watch.

The watch and the phone share one account. Joining on either signs the other in over WatchConnectivity, as a device of its own with its own push token, and deleting the account on either signs both out. Settings on the phone carries the watch's Play automatically switch, kept in step with the watch. The phone sends the transcripts of received clips to the watch over the same connection, never through the server, and the watch shows them in its inbox and its notifications. A notification for a clip the phone has not transcribed yet has a Transcribe button whenever the phone can be reached, which wakes the iPhone app to transcribe the clip and send the text back. A watch without a phone running Zuruf has no transcripts.

A clip's notification goes to the phone, and iOS shows it there while the phone is in use or passes it to the watch while the phone is locked. The watch shows it as Zuruf's own notification, so it plays at once when Play automatically is on; a watch whose phone is in use stays quiet. Before the notification shows, the phone transcribes the clip and puts the text in it, and the watch shows that text too. The notification sets the app's badge to the number of unplayed clips and wakes the app to refresh its conversations, which iOS does only while Background App Refresh is on and holds back when it chooses, so the phone also catches up whenever it is opened. Tapping it on the phone opens the conversation. Someone with only a watch gets the notification on the watch.

## Building

The app's identity, meaning the team id, the App Store bundle id, the display name and the default server, lives in `watch/Config/Zuruf.xcconfig`, and the version in `watch/Config/Version.xcconfig`. The project's `Zuruf` scheme builds the iPhone app with the watch app embedded, which is how both reach the App Store on one record; `ZurufWatch` builds the watch app alone for installing on a watch during development.

## The server

The server is a small PHP application backed by SQLite, written to run on ordinary cPanel shared hosting with nothing to keep running between requests. It needs PHP with the `pdo_sqlite`, `curl` and `openssl` extensions, and a curl built with HTTP/2, which APNs requires. This prints `true` when the host's curl qualifies:

```bash
php -r 'var_dump((bool)(curl_version()["features"] & CURL_VERSION_HTTP2));'
```

```
server/public/       The document root: index.php routes every request.
server/src/          Accounts and invites, clips, the APNs sender, the echo bot, admin.
server/cron.php      Hourly cleanup of expired clips and invites.
server/config.php    Your settings, copied from config.example.php. Never committed.
server/keys/         Your APNs keys. Never committed.
server/data/         The database and clip files, created on first request.
```

Only `public/` is reachable from the web. Everything else sits beside it, so the configuration, keys, database and audio stay outside the web root without depending on rewrite rules.

## Running a server

In Certificates, Identifiers & Profiles, enable Push Notifications on both App IDs, the watch app's and the iPhone app's, then create an APNs key for each app and each environment, restricted to that App ID's topic. Development builds installed from Xcode use the sandbox keys; TestFlight and App Store builds use the production keys. Apple lets you download each `.p8` file once.

Point a hostname's document root at `server/public/` and upload the `server/` directory. If your host will not move a document root, upload the contents of `public/` into the document root it gave you and the rest of `server/` into a folder named `zuruf-server` beside it; `index.php` looks there when it finds no server beside itself. The server must sit at the root of its hostname, and it refuses plain HTTP. Copy `config.example.php` to `config.php`, fill in your team id, each app's bundle id and key ids under `APNS_APPS`, the watch app's under `watchos` and the iPhone app's under `ios`, and a long random admin token, and put the `.p8` files in `keys/`. Then add an hourly cron job:

```bash
php /path/to/server/cron.php
```

The server is managed from its admin page, at `/admin` on the server's own address, in any browser on a computer or a phone. It signs in with the admin token and makes invite codes, lists who has joined and when each device last opened the app, creates, renames and deletes groups, adds and removes members, deletes people along with every message sent by or to them, sets the words to recognize, and hides or shows Echo. Words to recognize are names and words that transcribing should expect beyond those of the people and groups, such as a name that sounds like a common word, and reach every device with its contacts. Link a device makes a one-day code that adds a device to an existing person's account instead of making a new one, for a computer that no phone or watch can sign in. An invite or link code is shown once, when it is made, because the server keeps only its hash. Changes reach each device the next time Zuruf refreshes its contacts, such as when it is opened.

The page is a client of the server's `/v1/admin` API, which takes the same token as a bearer token and can be scripted directly:

```bash
curl -s -X POST https://zuruf.example.com/v1/admin/invites \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' -d '{}'
```

`GET /v1/admin/users` returns everyone and every group, `/v1/admin/groups` creates a group, `PATCH` and `DELETE` on `/v1/admin/groups/{id}` rename and delete one, `/v1/admin/groups/{id}/members` adds a member, and `DELETE /v1/admin/users/{id}` removes a person, `POST /v1/admin/users/{id}/link-codes` makes a link code for them, `PUT /v1/admin/vocabulary` with `{"words": [...]}` sets the words to recognize, up to 50 of up to 40 characters each, which `GET /v1/contacts` and `GET /v1/admin/users` return as `vocabulary`, and `PUT /v1/admin/echo` with `{"shown": false}` or `true` hides or shows Echo. Echo is a built-in contact that sends back any clip it receives, which makes it the quickest check that recording, upload, push and playback all work. Hiding it from the admin page deletes it along with everyone's messages with it, and showing it again makes a fresh one.

## Testing

`server/tests/smoke.sh` runs the API end to end against PHP's built-in server with a throwaway database, and needs `curl`, `jq` and `ffmpeg` besides PHP. It does not send pushes; those are checked on a real watch and iPhone.
