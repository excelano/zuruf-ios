# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately, using the **Report a vulnerability** button on the Security tab of this repository. If that button is not there, or you would rather not go through GitHub, email david.anderson@excelano.com instead. I aim to respond within seven days.

Please do not open public issues for security problems.

## Supported versions

The latest release receives security fixes. Older versions are not supported. An app fix ships in a new App Store release, and a server fix ships through `main`; pull and redeploy to apply it.

## What Zuruf can access

**Access comes only from an invitation.** There is no sign-up. An operator creates a single-use invite code that expires, and redeeming it creates an account and issues that device an API token. Joining on the watch or the iPhone signs the other in over WatchConnectivity, as a device of its own with its own token.

**A clip is readable only by the people it was sent to.** The audio endpoint serves a clip to its recipient, or to the members of its group, and to no one else, the sender included. Clip ids are random. Clip files live outside the web root and leave the server only through that authenticated endpoint.

**Apple carries alerts, not audio.** A push holds the sender's name, the clip id and the server id. The watch or the iPhone fetches the audio from the server directly.

**Transcripts stay on the phone and its watch.** The iPhone transcribes clips with Apple's speech recognition on the device, and sends the text to its paired watch over WatchConnectivity, never through the server.

**Uploads are checked.** The server rejects files that are not MPEG-4 audio, reads the clip's length from the file rather than trusting the client, and enforces the size cap, the length cap and a per-device upload rate.

## What Zuruf stores

The server stores invite codes and API tokens only as SHA-256 hashes, so the database alone cannot be used to sign in. Each clip carries an expiry, the server stops serving it once that passes, and the hourly cron deletes the file and its record. Deleting an account, from the app's Settings or by the operator, deletes its devices and every clip sent by or to it.

On each device the account and its API token are in the Keychain, transcripts are in the app's own container, and a clip waiting to upload is kept there until the server accepts it. Removing the app removes them.

## Operator responsibilities

**Serve over HTTPS.** The server refuses plain HTTP, but the certificate is yours to keep valid.

**Keep everything but `public/` out of the document root.** Either point the document root at `server/public/`, or put the rest of the server in a `zuruf-server` folder beside the document root. That is what keeps `config.php`, the APNs keys, the database and the clip files off the web; serving `server/` itself would expose all of them.

**Guard the admin token and the APNs keys.** The admin token can create accounts and remove users. A topic-restricted APNs key can push only to your app, but it can push anything to every device that has registered with it.

**Hand out invites directly.** An invite code works for whoever types it first. Failed redemptions are not rate-limited; the code's length and short life are what make guessing impractical, so do not lengthen invite lifetimes beyond what you need.
