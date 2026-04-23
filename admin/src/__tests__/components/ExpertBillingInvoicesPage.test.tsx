/**
 * ExpertBillingInvoicesPage.test.tsx
 *
 * Component (widget) tests for the expert billing invoices page.
 * - Billing form fields & submit button
 * - All Payment Invoices table rendering
 * - Download PDF button per invoice row
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { ExpertBillingInvoicesPage } from '../../pages/ExpertBillingInvoicesPage';
import type { ExpertPayoutInvoice } from '../../api/expert';

// ── Mock dependencies ─────────────────────────────────────────────────────────
vi.mock('../../api/expert', () => ({
  getExpertPayoutInvoices: vi.fn(),
  requestExpertPayout: vi.fn(),
}));

vi.mock('../../utils/invoice-pdf', () => ({
  downloadInvoicePdf: vi.fn().mockResolvedValue(undefined),
}));

import { getExpertPayoutInvoices, requestExpertPayout } from '../../api/expert';
import { downloadInvoicePdf } from '../../utils/invoice-pdf';

const mockGetInvoices = getExpertPayoutInvoices as ReturnType<typeof vi.fn>;
const mockRequestPayout = requestExpertPayout as ReturnType<typeof vi.fn>;
const mockDownloadPdf = downloadInvoicePdf as ReturnType<typeof vi.fn>;

function fakeInvoice(id = 'INV-001', status: ExpertPayoutInvoice['status'] = 'requested'): ExpertPayoutInvoice {
  return {
    invoiceId: id,
    amountEur: 90,
    claimedPlayers: 3,
    requestedAt: '2025-06-01T08:00:00.000Z',
    expectedPaymentAt: '2025-06-04T08:00:00.000Z',
    payoutProvider: 'bank_transfer',
    payoutDestinationMasked: '****1234',
    transactionReference: 'REF-001',
    status,
  };
}

function renderPage() {
  return render(
    <MemoryRouter>
      <ExpertBillingInvoicesPage />
    </MemoryRouter>,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────
describe('ExpertBillingInvoicesPage — form', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetInvoices.mockResolvedValue([]);
  });

  it('renders the page title', async () => {
    renderPage();
    expect(screen.getByText('Billing and Invoices')).toBeInTheDocument();
  });

  it('renders Submit Billing Details button', async () => {
    renderPage();
    expect(screen.getByText('Submit Billing Details')).toBeInTheDocument();
  });

  it('renders all form fields', async () => {
    renderPage();
    expect(screen.getByText('Payout Method')).toBeInTheDocument();
    expect(screen.getByText('Account Holder Name')).toBeInTheDocument();
    expect(screen.getByText('Bank Name')).toBeInTheDocument();
    expect(screen.getByText('Bank Account Number or IBAN')).toBeInTheDocument();
    expect(screen.getByText('SWIFT or BIC (optional)')).toBeInTheDocument();
  });

  it('shows validation error when submitting empty form', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByText('Submit Billing Details'));
    await waitFor(() => {
      // The validation message is distinct from the form label
      expect(screen.getByText('Please provide the account holder name.')).toBeInTheDocument();
    });
  });

  it('calls requestExpertPayout with correct data on valid submit', async () => {
    const user = userEvent.setup();
    mockRequestPayout.mockResolvedValueOnce({
      claimedPlayers: 3,
      claimedUsd: 90,
      message: 'Invoice sent!',
    });
    renderPage();

    await user.type(screen.getByPlaceholderText('Account holder name'), 'John Doe');
    await user.type(screen.getByPlaceholderText('Bank name'), 'BNP Paribas');
    await user.type(screen.getByPlaceholderText('Bank account number or IBAN'), 'FR761234567890');

    await user.click(screen.getByText('Submit Billing Details'));

    await waitFor(() => {
      expect(mockRequestPayout).toHaveBeenCalledWith(
        expect.objectContaining({
          accountHolderName: 'John Doe',
          bankName: 'BNP Paribas',
          bankAccountOrIban: 'FR761234567890',
        }),
      );
    });
  });

  it('shows success message after submit', async () => {
    const user = userEvent.setup();
    mockRequestPayout.mockResolvedValueOnce({
      claimedPlayers: 3,
      claimedUsd: 90,
      message: 'Billing details saved! Invoice sent.',
    });
    renderPage();

    await user.type(screen.getByPlaceholderText('Account holder name'), 'John Doe');
    await user.type(screen.getByPlaceholderText('Bank name'), 'BNP Paribas');
    await user.type(screen.getByPlaceholderText('Bank account number or IBAN'), 'FR761234567890');
    await user.click(screen.getByText('Submit Billing Details'));

    await waitFor(() => {
      expect(screen.getByText('Billing details saved! Invoice sent.')).toBeInTheDocument();
    });
  });
});

describe('ExpertBillingInvoicesPage — All Payment Invoices', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows loading text while fetching invoices', () => {
    // Never-resolving promise keeps loading state
    mockGetInvoices.mockReturnValue(new Promise(() => {}));
    renderPage();
    expect(screen.getByText(/loading invoices/i)).toBeInTheDocument();
  });

  it('shows empty state when no invoices', async () => {
    mockGetInvoices.mockResolvedValue([]);
    renderPage();
    await waitFor(() => {
      expect(screen.getByText(/no invoices yet/i)).toBeInTheDocument();
    });
  });

  it('renders invoice row with ID and amount', async () => {
    mockGetInvoices.mockResolvedValue([fakeInvoice('INV-EXP-123')]);
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('INV-EXP-123')).toBeInTheDocument();
      expect(screen.getByText('EUR 90')).toBeInTheDocument();
    });
  });

  it('renders Download PDF button for each invoice', async () => {
    mockGetInvoices.mockResolvedValue([fakeInvoice('INV-A'), fakeInvoice('INV-B')]);
    renderPage();
    await waitFor(() => {
      const buttons = screen.getAllByText(/download pdf/i);
      expect(buttons).toHaveLength(2);
    });
  });

  it('calls downloadInvoicePdf when Download PDF button is clicked', async () => {
    const user = userEvent.setup();
    mockGetInvoices.mockResolvedValue([fakeInvoice('INV-CLICK-ME')]);
    renderPage();

    await waitFor(() => screen.getByText(/download pdf/i));
    await user.click(screen.getByText(/download pdf/i));

    await waitFor(() => {
      expect(mockDownloadPdf).toHaveBeenCalledOnce();
      expect(mockDownloadPdf).toHaveBeenCalledWith(
        expect.objectContaining({ invoiceId: 'INV-CLICK-ME' }),
      );
    });
  });

  it('renders status badge for each invoice', async () => {
    mockGetInvoices.mockResolvedValue([fakeInvoice('INV-A', 'paid')]);
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('paid')).toBeInTheDocument();
    });
  });

  it('renders All Payment Invoices section title', async () => {
    mockGetInvoices.mockResolvedValue([]);
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('All Payment Invoices')).toBeInTheDocument();
    });
  });
});
