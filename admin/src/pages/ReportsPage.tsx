import { useState, useCallback, useMemo } from 'react';
import { getReports } from '../api/reports';
import { useApi } from '../hooks/useApi';
import { DataTable, type Column } from '../components/ui/DataTable';
import { Pagination } from '../components/ui/Pagination';
import { SearchInput } from '../components/ui/SearchInput';
import { MetricTile } from '../components/ui/MetricTile';
import { GlassCard } from '../components/ui/GlassCard';
import { PillBadge } from '../components/ui/PillBadge';
import { Modal } from '../components/ui/Modal';
import type { AdminReport } from '../types';

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', {
    day: '2-digit', month: 'short', year: 'numeric',
  });
}

export function ReportsPage() {
  const [page, setPage] = useState(1);
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<'newest' | 'oldest'>('newest');
  const [windowDays, setWindowDays] = useState<'7' | '30' | 'all'>('30');
  const [selectedReport, setSelectedReport] = useState<AdminReport | null>(null);

  const fetcher = useCallback(() => getReports(page, 20), [page]);
  const insightsFetcher = useCallback(() => getReports(1, 200), []);
  const { data, loading, error } = useApi(fetcher, [page]);
  const { data: insightsData } = useApi(insightsFetcher, []);

  const rows = data?.data ?? [];
  const insightRows = insightsData?.data ?? [];

  const filteredRows = useMemo(() => {
    const now = Date.now();
    const timeLimit = windowDays === 'all'
      ? 0
      : now - (Number(windowDays) * 24 * 60 * 60 * 1000);
    const q = query.trim().toLowerCase();

    return rows
      .filter((row) => {
        if (timeLimit > 0) {
          const created = new Date(row.createdAt).getTime();
          if (Number.isNaN(created) || created < timeLimit) return false;
        }

        if (!q) return true;
        return [row.title, row.notes, row.scouterDisplayName, row.playerDisplayName, row.scouterId, row.playerId]
          .join(' ')
          .toLowerCase()
          .includes(q);
      })
      .sort((a, b) => {
        const da = new Date(a.createdAt).getTime();
        const db = new Date(b.createdAt).getTime();
        return sort === 'newest' ? db - da : da - db;
      });
  }, [rows, windowDays, query, sort]);

  const insights = useMemo(() => {
    const source = insightRows;
    const total = source.length;
    const withVideo = source.filter((r) => !!r.videoId).length;
    const shortNotes = source.filter((r) => (r.notes?.trim().length ?? 0) < 30).length;
    const avgNotesLength = total
      ? Math.round(source.reduce((acc, r) => acc + (r.notes?.trim().length ?? 0), 0) / total)
      : 0;

    const scouters = new Map<string, { count: number; label: string }>();
    const players = new Map<string, { count: number; label: string }>();
    for (const r of source) {
      const scouterKey = r.scouterDisplayName || r.scouterId;
      const playerKey = r.playerDisplayName || r.playerId;
      const scouterPrev = scouters.get(scouterKey);
      const playerPrev = players.get(playerKey);
      scouters.set(scouterKey, { count: (scouterPrev?.count ?? 0) + 1, label: scouterKey });
      players.set(playerKey, { count: (playerPrev?.count ?? 0) + 1, label: playerKey });
    }

    const topScouter = [...scouters.values()].sort((a, b) => b.count - a.count)[0];
    const topPlayer = [...players.values()].sort((a, b) => b.count - a.count)[0];

    const last7Days = Array.from({ length: 7 }, (_, i) => {
      const d = new Date();
      d.setHours(0, 0, 0, 0);
      d.setDate(d.getDate() - (6 - i));
      return d;
    });

    const trend = last7Days.map((day) => {
      const label = day.toLocaleDateString('en-GB', { day: '2-digit', month: 'short' });
      const dayStart = day.getTime();
      const dayEnd = dayStart + 24 * 60 * 60 * 1000;
      const count = source.filter((r) => {
        const t = new Date(r.createdAt).getTime();
        return t >= dayStart && t < dayEnd;
      }).length;
      return { label, count };
    });

    return {
      sampleSize: total,
      withVideo,
      withoutVideo: total - withVideo,
      avgNotesLength,
      shortNotes,
      topScouter,
      topPlayer,
      trend,
    };
  }, [insightRows]);

  const columns: Column<AdminReport>[] = [
    {
      key: 'title',
      header: 'Title',
      render: (row) => (
        <button
          type="button"
          onClick={() => setSelectedReport(row)}
          style={{
            fontWeight: 700,
            color: 'var(--color-text)',
            background: 'transparent',
            border: 'none',
            textAlign: 'left',
            padding: 0,
            cursor: 'pointer',
          }}
          title="Open report details"
        >
          {row.title || '(untitled)'}
        </button>
      ),
    },
    {
      key: 'scouterDisplayName',
      header: 'Scouter',
      render: (row) => (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <span style={{ fontSize: 13, color: 'var(--color-text)', fontWeight: 600 }}>
            {row.scouterDisplayName || shortId(row.scouterId)}
          </span>
          <span style={{ fontSize: 11, color: 'var(--color-text-muted)', fontFamily: 'monospace' }}>
            {shortId(row.scouterId)}
          </span>
        </div>
      ),
    },
    {
      key: 'playerDisplayName',
      header: 'Player',
      render: (row) => (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <span style={{ fontSize: 13, color: 'var(--color-text)', fontWeight: 600 }}>
            {row.playerDisplayName || shortId(row.playerId)}
          </span>
          <span style={{ fontSize: 11, color: 'var(--color-text-muted)', fontFamily: 'monospace' }}>
            {shortId(row.playerId)}
          </span>
        </div>
      ),
    },
    {
      key: 'notes',
      header: 'Notes',
      render: (row) => {
        const notes = row.notes || '';
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
          {formatDate(row.createdAt)}
        </span>
      ),
    },
  ];

  if (error) {
    return <div style={{ color: 'var(--color-danger)', padding: 20 }}>Error: {error}</div>;
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 12 }}>
        <MetricTile label="Total Reports" value={data?.total ?? 0} valueColor="var(--color-text)" icon="📋" />
        <MetricTile label="Visible (Filters)" value={filteredRows.length} valueColor="var(--color-primary)" icon="🔎" />
        <MetricTile label="Avg Note Size" value={insights.avgNotesLength} valueColor="var(--color-accent)" icon="📝" />
        <MetricTile label="No Video Linked" value={insights.withoutVideo} valueColor="var(--color-warning)" icon="🎬" />
      </div>

      <GlassCard style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            <PillBadge variant="primary">Dynamic Report Insights</PillBadge>
            <PillBadge variant="muted">Sample: {insights.sampleSize}</PillBadge>
            {((insightsData?.total ?? 0) > insights.sampleSize) && (
              <PillBadge variant="warning">Partial sample of recent reports</PillBadge>
            )}
          </div>
          <div style={{ fontSize: 12, color: 'var(--color-text-muted)' }}>
            Trend updates from your latest reports in real time.
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 14 }}>
          <div style={insightPanelStyle}>
            <div style={insightTitleStyle}>Top Scouter</div>
            <div style={insightValueStyle}>{insights.topScouter?.label ?? 'No data'}</div>
            <div style={insightSubStyle}>{insights.topScouter?.count ?? 0} reports</div>
          </div>

          <div style={insightPanelStyle}>
            <div style={insightTitleStyle}>Most Reviewed Player</div>
            <div style={insightValueStyle}>{insights.topPlayer?.label ?? 'No data'}</div>
            <div style={insightSubStyle}>{insights.topPlayer?.count ?? 0} reports</div>
          </div>

          <div style={insightPanelStyle}>
            <div style={insightTitleStyle}>Data Quality Alert</div>
            <div style={insightValueStyle}>{insights.shortNotes}</div>
            <div style={insightSubStyle}>reports have very short notes (&lt; 30 chars)</div>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div style={{ fontSize: 12, fontWeight: 800, color: 'var(--color-text-muted)', letterSpacing: '1.2px', textTransform: 'uppercase' }}>
            Last 7 days report volume
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, minmax(0, 1fr))', gap: 8 }}>
            {insights.trend.map((p) => {
              const max = Math.max(...insights.trend.map((x) => x.count), 1);
              const heightPct = Math.max(16, Math.round((p.count / max) * 100));
              return (
                <div key={p.label} style={{ display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'center' }}>
                  <div style={{ height: 68, width: '100%', display: 'flex', alignItems: 'flex-end' }}>
                    <div
                      style={{
                        width: '100%',
                        borderRadius: 8,
                        height: `${heightPct}%`,
                        background: 'linear-gradient(180deg, rgba(29,99,255,0.9), rgba(183,244,8,0.8))',
                        border: '1px solid rgba(183,244,8,0.28)',
                      }}
                      title={`${p.label}: ${p.count}`}
                    />
                  </div>
                  <div style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>{p.label}</div>
                  <div style={{ fontSize: 12, color: 'var(--color-text)', fontWeight: 700 }}>{p.count}</div>
                </div>
              );
            })}
          </div>
        </div>
      </GlassCard>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, justifyContent: 'space-between', alignItems: 'center' }}>
        <SearchInput
          value={query}
          onChange={setQuery}
          placeholder="Search by title, notes, scouter name, player name"
          debounceMs={250}
        />
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <select value={windowDays} onChange={(e) => setWindowDays(e.target.value as '7' | '30' | 'all')} style={selectStyle}>
            <option value="7">Last 7 days</option>
            <option value="30">Last 30 days</option>
            <option value="all">All dates</option>
          </select>

          <select value={sort} onChange={(e) => setSort(e.target.value as 'newest' | 'oldest')} style={selectStyle}>
            <option value="newest">Newest first</option>
            <option value="oldest">Oldest first</option>
          </select>
        </div>
      </div>

      <DataTable
        columns={columns}
        rows={filteredRows}
        loading={loading}
        keyExtractor={(row) => row._id}
        emptyMessage="No reports found"
      />
      <Pagination
        page={page}
        total={data?.total ?? 0}
        limit={20}
        onChange={setPage}
      />

      <Modal
        open={!!selectedReport}
        onClose={() => setSelectedReport(null)}
        title={selectedReport?.title || 'Report details'}
        width={700}
      >
        {selectedReport && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
              <div style={detailBoxStyle}>
                <div style={detailLabelStyle}>Scouter</div>
                <div style={detailValueStyle}>{selectedReport.scouterDisplayName || 'Unknown'}</div>
                <div style={detailSubStyle}>{shortId(selectedReport.scouterId)}</div>
              </div>
              <div style={detailBoxStyle}>
                <div style={detailLabelStyle}>Player</div>
                <div style={detailValueStyle}>{selectedReport.playerDisplayName || 'Unknown'}</div>
                <div style={detailSubStyle}>{shortId(selectedReport.playerId)}</div>
              </div>
            </div>

            <div style={detailBoxStyle}>
              <div style={detailLabelStyle}>Created</div>
              <div style={detailValueStyle}>{formatDateTime(selectedReport.createdAt)}</div>
            </div>

            <div style={detailBoxStyle}>
              <div style={detailLabelStyle}>Video ID</div>
              <div style={detailSubStyle}>{selectedReport.videoId ? shortId(selectedReport.videoId) : 'No linked video'}</div>
            </div>

            <div style={detailBoxStyle}>
              <div style={detailLabelStyle}>Notes</div>
              <div style={{ whiteSpace: 'pre-wrap', color: 'var(--color-text)', fontSize: 14, lineHeight: 1.5 }}>
                {selectedReport.notes || 'No notes'}
              </div>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}

function shortId(value: string | undefined): string {
  if (!value) return 'No data';
  return `${value.slice(0, 4)}…${value.slice(-4)}`;
}

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString('en-GB', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

const insightPanelStyle: React.CSSProperties = {
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-card)',
  background: 'var(--color-surface2)',
  padding: '14px 16px',
};

const insightTitleStyle: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 800,
  textTransform: 'uppercase',
  letterSpacing: '1.1px',
  color: 'var(--color-text-muted)',
  marginBottom: 8,
};

const insightValueStyle: React.CSSProperties = {
  fontSize: 20,
  fontWeight: 900,
  color: 'var(--color-text)',
  marginBottom: 4,
};

const insightSubStyle: React.CSSProperties = {
  fontSize: 12,
  color: 'var(--color-text-muted)',
};

const selectStyle: React.CSSProperties = {
  background: 'var(--color-surface2)',
  border: '1px solid rgba(39,49,74,0.9)',
  borderRadius: 'var(--radius-input)',
  color: 'var(--color-text)',
  padding: '10px 12px',
  fontSize: 13,
};

const detailBoxStyle: React.CSSProperties = {
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-card)',
  background: 'var(--color-surface2)',
  padding: '12px 14px',
};

const detailLabelStyle: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 800,
  textTransform: 'uppercase',
  letterSpacing: '1.1px',
  color: 'var(--color-text-muted)',
  marginBottom: 6,
};

const detailValueStyle: React.CSSProperties = {
  fontSize: 15,
  fontWeight: 700,
  color: 'var(--color-text)',
};

const detailSubStyle: React.CSSProperties = {
  fontSize: 12,
  color: 'var(--color-text-muted)',
  marginTop: 4,
};
