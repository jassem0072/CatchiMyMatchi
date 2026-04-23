/**
 * ExpertProfilePage.test.tsx
 *
 * Component tests for the expert profile / earnings overview page.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { ExpertProfilePage } from '../../pages/ExpertProfilePage';

// ── Mock dependencies ─────────────────────────────────────────────────────────
vi.mock('../../api/expert', () => ({
  getExpertEarnings: vi.fn(),
}));

const mockNavigate = vi.fn();
vi.mock('react-router-dom', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-router-dom')>();
  return { ...actual, useNavigate: () => mockNavigate };
});

import { getExpertEarnings } from '../../api/expert';
const mockGetEarnings = getExpertEarnings as ReturnType<typeof vi.fn>;

function renderPage() {
  return render(
    <MemoryRouter>
      <ExpertProfilePage />
    </MemoryRouter>,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────
describe('ExpertProfilePage — loading / error', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows loading text while fetching', () => {
    mockGetEarnings.mockReturnValue(new Promise(() => {}));
    renderPage();
    expect(screen.getByText(/loading earnings/i)).toBeInTheDocument();
  });

  it('shows error text when fetch fails', async () => {
    mockGetEarnings.mockRejectedValueOnce(new Error('Server error'));
    renderPage();
    await waitFor(() => {
      expect(screen.getByText(/server error/i)).toBeInTheDocument();
    });
  });
});

describe('ExpertProfilePage — earnings tiles', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders Verified Players count', async () => {
    mockGetEarnings.mockResolvedValueOnce({
      verifiedPlayers: 7,
      paidPlayers: 3,
      pendingPlayers: 4,
      totalUsd: 210,
      paidUsd: 90,
      pendingUsd: 120,
    });
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('7')).toBeInTheDocument();
    });
  });

  it('renders Pending Payout amount', async () => {
    mockGetEarnings.mockResolvedValueOnce({
      verifiedPlayers: 4,
      paidPlayers: 1,
      pendingPlayers: 3,
      totalUsd: 120,
      paidUsd: 30,
      pendingUsd: 90,
    });
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('EUR 90')).toBeInTheDocument();
    });
  });

  it('renders Already Paid amount', async () => {
    mockGetEarnings.mockResolvedValueOnce({
      verifiedPlayers: 2,
      paidPlayers: 2,
      pendingPlayers: 0,
      totalUsd: 60,
      paidUsd: 60,
      pendingUsd: 0,
    });
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('EUR 60')).toBeInTheDocument();
    });
  });

  it('renders the tile labels', async () => {
    mockGetEarnings.mockResolvedValueOnce({
      verifiedPlayers: 1, paidPlayers: 0, pendingPlayers: 1,
      totalUsd: 30, paidUsd: 0, pendingUsd: 30,
    });
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('Verified Players')).toBeInTheDocument();
      expect(screen.getByText('Pending Payout')).toBeInTheDocument();
      expect(screen.getByText('Already Paid')).toBeInTheDocument();
    });
  });
});

describe('ExpertProfilePage — navigation', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders Open Billing and Invoices button', async () => {
    mockGetEarnings.mockResolvedValueOnce({
      verifiedPlayers: 1, paidPlayers: 0, pendingPlayers: 1,
      totalUsd: 30, paidUsd: 0, pendingUsd: 30,
    });
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('Open Billing and Invoices')).toBeInTheDocument();
    });
  });

  it('navigates to /billing-invoices on button click', async () => {
    const user = userEvent.setup();
    mockGetEarnings.mockResolvedValueOnce({
      verifiedPlayers: 1, paidPlayers: 0, pendingPlayers: 1,
      totalUsd: 30, paidUsd: 0, pendingUsd: 30,
    });
    renderPage();
    await waitFor(() => screen.getByText('Open Billing and Invoices'));
    await user.click(screen.getByText('Open Billing and Invoices'));
    expect(mockNavigate).toHaveBeenCalledWith('/billing-invoices');
  });
});
