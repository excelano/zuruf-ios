<?php
// reactions.php
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

declare(strict_types=1);

const REACTIONS = ['👍', '👎', '❤️', '😂', '‼️', '❓'];

// Reacting answers a clip, so it also counts as playing it. The sender hears
// about a new or changed reaction; one sent again unchanged stays quiet.
function setReaction(array $device, string $id, array $body): never {
    $clip = requireAudibleClip($device, $id);
    $emoji = (string)($body['emoji'] ?? '');
    if (!in_array($emoji, REACTIONS, true)) {
        fail(422, 'invalid_emoji');
    }
    $me = $device['user_id'];
    $now = time();
    $previous = query('SELECT emoji FROM clip_reactions WHERE clip_id = ? AND user_id = ?', [$clip['id'], $me])->fetchColumn();
    query(
        'INSERT INTO clip_reactions (clip_id, user_id, emoji, reacted_at) VALUES (?, ?, ?, ?)
         ON CONFLICT(clip_id, user_id) DO UPDATE SET emoji = excluded.emoji, reacted_at = excluded.reacted_at',
        [$clip['id'], $me, $emoji, $now]
    );
    query('INSERT OR IGNORE INTO clip_receipts (clip_id, user_id, played_at) VALUES (?, ?, ?)', [$clip['id'], $me, $now]);

    send(200, ['emoji' => $emoji]);
    if ($previous !== $emoji) {
        finishRequest();
        pushReaction($clip, $device['display_name'], $emoji);
    }
    exit;
}

function removeReaction(array $device, string $id): never {
    $clip = requireAudibleClip($device, $id);
    query('DELETE FROM clip_reactions WHERE clip_id = ? AND user_id = ?', [$clip['id'], $device['user_id']]);
    respond(200, ['emoji' => null]);
}

// Every reaction on the given clips, oldest first, by clip id.
function reactionsByClip(array $clipIds): array {
    if (!$clipIds) {
        return [];
    }
    $placeholders = implode(',', array_fill(0, count($clipIds), '?'));
    $rows = query(
        "SELECT clip_id, user_id, emoji FROM clip_reactions WHERE clip_id IN ($placeholders) ORDER BY reacted_at, rowid",
        $clipIds
    )->fetchAll();
    $reactions = [];
    foreach ($rows as $row) {
        $reactions[$row['clip_id']][] = ['user_id' => $row['user_id'], 'emoji' => $row['emoji']];
    }
    return $reactions;
}
