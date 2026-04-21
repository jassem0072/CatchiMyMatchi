import { useState, useCallback } from 'react';
import { getPlayers, getPlayerDetail } from '../api/players';
import { deleteUser, banUser, unbanUser } from '../api/users';
import { useApi } from '../hooks/useApi';
import { DataTable, type Column } from '../components/ui/DataTable';
import { PillBadge } from '../components/ui/PillBadge';
import { Button } from '../components/ui/Button';
import { SearchInput } from '../components/ui/SearchInput';
import { Pagination } from '../components/ui/Pagination';
import { ConfirmDialog } from '../components/ui/ConfirmDialog';
import { MetricTile } from '../components/ui/MetricTile';
import { GlassCard } from '../components/ui/GlassCard';
import type { AdminPlayer, PlayerDetail } from '../types';

function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
}

function calcAge(dob: string | null | undefined): string {
    if (!dob) return '—';
    const birth = new Date(dob);
    const today = new Date();
    const age = today.getFullYear() - birth.getFullYear();
    return String(age);
}

// ── Detail Panel ────────────────────────────────────────────────────────────

function PlayerDetailPanel({
    playerId,
    onClose,
    onAction,
}: {
    playerId: string;
    onClose: () => void;
    onAction: () => void;
}) {
    const fetcher = useCallback(() => getPlayerDetail(playerId), [playerId]);
    const { data, loading, error } = useApi(fetcher, [playerId]);

    return (
        <div style={panelOverlay} onClick={onClose}>
            <div style={panelDrawer} onClick={(e) => e.stopPropagation()}>
                {/* Header */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
                    <div>
                        <h2 style={{ fontSize: 20, fontWeight: 900, color: 'var(--color-text)', margin: 0 }}>
                            {loading ? 'Loading…' : data?.player.displayName || data?.player.email || '—'}
                        </h2>
                        <div style={{ fontSize: 12, color: 'var(--color-text-muted)', marginTop: 2 }}>
                            Player Profile
                        </div>
                    </div>
                    <button
                        onClick={onClose}
                        style={{ background: 'none', border: 'none', color: 'var(--color-text-muted)', fontSize: 20, cursor: 'pointer' }}
                    >
                        ✕
                    </button>
                </div>

                {loading && <div style={{ color: 'var(--color-text-muted)', padding: 40, textAlign: 'center' }}>Loading…</div>}
                {error && <div style={{ color: 'var(--color-danger)', padding: 20 }}>{error}</div>}

                {data && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
                        {/* Analytics tiles */}
                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))', gap: 10 }}>
                            <StatBox label="Videos" value={String(data.analytics.totalVideos)} icon="🎬" />
                            <StatBox label="Analyzed" value={String(data.analytics.analyzedVideos)} icon="📊" />
                            <StatBox label="Reports" value={String(data.analytics.reportsAboutPlayer)} icon="📋" />
                            <StatBox label="Max Speed" value={`${data.analytics.maxSpeedKmh} km/h`} icon="⚡" />
                            <StatBox label="Avg Speed" value={`${data.analytics.avgSpeedKmh} km/h`} icon="🏃" />
                            <StatBox label="Sprints" value={String(data.analytics.totalSprints)} icon="💨" />
                        </div>

                        {/* Profile info */}
                        <GlassCard>
                            <div style={sectionTitle}>Profile</div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '6px 20px' }}>
                                <InfoRow label="Email" value={data.player.email} />
                                <InfoRow label="Position" value={data.player.position || '—'} />
                                <InfoRow label="Nation" value={data.player.nation || '—'} />
                                <InfoRow label="Age" value={calcAge(data.player.dateOfBirth)} />
                                <InfoRow label="Height" value={data.player.height ? `${data.player.height} cm` : '—'} />
                                <InfoRow label="Badge" value={data.player.badgeVerified ? '✅ Verified' : '—'} />
                                <InfoRow label="Plan" value={data.player.subscriptionTier || 'None'} />
                                <InfoRow label="Joined" value={formatDate(data.player.createdAt)} />
                            </div>
                        </GlassCard>

                        {/* Videos */}
                        {data.videos.length > 0 && (
                            <GlassCard>
                                <div style={sectionTitle}>Videos ({data.videos.length})</div>
                                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 180, overflowY: 'auto' }}>
                                    {data.videos.map((v) => (
                                        <div key={v._id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, padding: '4px 0', borderBottom: '1px solid var(--color-border)' }}>
                                            <span style={{ color: 'var(--color-text)', fontWeight: 600 }}>{v.originalName}</span>
                                            <span style={{ color: 'var(--color-text-muted)' }}>{formatDate(v.createdAt)}</span>
                                        </div>
                                    ))}
                                </div>
                            </GlassCard>
                        )}

                        {/* Reports */}
                        {data.reports.length > 0 && (
                            <GlassCard>
                                <div style={sectionTitle}>Scouting Reports ({data.reports.length})</div>
                                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 180, overflowY: 'auto' }}>
                                    {data.reports.map((r) => (
                                        <div key={r._id} style={{ fontSize: 12, padding: '6px 0', borderBottom: '1px solid var(--color-border)' }}>
                                            <div style={{ fontWeight: 700, color: 'var(--color-text)' }}>{r.title || '(untitled)'}</div>
                                            <div style={{ color: 'var(--color-text-muted)', marginTop: 2 }}>
                                                {r.notes.length > 80 ? r.notes.slice(0, 80) + '…' : r.notes}
                                            </div>
                                            <div style={{ color: 'var(--color-text-muted)', marginTop: 2 }}>{formatDate(r.createdAt)}</div>
                                        </div>
                                    ))}
                                </div>
                            </GlassCard>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
}

// ── Main Page ────────────────────────────────────────────────────────────────

export function PlayersPage() {
    const [page, setPage] = useState(1);
    const [search, setSearch] = useState('');
    const [tierFilter, setTierFilter] = useState('');
    const [selectedId, setSelectedId] = useState<string | null>(null);
    const [deleteTarget, setDeleteTarget] = useState<AdminPlayer | null>(null);
    const [actionLoading, setActionLoading] = useState(false);

    const fetcher = useCallback(
        () => getPlayers({ page, limit: 20, search, subscriptionTier: tierFilter || undefined }),
        [page, search, tierFilter],
    );
    const { data, loading, refetch } = useApi(fetcher, [page, search, tierFilter]);

    const players = (data?.data ?? []) as AdminPlayer[];
    const total = data?.total ?? 0;

    // Summary KPIs from loaded slice
    const totalLoaded = players.length;
    const withBadge = players.filter((p) => p.badgeVerified).length;
    const banned = players.filter((p) => p.isBanned).length;
    const avgVideos = totalLoaded ? (players.reduce((s, p) => s + (p.videoCount ?? 0), 0) / totalLoaded).toFixed(1) : '0';

    async function handleDelete(player: AdminPlayer) {
        setActionLoading(true);
        try {
            await deleteUser(player._id);
            setDeleteTarget(null);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Delete failed');
        } finally {
            setActionLoading(false);
        }
    }

    async function handleToggleBan(player: AdminPlayer) {
        try {
            if (player.isBanned) await unbanUser(player._id);
            else await banUser(player._id);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Action failed');
        }
    }

    const columns: Column<Record<string, unknown>>[] = [
        {
            key: 'displayName',
            header: 'Player',
            render: (row) => (
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <div style={avatarStyle}>{(row.displayName as string || row.email as string || '?')[0].toUpperCase()}</div>
                    <div>
                        <div style={{ fontWeight: 700, fontSize: 13 }}>{(row.displayName as string) || '—'}</div>
                        <div style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>{row.email as string}</div>
                    </div>
                </div>
            ),
        },
        {
            key: 'position',
            header: 'Position',
            render: (row) => <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>{(row.position as string) || '—'}</span>,
        },
        {
            key: 'nation',
            header: 'Nation',
            render: (row) => <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>{(row.nation as string) || '—'}</span>,
        },
        {
            key: 'age',
            header: 'Age',
            render: (row) => <span style={{ fontSize: 12 }}>{calcAge(row.dateOfBirth as string)}</span>,
        },
        {
            key: 'height',
            header: 'Height',
            render: (row) => <span style={{ fontSize: 12 }}>{row.height ? `${row.height} cm` : '—'}</span>,
        },
        {
            key: 'subscriptionTier',
            header: 'Plan',
            render: (row) =>
                row.subscriptionTier ? (
                    <PillBadge variant="warning">{row.subscriptionTier as string}</PillBadge>
                ) : (
                    <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>—</span>
                ),
        },
        {
            key: 'videoCount',
            header: 'Videos',
            render: (row) => (
                <span style={{ fontWeight: 700, color: 'var(--color-primary)', fontSize: 13 }}>{row.videoCount as number ?? 0}</span>
            ),
        },
        {
            key: 'reportCount',
            header: 'Reports',
            render: (row) => (
                <span style={{ fontWeight: 700, color: 'var(--color-accent)', fontSize: 13 }}>{row.reportCount as number ?? 0}</span>
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
            width: 200,
            render: (row) => {
                const player = row as unknown as AdminPlayer;
                return (
                    <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                        <Button size="sm" variant="ghost" onClick={() => setSelectedId(player._id)} style={{ fontSize: 11 }}>
                            View
                        </Button>
                        <Button size="sm" variant="warning" onClick={() => handleToggleBan(player)} style={{ fontSize: 11 }}>
                            {player.isBanned ? 'Unban' : 'Ban'}
                        </Button>
                        <Button size="sm" variant="danger" onClick={() => setDeleteTarget(player)} style={{ fontSize: 11 }}>
                            Delete
                        </Button>
                    </div>
                );
            },
        },
    ];

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            {/* KPI Tiles */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 14 }}>
                <MetricTile label="Total Players" value={total} valueColor="var(--color-primary)" icon="⚽" />
                <MetricTile label="Avg Videos / Player" value={Number(avgVideos)} valueColor="var(--color-text)" icon="🎬" />
                <MetricTile label="Badge Verified" value={withBadge} valueColor="var(--color-accent)" icon="✅" />
                <MetricTile label="Banned" value={banned} valueColor="var(--color-danger)" icon="🚫" />
            </div>

            {/* Filters */}
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center' }}>
                <SearchInput
                    value={search}
                    onChange={(v) => { setSearch(v); setPage(1); }}
                    placeholder="Search by name or email…"
                />
                <select
                    value={tierFilter}
                    onChange={(e) => { setTierFilter(e.target.value); setPage(1); }}
                    style={selectStyle}
                >
                    <option value="">All plans</option>
                    <option value="basic">Basic</option>
                    <option value="premium">Premium</option>
                    <option value="elite">Elite</option>
                </select>
            </div>

            {/* Table */}
            <DataTable
                columns={columns}
                rows={players as unknown as Record<string, unknown>[]}
                loading={loading}
                keyExtractor={(row) => String(row._id)}
                emptyMessage="No players found"
            />

            {/* Pagination */}
            <Pagination page={page} total={total} limit={20} onChange={setPage} />

            {/* Detail panel */}
            {selectedId && (
                <PlayerDetailPanel
                    playerId={selectedId}
                    onClose={() => setSelectedId(null)}
                    onAction={refetch}
                />
            )}

            {/* Confirm delete */}
            <ConfirmDialog
                open={!!deleteTarget}
                title="Delete Player"
                message={`Permanently delete "${deleteTarget?.email}"?`}
                confirmLabel="Delete"
                onConfirm={() => deleteTarget && handleDelete(deleteTarget)}
                onCancel={() => setDeleteTarget(null)}
                loading={actionLoading}
            />
        </div>
    );
}

// ── Sub-components ────────────────────────────────────────────────────────────

function StatBox({ label, value, icon }: { label: string; value: string; icon: string }) {
    return (
        <div style={{
            background: 'var(--color-surface2)',
            borderRadius: 12,
            padding: '12px 14px',
            border: '1px solid var(--color-border)',
            display: 'flex',
            flexDirection: 'column',
            gap: 4,
        }}>
            <span style={{ fontSize: 18 }}>{icon}</span>
            <span style={{ fontSize: 16, fontWeight: 900, color: 'var(--color-text)' }}>{value}</span>
            <span style={{ fontSize: 10, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '0.8px' }}>{label}</span>
        </div>
    );
}

function InfoRow({ label, value }: { label: string; value: string }) {
    return (
        <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: '1px solid var(--color-border)', fontSize: 12 }}>
            <span style={{ color: 'var(--color-text-muted)' }}>{label}</span>
            <span style={{ color: 'var(--color-text)', fontWeight: 600 }}>{value}</span>
        </div>
    );
}

// ── Styles ─────────────────────────────────────────────────────────────────

const panelOverlay: React.CSSProperties = {
    position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.55)', zIndex: 900, display: 'flex', justifyContent: 'flex-end',
};

const panelDrawer: React.CSSProperties = {
    width: 480,
    maxWidth: '95vw',
    height: '100vh',
    background: 'var(--color-surface)',
    borderLeft: '1px solid var(--color-border)',
    padding: 28,
    overflowY: 'auto',
    boxShadow: '-8px 0 40px rgba(0,0,0,0.4)',
};

const selectStyle: React.CSSProperties = {
    background: 'var(--color-surface2)',
    border: '1px solid rgba(39,49,74,0.9)',
    borderRadius: 'var(--radius-input)',
    color: 'var(--color-text)',
    padding: '10px 14px',
    fontSize: 13,
    cursor: 'pointer',
};

const avatarStyle: React.CSSProperties = {
    width: 34,
    height: 34,
    borderRadius: '50%',
    background: 'linear-gradient(135deg, var(--color-primary), var(--color-accent))',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontWeight: 900,
    fontSize: 14,
    flexShrink: 0,
};

const sectionTitle: React.CSSProperties = {
    fontSize: 10,
    fontWeight: 800,
    color: 'var(--color-text-muted)',
    textTransform: 'uppercase',
    letterSpacing: '1.4px',
    marginBottom: 12,
};
