import { useState, useCallback } from 'react';
import { getVideos, deleteVideo, setVideoVisibility } from '../api/videos';
import { useApi } from '../hooks/useApi';
import { DataTable, type Column } from '../components/ui/DataTable';
import { PillBadge } from '../components/ui/PillBadge';
import { Button } from '../components/ui/Button';
import { Pagination } from '../components/ui/Pagination';
import { ConfirmDialog } from '../components/ui/ConfirmDialog';
import type { AdminVideo } from '../types';

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', {
    day: '2-digit', month: 'short', year: 'numeric',
  });
}

export function VideosPage() {
  const [page, setPage] = useState(1);
  const [deleteTarget, setDeleteTarget] = useState<AdminVideo | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  const fetcher = useCallback(() => getVideos(page, 20), [page]);
  const { data, loading, refetch } = useApi(fetcher, [page]);

  async function handleDelete(video: AdminVideo) {
    setActionLoading(true);
    try {
      await deleteVideo(video._id);
      setDeleteTarget(null);
      refetch();
    } catch (e: unknown) {
      alert((e as any)?.response?.data?.message || 'Delete failed');
    } finally {
      setActionLoading(false);
    }
  }

  async function handleToggleVisibility(video: AdminVideo) {
    try {
      await setVideoVisibility(video._id, video.visibility === 'public' ? 'private' : 'public');
      refetch();
    } catch (e: unknown) {
      alert((e as any)?.response?.data?.message || 'Update failed');
    }
  }

  const columns: Column<Record<string, unknown>>[] = [
    {
      key: 'originalName',
      header: 'Filename',
      render: (row) => (
        <div>
          <div style={{ fontSize: 13, fontWeight: 600 }}>{row.originalName as string}</div>
          <div style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>{row.filename as string}</div>
        </div>
      ),
    },
    {
      key: 'ownerDisplayName',
      header: 'Owner',
      render: (row) => (
        <span style={{ color: 'var(--color-text-muted)' }}>{row.ownerDisplayName as string}</span>
      ),
    },
    {
      key: 'size',
      header: 'Size',
      render: (row) => formatSize(row.size as number),
    },
    {
      key: 'visibility',
      header: 'Visibility',
      render: (row) => {
        const vis = row.visibility as string;
        return (
          <PillBadge variant={vis === 'public' ? 'success' : 'muted'}>
            {vis}
          </PillBadge>
        );
      },
    },
    {
      key: 'analyzed',
      header: 'Analyzed',
      render: (row) =>
        row.lastAnalysis ? (
          <PillBadge variant="primary">Yes</PillBadge>
        ) : (
          <PillBadge variant="muted">No</PillBadge>
        ),
    },
    {
      key: 'createdAt',
      header: 'Uploaded',
      render: (row) => (
        <span style={{ fontSize: 12, color: 'var(--color-text-muted)' }}>{formatDate(row.createdAt as string)}</span>
      ),
    },
    {
      key: '_actions',
      header: '',
      width: 180,
      render: (row) => {
        const video = row as unknown as AdminVideo;
        return (
          <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => handleToggleVisibility(video)}
              style={{ fontSize: 11 }}
            >
              {video.visibility === 'public' ? 'Make Private' : 'Make Public'}
            </Button>
            <Button
              size="sm"
              variant="danger"
              onClick={() => setDeleteTarget(video)}
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
      <DataTable
        columns={columns}
        rows={(data?.data ?? []) as unknown as Record<string, unknown>[]}
        loading={loading}
        keyExtractor={(row) => String(row._id)}
        emptyMessage="No videos found"
      />

      <Pagination
        page={page}
        total={data?.total ?? 0}
        limit={20}
        onChange={setPage}
      />

      <ConfirmDialog
        open={!!deleteTarget}
        title="Delete Video"
        message={`Are you sure you want to permanently delete "${deleteTarget?.originalName}"?`}
        confirmLabel="Delete"
        onConfirm={() => deleteTarget && handleDelete(deleteTarget)}
        onCancel={() => setDeleteTarget(null)}
        loading={actionLoading}
      />
    </div>
  );
}
