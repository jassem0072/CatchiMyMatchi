import { useState, useCallback } from 'react';
import { getReports } from '../api/reports';
import { useApi } from '../hooks/useApi';
import { DataTable, type Column } from '../components/ui/DataTable';
import { Pagination } from '../components/ui/Pagination';

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', {
    day: '2-digit', month: 'short', year: 'numeric',
  });
}

export function ReportsPage() {
  const [page, setPage] = useState(1);
  const fetcher = useCallback(() => getReports(page, 20), [page]);
  const { data, loading } = useApi(fetcher, [page]);

  const columns: Column<Record<string, unknown>>[] = [
    {
      key: 'title',
      header: 'Title',
      render: (row) => (
        <span style={{ fontWeight: 600 }}>{(row.title as string) || '(untitled)'}</span>
      ),
    },
    {
      key: 'scouterId',
      header: 'Scouter ID',
      render: (row) => (
        <span style={{ fontSize: 11, color: 'var(--color-text-muted)', fontFamily: 'monospace' }}>
          {String(row.scouterId).slice(-8)}…
        </span>
      ),
    },
    {
      key: 'playerId',
      header: 'Player ID',
      render: (row) => (
        <span style={{ fontSize: 11, color: 'var(--color-text-muted)', fontFamily: 'monospace' }}>
          {String(row.playerId).slice(-8)}…
        </span>
      ),
    },
    {
      key: 'notes',
      header: 'Notes',
      render: (row) => {
        const notes = (row.notes as string) || '';
        return (
          <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>
            {notes.length > 80 ? notes.slice(0, 80) + '…' : notes || '—'}
          </span>
        );
      },
    },
    {
      key: 'createdAt',
      header: 'Date',
      render: (row) => (
        <span style={{ fontSize: 12, color: 'var(--color-text-muted)' }}>
          {formatDate(row.createdAt as string)}
        </span>
      ),
    },
  ];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      <DataTable
        columns={columns}
        rows={(data?.data ?? []) as unknown as Record<string, unknown>[]}
        loading={loading}
        keyExtractor={(row) => String(row._id)}
        emptyMessage="No reports found"
      />
      <Pagination
        page={page}
        total={data?.total ?? 0}
        limit={20}
        onChange={setPage}
      />
    </div>
  );
}
