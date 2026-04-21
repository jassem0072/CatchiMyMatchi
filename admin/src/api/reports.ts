import client from './client';
import type { AdminReport, PaginatedResponse } from '../types';

export async function getReports(page = 1, limit = 20): Promise<PaginatedResponse<AdminReport>> {
  const res = await client.get<PaginatedResponse<AdminReport>>('/admin/reports', { params: { page, limit } });
  return res.data;
}
