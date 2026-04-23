/**
 * DashboardPage.test.tsx — Component tests for the admin dashboard
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { DashboardPage } from '../../pages/DashboardPage';

vi.mock('../../api/stats', () => ({ getStats: vi.fn() }));
vi.mock('../../api/analytics', () => ({ getAnalytics: vi.fn() }));
// Recharts causes canvas errors in jsdom; stub all chart components
vi.mock('../../charts/RegistrationsLineChart', () => ({ RegistrationsLineChart: () => <div data-testid="line-chart" /> }));
vi.mock('../../charts/RoleDonutChart', () => ({ RoleDonutChart: () => <div data-testid="donut-chart" /> }));
vi.mock('../../charts/SubscriptionBarChart', () => ({ SubscriptionBarChart: () => <div data-testid="bar-chart" /> }));

import { getStats } from '../../api/stats';
import { getAnalytics } from '../../api/analytics';

const mockGetStats = getStats as ReturnType<typeof vi.fn>;
const mockGetAnalytics = getAnalytics as ReturnType<typeof vi.fn>;

function fakeStats(overrides = {}) {
  return {
    totalPlayers: 42,
    totalScouterss: 7,
    totalVideos: 120,
    analyzedVideos: 95,
    registrations: [],
    subscriptions: { basic: 10, premium: 5, elite: 2 },
    ...overrides,
  };
}

function fakeAnalytics(overrides = {}) {
  return {
    activeSubscriptions: 17,
    expiringSoon: 3,
    bannedUsers: 1,
    totalReports: 8,
    revenueByTier: { basic: 10, premium: 5, elite: 2 },
    revenueTotal: 45000,
    topScouters: [{ displayName: 'Scout A', reportCount: 12 }],
    topPlayers: [{ displayName: 'Player B', position: 'ST', reportCount: 9 }],
    ...overrides,
  };
}

function renderPage() {
  return render(<MemoryRouter><DashboardPage /></MemoryRouter>);
}

describe('DashboardPage — loading / error', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows loading text while fetching', () => {
    mockGetStats.mockReturnValue(new Promise(() => {}));
    mockGetAnalytics.mockReturnValue(new Promise(() => {}));
    renderPage();
    expect(screen.getByText(/loading stats/i)).toBeInTheDocument();
  });

  it('shows error when stats fetch fails', async () => {
    mockGetStats.mockRejectedValueOnce(new Error('Server down'));
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics());
    renderPage();
    await waitFor(() => {
      expect(screen.getByText(/server down/i)).toBeInTheDocument();
    });
  });
});

describe('DashboardPage — KPI tiles', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders Total Players tile', async () => {
    mockGetStats.mockResolvedValueOnce(fakeStats({ totalPlayers: 42 }));
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics());
    renderPage();
    await waitFor(() => expect(screen.getByText('Total Players')).toBeInTheDocument());
    expect(screen.getByText('42')).toBeInTheDocument();
  });

  it('renders Total Videos tile', async () => {
    mockGetStats.mockResolvedValueOnce(fakeStats({ totalVideos: 120 }));
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics());
    renderPage();
    await waitFor(() => expect(screen.getByText('Total Videos')).toBeInTheDocument());
    expect(screen.getByText('120')).toBeInTheDocument();
  });

  it('renders Analyses Run tile', async () => {
    mockGetStats.mockResolvedValueOnce(fakeStats({ analyzedVideos: 95 }));
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics());
    renderPage();
    await waitFor(() => expect(screen.getByText('Analyses Run')).toBeInTheDocument());
    expect(screen.getByText('95')).toBeInTheDocument();
  });

  it('renders analytics tiles when analytics loads', async () => {
    mockGetStats.mockResolvedValueOnce(fakeStats());
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics({ activeSubscriptions: 17, bannedUsers: 1 }));
    renderPage();
    await waitFor(() => expect(screen.getByText('Active Subs')).toBeInTheDocument());
    expect(screen.getByText('Banned Users')).toBeInTheDocument();
  });
});

describe('DashboardPage — charts', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders all three chart stubs', async () => {
    mockGetStats.mockResolvedValueOnce(fakeStats());
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics());
    renderPage();
    await waitFor(() => expect(screen.getByTestId('line-chart')).toBeInTheDocument());
    expect(screen.getByTestId('donut-chart')).toBeInTheDocument();
    expect(screen.getByTestId('bar-chart')).toBeInTheDocument();
  });

  it('renders Monthly Registrations section title', async () => {
    mockGetStats.mockResolvedValueOnce(fakeStats());
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics());
    renderPage();
    await waitFor(() => expect(screen.getByText('Monthly Registrations')).toBeInTheDocument());
  });
});

describe('DashboardPage — leaderboards', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders top scouter name', async () => {
    mockGetStats.mockResolvedValueOnce(fakeStats());
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics({ topScouters: [{ displayName: 'Super Scout', reportCount: 15 }] }));
    renderPage();
    await waitFor(() => expect(screen.getByText('Super Scout')).toBeInTheDocument());
  });

  it('renders top player name', async () => {
    mockGetStats.mockResolvedValueOnce(fakeStats());
    mockGetAnalytics.mockResolvedValueOnce(fakeAnalytics({ topPlayers: [{ displayName: 'Goal King', position: 'CF', reportCount: 20 }] }));
    renderPage();
    await waitFor(() => expect(screen.getByText('Goal King')).toBeInTheDocument());
  });
});
