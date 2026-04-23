/**
 * UsersPage.test.tsx
 *
 * Component tests for the Users management page.
 * - Expert role filter option
 * - Notify Invoice button appears only for experts
 * - Notify Invoice flow (success + error)
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { UsersPage } from '../../pages/UsersPage';

// ── Mock dependencies ─────────────────────────────────────────────────────────
vi.mock('../../api/users', () => ({
  getUsers: vi.fn(),
  deleteUser: vi.fn(),
  banUser: vi.fn(),
  unbanUser: vi.fn(),
  promoteToAdmin: vi.fn(),
  approveAdminRequest: vi.fn(),
}));

vi.mock('../../api/expert', () => ({
  notifyExpertInvoiceReady: vi.fn(),
}));

import { getUsers } from '../../api/users';
import { notifyExpertInvoiceReady } from '../../api/expert';

const mockGetUsers = getUsers as ReturnType<typeof vi.fn>;
const mockNotify = notifyExpertInvoiceReady as ReturnType<typeof vi.fn>;

// ── Fixtures ──────────────────────────────────────────────────────────────────
function userRow(overrides = {}) {
  return {
    _id: 'user-1',
    email: 'user@example.com',
    displayName: 'Test User',
    role: 'player',
    isBanned: false,
    adminAccessRequestStatus: undefined,
    subscriptionTier: null,
    ...overrides,
  };
}

function expertRow(overrides = {}) {
  return userRow({ _id: 'expert-1', email: 'expert@example.com', displayName: 'Expert One', role: 'expert', ...overrides });
}

function pagedResponse(users: object[]) {
  return { data: users, total: users.length, page: 1, limit: 20 };
}

function renderPage() {
  return render(
    <MemoryRouter>
      <UsersPage />
    </MemoryRouter>,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────
describe('UsersPage — role filter', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUsers.mockResolvedValue(pagedResponse([]));
  });

  it('renders the Expert option in role filter', () => {
    renderPage();
    const select = screen.getByRole('combobox');
    expect(select).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Expert' })).toBeInTheDocument();
  });

  it('renders All roles, Player, Scouter, Expert, Admin options', () => {
    renderPage();
    expect(screen.getByRole('option', { name: 'All roles' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Player' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Scouter' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Expert' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Admin' })).toBeInTheDocument();
  });
});

describe('UsersPage — Notify Invoice button', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows Notify Invoice button for expert rows', async () => {
    mockGetUsers.mockResolvedValue(pagedResponse([expertRow()]));
    renderPage();

    await waitFor(() => {
      expect(screen.getByText(/notify invoice/i)).toBeInTheDocument();
    });
  });

  it('does NOT show Notify Invoice button for player rows', async () => {
    mockGetUsers.mockResolvedValue(pagedResponse([userRow({ role: 'player' })]));
    renderPage();

    await waitFor(() => {
      expect(screen.queryByText(/notify invoice/i)).not.toBeInTheDocument();
    });
  });

  it('does NOT show Notify Invoice button for scouter rows', async () => {
    mockGetUsers.mockResolvedValue(pagedResponse([userRow({ role: 'scouter' })]));
    renderPage();

    await waitFor(() => {
      expect(screen.queryByText(/notify invoice/i)).not.toBeInTheDocument();
    });
  });

  it('calls notifyExpertInvoiceReady with expert id on click', async () => {
    const user = userEvent.setup();
    mockGetUsers.mockResolvedValue(pagedResponse([expertRow({ _id: 'exp-abc' })]));
    mockNotify.mockResolvedValueOnce({ sent: true, invoiceId: 'INV-001', amountEur: 30 });

    // Suppress the alert
    vi.spyOn(window, 'alert').mockImplementation(() => {});

    renderPage();
    await waitFor(() => screen.getByText(/notify invoice/i));

    await user.click(screen.getByText(/notify invoice/i));

    await waitFor(() => {
      expect(mockNotify).toHaveBeenCalledWith('exp-abc');
    });
  });

  it('shows success alert after notify', async () => {
    const user = userEvent.setup();
    mockGetUsers.mockResolvedValue(pagedResponse([expertRow({ _id: 'exp-xyz', displayName: 'Dr Expert' })]));
    mockNotify.mockResolvedValueOnce({ sent: true, invoiceId: 'INV-NOTIFY', amountEur: 60 });

    const alertSpy = vi.spyOn(window, 'alert').mockImplementation(() => {});

    renderPage();
    await waitFor(() => screen.getByText(/notify invoice/i));
    await user.click(screen.getByText(/notify invoice/i));

    await waitFor(() => {
      expect(alertSpy).toHaveBeenCalledWith(
        expect.stringContaining('INV-NOTIFY'),
      );
    });
  });

  it('shows error alert when notification fails', async () => {
    const user = userEvent.setup();
    mockGetUsers.mockResolvedValue(pagedResponse([expertRow()]));
    mockNotify.mockRejectedValueOnce({
      response: { data: { message: 'Expert has no invoices yet' } },
    });

    const alertSpy = vi.spyOn(window, 'alert').mockImplementation(() => {});

    renderPage();
    await waitFor(() => screen.getByText(/notify invoice/i));
    await user.click(screen.getByText(/notify invoice/i));

    await waitFor(() => {
      expect(alertSpy).toHaveBeenCalledWith(
        expect.stringContaining('Expert has no invoices yet'),
      );
    });
  });
});

describe('UsersPage — table rendering', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders user email in table', async () => {
    mockGetUsers.mockResolvedValue(pagedResponse([userRow({ email: 'player@test.com' })]));
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('player@test.com')).toBeInTheDocument();
    });
  });

  it('renders expert role badge', async () => {
    mockGetUsers.mockResolvedValue(pagedResponse([expertRow()]));
    renderPage();
    await waitFor(() => {
      expect(screen.getByText('expert')).toBeInTheDocument();
    });
  });

  it('renders search input', () => {
    mockGetUsers.mockResolvedValue(pagedResponse([]));
    renderPage();
    expect(screen.getByPlaceholderText(/search by email or name/i)).toBeInTheDocument();
  });
});
