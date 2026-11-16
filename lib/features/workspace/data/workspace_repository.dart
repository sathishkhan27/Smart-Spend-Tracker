import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/failures.dart';
import '../domain/workspace.dart';

/// Users, workspaces and membership.
class WorkspaceRepository {
  WorkspaceRepository(this._db, this._functions);
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _workspaces => _db.collection('workspaces');
  CollectionReference<Map<String, dynamic>> get _members => _db.collection('workspace_members');

  // ---------------- Profile ----------------

  Stream<UserProfile?> watchProfile(String uid) =>
      _users.doc(uid).snapshots().map((s) => s.exists ? _profile(s.id, s.data()!) : null);

  Future<UserProfile?> getProfile(String uid) async {
    final s = await _users.doc(uid).get();
    return s.exists ? _profile(s.id, s.data()!) : null;
  }

  /// Creates the user profile and a personal workspace on first sign-in.
  /// Idempotent: does nothing if the profile already exists.
  Future<void> ensureProfile(User user) async {
    try {
      final ref = _users.doc(user.uid);
      final snap = await ref.get();
      if (snap.exists) return;
      final wsRef = _workspaces.doc();
      final name = user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : user.email!.split('@').first;
      final batch = _db.batch();
      batch.set(wsRef, {
        'name': "$name's Workspace",
        'ownerId': user.uid,
        'timezone': 'Asia/Kolkata',
        'currency': 'INR',
        'memberCount': 1,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(_members.doc(WorkspaceMember.docId(wsRef.id, user.uid)), {
        'workspaceId': wsRef.id,
        'userId': user.uid,
        'role': WorkspaceRole.admin.name,
        'displayName': name,
        'email': user.email,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      batch.set(ref, {
        'email': user.email,
        'displayName': name,
        'activeWorkspaceId': wsRef.id,
        'timezone': 'Asia/Kolkata',
        'currency': 'INR',
        'consents': {},
        'onboardingComplete': false,
        'initialSyncComplete': false,
        'themeMode': 'light',
        'notificationPrefs': {},
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<void> updateProfile(String uid, Map<String, Object?> fields) async {
    try {
      await _users.doc(uid).set({...fields, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Consent is recorded with timestamp, scope and policy version for audit.
  Future<void> recordConsent(String uid, {required String source, required bool granted, String? scope}) async {
    try {
      await _users.doc(uid).update({
        'consents.$source': {
          'granted': granted,
          'scope': scope,
          'policyVersion': '2026-01',
          'at': FieldValue.serverTimestamp(),
        },
        'consentHistory': FieldValue.arrayUnion([
          {'source': source, 'granted': granted, 'scope': scope, 'at': Timestamp.now()},
        ]),
      });
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Registers this phone for push under users/{uid}/devices/{deviceId}.
  /// A refreshed token overwrites the same device entry (no duplicates).
  Future<void> registerDevice(String uid, {required String deviceId, required String token, required String platform}) async {
    await _users.doc(uid).collection('devices').doc(deviceId).set({
      'token': token,
      'platform': platform,
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // Clean up the legacy token list written by older builds.
    await _users.doc(uid).update({'fcmTokens': FieldValue.arrayRemove([token])}).catchError((Object _) {});
  }

  /// Stops pushes to this phone (called before signing out).
  Future<void> unregisterDevice(String uid, String deviceId) => _users.doc(uid).collection('devices').doc(deviceId).delete();

  // ---------------- Workspaces ----------------

  Stream<List<WorkspaceMember>> watchMemberships(String uid) => _members
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((q) => q.docs.map((d) => _member(d.data())).toList());

  Stream<Workspace?> watchWorkspace(String id) =>
      _workspaces.doc(id).snapshots().map((s) => s.exists ? _workspace(s.id, s.data()!) : null);

  Future<List<Workspace>> getWorkspaces(List<String> ids) async {
    if (ids.isEmpty) return [];
    final out = <Workspace>[];
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, min(i + 10, ids.length));
      final q = await _workspaces.where(FieldPath.documentId, whereIn: chunk).get();
      out.addAll(q.docs.map((d) => _workspace(d.id, d.data())));
    }
    return out;
  }

  Stream<List<WorkspaceMember>> watchMembers(String workspaceId) => _members
      .where('workspaceId', isEqualTo: workspaceId)
      .snapshots()
      .map((q) => q.docs.map((d) => _member(d.data())).toList()..sort((a, b) => a.role.index.compareTo(b.role.index)));

  Future<void> renameWorkspace(String id, String name) => _workspaces.doc(id).update({'name': name});

  /// Admin-only: creates a short-lived invite code. Joining is done server-side
  /// (`joinWorkspace` callable) so clients can never add themselves directly.
  Future<String> createInvite(String workspaceId, String createdBy) async {
    try {
      const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rnd = Random.secure();
      final code = List.generate(8, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
      await _db.collection('workspace_invites').doc(code).set({
        'workspaceId': workspaceId,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
        'role': WorkspaceRole.member.name,
      });
      return code;
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<String> joinWithCode(String code) async {
    try {
      final res = await _functions.httpsCallable('joinWorkspace').call({'code': code.trim().toUpperCase()});
      return (res.data as Map)['workspaceId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw AppFailure(e.message ?? 'Could not join workspace', code: e.code);
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<void> setMemberRole(String workspaceId, String userId, WorkspaceRole role) =>
      _members.doc(WorkspaceMember.docId(workspaceId, userId)).update({'role': role.name});

  Future<void> removeMember(String workspaceId, String userId) async {
    try {
      await _functions.httpsCallable('removeWorkspaceMember').call({'workspaceId': workspaceId, 'userId': userId});
    } on FirebaseFunctionsException catch (e) {
      throw AppFailure(e.message ?? 'Could not remove member', code: e.code);
    }
  }

  /// Server-side deletion of the user's contributed data and account.
  Future<void> requestDataDeletion() async {
    try {
      await _functions.httpsCallable('deleteMyData').call();
    } on FirebaseFunctionsException catch (e) {
      throw AppFailure(e.message ?? 'Could not process deletion request', code: e.code);
    }
  }

  // ---------------- Mapping ----------------

  UserProfile _profile(String uid, Map<String, dynamic> d) {
    final consents = (d['consents'] as Map?) ?? const {};
    bool granted(String k) => (consents[k] as Map?)?['granted'] == true;
    return UserProfile(
      uid: uid,
      email: d['email'] as String? ?? '',
      displayName: d['displayName'] as String?,
      phone: d['phone'] as String?,
      activeWorkspaceId: d['activeWorkspaceId'] as String?,
      timezone: d['timezone'] as String? ?? 'Asia/Kolkata',
      currency: d['currency'] as String? ?? 'INR',
      smsConsent: granted('sms'),
      emailConsent: granted('gmail'),
      onboardingComplete: d['onboardingComplete'] as bool? ?? false,
      initialSyncComplete: d['initialSyncComplete'] as bool? ?? false,
      themeMode: d['themeMode'] as String? ?? 'light',
      notificationPrefs: Map<String, bool>.from((d['notificationPrefs'] as Map?) ?? const {}),
      monthlyBudget: (d['monthlyBudget'] as num?)?.toDouble(),
      budgetAlerts: {
        for (final e in ((d['budgetAlerts'] as Map?) ?? const {}).entries)
          if (e.value is num) e.key as String: (e.value as num).toInt(),
      },
    );
  }

  Workspace _workspace(String id, Map<String, dynamic> d) => Workspace(
        id: id,
        name: d['name'] as String? ?? 'Workspace',
        ownerId: d['ownerId'] as String? ?? '',
        timezone: d['timezone'] as String? ?? 'Asia/Kolkata',
        currency: d['currency'] as String? ?? 'INR',
        memberCount: (d['memberCount'] as num?)?.toInt() ?? 1,
      );

  WorkspaceMember _member(Map<String, dynamic> d) => WorkspaceMember(
        workspaceId: d['workspaceId'] as String,
        userId: d['userId'] as String,
        role: d['role'] == 'admin' ? WorkspaceRole.admin : WorkspaceRole.member,
        displayName: d['displayName'] as String?,
        email: d['email'] as String?,
        joinedAt: (d['joinedAt'] as Timestamp?)?.toDate(),
      );
}
