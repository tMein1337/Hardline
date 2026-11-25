// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// The content of the messages this client sends, as plain maps.
//
// Pure, so what goes on the wire can be tested without a homeserver — the
// same reason `mentions.dart` is kept apart from the widgets.

import 'package:matrix/matrix.dart';

import 'markdown_format.dart';
import 'mentions.dart';

/// The content of a text message saying [body].
///
/// [body] is Markdown, and goes out as typed; the HTML rendering of it goes
/// alongside as `formatted_body` whenever it says more than the plain text
/// (see `markdown_format.dart`). [candidates] are the room's members, for
/// turning `@name` into a real mention; [alsoMention] adds people the text
/// does not name, such as the sender of the message a reply answers.
Map<String, Object?> textMessageContent(
  String body, {
  List<MentionCandidate> candidates = const [],
  Set<String> alsoMention = const {},
  String msgtype = MessageTypes.Text,
}) {
  final mentioned = {...mentionedUserIds(body, candidates), ...alsoMention};
  final html = markdownToMatrixHtml(body, candidates: candidates);
  final mentionsRoom = _roomMention.hasMatch(body);

  return {
    'msgtype': msgtype,
    'body': body,
    if (html != null) ...{
      'format': 'org.matrix.custom.html',
      'formatted_body': html,
    },
    if (mentioned.isNotEmpty || mentionsRoom)
      'm.mentions': {
        ...mentionsBlock(mentioned),
        if (mentionsRoom) 'room': true,
      },
  };
}

/// `@room` as a word of its own, which pings everybody who may be pinged.
/// Permission is the homeserver's to check, not ours.
final _roomMention = RegExp(r'(^|\s)@room\b');

/// The content of an edit replacing [originalEventId] with [newContent].
///
/// Shaped as the spec asks (`m.replace`):
///
///  * `m.new_content` is the whole new message, and is what every client that
///    understands edits draws;
///  * the top level is a fallback for clients that do not, so its body is the
///    new text marked with an asterisk, the way people mark a correction by
///    hand;
///  * the top-level `m.mentions` holds only the people the edit names who the
///    message did not name before. Anybody already mentioned was notified
///    once, and repeating it on every typo fix would notify them again.
Map<String, Object?> editContent(
  Map<String, Object?> newContent, {
  required String originalEventId,
  Set<String> previouslyMentioned = const {},
}) {
  final mentions = newContent['m.mentions'];
  final now = mentions is Map
      ? {...?(mentions['user_ids'] as List?)?.cast<String>()}
      : <String>{};
  final added = now.difference(previouslyMentioned);

  final body = newContent['body'];
  final formatted = newContent['formatted_body'];

  return {
    'msgtype': newContent['msgtype'],
    'body': '* $body',
    if (formatted is String) ...{
      'format': newContent['format'],
      'formatted_body': '* $formatted',
    },
    'm.mentions': mentionsBlock(added),
    'm.new_content': newContent,
    'm.relates_to': {
      'rel_type': RelationshipTypes.edit,
      'event_id': originalEventId,
    },
  };
}

/// Message types whose text can be edited here.
///
/// Attachments are left out: their body is a file name or a caption, and
/// changing one is not what "edit" offers.
const editableMessageTypes = {
  MessageTypes.Text,
  MessageTypes.Emote,
  MessageTypes.Notice,
};

/// Whether [original] is a message this account may edit from the composer.
bool isEditableByMe(Event original) =>
    original.senderId == original.room.client.userID &&
    original.type == EventTypes.Message &&
    !original.redacted &&
    original.status.isSent &&
    editableMessageTypes.contains(original.messageType);
