/**
 * auth-api.test.ts — Logic tests for all auth API functions
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../../api/client', () => ({
  default: { get: vi.fn(), post: vi.fn(), patch: vi.fn() },
}));

import client from '../../api/client';
import {
  adminLogin,
  adminGoogleLogin,
  getAuthMe,
  updateAuthMe,
  updateAuthPassword,
  requestPasswordReset,
  resetPassword,
  registerExpert,
  requestAdminAccess,
} from '../../api/auth';

const mockGet = client.get as ReturnType<typeof vi.fn>;
const mockPost = client.post as ReturnType<typeof vi.fn>;
const mockPatch = client.patch as ReturnType<typeof vi.fn>;

// AuthResponse only has accessToken per types/index.ts
const tokenResponse = { accessToken: 'tok-abc' };
const meResponse = { _id: 'u1', email: 'a@b.com', role: 'admin' as const };

describe('adminLogin', () => {
  beforeEach(() => vi.clearAllMocks());

  it('POSTs to /auth/admin-login with credentials', async () => {
    mockPost.mockResolvedValueOnce({ data: tokenResponse });
    await adminLogin('a@b.com', 'pass');
    expect(mockPost).toHaveBeenCalledWith('/auth/admin-login', { email: 'a@b.com', password: 'pass' });
  });

  it('returns auth response with accessToken', async () => {
    mockPost.mockResolvedValueOnce({ data: tokenResponse });
    const res = await adminLogin('a@b.com', 'pass');
    expect(res.accessToken).toBe('tok-abc');
  });
});

describe('adminGoogleLogin', () => {
  beforeEach(() => vi.clearAllMocks());

  it('POSTs to /auth/admin-google-login with idToken', async () => {
    mockPost.mockResolvedValueOnce({ data: tokenResponse });
    await adminGoogleLogin({ idToken: 'gtoken' });
    expect(mockPost).toHaveBeenCalledWith('/auth/admin-google-login', { idToken: 'gtoken' });
  });

  it('accepts accessToken + displayName variant', async () => {
    mockPost.mockResolvedValueOnce({ data: tokenResponse });
    await adminGoogleLogin({ accessToken: 'atoken', displayName: 'Alice' });
    expect(mockPost).toHaveBeenCalledWith('/auth/admin-google-login', { accessToken: 'atoken', displayName: 'Alice' });
  });
});

describe('getAuthMe', () => {
  beforeEach(() => vi.clearAllMocks());

  it('GETs /auth/me with no headers when token is absent', async () => {
    mockGet.mockResolvedValueOnce({ data: meResponse });
    await getAuthMe();
    expect(mockGet).toHaveBeenCalledWith('/auth/me', { headers: undefined });
  });

  it('passes Authorization Bearer header when token is provided', async () => {
    mockGet.mockResolvedValueOnce({ data: meResponse });
    await getAuthMe('mytoken');
    expect(mockGet).toHaveBeenCalledWith('/auth/me', { headers: { Authorization: 'Bearer mytoken' } });
  });

  it('returns the me response fields', async () => {
    mockGet.mockResolvedValueOnce({ data: meResponse });
    const res = await getAuthMe();
    expect(res.email).toBe('a@b.com');
    expect(res._id).toBe('u1');
  });
});

describe('updateAuthMe', () => {
  beforeEach(() => vi.clearAllMocks());

  it('PATCHes /auth/me with the provided payload', async () => {
    mockPatch.mockResolvedValueOnce({ data: meResponse });
    await updateAuthMe({ displayName: 'Bob' });
    expect(mockPatch).toHaveBeenCalledWith('/auth/me', { displayName: 'Bob' });
  });
});

describe('updateAuthPassword', () => {
  beforeEach(() => vi.clearAllMocks());

  it('PATCHes /auth/me/password with current and new password', async () => {
    mockPatch.mockResolvedValueOnce({ data: { ok: true } });
    const res = await updateAuthPassword({ currentPassword: 'old', newPassword: 'new' });
    expect(mockPatch).toHaveBeenCalledWith('/auth/me/password', { currentPassword: 'old', newPassword: 'new' });
    expect(res.ok).toBe(true);
  });
});

describe('requestPasswordReset', () => {
  beforeEach(() => vi.clearAllMocks());

  it('POSTs to /auth/forgot-password with email', async () => {
    mockPost.mockResolvedValueOnce({ data: { ok: true } });
    const res = await requestPasswordReset('u@example.com');
    expect(mockPost).toHaveBeenCalledWith('/auth/forgot-password', { email: 'u@example.com' });
    expect(res.ok).toBe(true);
  });
});

describe('resetPassword', () => {
  beforeEach(() => vi.clearAllMocks());

  it('POSTs to /auth/reset-password with all required fields', async () => {
    mockPost.mockResolvedValueOnce({ data: { ok: true } });
    await resetPassword({ email: 'u@e.com', token: 'tok', newPassword: 'newpw' });
    expect(mockPost).toHaveBeenCalledWith('/auth/reset-password', {
      email: 'u@e.com', token: 'tok', newPassword: 'newpw',
    });
  });
});

describe('registerExpert', () => {
  beforeEach(() => vi.clearAllMocks());

  it('POSTs to /auth/register-expert with expert fields', async () => {
    mockPost.mockResolvedValueOnce({ data: { email: 'ex@example.com' } });
    const res = await registerExpert({ email: 'ex@example.com', password: 'pw', displayName: 'Expert' });
    expect(mockPost).toHaveBeenCalledWith('/auth/register-expert', expect.objectContaining({ email: 'ex@example.com' }));
    expect(res.email).toBe('ex@example.com');
  });
});

describe('requestAdminAccess', () => {
  beforeEach(() => vi.clearAllMocks());

  it('POSTs to /auth/request-admin-access', async () => {
    mockPost.mockResolvedValueOnce({ data: { email: 'a@b.com', status: 'pending' } });
    const res = await requestAdminAccess({ email: 'a@b.com', password: 'pw' });
    expect(mockPost).toHaveBeenCalledWith('/auth/request-admin-access', { email: 'a@b.com', password: 'pw' });
    expect(res.status).toBe('pending');
  });
});
