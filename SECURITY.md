# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately, using the **Report a vulnerability** button on the Security tab of this repository. If that button is not there, or you would rather not go through GitHub, email david.anderson@excelano.com instead. I aim to respond within seven days.

Please do not open public issues for security problems.

## Supported versions

The latest release receives security fixes. Older versions are not supported. A fix ships in a new App Store release.

## What Zuruf can access

**Access comes only from an invitation.** There is no sign-up. An operator creates a single-use invite code that expires, and redeeming it creates an account and issues that device an API token. Joining on the watch or the iPhone signs the other in over WatchConnectivity, as a device of its own with its own token.

**The apps talk only to the server they joined and to Apple.** A push holds the sender's name, the clip id and the server id, and the watch or the iPhone fetches the audio from the server directly.

**Transcripts stay on the phone and its watch.** The iPhone transcribes clips with Apple's speech recognition on the device, and sends the text to its paired watch over WatchConnectivity, never through the server.

## What Zuruf stores

On each device the account and its API token are in the Keychain, transcripts are in the app's own container, and a clip waiting to upload is kept there until the server accepts it.
