/** Pure helpers for incremental monthly aggregates (unit-tested). */

export interface TxData {
  workspaceId: string;
  ownerUserId: string;
  ownerName?: string | null;
  amount: number;
  currency: string;
  direction: 'inflow' | 'outflow';
  status: string;
  isInternalTransfer?: boolean;
  categoryId: string;
  paymentMode?: string;
  bankName?: string | null;
  counterparty?: string | null;
  merchant?: string | null;
  monthKey: string;
}

export interface Contribution {
  statId: string;
  monthKey: string;
  currency: string;
  inflow: number;
  outflow: number;
  refunds: number;
  categoryId: string;
  paymentMode?: string;
  bankKey?: string;
  user: { id: string; name: string };
  counterparty?: { key: string; name: string };
}

const PAYMENT_LABELS: Record<string, string> = {
  upi: 'UPI', neft: 'NEFT', imps: 'IMPS', rtgs: 'RTGS', debitCard: 'Debit Card', creditCard: 'Credit Card',
  netBanking: 'Net Banking', atm: 'ATM', cash: 'Cash', wallet: 'Wallet', autoDebit: 'Auto Debit', cheque: 'Cheque', other: 'Other',
};

export const safeKey = (s: string): string => s.replace(/[^A-Za-z0-9 _-]/g, '').trim().slice(0, 60) || 'Unknown';

/** What a transaction contributes to totals; null when it must be excluded. */
export function contribution(d: TxData | undefined | null): Contribution | null {
  if (!d || d.status !== 'success' || d.isInternalTransfer) return null;
  if (typeof d.amount !== 'number' || !d.monthKey) return null;
  const inflow = d.direction === 'inflow' ? d.amount : 0;
  const outflow = d.direction === 'outflow' ? d.amount : 0;
  const cp = d.counterparty ?? d.merchant;
  return {
    statId: `${d.monthKey}_${d.currency}`,
    monthKey: d.monthKey,
    currency: d.currency,
    inflow,
    outflow,
    refunds: d.categoryId === 'refund' ? inflow : 0,
    categoryId: d.categoryId,
    paymentMode: outflow > 0 ? PAYMENT_LABELS[d.paymentMode ?? 'other'] ?? 'Other' : undefined,
    bankKey: outflow > 0 ? safeKey(d.bankName ?? 'Unknown') : undefined,
    user: { id: d.ownerUserId, name: d.ownerName ?? 'Member' },
    counterparty: outflow > 0 && cp ? { key: safeKey(cp.toLowerCase()), name: cp } : undefined,
  };
}

/** Builds a Firestore merge payload; `inc` wraps numbers in FieldValue.increment. */
export function statDelta(c: Contribution, sign: 1 | -1, inc: (n: number) => unknown): Record<string, unknown> {
  const amount = c.inflow + c.outflow;
  const payload: Record<string, unknown> = {
    monthKey: c.monthKey,
    currency: c.currency,
    inflow: inc(sign * c.inflow),
    outflow: inc(sign * c.outflow),
    refunds: inc(sign * c.refunds),
    count: inc(sign),
    categories: { [c.categoryId]: { amount: inc(sign * amount), count: inc(sign) } },
  };
  if (c.paymentMode) payload.paymentModes = { [c.paymentMode]: inc(sign * c.outflow) };
  if (c.bankKey) payload.banks = { [c.bankKey]: inc(sign * c.outflow) };
  if (c.outflow > 0) payload.users = { [c.user.id]: { amount: inc(sign * c.outflow), name: c.user.name } };
  if (c.counterparty) {
    payload.counterparties = { [c.counterparty.key]: { amount: inc(sign * c.outflow), count: inc(sign), name: c.counterparty.name } };
  }
  return payload;
}

/** Advance a due date by a recurrence frequency, clamping to month end. */
export function advance(date: Date, frequency: string): Date {
  const months: Record<string, number> = { monthly: 1, quarterly: 3, halfYearly: 6, yearly: 12 };
  if (frequency === 'weekly') return new Date(date.getTime() + 7 * 86400000);
  const m = months[frequency] ?? 1;
  const target = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + m, 1, date.getUTCHours(), date.getUTCMinutes()));
  const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(date.getUTCDate(), lastDay));
  return target;
}

// ---------------------------------------------------------------------------
// Due-date helpers (calendar days in the workspace timezone)
// ---------------------------------------------------------------------------

/** Calendar day number (days since epoch) of [d] as seen in [timeZone]. */
export function dayNumber(d: Date, timeZone = 'Asia/Kolkata'): number {
  const s = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
  return Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10)) / 86400000;
}

/** Days between today and the due date; negative = overdue. */
export function daysUntil(due: Date, now: Date, timeZone = 'Asia/Kolkata'): number {
  return dayNumber(due, timeZone) - dayNumber(now, timeZone);
}

/** Overdue dues stay unpaid/overdue for this long before rolling forward. */
export const OVERDUE_GRACE_DAYS = 7;

/** Which reminder (if any) to send for a due [days] away. */
export function reminderFor(days: number): { title: (label: string) => string } | null {
  if (days === 2) return { title: (l) => `${l} due in 2 days` };
  if (days === 1) return { title: (l) => `${l} due tomorrow` };
  if (days === 0) return { title: (l) => `${l} due today` };
  if (days === -1 || days === -3 || days === -OVERDUE_GRACE_DAYS) {
    return { title: (l) => `${l} overdue by ${-days} day${days === -1 ? '' : 's'}` };
  }
  return null;
}
