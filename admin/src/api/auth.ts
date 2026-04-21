import client from './client';
import type { AuthResponse } from '../types';

export async function adminLogin(email: string, password: string): Promise<AuthResponse> {
  const res = await client.post<AuthResponse>('/auth/admin-login', { email, password });
  return res.data;
}
