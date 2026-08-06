import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// The MatrixRTC "slot" that identifies an ordinary room-scoped voice call.
///
/// Looks like a typo and is not. `lk-jwt-service` derives the LiveKit room name
/// as `SHA256(json([matrixRoomId, slotId]))`, and its legacy `/sfu/get` handler
/// hardcodes exactly this string (`slotId := "m.call#ROOM"`, asserted in the
/// project's own `sfu_get_test.go`). It encodes application `m.call` plus scope
/// `ROOM`. Sending anything else — the obvious-looking `m.call`, for instance —
/// produces a different hash and lands us in an empty LiveKit room.
const String kMatrixRtcSlotId = 'm.call#ROOM';

/// A LiveKit connection, as issued by `lk-jwt-service`.
@immutable
class LiveKitCredentials {
  const LiveKitCredentials({required this.url, required this.token});

  /// `wss://…` address of the SFU.
  final String url;

  /// Short-lived access token scoped to one room and identity.
  final String token;
}

/// Exchanges a Matrix OpenID token for a LiveKit JWT.
///
/// This is the MatrixRTC authorisation handshake Element Call uses:
///
///   1. ask our homeserver for an OpenID token that proves who we are,
///   2. hand it to the room's `lk-jwt-service`, which verifies it against the
///      homeserver and mints a LiveKit JWT scoped to that room,
///   3. connect to the SFU with it.
///
/// The service is not part of the homeserver and is not authenticated with our
/// access token — the OpenID token is deliberately the only credential that
/// leaves, and it proves identity without granting account access.
class LiveKitTokenService {
  LiveKitTokenService({required this.client, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final Client client;
  final http.Client _http;

  /// Requests credentials for [roomId] from the SFU at [serviceUrl].
  ///
  /// **`/sfu/get` is tried first even though it is deprecated**, and that is
  /// deliberate. The two endpoints are not interchangeable: they place a client
  /// in different LiveKit rooms and give it different identities.
  ///
  ///  * The LiveKit room name is `SHA256(json([matrixRoomId, slotId]))`. The
  ///    legacy endpoint hardcodes the slot `m.call#ROOM` server-side, so a
  ///    client sending the plain `m.call` to `/get_token` gets a *different*
  ///    hash — it connects successfully, alone, in a room nobody else is in.
  ///    The symptom is brutal to diagnose: everything reports success, no audio
  ///    flows either way, and other clients show "waiting for media" because
  ///    the Matrix membership says we joined but we never appear on their SFU.
  ///  * The legacy identity is the plain string `@user:server:DEVICEID`, while
  ///    `/get_token` uses a hash. Element matches LiveKit participants to
  ///    Matrix memberships by identity, so the hashed form would leave us
  ///    unattributed even in the right room.
  ///
  /// Since we read and write `org.matrix.msc3401.call.member` — the same
  /// protocol generation the legacy endpoint belongs to — using the legacy
  /// endpoint keeps every part consistent. Mixing generations is what breaks.
  ///
  /// The fallback passes [kMatrixRtcSlotId] explicitly so that a deployment
  /// which has dropped `/sfu/get` still yields the identical room alias.
  Future<LiveKitCredentials> fetch({
    required String serviceUrl,
    required String roomId,
    String slotId = kMatrixRtcSlotId,
  }) async {
    final userId = client.userID;
    final deviceId = client.deviceID;
    if (userId == null || deviceId == null) {
      throw StateError('Not logged in');
    }

    // The second argument is spec'd as "an empty object, reserved for future
    // expansion" and has no default in the generated API.
    final openId = await client.requestOpenIdToken(userId, {});
    // `toJson()` already emits access_token / token_type / matrix_server_name /
    // expires_in, which is exactly the shape the service's OpenIDTokenType
    // expects — so it is passed through rather than rebuilt by hand.
    final openIdJson = openId.toJson();

    final base = serviceUrl.endsWith('/')
        ? serviceUrl.substring(0, serviceUrl.length - 1)
        : serviceUrl;

    final legacy = await _post('$base/sfu/get', {
      'room': roomId,
      'device_id': deviceId,
      'openid_token': openIdJson,
    });
    if (legacy != null) {
      debugPrint('[voice] LiveKit token via /sfu/get (slot $kMatrixRtcSlotId)');
      return legacy;
    }

    final current = await _post('$base/get_token', {
      'room_id': roomId,
      'slot_id': slotId,
      'openid_token': openIdJson,
      'member': {
        'id': '$userId:$deviceId',
        'claimed_user_id': userId,
        'claimed_device_id': deviceId,
      },
    });
    if (current != null) {
      debugPrint('[voice] LiveKit token via /get_token (slot $slotId)');
      return current;
    }

    throw Exception('SFU service at $base rejected both token endpoints');
  }

  /// Returns null when the endpoint does not exist, so the caller can fall
  /// back. Any other failure throws, because falling back would hide it.
  Future<LiveKitCredentials?> _post(
    String url,
    Map<String, Object?> body,
  ) async {
    final response = await _http.post(
      Uri.parse(url),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception(
        'SFU token request to $url failed: '
        '${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('SFU returned a non-object body');

    final sfuUrl = decoded['url'];
    final jwt = decoded['jwt'];
    if (sfuUrl is! String || jwt is! String) {
      throw Exception('SFU response is missing url/jwt');
    }
    return LiveKitCredentials(url: sfuUrl, token: jwt);
  }

  void dispose() => _http.close();
}
