import { useState, useCallback } from 'react';
import { getUsers, deleteUser, banUser, unbanUser, promoteToAdmin } from '../api/users';
import { useApi } from '../hooks/useApi';
import { DataTable, type Column } from '../components/ui/DataTable';
import { PillBadge } from '../components/ui/PillBadge';
import { Button } from '../components/ui/Button';
import { SearchInput } from '../components/ui/SearchInput';
import { Pagination } from '../components/ui/Pagination';
import { ConfirmDialog } from '../components/ui/ConfirmDialog';
import type { AdminUser } from '../types';

export function UsersPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('');

  const [deleteTarget, setDeleteTarget] = useState<AdminUser | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  const fetcher = useCallback(
    () => getUsers({ page, limit: 20, search, role: roleFilter || undefined }),
    [page, search, roleFilter],
  );

  const { data, loading, refetch } = useApi(fetcher, [page, search, roleFilter]);

  async function handleDelete(user: AdminUser) {
    setActionLoading(true);
    try {
      await deleteUser(user._id);
      setDeleteTarget(null);
      refetch();
    } catch (e: unknown) {
      alert((e as any)?.response?.data?.message || 'Delete failed');
    } finally {
      setActionLoading(false);
    }
  }

  async function handleToggleBan(user: AdminUser) {
    try {
      if (user.isBanned) await unbanUser(user._id);
      else await banUser(user._id);
      refetch();
    } catch (e: unknown) {
      alert((e as any)?.response?.data?.message || 'Action failed');
    }
  }

  async function handlePromoteToAdmin(user: AdminUser) {
    if (!confirm(`Promote "${user.email}" to admin?`)) return;
    try {
      await promoteToAdmin(user._id);
      refetch();
    } catch (e: unknown) {
      alert((e as any)?.response?.data?.message || 'Action failed');
    }
  }

  const columns: Column<Record<string, unknown>>[] = [
    {
      key: 'email',
      header: 'Email',
      render: (row) => (
        <span style={{ fontSize: 13, color: 'var(--color-text)' }}>{row.email as string}</span>
      ),
    },
    {
      key: 'displayName',
      header: 'Name',
      render: (row) => <span style={{ color: 'var(--color-text-muted)' }}>{(row.displayName as string) || '—'}</span>,
    },
    {
      key: 'role',
      header: 'Role',
      render: (row) => {
        const role = row.role as string;
        return (
          <PillBadge variant={role === 'scouter' ? 'primary' : role === 'admin' ? 'accent' : 'success'}>
            {role}
          </PillBadge>
        );
      },
    },
    {
      key: 'subscriptionTier',
      header: 'Plan',
      render: (row) =>
        row.subscriptionTier ? (
          <PillBadge variant="warning">{row.subscriptionTier as string}</PillBadge>
        ) : (
          <span style={{ color: 'var(--color-text-muted)' }}>—</span>
        ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (row) =>
        row.isBanned ? (
          <PillBadge variant="danger">Banned</PillBadge>
        ) : (
          <PillBadge variant="success">Active</PillBadge>
        ),
    },
    {
      key: '_actions',
      header: '',
      width: 240,
      render: (row) => {
        const user = row as unknown as AdminUser;
        return (
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            {user.role !== 'admin' && (
              <Button
                size="sm"
                variant="primary"
                onClick={() => handlePromoteToAdmin(user)}
                style={{ fontSize: 11 }}
              >
                Make Admin
              </Button>
            )}
            <Button
              size="sm"
              variant={user.isBanned ? 'warning' : 'warning'}
              onClick={() => handleToggleBan(user)}
              style={{ fontSize: 11 }}
            >
              {user.isBanned ? 'Unban' : 'Ban'}
            </Button>
            <Button
              size="sm"
              variant="danger"
              onClick={() => setDeleteTarget(user)}
              style={{ fontSize: 11 }}
            >
              Delete
            </Button>
          </div>
        );
      },
    },
  ];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      {/* Filters */}
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center' }}>
        <SearchInput
          value={search}
          onChange={(v) => { setSearch(v); setPage(1); }}
          placeholder="Search by email or name…"
        />
        <select
          value={roleFilter}
          onChange={(e) => { setRoleFilter(e.target.value); setPage(1); }}
          style={selectStyle}
        >
          <option value="">All roles</option>
          <option value="player">Player</option>
          <option value="scouter">Scouter</option>
          <option value="admin">Admin</option>
        </select>
      </div>

      {/* Table */}
      <DataTable
        columns={columns}
        rows={(data?.data ?? []) as unknown as Record<string, unknown>[]}
        loading={loading}
        keyExtractor={(row) => String(row._id)}
        emptyMessage="No users found"
      />

      {/* Pagination */}
      <Pagination
        page={page}
        total={data?.total ?? 0}
        limit={20}
        onChange={setPage}
      />

      {/* Confirm delete */}
      <ConfirmDialog
        open={!!deleteTarget}
        title="Delete User"
        message={`Are you sure you want to permanently delete "${deleteTarget?.email}"? This cannot be undone.`}
        confirmLabel="Delete"
        onConfirm={() => deleteTarget && handleDelete(deleteTarget)}
        onCancel={() => setDeleteTarget(null)}
        loading={actionLoading}
      />
    </div>
  );
}

const selectStyle: React.CSSProperties = {
  background: 'var(--color-surface2)',
  border: '1px solid rgba(39,49,74,0.9)',
  borderRadius: 'var(--radius-input)',
  color: 'var(--color-text)',
  padding: '10px 14px',
  fontSize: 13,
  cursor: 'pointer',
};
