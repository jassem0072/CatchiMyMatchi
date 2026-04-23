/**
 * expert-api.test.ts
 *
 * Logic tests for the expert API module.
 * The axios client is mocked to avoid real HTTP calls.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

// ── Mock the axios client ─────────────────────────────────────────────────────
vi.mock('../../api/client', () => ({
  default: {
    get: vi.fn(),
    post: vi.fn(),
  },
}));

import client from '../../api/client';
import {
  getExpertEarnings,
  getExpertPayoutInvoices,
  requestExpertPayout,
  notifyExpertInvoiceReady,
  type ExpertPayoutInvoice,
} from '../../api/expert';

const mockGet = client.get as ReturnType<typeof vi.fn>;
const mockPost = client.post as ReturnType<typeof vi.fn>;

// ── Fixtures ──────────────────────────────────────────────────────────────────
const earningsSummary = {
  verifiedPlayers: 5,
  paidPlayers: 2,
  pendingPlayers: 3,
  totalUsd: 150,
  paidUsd: 60,
  pendingUsd: 90,
};

const invoice: ExpertPayoutInvoice = {
  invoiceId: 'INV-EXP-001',
  amountEur: 90,
  claimedPlayers: 3,
  requestedAt: '2025-06-01T08:00:00.000Z',
  expectedPaymentAt: '2025-06-04T08:00:00.000Z',
  payoutProvider: 'bank_transfer',
  payoutDestinationMasked: '****1234',
  transactionReference: 'REF-001',
  status: 'requested',
};

// ── Tests ─────────────────────────────────────────────────────────────────────
describe('getExpertEarnings', () => {
  beforeEach(() => vi.clearAllMocks());

  it('calls GET /admin/expert/earnings', async () => {
    mockGet.mockResolvedValueOnce({ data: earningsSummary });
    await getExpertEarnings();
    expect(mockGet).toHaveBeenCalledWith('/admin/expert/earnings');
  });

  it('returns the earnings summary', async () => {
    mockGet.mockResolvedValueOnce({ data: earningsSummary });
    const result = await getExpertEarnings();
    expect(result.verifiedPlayers).toBe(5);
    expect(result.pendingUsd).toBe(90);
  });
});

describe('getExpertPayoutInvoices', () => {
  beforeEach(() => vi.clearAllMocks());

  it('calls GET /admin/expert/invoices', async () => {
    mockGet.mockResolvedValueOnce({ data: [] });
    await getExpertPayoutInvoices();
    expect(mockGet).toHaveBeenCalledWith('/admin/expert/invoices');
  });

  it('returns a list of invoices', async () => {
    mockGet.mockResolvedValueOnce({ data: [invoice] });
    const result = await getExpertPayoutInvoices();
    expect(result).toHaveLength(1);
    expect(result[0].invoiceId).toBe('INV-EXP-001');
    expect(result[0].amountEur).toBe(90);
    expect(result[0].status).toBe('requested');
  });

  it('returns an empty array when no invoices', async () => {
    mockGet.mockResolvedValueOnce({ data: [] });
    const result = await getExpertPayoutInvoices();
    expect(result).toHaveLength(0);
  });
});

describe('requestExpertPayout', () => {
  beforeEach(() => vi.clearAllMocks());

  it('calls POST /admin/expert/claim-earnings', async () => {
    mockPost.mockResolvedValueOnce({ data: { claimedPlayers: 3, claimedUsd: 90, message: 'ok' } });
    await requestExpertPayout({
      payoutProvider: 'bank_transfer',
      accountHolderName: 'John Doe',
      bankName: 'BNP',
      bankAccountOrIban: 'FR76001234',
    });
    expect(mockPost).toHaveBeenCalledWith('/admin/expert/claim-earnings', expect.any(Object));
  });

  it('passes all required fields', async () => {
    mockPost.mockResolvedValueOnce({ data: { claimedPlayers: 1, claimedUsd: 30, message: 'done' } });
    await requestExpertPayout({
      payoutProvider: 'paypal',
      accountHolderName: 'Jane Smith',
      bankName: 'PayPal',
      bankAccountOrIban: 'jane@paypal.com',
      swiftBic: 'BNPAFRPP',
    });
    const body = mockPost.mock.calls[0][1];
    expect(body.payoutProvider).toBe('paypal');
    expect(body.accountHolderName).toBe('Jane Smith');
    expect(body.swiftBic).toBe('BNPAFRPP');
  });

  it('returns claimedPlayers and message', async () => {
    mockPost.mockResolvedValueOnce({ data: { claimedPlayers: 2, claimedUsd: 60, message: 'Invoice sent' } });
    const result = await requestExpertPayout({
      payoutProvider: 'bank_transfer',
      accountHolderName: 'A',
      bankName: 'B',
      bankAccountOrIban: 'C',
    });
    expect(result.claimedPlayers).toBe(2);
    expect(result.message).toBe('Invoice sent');
  });
});

describe('notifyExpertInvoiceReady', () => {
  beforeEach(() => vi.clearAllMocks());

  it('calls POST /admin/experts/:id/notify-invoice-ready', async () => {
    mockPost.mockResolvedValueOnce({ data: { sent: true, invoiceId: 'INV-001', amountEur: 30 } });
    await notifyExpertInvoiceReady('expert-id-123');
    expect(mockPost).toHaveBeenCalledWith('/admin/experts/expert-id-123/notify-invoice-ready');
  });

  it('returns sent flag, invoiceId and amountEur', async () => {
    mockPost.mockResolvedValueOnce({ data: { sent: true, invoiceId: 'INV-EXP-999', amountEur: 60 } });
    const result = await notifyExpertInvoiceReady('abc');
    expect(result.sent).toBe(true);
    expect(result.invoiceId).toBe('INV-EXP-999');
    expect(result.amountEur).toBe(60);
  });
});
