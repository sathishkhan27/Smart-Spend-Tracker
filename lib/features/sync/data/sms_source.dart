import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../transactions/domain/engines/raw_message.dart';
import '../../transactions/domain/transaction_enums.dart';

/// Android-only SMS inbox access through the native `SmsBridge`.
/// iOS does not allow third-party apps to read the SMS inbox.
class SmsSource {
  SmsSource({MethodChannel? channel, EventChannel? events})
      : _channel = channel ?? const MethodChannel('smart_spend/sms'),
        _events = events ?? const EventChannel('smart_spend/sms_events');

  final MethodChannel _channel;
  final EventChannel _events;

  bool get isSupported => Platform.isAndroid;

  Future<bool> hasPermission() async => isSupported && await Permission.sms.isGranted;

  /// Must only be called after the user accepted the in-app consent screen.
  Future<PermissionStatus> requestPermission() async {
    if (!isSupported) return PermissionStatus.permanentlyDenied;
    return Permission.sms.request();
  }

  Future<int> count({required DateTime since}) async {
    if (!await hasPermission()) return 0;
    return await _channel.invokeMethod<int>('count', {'sinceMillis': since.millisecondsSinceEpoch}) ?? 0;
  }

  /// Pages through the inbox in ascending `_id` order so a checkpoint (the
  /// last processed id) makes incremental sync cheap and restartable.
  Stream<List<RawMessage>> read({required DateTime since, int afterId = 0, int pageSize = 200}) async* {
    if (!await hasPermission()) return;
    var cursor = afterId;
    while (true) {
      final rows = await _channel.invokeListMethod<Map>('query', {
            'sinceMillis': since.millisecondsSinceEpoch,
            'afterId': cursor,
            'limit': pageSize,
          }) ??
          const [];
      if (rows.isEmpty) break;
      final page = rows.map(_toRaw).toList();
      yield page;
      cursor = int.tryParse(page.last.id) ?? cursor;
      if (rows.length < pageSize) break;
    }
  }

  /// Live incoming SMS while the app is running.
  Stream<RawMessage> incoming() => _events.receiveBroadcastStream().map((e) => _toRaw(e as Map));

  RawMessage _toRaw(Map m) => RawMessage(
        id: m['id'].toString(),
        source: TxSource.sms,
        sender: (m['address'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        receivedAt: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
      );
}
