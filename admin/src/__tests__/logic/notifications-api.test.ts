/**
 * notifications-api.test.ts — Logic tests for the notifications broadcast API
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../../api/client', () => ({
  default: { post: vi.fn() },
}));

import client from '../../api/client';
import { broadcastNotification } from '../../api/notifications';

const mockPost = client.post as ReturnType<typeof vi.fn>;

describe('broadcastNotification', () => {
  beforeEach(() => vi.clearAllMocks());

  it('POSTs to /admin/notifications/broadcast', async () => {
    mockPost.mockResolvedValueOnce({ data: { sent: 150 } });
    await broadcastNotification({ titleEN: 'Hello', titleFR: 'Bonjour' });
    expect(mockPost).toHaveBeenCalledWith('/admin/notifications/broadcast', expect.any(Object));
  });

  it('passes all four fields', async () => {
    mockPost.mockResolvedValueOnce({ data: { sent: 50 } });
    await broadcastNotification({
      titleEN: 'Hello', titleFR: 'Bonjour',
      bodyEN: 'Body EN', bodyFR: 'Corps FR',
    });
    const payload = mockPost.mock.calls[0][1];
    expect(payload.titleEN).toBe('Hello');
    expect(payload.titleFR).toBe('Bonjour');
    expect(payload.bodyEN).toBe('Body EN');
    expect(payload.bodyFR).toBe('Corps FR');
  });

  it('works with only required fields (no body)', async () => {
    mockPost.mockResolvedValueOnce({ data: { sent: 10 } });
    await broadcastNotification({ titleEN: 'T', titleFR: 'T' });
    const payload = mockPost.mock.calls[0][1];
    expect(payload.bodyEN).toBeUndefined();
    expect(payload.bodyFR).toBeUndefined();
  });

  it('returns the sent count', async () => {
    mockPost.mockResolvedValueOnce({ data: { sent: 314 } });
    const res = await broadcastNotification({ titleEN: 'A', titleFR: 'B' });
    expect(res.sent).toBe(314);
  });

  it('returns 0 sent when no users', async () => {
    mockPost.mockResolvedValueOnce({ data: { sent: 0 } });
    const res = await broadcastNotification({ titleEN: 'A', titleFR: 'B' });
    expect(res.sent).toBe(0);
  });
});
