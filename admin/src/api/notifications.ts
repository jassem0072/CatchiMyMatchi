import client from './client';

export interface BroadcastPayload {
  titleEN: string;
  titleFR: string;
  bodyEN?: string;
  bodyFR?: string;
}

export async function broadcastNotification(payload: BroadcastPayload): Promise<{ sent: number }> {
  const res = await client.post<{ sent: number }>('/admin/notifications/broadcast', payload);
  return res.data;
}
