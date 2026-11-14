import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../transactions/domain/engines/raw_message.dart';
import '../../transactions/domain/transaction_enums.dart';

/// Gmail integration via OAuth 2.0 (google_sign_in) and the Gmail REST API.
///
/// * Only the `gmail.readonly` scope is requested.
/// * No passwords are ever collected; tokens are held by the platform's
///   Google identity services, not by this app or Firestore.
/// * Incremental sync uses Gmail `historyId` checkpoints.
class GmailSource {
  GmailSource({http.Client? client}) : _http = client ?? http.Client();

  static const scope = 'https://www.googleapis.com/auth/gmail.readonly';
  static const _base = 'https://gmail.googleapis.com/gmail/v1/users/me';

  /// Server-side query that narrows the mailbox to likely financial mail.
  static const searchQuery =
      '{debited credited "transaction alert" "txn" "payment received" "payment successful" "amount paid" refund "order total" '
      'EMI salary premium renewal subscription "spent" "UPI"} -category:promotions -category:social';

  /// Google sign-in needs an OAuth web client ID (Android) / iOS client ID,
  /// passed with --dart-define. Without it the connect flow cannot start.
  static bool get isConfigured => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => AppConfig.googleIosClientId.isNotEmpty && AppConfig.googleServerClientId.isNotEmpty,
        _ => AppConfig.googleServerClientId.isNotEmpty,
      };

  final http.Client _http;
  bool _initialized = false;
  GoogleSignInAccount? _account;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: AppConfig.googleIosClientId.isEmpty ? null : AppConfig.googleIosClientId,
      serverClientId: AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
    );
    _initialized = true;
  }

  /// Interactive connect: account picker + Gmail consent screen.
  Future<String> connect() async {
    if (!isConfigured) {
      throw const AppFailure('Gmail sign-in is not set up for this build yet.', code: 'gmail-not-configured');
    }
    try {
      await _init();
      _account = await GoogleSignIn.instance.authenticate(scopeHint: const [scope]);
      await _account!.authorizationClient.authorizeScopes(const [scope]);
      return _account!.email;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AppFailure('Gmail connection was cancelled.', code: 'cancelled');
      }
      throw AppFailure('Could not connect Gmail: ${e.description ?? e.code.name}', code: e.code.name);
    }
  }

  /// Non-interactive token (background sync). Returns null if the user must
  /// re-authorize in the foreground.
  Future<String?> _token({bool interactive = false}) async {
    await _init();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    final acc = _account;
    if (acc == null) return null;
    final auth = await acc.authorizationClient.authorizationForScopes(const [scope]) ??
        (interactive ? await acc.authorizationClient.authorizeScopes(const [scope]) : null);
    return auth?.accessToken;
  }

  Future<bool> isAuthorized() async => (await _token()) != null;

  Future<void> disconnect() async {
    await _init();
    try {
      await GoogleSignIn.instance.disconnect(); // revokes the grant
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
    _account = null;
  }

  Future<Map<String, dynamic>> _get(String token, String path, [Map<String, String>? params]) async {
    final uri = Uri.parse('$_base/$path').replace(queryParameters: params);
    final res = await _http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) throw const AppFailure('Gmail authorization expired. Please reconnect.', code: 'gmail-unauthorized');
    if (res.statusCode == 404) throw const AppFailure('Not found', code: 'gmail-404');
    if (res.statusCode >= 400) throw AppFailure('Gmail API error ${res.statusCode}', code: 'gmail-${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> currentHistoryId() async {
    final token = await _requireToken();
    final p = await _get(token, 'profile');
    return p['historyId'].toString();
  }

  Future<String> _requireToken() async {
    final t = await _token();
    if (t == null) throw const AppFailure('Gmail is not connected or needs re-authorization.', code: 'gmail-unauthorized');
    return t;
  }

  /// Message IDs for the initial scan; [estimate] receives Gmail's size estimate.
  Future<List<String>> listInitial({int days = 180, int max = 1500, void Function(int estimate)? estimate}) async {
    final token = await _requireToken();
    final ids = <String>[];
    String? pageToken;
    var first = true;
    do {
      final res = await _get(token, 'messages', {
        'q': '$searchQuery newer_than:${days}d',
        'maxResults': '100',
        'pageToken': ?pageToken,
      });
      if (first) {
        estimate?.call((res['resultSizeEstimate'] as num?)?.toInt() ?? 0);
        first = false;
      }
      ids.addAll(((res['messages'] as List?) ?? const []).map((m) => (m as Map)['id'] as String));
      pageToken = res['nextPageToken'] as String?;
    } while (pageToken != null && ids.length < max);
    return ids;
  }

  /// Incremental: messages added since [historyId]. Falls back to a short
  /// date-window query when the history checkpoint has expired.
  Future<List<String>> listSince(String historyId) async {
    final token = await _requireToken();
    try {
      final ids = <String>{};
      String? pageToken;
      do {
        final res = await _get(token, 'history', {
          'startHistoryId': historyId,
          'historyTypes': 'messageAdded',
          'maxResults': '500',
          'pageToken': ?pageToken,
        });
        for (final h in (res['history'] as List? ?? const [])) {
          for (final m in ((h as Map)['messagesAdded'] as List? ?? const [])) {
            final msg = (m as Map)['message'] as Map;
            final labels = List<String>.from(msg['labelIds'] as List? ?? const []);
            if (labels.contains('CATEGORY_PROMOTIONS') || labels.contains('SPAM')) continue;
            ids.add(msg['id'] as String);
          }
        }
        pageToken = res['nextPageToken'] as String?;
      } while (pageToken != null);
      return ids.toList();
    } on AppFailure catch (e) {
      if (e.code == 'gmail-404') return listInitial(days: 7);
      rethrow;
    }
  }

  Future<RawMessage?> fetch(String id) async {
    final token = await _requireToken();
    final m = await _get(token, 'messages/$id', {'format': 'full'});
    final payload = m['payload'] as Map<String, dynamic>? ?? const {};
    final headers = {
      for (final h in (payload['headers'] as List? ?? const [])) ((h as Map)['name'] as String).toLowerCase(): h['value'] as String,
    };
    final from = headers['from'] ?? '';
    final match = RegExp(r'^(.*?)\s*<([^>]+)>').firstMatch(from);
    final body = _extractBody(payload);
    if (body.isEmpty) return null;
    return RawMessage(
      id: id,
      source: TxSource.email,
      sender: (match?.group(2) ?? from).trim().toLowerCase(),
      senderName: match?.group(1)?.replaceAll('"', '').trim(),
      subject: headers['subject'],
      body: body,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse(m['internalDate']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  String _extractBody(Map<String, dynamic> part) {
    String? plain, html;
    void walk(Map<String, dynamic> p) {
      final mime = p['mimeType'] as String? ?? '';
      final data = (p['body'] as Map?)?['data'] as String?;
      if (data != null) {
        final text = utf8.decode(base64Url.decode(base64Url.normalize(data)), allowMalformed: true);
        if (mime == 'text/plain') plain ??= text;
        if (mime == 'text/html') html ??= text;
      }
      for (final c in (p['parts'] as List? ?? const [])) {
        walk(c as Map<String, dynamic>);
      }
    }

    walk(part);
    return plain ?? html ?? '';
  }
}
