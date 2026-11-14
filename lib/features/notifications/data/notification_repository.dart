import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/notification_kind.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.read = false,
    this.route,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final bool read;
  final String? route;

  NotificationKind get kind => NotificationKind.fromType(type);
}

class NotificationRepository {
  NotificationRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('notifications');

  Stream<List<AppNotification>> watch(String uid, {int limit = 50}) => _col
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs
          .map((d) => AppNotification(
                id: d.id,
                title: d['title'] as String? ?? '',
                body: d['body'] as String? ?? '',
                type: d['type'] as String? ?? 'info',
                createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                read: d['read'] as bool? ?? false,
                route: d.data()['route'] as String?,
              ))
          .toList());

  /// [fanout] asks the server to push this to the user's other phones
  /// (all registered devices except [originDevice], which already showed it).
  Future<void> add(
    String uid, {
    required String title,
    required String body,
    required String type,
    String? route,
    List<String> lines = const [],
    bool fanout = false,
    String? originDevice,
  }) =>
      _col.add({
        'userId': uid,
        'title': title,
        'body': body,
        'type': type,
        'route': route,
        if (lines.isNotEmpty) 'lines': lines,
        if (fanout) 'fanout': true,
        'originDevice': ?originDevice,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> markRead(String id) => _col.doc(id).update({'read': true});

  Future<void> delete(String id) => _col.doc(id).delete();

  Future<void> markAllRead(String uid) async {
    final q = await _col.where('userId', isEqualTo: uid).where('read', isEqualTo: false).limit(400).get();
    final batch = _db.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }
}
