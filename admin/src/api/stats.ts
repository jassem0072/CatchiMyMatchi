import client from './client';
import type { Stats } from '../types';

export async function getStats(): Promise<Stats> {
  const res = await client.get<Stats>('/admin/stats');
  return res.data;
}
