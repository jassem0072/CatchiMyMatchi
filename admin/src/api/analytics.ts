import client from './client';
import type { AdminAnalytics } from '../types';

export async function getAnalytics(): Promise<AdminAnalytics> {
    const res = await client.get<AdminAnalytics>('/admin/analytics');
    return res.data;
}
