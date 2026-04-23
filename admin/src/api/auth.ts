import client from './client';
import type { AuthResponse } from '../types';

export interface AuthMeResponse {
  _id: string;
  email: string;
  role: 'admin' | 'expert';
  displayName?: string;
  position?: string;
  nation?: string;
  dateOfBirth?: string | null;
  height?: number | null;
  playerIdNumber?: string;
  emailVerified?: boolean;
  badgeVerified?: boolean;
  createdAt?: string;
  updatedAt?: string;
}

export async function adminLogin(email: string, password: string): Promise<AuthResponse> {
  const res = await client.post<AuthResponse>('/auth/admin-login', { email, password });
  return res.data;
}

export async function adminGoogleLogin(payload: {
  idToken?: string;
  accessToken?: string;
  displayName?: string;
}): Promise<AuthResponse> {
  const res = await client.post<AuthResponse>('/auth/admin-google-login', payload);
  return res.data;
}

export async function getAuthMe(token?: string): Promise<AuthMeResponse> {
  const headers = token ? { Authorization: `Bearer ${token}` } : undefined;
  const res = await client.get<AuthMeResponse>('/auth/me', { headers });
  return res.data;
}

export async function updateAuthMe(payload: {
  displayName?: string;
  position?: string;
  nation?: string;
  dateOfBirth?: string;
  height?: number;
  playerIdNumber?: string;
}): Promise<AuthMeResponse> {
  const res = await client.patch<AuthMeResponse>('/auth/me', payload);
  return res.data;
}

export async function updateAuthPassword(payload: {
  currentPassword: string;
  newPassword: string;
}): Promise<{ ok: boolean }> {
  const res = await client.patch<{ ok: boolean }>('/auth/me/password', payload);
  return res.data;
}

export async function requestPasswordReset(email: string): Promise<{ ok: boolean }> {
  const res = await client.post<{ ok: boolean }>('/auth/forgot-password', { email });
  return res.data;
}

export async function resetPassword(payload: {
  email: string;
  token: string;
  newPassword: string;
}): Promise<{ ok: boolean }> {
  const res = await client.post<{ ok: boolean }>('/auth/reset-password', payload);
  return res.data;
}

export async function registerExpert(payload: {
  email: string;
  password: string;
  displayName?: string;
  position?: string;
  nation?: string;
}): Promise<{ email: string }> {
  const res = await client.post<{ email: string }>('/auth/register-expert', payload);
  return res.data;
}

export async function requestAdminAccess(payload: {
  email: string;
  password: string;
  displayName?: string;
}): Promise<{ email: string; status: 'pending' }> {
  const res = await client.post<{ email: string; status: 'pending' }>('/auth/request-admin-access', payload);
  return res.data;
}
