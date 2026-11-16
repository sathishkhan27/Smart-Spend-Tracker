import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// On-device store for sync bookkeeping:
/// * `processed_messages` – makes SMS/email processing idempotent & incremental
/// * `outbox` – offline queue of transactions waiting to be written to Firestore
/// * `cursors` – per-source sync checkpoints (last SMS id, Gmail historyId)
///
/// Raw message bodies are never persisted here.
class LocalStore {
  LocalStore._(this._db);
  final Database _db;

  static Future<LocalStore> open({String name = 'smart_spend.db'}) async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, name),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE processed_messages(
            source_key TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            status TEXT NOT NULL,
            tx_id TEXT,
            processed_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE outbox(
            tx_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            op TEXT NOT NULL,
            payload TEXT NOT NULL,
            private_payload TEXT,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (tx_id, user_id)
          )''');
        await db.execute('CREATE TABLE cursors(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    );
    return LocalStore._(db);
  }

  // ---- processed messages ----
  Future<Set<String>> processedKeys(String userId, Iterable<String> keys) async {
    final list = keys.toList();
    final out = <String>{};
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
      final rows = await _db.query('processed_messages',
          columns: ['source_key'],
          where: 'user_id = ? AND source_key IN (${List.filled(chunk.length, '?').join(',')})',
          whereArgs: [userId, ...chunk]);
      out.addAll(rows.map((r) => r['source_key'] as String));
    }
    return out;
  }

  /// Saved transaction id for each of [keys] that produced one.
  Future<Map<String, String>> processedTxIds(String userId, Iterable<String> keys) async {
    final list = keys.toList();
    final out = <String, String>{};
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
      final rows = await _db.query('processed_messages',
          columns: ['source_key', 'tx_id'],
          where: 'user_id = ? AND tx_id IS NOT NULL AND source_key IN (${List.filled(chunk.length, '?').join(',')})',
          whereArgs: [userId, ...chunk]);
      for (final r in rows) {
        out[r['source_key'] as String] = r['tx_id'] as String;
      }
    }
    return out;
  }

  Future<void> markProcessed(String userId, Map<String, ({String status, String? txId})> entries) async {
    final batch = _db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    entries.forEach((key, v) {
      batch.insert('processed_messages', {'source_key': key, 'user_id': userId, 'status': v.status, 'tx_id': v.txId, 'processed_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  // ---- outbox ----
  Future<void> enqueue(OutboxEntry e) => _db.insert(
        'outbox',
        {
          'tx_id': e.txId,
          'user_id': e.userId,
          'op': e.op,
          'payload': jsonEncode(e.payload),
          'private_payload': e.privatePayload == null ? null : jsonEncode(e.privatePayload),
          'attempts': 0,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<OutboxEntry>> pending(String userId, {int limit = 200}) async {
    final rows = await _db.query('outbox', where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at ASC', limit: limit);
    return rows
        .map((r) => OutboxEntry(
              txId: r['tx_id'] as String,
              userId: r['user_id'] as String,
              op: r['op'] as String,
              payload: jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              privatePayload: r['private_payload'] == null ? null : jsonDecode(r['private_payload'] as String) as Map<String, dynamic>,
              attempts: r['attempts'] as int,
            ))
        .toList();
  }

  Future<int> pendingCount(String userId) async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM outbox WHERE user_id = ?', [userId])) ?? 0;

  Future<void> removeFromOutbox(String userId, String txId) =>
      _db.delete('outbox', where: 'user_id = ? AND tx_id = ?', whereArgs: [userId, txId]);

  Future<void> markAttempt(String userId, String txId, String error) => _db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE user_id = ? AND tx_id = ?', [error, userId, txId]);

  // ---- cursors ----
  Future<String?> cursor(String key) async {
    final rows = await _db.query('cursors', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setCursor(String key, String value) =>
      _db.insert('cursors', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Forgets messages that were skipped (status "ignored") so an improved
  /// parser can read them again. Processed transactions are kept.
  Future<int> forgetIgnored(String userId) =>
      _db.delete('processed_messages', where: 'user_id = ? AND status = ?', whereArgs: [userId, 'ignored']);

  Future<void> clearUser(String userId) async {
    await _db.delete('processed_messages', where: 'user_id = ?', whereArgs: [userId]);
    await _db.delete('outbox', where: 'user_id = ?', whereArgs: [userId]);
    await _db.delete('cursors', where: 'key LIKE ?', whereArgs: ['$userId:%']);
  }
}

class OutboxEntry {
  const OutboxEntry({
    required this.txId,
    required this.userId,
    required this.op,
    required this.payload,
    this.privatePayload,
    this.attempts = 0,
  });

  static const create = 'create';
  static const merge = 'merge';

  final String txId;
  final String userId;

  /// [create] or [merge].
  final String op;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? privatePayload;
  final int attempts;
}
