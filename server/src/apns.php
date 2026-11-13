<?php
// apns.php
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

declare(strict_types=1);

const APNS_HOSTS = [
    'sandbox' => 'https://api.sandbox.push.apple.com',
    'production' => 'https://api.push.apple.com',
];

// APNs rejects tokens older than an hour and throttles ones refreshed more
// often than every 20 minutes.
const APNS_JWT_LIFETIME = 50 * 60;

function base64Url(string $data): string {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

// openssl_sign returns a DER sequence of two integers; JWS wants r and s as
// fixed 32-byte values.
function derToJose(string $der): string {
    $offset = 2 + (ord($der[1]) & 0x80 ? ord($der[1]) & 0x7f : 0);
    $parts = '';
    for ($i = 0; $i < 2; $i++) {
        $length = ord($der[$offset + 1]);
        $value = ltrim(substr($der, $offset + 2, $length), "\0");
        $parts .= str_pad($value, 32, "\0", STR_PAD_LEFT);
        $offset += 2 + $length;
    }
    return $parts;
}

function apnsJwt(array $key): ?string {
    $cached = json_decode(getSetting('apns_jwt_' . $key['id']) ?? '', true);
    if (is_array($cached) && time() - $cached['issued_at'] < APNS_JWT_LIFETIME) {
        return $cached['jwt'];
    }

    $privateKey = openssl_pkey_get_private('file://' . $key['path']);
    if ($privateKey === false) {
        error_log("zuruf: cannot read APNs key {$key['id']} at {$key['path']}");
        return null;
    }
    $issuedAt = time();
    $input = base64Url(json_encode(['alg' => 'ES256', 'kid' => $key['id']]))
        . '.' . base64Url(json_encode(['iss' => APNS_TEAM_ID, 'iat' => $issuedAt]));
    if (!openssl_sign($input, $signature, $privateKey, OPENSSL_ALGO_SHA256)) {
        error_log("zuruf: signing the APNs token for key {$key['id']} failed");
        return null;
    }
    $jwt = $input . '.' . base64Url(derToJose($signature));
    setSetting('apns_jwt_' . $key['id'], json_encode(['jwt' => $jwt, 'issued_at' => $issuedAt]));
    return $jwt;
}

function apnsSend(CurlHandle $handle, array $device, array $payload, int $expiresAt): void {
    $app = APNS_APPS[$device['platform']];
    $key = $app['keys'][$device['apns_env']];
    $jwt = $key['id'] === '' ? null : apnsJwt($key);
    if ($jwt === null) {
        error_log("zuruf: no APNs {$device['platform']} {$device['apns_env']} key; push to device {$device['id']} skipped");
        return;
    }
    curl_setopt_array($handle, [
        CURLOPT_URL => APNS_HOSTS[$device['apns_env']] . '/3/device/' . $device['apns_token'],
        CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_2_0,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE),
        CURLOPT_HTTPHEADER => [
            'authorization: bearer ' . $jwt,
            'apns-topic: ' . $app['topic'],
            'apns-push-type: alert',
            'apns-priority: 10',
            'apns-expiration: ' . $expiresAt,
        ],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 10,
    ]);
    $response = curl_exec($handle);
    $status = curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
    if ($status === 200) {
        return;
    }
    $reason = json_decode((string)$response, true)['reason'] ?? curl_error($handle);
    if ($status === 410 || $reason === 'BadDeviceToken') {
        query('UPDATE devices SET apns_token = NULL WHERE id = ?', [$device['id']]);
    }
    error_log("zuruf: APNs $status $reason for device {$device['id']}");
}

function pushClip(array $clip): void {
    $recipients = clipRecipientIds($clip);
    if (!$recipients) {
        return;
    }
    $sender = query('SELECT display_name FROM users WHERE id = ?', [$clip['sender_id']])->fetchColumn();
    $alert = [
        'aps' => [
            'alert' => [
                'title' => pushTitle($sender, $clip),
                'body' => 'New message',
            ],
            'sound' => 'default',
            'category' => 'clip',
            'mutable-content' => 1,
            'interruption-level' => 'time-sensitive',
        ],
        'clip_id' => $clip['id'],
        'server_id' => serverId(),
    ];
    // content-available also wakes the app, to refresh and transcribe.
    pushEach(pushTargets($recipients), (int)$clip['expires_at'], function (array $device) use ($alert) {
        if ($device['platform'] === 'ios') {
            $alert['aps']['badge'] = unplayedCount($device['user_id']);
            $alert['aps']['content-available'] = 1;
        }
        return $alert;
    });
}

// A quiet alert to the clip's sender: no sound, no clip to fetch and no
// badge change. It names the clip by a key of its own, since the
// notification extensions fetch the audio of any clip_id. The phone wakes to refresh, so the reaction shows on the clip.
function pushReaction(array $clip, string $reactor, string $emoji): void {
    $alert = [
        'aps' => [
            'alert' => [
                'title' => pushTitle($reactor, $clip),
                'body' => "Reacted $emoji to your message",
            ],
        ],
        'reacted_clip_id' => $clip['id'],
        'server_id' => serverId(),
    ];
    pushEach(pushTargets([$clip['sender_id']]), (int)$clip['expires_at'], function (array $device) use ($alert) {
        if ($device['platform'] === 'ios') {
            $alert['aps']['content-available'] = 1;
        }
        return $alert;
    });
}

function pushTitle(string $name, array $clip): string {
    if ($clip['group_id'] === null) {
        return $name;
    }
    $groupName = query('SELECT name FROM groups WHERE id = ?', [$clip['group_id']])->fetchColumn();
    return "$name in $groupName";
}

// APNs ties a connection to the first key used on it, so each key, which is
// one per platform and environment, gets a connection of its own.
function pushEach(array $devices, int $expiresAt, callable $payloadFor): void {
    if (!$devices) {
        return;
    }
    if (!function_exists('curl_init')) {
        error_log('zuruf: the curl extension is missing; pushes are disabled');
        return;
    }
    $handles = [];
    foreach ($devices as $device) {
        $handle = $handles[$device['platform'] . '/' . $device['apns_env']] ??= curl_init();
        apnsSend($handle, $device, $payloadFor($device), $expiresAt);
    }
    foreach ($handles as $handle) {
        curl_close($handle);
    }
}

// A phone gets the notification, and iOS shows it on the phone or passes it
// to the watch. A watch gets it only when its owner has no phone.
function pushTargets(array $userIds): array {
    $placeholders = implode(',', array_fill(0, count($userIds), '?'));
    $devices = query(
        "SELECT id, user_id, platform, apns_token, apns_env FROM devices
         WHERE apns_token IS NOT NULL AND user_id IN ($placeholders)",
        $userIds
    )->fetchAll();
    $hasPhone = [];
    foreach ($devices as $device) {
        if ($device['platform'] === 'ios') {
            $hasPhone[$device['user_id']] = true;
        }
    }
    return array_values(array_filter(
        $devices,
        fn($device) => $device['platform'] === 'ios' || !isset($hasPhone[$device['user_id']])
    ));
}
