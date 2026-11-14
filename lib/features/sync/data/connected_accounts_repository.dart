import 'package:cloud_firestore/cloud_firestore.dart';

enum SourceProvider { sms, gmail, outlook }

enum ConnectionStatus { connected, needsReauth, disconnected, error }

class ConnectedAccount {
  const ConnectedAccount({
    required this.provider,
    required this.status,
    this.identifier,
    this.lastSyncAt,
    this.lastError,
    this.messagesScanned = 0,
    this.transactionsFound = 0,
  });

  final SourceProvider provider;
  final ConnectionStatus status;
  final String? identifier;
  final DateTime? lastSyncAt;
  final String? lastError;
  final int messagesScanned;
  final int transactionsFound;

  bool get isConnected => status == ConnectionStatus.connected;
}

/// `connected_accounts/{uid}_{provider}` – owner-only. Holds connection
/// status and sync metadata, never OAuth tokens.
class ConnectedAccountsRepository {
  ConnectedAccountsRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('connected_accounts');

  Stream<List<ConnectedAccount>> watch(String uid) => _col.where('userId', isEqualTo: uid).snapshots().map(
        (q) => q.docs
            .map((d) => ConnectedAccount(
                  provider: SourceProvider.values.firstWhere((p) => p.name == d['provider'], orElse: () => SourceProvider.sms),
                  status: ConnectionStatus.values.firstWhere((s) => s.name == d['status'], orElse: () => ConnectionStatus.disconnected),
                  identifier: d.data()['identifier'] as String?,
                  lastSyncAt: (d.data()['lastSyncAt'] as Timestamp?)?.toDate(),
                  lastError: d.data()['lastError'] as String?,
                  messagesScanned: (d.data()['messagesScanned'] as num?)?.toInt() ?? 0,
                  transactionsFound: (d.data()['transactionsFound'] as num?)?.toInt() ?? 0,
                ))
            .toList(),
      );

  Future<void> upsert(String uid, String workspaceId, SourceProvider p, ConnectionStatus s,
          {String? identifier, String? error, int? scanned, int? found, bool synced = false}) =>
      _col.doc('${uid}_${p.name}').set({
        'userId': uid,
        'workspaceId': workspaceId,
        'provider': p.name,
        'status': s.name,
        'identifier': ?identifier,
        'lastError': error,
        if (scanned != null) 'messagesScanned': FieldValue.increment(scanned),
        if (found != null) 'transactionsFound': FieldValue.increment(found),
        if (synced) 'lastSyncAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> log(String uid, String workspaceId, Map<String, Object?> entry) => _db.collection('sync_logs').add({
        'userId': uid,
        'workspaceId': workspaceId,
        ...entry,
        'createdAt': FieldValue.serverTimestamp(),
      });
}
