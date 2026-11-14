import { test } from 'node:test';
import assert from 'node:assert/strict';
import { advance, contribution, statDelta } from '../stats';

const base = {
  workspaceId: 'w', ownerUserId: 'u', amount: 500, currency: 'INR', direction: 'outflow' as const,
  status: 'success', categoryId: 'food_dining', paymentMode: 'upi', monthKey: '2026-11', counterparty: 'Swiggy',
};

test('excludes failed, pending and internal transfers', () => {
  assert.equal(contribution({ ...base, status: 'failed' }), null);
  assert.equal(contribution({ ...base, status: 'pending' }), null);
  assert.equal(contribution({ ...base, isInternalTransfer: true }), null);
  assert.ok(contribution(base));
});

test('delta reverses exactly', () => {
  const c = contribution(base)!;
  const plus = statDelta(c, 1, (n) => n);
  const minus = statDelta(c, -1, (n) => n);
  assert.equal(plus.outflow, 500);
  assert.equal(minus.outflow, -500);
  assert.deepEqual((plus.paymentModes as Record<string, number>).UPI, 500);
});

test('refunds tracked separately', () => {
  const c = contribution({ ...base, direction: 'inflow', categoryId: 'refund' })!;
  assert.equal(c.refunds, 500);
  assert.equal(c.inflow, 500);
});

test('advance clamps month end', () => {
  assert.equal(advance(new Date(Date.UTC(2026, 0, 31)), 'monthly').toISOString().slice(0, 10), '2026-02-28');
  assert.equal(advance(new Date(Date.UTC(2026, 0, 1)), 'weekly').toISOString().slice(0, 10), '2026-01-08');
});

test('due days use the workspace calendar, not UTC', async () => {
  const { daysUntil, reminderFor } = await import('../stats');
  // Due 15 Nov IST is stored as 14 Nov 18:30 UTC.
  const due = new Date('2026-11-14T18:30:00Z');
  const nineAmIst = (d: number) => new Date(Date.UTC(2026, 10, d, 3, 30));
  assert.equal(daysUntil(due, nineAmIst(13)), 2);
  assert.equal(daysUntil(due, nineAmIst(14)), 1);
  assert.equal(daysUntil(due, nineAmIst(15)), 0);
  assert.equal(daysUntil(due, nineAmIst(16)), -1);
  assert.equal(reminderFor(2)?.title('Rent'), 'Rent due in 2 days');
  assert.equal(reminderFor(1)?.title('EMI'), 'EMI due tomorrow');
  assert.equal(reminderFor(0)?.title('Bill'), 'Bill due today');
  assert.equal(reminderFor(-1)?.title('Bill'), 'Bill overdue by 1 day');
  assert.equal(reminderFor(5), null);
});
