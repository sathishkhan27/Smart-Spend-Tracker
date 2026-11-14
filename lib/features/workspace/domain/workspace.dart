enum WorkspaceRole { admin, member }

class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.ownerId,
    this.timezone = 'Asia/Kolkata',
    this.currency = 'INR',
    this.memberCount = 1,
  });

  final String id;
  final String name;
  final String ownerId;
  final String timezone;
  final String currency;
  final int memberCount;
}

class WorkspaceMember {
  const WorkspaceMember({
    required this.workspaceId,
    required this.userId,
    required this.role,
    this.displayName,
    this.email,
    this.joinedAt,
  });

  static String docId(String workspaceId, String userId) => '${workspaceId}_$userId';

  final String workspaceId;
  final String userId;
  final WorkspaceRole role;
  final String? displayName;
  final String? email;
  final DateTime? joinedAt;

  bool get isAdmin => role == WorkspaceRole.admin;
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    this.displayName,
    this.phone,
    this.activeWorkspaceId,
    this.timezone = 'Asia/Kolkata',
    this.currency = 'INR',
    this.smsConsent = false,
    this.emailConsent = false,
    this.onboardingComplete = false,
    this.initialSyncComplete = false,
    this.themeMode = 'light',
    this.notificationPrefs = const {},
  });

  final String uid;
  final String email;
  final String? displayName;
  final String? phone;
  final String? activeWorkspaceId;
  final String timezone;
  final String currency;
  final bool smsConsent;
  final bool emailConsent;
  final bool onboardingComplete;
  final bool initialSyncComplete;
  final String themeMode;
  final Map<String, bool> notificationPrefs;

  String get firstName => (displayName ?? email).split(RegExp(r'[\s@]')).first;
  String get initials {
    final parts = (displayName ?? email).trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.first.isEmpty ? '?' : parts.first[0].toUpperCase();
  }

  bool pref(String key) => notificationPrefs[key] ?? true;
}

/// Notification preference keys (shared with Cloud Functions).
abstract final class NotificationPrefKeys {
  static const newTransaction = 'newTransaction';
  static const syncCompleted = 'syncCompleted';
  static const upcomingPayments = 'upcomingPayments';
  static const uncategorized = 'uncategorized';
  static const syncFailed = 'syncFailed';
  static const unusualSpending = 'unusualSpending';
  static const workspaceActivity = 'workspaceActivity';

  static const labels = {
    newTransaction: 'New transaction detected',
    syncCompleted: 'Sync completed',
    upcomingPayments: 'Upcoming EMI, rent, bills & card payments',
    uncategorized: 'Uncategorized transactions',
    syncFailed: 'Failed synchronization',
    unusualSpending: 'Unusual spending',
    workspaceActivity: 'Shared workspace activity',
  };
}
