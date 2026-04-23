/**
 * NotificationsPage.test.tsx — Component tests for broadcast notifications
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { NotificationsPage } from '../../pages/NotificationsPage';

vi.mock('../../api/notifications', () => ({ broadcastNotification: vi.fn() }));

import { broadcastNotification } from '../../api/notifications';
const mockBroadcast = broadcastNotification as ReturnType<typeof vi.fn>;

function renderPage() {
  return render(<NotificationsPage />);
}

describe('NotificationsPage — structure', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders Broadcast to All Users button', () => {
    renderPage();
    expect(screen.getByText(/broadcast to all users/i)).toBeInTheDocument();
  });

  it('renders Title (English) field', () => {
    renderPage();
    expect(screen.getByText('Title (English)')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Announcement')).toBeInTheDocument();
  });

  it('renders Title (Français) field', () => {
    renderPage();
    expect(screen.getByText('Title (Français)')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Annonce')).toBeInTheDocument();
  });

  it('renders Body (English) and Body (Français) textareas', () => {
    renderPage();
    expect(screen.getByText('Body (English)')).toBeInTheDocument();
    expect(screen.getByText('Body (Français)')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Message content…')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Contenu du message…')).toBeInTheDocument();
  });

  it('does not show result or error initially', () => {
    renderPage();
    expect(screen.queryByText(/notification sent to/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/broadcast failed/i)).not.toBeInTheDocument();
  });
});

describe('NotificationsPage — submit flow', () => {
  beforeEach(() => vi.clearAllMocks());

  it('calls broadcastNotification with entered fields', async () => {
    const user = userEvent.setup();
    mockBroadcast.mockResolvedValueOnce({ sent: 42 });
    renderPage();

    await user.type(screen.getByPlaceholderText('Announcement'), 'Hello');
    await user.type(screen.getByPlaceholderText('Annonce'), 'Bonjour');
    await user.type(screen.getByPlaceholderText('Message content…'), 'Body EN');
    await user.type(screen.getByPlaceholderText('Contenu du message…'), 'Corps FR');

    await user.click(screen.getByText(/broadcast to all users/i));

    await waitFor(() => {
      expect(mockBroadcast).toHaveBeenCalledWith({
        titleEN: 'Hello',
        titleFR: 'Bonjour',
        bodyEN: 'Body EN',
        bodyFR: 'Corps FR',
      });
    });
  });

  it('shows sent count after success', async () => {
    const user = userEvent.setup();
    mockBroadcast.mockResolvedValueOnce({ sent: 42 });
    renderPage();

    await user.type(screen.getByPlaceholderText('Announcement'), 'Hi');
    await user.type(screen.getByPlaceholderText('Annonce'), 'Salut');
    await user.click(screen.getByText(/broadcast to all users/i));

    await waitFor(() => {
      expect(screen.getByText(/notification sent to 42 users/i)).toBeInTheDocument();
    });
  });

  it('shows error message when broadcast fails', async () => {
    const user = userEvent.setup();
    mockBroadcast.mockRejectedValueOnce({
      response: { data: { message: 'Service unavailable' } },
    });
    renderPage();

    await user.type(screen.getByPlaceholderText('Announcement'), 'Hi');
    await user.type(screen.getByPlaceholderText('Annonce'), 'Salut');
    await user.click(screen.getByText(/broadcast to all users/i));

    await waitFor(() => {
      expect(screen.getByText('Service unavailable')).toBeInTheDocument();
    });
  });

  it('shows default error when no message in response', async () => {
    const user = userEvent.setup();
    mockBroadcast.mockRejectedValueOnce(new Error('Network error'));
    renderPage();

    await user.type(screen.getByPlaceholderText('Announcement'), 'Hi');
    await user.type(screen.getByPlaceholderText('Annonce'), 'Salut');
    await user.click(screen.getByText(/broadcast to all users/i));

    await waitFor(() => {
      expect(screen.getByText('Broadcast failed')).toBeInTheDocument();
    });
  });

  it('clears fields after successful broadcast', async () => {
    const user = userEvent.setup();
    mockBroadcast.mockResolvedValueOnce({ sent: 5 });
    renderPage();

    const titleInput = screen.getByPlaceholderText('Announcement');
    await user.type(titleInput, 'Hello');
    await user.type(screen.getByPlaceholderText('Annonce'), 'Bonjour');
    await user.click(screen.getByText(/broadcast to all users/i));

    await waitFor(() => {
      expect(titleInput).toHaveValue('');
    });
  });
});
