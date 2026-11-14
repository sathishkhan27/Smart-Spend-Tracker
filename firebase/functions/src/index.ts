import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { setGlobalOptions, logger } from 'firebase-functions/v2';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { advance, contribution, daysUntil, OVERDUE_GRACE_DAYS, reminderFor, statDelta, TxData } from './stats';

initializeApp();
setGlobalOptions({ region: 'asia-south1', maxInstances: 10 });
const db = getFirestore();
const inc = (n: number) => FieldValue.increment(n);

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

type PrefKey = 'newTransaction' | 'syncCompleted' | 'upcomingPayments' | 'uncategorized' | 'syncFailed' | 'unusualSpending' | 'workspaceActivity';

// Must match NotificationChannel / NotificationKind in the app
// (lib/features/notifications/domain/notification_kind.dart).
// v2 channels play the app's custom "ding" (res/raw/notification_ding.mp3).
const channelFor = (type: string): string =>
  ({ upcoming: 'ss_reminders_v2', overdue: 'ss_alerts_v2', unusual: 'ss_alerts_v2', workspace: 'ss_workspace_v2', sync: 'ss_sync' } as Record<string, string>)[type] ??
  'ss_transactions_v2';
const NOTIFICATION_SOUND = 'notification_ding';
const IOS_NOTIFICATION_SOUND = 'notification_ding.caf';
const colorFor = (type: string): string =>
  ({ upcoming: '#E09A1F', overdue: '#E05252', unusual: '#EB6834', workspace: '#6250D6', uncategorized: '#7B8495' } as Record<string, string>)[type] ??
  '#3478F6';

/** Push targets for a user: one token per registered phone
 *  (users/{uid}/devices/{deviceId}) plus tokens from older builds. */
async function pushTargets(uid: string, legacy: string[] = [], excludeDevice?: string): Promise<{ token: string; device?: string }[]> {
  const devices = await db.collection('users').doc(uid).collection('devices').get();
  const seen = new Set<string>();
  const out: { token: string; device?: string }[] = [];
  for (const d of devices.docs) {
    const token = d.data().token as string | undefined;
    if (!token || d.id === excludeDevice || seen.has(token)) continue;
    seen.add(token);
    out.push({ token, device: d.id });
  }
  for (const token of legacy) {
    if (!seen.has(token)) {
      seen.add(token);
      out.push({ token });
    }
  }
  return out;
}

/** Sends one push to every target; removes tokens that no longer exist. */
async function sendPush(
  uid: string,
  targets: { token: string; device?: string }[],
  msg: { title: string; body: string; type: string; route?: string; tag?: string },
): Promise<void> {
  if (targets.length === 0) return;
  const res = await getMessaging().sendEachForMulticast({
    tokens: targets.map((t) => t.token),
    notification: { title: msg.title, body: msg.body },
    data: { type: msg.type, route: msg.route ?? '', tag: msg.tag ?? '' },
    android: {
      priority: 'high',
      notification: {
        channelId: channelFor(msg.type),
        // Android 7 and older read the sound from the message; 8+ from the channel.
        ...(msg.type === 'sync' ? {} : { sound: NOTIFICATION_SOUND }),
        icon: 'ic_notification',
        color: colorFor(msg.type),
        ...(msg.tag ? { tag: msg.tag } : {}),
      },
    },
    apns: {
      headers: { 'apns-priority': '10', ...(msg.tag ? { 'apns-collapse-id': msg.tag } : {}) },
      payload: { aps: { 'thread-id': msg.type, ...(msg.type === 'sync' ? {} : { sound: IOS_NOTIFICATION_SOUND }) } },
    },
  });
  logger.info('push', { uid, targets: targets.length, sent: res.successCount, failed: res.failureCount });
  const dead = ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'];
  const userRef = db.collection('users').doc(uid);
  await Promise.all(
    res.responses.map(async (r, i) => {
      if (r.success || !dead.includes(r.error?.code ?? '')) return;
      const t = targets[i];
      if (t.device) await userRef.collection('devices').doc(t.device).delete();
      else await userRef.update({ fcmTokens: FieldValue.arrayRemove(t.token) });
    }),
  );
}

async function notifyUser(uid: string, pref: PrefKey, title: string, body: string, type: string, route?: string, tag?: string): Promise<void> {
  const user = await db.collection('users').doc(uid).get();
  const data = user.data();
  if (!data) return;
  if ((data.notificationPrefs ?? {})[pref] === false) return;
  await db.collection('notifications').add({ userId: uid, title, body, type, route: route ?? null, read: false, createdAt: FieldValue.serverTimestamp() });
  // Every phone the user is signed in on.
  await sendPush(uid, await pushTargets(uid, data.fcmTokens ?? []), { title, body, type, route, tag });
}

// ---------------------------------------------------------------------------
// "Send test notification" (Profile → Notifications): pushes to every phone
// the caller is signed in on, so delivery in foreground/background can be checked.
// ---------------------------------------------------------------------------

export const sendTestNotification = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const user = await db.collection('users').doc(uid).get();
  const targets = await pushTargets(uid, user.data()?.fcmTokens ?? []);
  const title = 'Test notification';
  const body = targets.length > 1 ? `Delivered to your ${targets.length} phones` : 'Notifications are working on this phone';
  await db.collection('notifications').add({ userId: uid, title, body, type: 'transaction', route: '/notifications', read: false, createdAt: FieldValue.serverTimestamp() });
  await sendPush(uid, targets, { title, body, type: 'transaction', route: '/notifications', tag: 'test' });
  return { devices: targets.length };
});

// ---------------------------------------------------------------------------
// Sync summaries written by the app ("3 new transactions …") are pushed to the
// user's OTHER phones; the phone that synced already showed it locally.
// ---------------------------------------------------------------------------

export const onNotificationCreated = onDocumentCreated('notifications/{id}', async (event) => {
  const n = event.data?.data();
  if (!n || n.fanout !== true || typeof n.userId !== 'string') return;
  const user = await db.collection('users').doc(n.userId).get();
  const data = user.data();
  if (!data || (data.notificationPrefs ?? {}).newTransaction === false) return;
  const lines: string[] = Array.isArray(n.lines) ? n.lines.slice(0, 5) : [];
  const body = [n.body as string, ...lines].filter(Boolean).join('\n');
  const targets = await pushTargets(n.userId, data.fcmTokens ?? [], n.originDevice as string | undefined);
  await sendPush(n.userId, targets, { title: n.title as string, body, type: (n.type as string) ?? 'transaction', route: n.route ?? undefined, tag: 'tx_summary' });
});

const money = (n: number, c: string) => `${c === 'INR' ? '₹' : c + ' '}${Math.round(n).toLocaleString('en-IN')}`;

// ---------------------------------------------------------------------------
// Transaction trigger: aggregates, counterparties, notifications, cleanup
// ---------------------------------------------------------------------------

export const onTransactionWritten = onDocumentWritten('transactions/{txId}', async (event) => {
  const before = event.data?.before.data() as TxData | undefined;
  const after = event.data?.after.data() as (TxData & Record<string, unknown>) | undefined;
  const wid = (after ?? before)?.workspaceId;
  if (!wid) return;

  // 1. Incremental monthly aggregates (exactly-once per change via delta).
  const oldC = contribution(before);
  const newC = contribution(after);
  const statsCol = db.collection('workspaces').doc(wid).collection('monthly_stats');
  const batch = db.batch();
  if (oldC) batch.set(statsCol.doc(oldC.statId), statDelta(oldC, -1, inc), { merge: true });
  if (newC) batch.set(statsCol.doc(newC.statId), { ...statDelta(newC, 1, inc), updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  // 2. Counterparty directory.
  if (newC?.counterparty && !oldC) {
    batch.set(
      db.collection('counterparties').doc(`${wid}_${newC.counterparty.key.replace(/\s+/g, '_')}`),
      { workspaceId: wid, name: newC.counterparty.name, totalSpent: inc(newC.outflow), count: inc(1), lastSeenAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }
  if (oldC || newC) await batch.commit();

  // 3. Cleanup private source docs on delete.
  if (before && !after) {
    const privates = await db.collection('transactions').doc(event.params.txId).collection('private').listDocuments();
    await Promise.all(privates.map((d) => d.delete()));
    return;
  }

  // 4. Notifications for newly created records only.
  if (!before && after) {
    const amount = after.amount as number;
    const currency = after.currency as string;
    const owner = after.ownerUserId as string;
    const name = (after.counterparty as string) ?? (after.merchant as string) ?? 'a transaction';
    const route = `/transactions/view/${event.params.txId}`;

    // Shared workspace activity → other members.
    const members = await db.collection('workspace_members').where('workspaceId', '==', wid).get();
    await Promise.all(
      members.docs
        .map((m) => m.data().userId as string)
        .filter((u) => u !== owner)
        .map((u) =>
          notifyUser(u, 'workspaceActivity', `${(after.ownerName as string) ?? 'A member'} added a transaction`,
            `${after.direction === 'inflow' ? 'Received' : 'Spent'} ${money(amount, currency)} • ${name}`, 'workspace', route),
        ),
    );

    // Uncategorized → owner.
    if (after.categoryId === 'others' || after.status === 'needsReview') {
      await notifyUser(owner, 'uncategorized', 'Transaction needs a category', `${money(amount, currency)} • ${name}`, 'uncategorized', route);
    }

    // Unusual spending: > 3× the category's average monthly spend (last 3 months) and above a floor.
    if (after.direction === 'outflow' && after.status === 'success' && amount >= 2000) {
      const [y, m] = (after.monthKey as string).split('-').map(Number);
      const keys = [1, 2, 3].map((k) => {
        const d = new Date(Date.UTC(y, m - 1 - k, 1));
        return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}_${currency}`;
      });
      const stats = await Promise.all(keys.map((k) => statsCol.doc(k).get()));
      const amounts = stats.map((s) => (s.data()?.categories?.[after.categoryId as string]?.amount as number) ?? 0);
      const avg = amounts.reduce((a, b) => a + b, 0) / 3;
      if (avg > 0 && amount > avg * 3) {
        await notifyUser(owner, 'unusualSpending', 'Unusual spending detected',
          `${money(amount, currency)} on ${after.categoryName} is well above your usual ${money(avg, currency)}/month`, 'unusual', route);
      }
    }
  }
});

// ---------------------------------------------------------------------------
// Workspace membership (server-side so clients can never add themselves)
// ---------------------------------------------------------------------------

export const joinWorkspace = onCall({ enforceAppCheck: false }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (!req.auth?.token.email_verified) throw new HttpsError('permission-denied', 'Verify your email first.');
  const code = String(req.data?.code ?? '').trim().toUpperCase();
  if (!/^[A-Z0-9]{6,12}$/.test(code)) throw new HttpsError('invalid-argument', 'Invalid invite code.');

  return db.runTransaction(async (t) => {
    const inviteRef = db.collection('workspace_invites').doc(code);
    const invite = await t.get(inviteRef);
    if (!invite.exists) throw new HttpsError('not-found', 'Invite code not found.');
    const inv = invite.data()!;
    if ((inv.expiresAt as Timestamp).toMillis() < Date.now()) throw new HttpsError('failed-precondition', 'This invite has expired.');
    const wid = inv.workspaceId as string;
    const memberRef = db.collection('workspace_members').doc(`${wid}_${uid}`);
    if ((await t.get(memberRef)).exists) return { workspaceId: wid };
    const user = await getAuth().getUser(uid);
    t.set(memberRef, {
      workspaceId: wid, userId: uid, role: 'member', displayName: user.displayName ?? null, email: user.email ?? null,
      joinedAt: FieldValue.serverTimestamp(), invitedBy: inv.createdBy,
    });
    t.update(db.collection('workspaces').doc(wid), { memberCount: FieldValue.increment(1) });
    return { workspaceId: wid };
  });
});

export const removeWorkspaceMember = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const { workspaceId, userId } = req.data ?? {};
  const me = await db.collection('workspace_members').doc(`${workspaceId}_${uid}`).get();
  if (me.data()?.role !== 'admin') throw new HttpsError('permission-denied', 'Only admins can remove members.');
  if (userId === uid) throw new HttpsError('failed-precondition', 'Admins cannot remove themselves.');
  const ref = db.collection('workspace_members').doc(`${workspaceId}_${userId}`);
  if (!(await ref.get()).exists) return { ok: true };
  await ref.delete();
  await db.collection('workspaces').doc(workspaceId).update({ memberCount: FieldValue.increment(-1) });
  // Their contributed transactions stay with them: remove from this workspace view.
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Data deletion request
// ---------------------------------------------------------------------------

export const deleteMyData = onCall({ timeoutSeconds: 540, memory: '512MiB' }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');

  const deleteQuery = async (q: FirebaseFirestore.Query) => {
    for (;;) {
      const snap = await q.limit(300).get();
      if (snap.empty) break;
      await Promise.all(snap.docs.map((d) => db.recursiveDelete(d.ref)));
    }
  };

  await deleteQuery(db.collection('transactions').where('ownerUserId', '==', uid)); // triggers aggregate reversal
  await deleteQuery(db.collection('connected_accounts').where('userId', '==', uid));
  await deleteQuery(db.collection('sync_logs').where('userId', '==', uid));
  await deleteQuery(db.collection('notifications').where('userId', '==', uid));

  const memberships = await db.collection('workspace_members').where('userId', '==', uid).get();
  for (const m of memberships.docs) {
    const wid = m.data().workspaceId as string;
    const others = await db.collection('workspace_members').where('workspaceId', '==', wid).get();
    const remaining = others.docs.filter((d) => d.id !== m.id);
    if (remaining.length === 0) {
      await deleteQuery(db.collection('recurring_expenses').where('workspaceId', '==', wid));
      await deleteQuery(db.collection('transaction_rules').where('workspaceId', '==', wid));
      await db.recursiveDelete(db.collection('workspaces').doc(wid));
    } else {
      if (m.data().role === 'admin' && !remaining.some((d) => d.data().role === 'admin')) {
        await remaining[0].ref.update({ role: 'admin' });
        await db.collection('workspaces').doc(wid).update({ ownerId: remaining[0].data().userId });
      }
      await db.collection('workspaces').doc(wid).update({ memberCount: FieldValue.increment(-1) });
    }
    await m.ref.delete();
  }
  // Removes the profile and its registered devices (push tokens).
  await db.recursiveDelete(db.collection('users').doc(uid));
  await db.collection('data_deletion_audit').add({ userId: uid, completedAt: FieldValue.serverTimestamp() });
  await getAuth().deleteUser(uid);
  logger.info('Deleted user data', { uid });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Daily reminders for upcoming recurring payments
// ---------------------------------------------------------------------------

export const dailyReminders = onSchedule({ schedule: 'every day 09:00', timeZone: 'Asia/Kolkata' }, async () => {
  const now = new Date();
  // Dues up to 3 days ahead (2-day reminder + timezone slack); overdue ones are older.
  const horizon = new Date(now.getTime() + 3 * 86400000);
  const due = await db
    .collection('recurring_expenses')
    .where('status', '==', 'active')
    .where('reminderEnabled', '==', true)
    .where('nextDueDate', '<=', Timestamp.fromDate(horizon))
    .get();

  const tzCache = new Map<string, string>();
  const tzOf = async (wid: string) => {
    if (!tzCache.has(wid)) tzCache.set(wid, ((await db.collection('workspaces').doc(wid).get()).data()?.timezone as string) ?? 'Asia/Kolkata');
    return tzCache.get(wid)!;
  };

  for (const doc of due.docs) {
    const r = doc.data();
    const tz = await tzOf(r.workspaceId);
    let next = (r.nextDueDate as Timestamp).toDate();
    let days = daysUntil(next, now, tz);
    // Past the overdue grace period: treat as missed and roll to the next period.
    if (days < -OVERDUE_GRACE_DAYS) {
      let guard = 0;
      while (daysUntil(next, now, tz) < 0 && guard++ < 100) next = advance(next, r.frequency);
      await doc.ref.update({ nextDueDate: Timestamp.fromDate(next) });
      days = daysUntil(next, now, tz);
    }

    const reminder = reminderFor(days);
    if (!reminder) continue;
    const label = r.categoryId === 'loan_emi' ? 'EMI' : r.categoryId === 'rent' ? 'Rent' : r.categoryId === 'credit_card_payment' ? 'Credit card payment' : r.categoryId === 'subscriptions' ? 'Subscription' : 'Bill';
    const title = reminder.title(label);
    const body = `${r.name}: ${money(r.expectedAmount, r.currency ?? 'INR')}${days < 0 ? ' • tap to mark as paid' : ''}`;
    const members = await db.collection('workspace_members').where('workspaceId', '==', r.workspaceId).get();
    await Promise.all(
      members.docs.map((m) => notifyUser(m.data().userId, 'upcomingPayments', title, body, days < 0 ? 'overdue' : 'upcoming', '/upcoming', `due_${doc.id}`)),
    );
  }
});
