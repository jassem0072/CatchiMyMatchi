/**
 * invoice-pdf.test.ts
 *
 * Logic tests for the invoice PDF generation utility.
 * pdf-lib runs in jsdom; browser download APIs are mocked with vi.fn().
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { ExpertPayoutInvoice } from '../../api/expert';

// ── Mock anchor element ───────────────────────────────────────────────────────
const mockClick = vi.fn();
const mockAnchor = { href: '', download: '', click: mockClick };

vi.spyOn(document, 'createElement').mockImplementation((tag: string) => {
  if (tag === 'a') return mockAnchor as unknown as HTMLElement;
  // For all other tags use the real implementation via a temporary restoration
  const spy = vi.spyOn(document, 'createElement');
  spy.mockRestore();
  const el = document.createElement(tag);
  // Re-apply the mock for subsequent calls
  vi.spyOn(document, 'createElement').mockImplementation((t: string) =>
    t === 'a' ? (mockAnchor as unknown as HTMLElement) : document.createElement(t),
  );
  return el;
});

// ── Mock URL download APIs ────────────────────────────────────────────────────
const mockCreateObjectURL = vi.fn().mockReturnValue('blob://mock-url');
const mockRevokeObjectURL = vi.fn();
Object.assign(URL, {
  createObjectURL: mockCreateObjectURL,
  revokeObjectURL: mockRevokeObjectURL,
});

// ── Import AFTER mocks are wired ──────────────────────────────────────────────
const { downloadInvoicePdf } = await import('../../utils/invoice-pdf');

// ── Fixture ───────────────────────────────────────────────────────────────────
function fakeInvoice(overrides: Partial<ExpertPayoutInvoice> = {}): ExpertPayoutInvoice {
  return {
    invoiceId: 'INV-EXP-001',
    amountEur: 90,
    claimedPlayers: 3,
    requestedAt: '2025-06-01T08:00:00.000Z',
    expectedPaymentAt: '2025-06-04T08:00:00.000Z',
    payoutProvider: 'bank_transfer',
    payoutDestinationMasked: '****1234',
    transactionReference: 'REF-001',
    status: 'requested',
    ...overrides,
  };
}

// ── Tests ─────────────────────────────────────────────────────────────────────
describe('downloadInvoicePdf', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockCreateObjectURL.mockReturnValue('blob://mock-url');
    mockAnchor.href = '';
    mockAnchor.download = '';
  });

  it('is an async function', () => {
    expect(typeof downloadInvoicePdf).toBe('function');
  });

  it('returns a Promise that resolves to undefined', async () => {
    const result = downloadInvoicePdf(fakeInvoice());
    expect(result).toBeInstanceOf(Promise);
    await expect(result).resolves.toBeUndefined();
  });

  it('calls URL.createObjectURL with a PDF Blob', async () => {
    await downloadInvoicePdf(fakeInvoice());
    expect(mockCreateObjectURL).toHaveBeenCalledOnce();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const blob = (mockCreateObjectURL.mock.calls[0] as any)[0] as Blob;
    expect(blob).toBeInstanceOf(Blob);
    expect(blob.type).toBe('application/pdf');
  });

  it('generates a non-empty, valid PDF (starts with %PDF)', async () => {
    let capturedBlob: Blob | undefined;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    mockCreateObjectURL.mockImplementation((...args: any[]) => {
      capturedBlob = args[0] as Blob;
      return 'blob://mock-url';
    });

    await downloadInvoicePdf(fakeInvoice());

    expect(capturedBlob).toBeDefined();
    const text = await capturedBlob!.text();
    expect(text.startsWith('%PDF')).toBe(true);
  });

  it('sets the anchor download filename correctly', async () => {
    await downloadInvoicePdf(fakeInvoice({ invoiceId: 'INV-TESTID-99' }));
    expect(mockAnchor.download).toBe('ScoutAI_Invoice_INV-TESTID-99.pdf');
  });

  it('sets the anchor href to the blob URL', async () => {
    await downloadInvoicePdf(fakeInvoice());
    expect(mockAnchor.href).toBe('blob://mock-url');
  });

  it('clicks the anchor to trigger the download', async () => {
    await downloadInvoicePdf(fakeInvoice());
    expect(mockClick).toHaveBeenCalledOnce();
  });

  it('produces a PDF at least as large when email is provided', async () => {
    let sizeWithEmail = 0;
    let sizeWithout = 0;

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    mockCreateObjectURL.mockImplementation((...args: any[]) => {
      sizeWithEmail = (args[0] as Blob).size;
      return 'blob://mock-url';
    });
    await downloadInvoicePdf(fakeInvoice(), 'expert@example.com');

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    mockCreateObjectURL.mockImplementation((...args: any[]) => {
      sizeWithout = (args[0] as Blob).size;
      return 'blob://mock-url';
    });
    await downloadInvoicePdf(fakeInvoice());

    expect(sizeWithEmail).toBeGreaterThanOrEqual(sizeWithout);
  });

  it('works with bank_transfer provider and requested status', async () => {
    await expect(
      downloadInvoicePdf(fakeInvoice({ payoutProvider: 'bank_transfer', status: 'requested' })),
    ).resolves.toBeUndefined();
  });

  it('works with paypal provider and paid status', async () => {
    await expect(
      downloadInvoicePdf(fakeInvoice({ payoutProvider: 'paypal', status: 'paid' })),
    ).resolves.toBeUndefined();
  });

  it('works with processing status', async () => {
    await expect(
      downloadInvoicePdf(fakeInvoice({ status: 'processing' })),
    ).resolves.toBeUndefined();
  });

  it('handles zero amount invoice without throwing', async () => {
    await expect(
      downloadInvoicePdf(fakeInvoice({ amountEur: 0, claimedPlayers: 0 })),
    ).resolves.toBeUndefined();
  });
});
