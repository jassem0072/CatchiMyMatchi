/**
 * users-api.test.ts — Logic tests for users API module
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../../api/client', () => ({
  default: { get: vi.fn(), patch: vi.fn(), delete: vi.fn() },
}));

import client from '../../api/client';
import { getUsers, deleteUser, banUser, unbanUser, promoteToAdmin, approveAdminRequest } from '../../api/users';

const mockGet = client.get as ReturnType<typeof vi.fn>;
const mockPatch = client.patch as ReturnType<typeof vi.fn>;
const mockDelete = client.delete as ReturnType<typeof vi.fn>;

const fakeUser = { _id: 'u1', email: 'u@example.com', role: 'player', isBanned: false };

describe('getUsers', () => {
  beforeEach(() => vi.clearAllMocks());
  it('calls GET /admin/users with empty params by default', async () => {
    mockGet.mockResolvedValueOnce({ data: { data: [], total: 0 } });
    await getUsers();
    expect(mockGet).toHaveBeenCalledWith('/admin/users', { params: {} });
  });
  it('passes page, limit, search, role params', async () => {
    mockGet.mockResolvedValueOnce({ data: { data: [], total: 0 } });
    await getUsers({ page: 2, limit: 10, search: 'alice', role: 'expert' });
    expect(mockGet).toHaveBeenCalledWith('/admin/users', { params: { page: 2, limit: 10, search: 'alice', role: 'expert' } });
  });
  it('returns paginated response', async () => {
    mockGet.mockResolvedValueOnce({ data: { data: [fakeUser], total: 1 } });
    const res = await getUsers();
    expect(res.data).toHaveLength(1);
    expect(res.data[0].email).toBe('u@example.com');
    expect(res.total).toBe(1);
  });
  it('omits undefined params', async () => {
    mockGet.mockResolvedValueOnce({ data: { data: [], total: 0 } });
    await getUsers({ search: 'bob' });
    const params = (mockGet.mock.calls[0][1] as { params: Record<string, unknown> }).params;
    expect(params.search).toBe('bob');
    expect(params.page).toBeUndefined();
  });
});

describe('deleteUser', () => {
  beforeEach(() => vi.clearAllMocks());
  it('calls DELETE /admin/users/:id', async () => {
    mockDelete.mockResolvedValueOnce({});
    await deleteUser('u-del');
    expect(mockDelete).toHaveBeenCalledWith('/admin/users/u-del');
  });
});

describe('banUser', () => {
  beforeEach(() => vi.clearAllMocks());
  it('PATCHes /admin/users/:id/ban', async () => {
    mockPatch.mockResolvedValueOnce({ data: { ...fakeUser, isBanned: true } });
    const res = await banUser('u1');
    expect(mockPatch).toHaveBeenCalledWith('/admin/users/u1/ban');
    expect(res.isBanned).toBe(true);
  });
});

describe('unbanUser', () => {
  beforeEach(() => vi.clearAllMocks());
  it('PATCHes /admin/users/:id/unban', async () => {
    mockPatch.mockResolvedValueOnce({ data: { ...fakeUser, isBanned: false } });
    const res = await unbanUser('u1');
    expect(mockPatch).toHaveBeenCalledWith('/admin/users/u1/unban');
    expect(res.isBanned).toBe(false);
  });
});

describe('promoteToAdmin', () => {
  beforeEach(() => vi.clearAllMocks());
  it('PATCHes /admin/users/:id/role with admin role', async () => {
    mockPatch.mockResolvedValueOnce({ data: { ...fakeUser, role: 'admin' } });
    const res = await promoteToAdmin('u1');
    expect(mockPatch).toHaveBeenCalledWith('/admin/users/u1/role', { role: 'admin' });
    expect(res.role).toBe('admin');
  });
});

describe('approveAdminRequest', () => {
  beforeEach(() => vi.clearAllMocks());
  it('PATCHes /admin/users/:id/approve-admin-request', async () => {
    mockPatch.mockResolvedValueOnce({ data: fakeUser });
    await approveAdminRequest('u1');
    expect(mockPatch).toHaveBeenCalledWith('/admin/users/u1/approve-admin-request');
  });
});
