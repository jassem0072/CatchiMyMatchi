import client from './client';
import type { AdminUser, PaginatedResponse } from '../types';

export interface UsersQuery {
  page?: number;
  limit?: number;
  search?: string;
  role?: string;
}

export async function getUsers(query: UsersQuery = {}): Promise<PaginatedResponse<AdminUser>> {
  const params: Record<string, string | number> = {};
  if (query.page) params.page = query.page;
  if (query.limit) params.limit = query.limit;
  if (query.search) params.search = query.search;
  if (query.role) params.role = query.role;
  const res = await client.get<PaginatedResponse<AdminUser>>('/admin/users', { params });
  return res.data;
}

export async function deleteUser(id: string): Promise<void> {
  await client.delete(`/admin/users/${id}`);
}

export async function banUser(id: string): Promise<AdminUser> {
  const res = await client.patch<AdminUser>(`/admin/users/${id}/ban`);
  return res.data;
}

export async function unbanUser(id: string): Promise<AdminUser> {
  const res = await client.patch<AdminUser>(`/admin/users/${id}/unban`);
  return res.data;
}

export async function promoteToAdmin(id: string): Promise<AdminUser> {
  const res = await client.patch<AdminUser>(`/admin/users/${id}/role`, { role: 'admin' });
  return res.data;
}

export async function approveAdminRequest(id: string): Promise<AdminUser> {
  const res = await client.patch<AdminUser>(`/admin/users/${id}/approve-admin-request`);
  return res.data;
}
