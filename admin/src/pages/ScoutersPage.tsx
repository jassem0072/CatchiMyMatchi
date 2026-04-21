import { useState, useCallback } from 'react';
import { getScouters, getScouterDetail, updateSubscription } from '../api/scouters';
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
import type { AdminScouter, ScouterDetail } from '../types';

function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
}

// ── Subscription Modal ────────────────────────────────────────────────────────

function SubscriptionModal({
    scouter,
    onClose,
    onSaved,
}: {
    scouter: AdminScouter;
    onClose: () => void;
    onSaved: () => void;
}) {
    const [tier, setTier] = useState<string>(scouter.subscriptionTier || '');
    const [expiresAt, setExpiresAt] = useState<string>(
        scouter.subscriptionExpiresAt ? scouter.subscriptionExpiresAt.slice(0, 10) : '',
    );
    const [loading, setLoading] = useState(false);

    async function handleSave() {
        setLoading(true);
        try {
            await updateSubscription(scouter._id, tier || null, expiresAt || null);
            onSaved();
            onClose();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Update failed');
        } finally {
            setLoading(false);
        }
    }

    return (
        <div style={modalOverlay} onClick={onClose}>
            <div style={modalBox} onClick={(e) => e.stopPropagation()}>
                <h3 style={{ fontSize: 16, fontWeight: 900, marginBottom: 20 }}>Edit Subscription</h3>
                <div style={{ fontSize: 13, color: 'var(--color-text-muted)', marginBottom: 16 }}>
                    {scouter.displayName || scouter.email}
                </div>

                <label style={labelStyle}>Subscription Tier</label>
                <select value={tier} onChange={(e) => setTier(e.target.value)} style={{ ...inputStyle, marginBottom: 14 }}>
                    <option value="">No subscription</option>
                    <option value="basic">Basic — €1,000</option>
                    <option value="premium">Premium — €5,000</option>
                    <option value="elite">Elite — €10,000</option>
                </select>

                <label style={labelStyle}>Expires At</label>
                <input
                    type="date"
                    value={expiresAt}
                    onChange={(e) => setExpiresAt(e.target.value)}
                    style={{ ...inputStyle, marginBottom: 24 }}
                />

                <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
                    <Button variant="ghost" onClick={onClose}>Cancel</Button>
                    <Button variant="primary" onClick={handleSave} disabled={loading}>
                        {loading ? 'Saving…' : 'Save'}
                    </Button>
                </div>
            </div>
        </div>
    );
}

// ── Detail Panel ────────────────────────────────────────────────────────────

function ScouterDetailPanel({
    scouterId,
    onClose,
}: {
    scouterId: string;
    onClose: () => void;
}) {
    const fetcher = useCallback(() => getScouterDetail(scouterId), [scouterId]);
    const { data, loading, error } = useApi<ScouterDetail>(fetcher, [scouterId]);

    return (
        <div style={panelOverlay} onClick={onClose}>
            <div style={panelDrawer} onClick={(e) => e.stopPropagation()}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
                    <div>
                        <h2 style={{ fontSize: 20, fontWeight: 900, color: 'var(--color-text)', margin: 0 }}>
                            {loading ? 'Loading…' : data?.scouter.displayName || data?.scouter.email || '—'}
                        </h2>
                        <div style={{ fontSize: 12, color: 'var(--color-text-muted)', marginTop: 2 }}>Scouter Profile</div>
                    </div>
                    <button onClick={onClose} style={{ background: 'none', border: 'none', color: 'var(--color-text-muted)', fontSize: 20, cursor: 'pointer' }}>
                        ✕
                    </button>
                </div>

                {loading && <div style={{ color: 'var(--color-text-muted)', padding: 40, textAlign: 'center' }}>Loading…</div>}
                {error && <div style={{ color: 'var(--color-danger)', padding: 20 }}>{error}</div>}

                {data && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
                        {/* Stats tiles */}
                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))', gap: 10 }}>
                            <StatBox label="Reports Written" value={String(data.reports.length)} icon="📋" />
                            <StatBox label="Subscription" value={data.scouter.subscriptionTier || 'None'} icon="💳" />
                            <StatBox label="Sub Status" value={data.isExpired ? '⚠️ Expired' : '✅ Active'} icon="🗓️" />
                        </div>

                        {/* Profile */}
                        <GlassCard>
                            <div style={sectionTitle}>Profile</div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '6px 20px' }}>
                                <InfoRow label="Email" value={data.scouter.email} />
                                <InfoRow label="Plan" value={data.scouter.subscriptionTier || 'None'} />
                                <InfoRow label="Expires" value={data.scouter.subscriptionExpiresAt ? formatDate(data.scouter.subscriptionExpiresAt) : '—'} />
                                <InfoRow label="Badge" value={data.scouter.badgeVerified ? '✅ Verified' : '—'} />
                                <InfoRow label="Status" value={data.scouter.isBanned ? '🚫 Banned' : '✅ Active'} />
                                <InfoRow label="Joined" value={formatDate(data.scouter.createdAt)} />
                            </div>
                        </GlassCard>

                        {/* Reports */}
                        {data.reports.length > 0 && (
                            <GlassCard>
                                <div style={sectionTitle}>Reports Written ({data.reports.length})</div>
                                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 260, overflowY: 'auto' }}>
                                    {data.reports.map((r) => (
                                        <div key={r._id} style={{ fontSize: 12, padding: '8px 0', borderBottom: '1px solid var(--color-border)' }}>
                                            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                                                <span style={{ fontWeight: 700, color: 'var(--color-text)' }}>{r.title || '(untitled)'}</span>
                                                <span style={{ color: 'var(--color-text-muted)' }}>{formatDate(r.createdAt)}</span>
                                            </div>
                                            <div style={{ color: 'var(--color-accent)', marginTop: 2 }}>👤 {r.playerDisplayName}</div>
                                            <div style={{ color: 'var(--color-text-muted)', marginTop: 2 }}>
                                                {r.notes.length > 100 ? r.notes.slice(0, 100) + '…' : r.notes}
                                            </div>
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

export function ScoutersPage() {
    const [page, setPage] = useState(1);
    const [search, setSearch] = useState('');
    const [tierFilter, setTierFilter] = useState('');
    const [selectedId, setSelectedId] = useState<string | null>(null);
    const [subTarget, setSubTarget] = useState<AdminScouter | null>(null);
    const [deleteTarget, setDeleteTarget] = useState<AdminScouter | null>(null);
    const [actionLoading, setActionLoading] = useState(false);

    const fetcher = useCallback(
        () => getScouters({ page, limit: 20, search, subscriptionTier: tierFilter || undefined }),
        [page, search, tierFilter],
    );
    const { data, loading, refetch } = useApi(fetcher, [page, search, tierFilter]);

    const scouters = (data?.data ?? []) as AdminScouter[];
    const total = data?.total ?? 0;
    const activeSubs = scouters.filter((s) => s.subscriptionTier && !s.isExpired).length;
    const expiring = scouters.filter((s) => s.subscriptionTier && !s.isExpired && (s.expiresInDays ?? 999) <= 30).length;
    const banned = scouters.filter((s) => s.isBanned).length;

    async function handleDelete(scouter: AdminScouter) {
        setActionLoading(true);
        try {
            await deleteUser(scouter._id);
            setDeleteTarget(null);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Delete failed');
        } finally {
            setActionLoading(false);
        }
    }

    async function handleToggleBan(scouter: AdminScouter) {
        try {
            if (scouter.isBanned) await unbanUser(scouter._id);
            else await banUser(scouter._id);
            refetch();
        } catch (e: unknown) {
            alert((e as any)?.response?.data?.message || 'Action failed');
        }
    }

    const columns: Column<Record<string, unknown>>[] = [
        {
            key: 'displayName',
            header: 'Scouter',
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
            key: 'subscriptionTier',
            header: 'Plan',
            render: (row) => {
                const tier = row.subscriptionTier as string;
                const expired = row.isExpired as boolean;
                if (!tier) return <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>No Plan</span>;
                return (
                    <div>
                        <PillBadge variant={expired ? 'danger' : 'warning'}>{tier}</PillBadge>
                        {expired && <div style={{ fontSize: 10, color: 'var(--color-danger)', marginTop: 2 }}>EXPIRED</div>}
                    </div>
                );
            },
        },
        {
            key: 'subscriptionExpiresAt',
            header: 'Expires',
            render: (row) => {
                if (!row.subscriptionExpiresAt) return <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>—</span>;
                const days = row.expiresInDays as number;
                const color = days < 0 ? 'var(--color-danger)' : days <= 30 ? 'var(--color-warning)' : 'var(--color-text-muted)';
                return (
                    <div>
                        <div style={{ fontSize: 12, color }}>{formatDate(row.subscriptionExpiresAt as string)}</div>
                        {days !== null && <div style={{ fontSize: 10, color }}>{days < 0 ? `${Math.abs(days)}d ago` : `${days}d left`}</div>}
                    </div>
                );
            },
        },
        {
            key: 'reportCount',
            header: 'Reports',
            render: (row) => (
                <span style={{ fontWeight: 700, color: 'var(--color-accent)', fontSize: 13 }}>{row.reportCount as number ?? 0}</span>
            ),
        },
        {
            key: 'badgeVerified',
            header: 'Badge',
            render: (row) =>
                row.badgeVerified ? <PillBadge variant="success">Verified</PillBadge> : <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>—</span>,
        },
        {
            key: 'status',
            header: 'Status',
            render: (row) =>
                row.isBanned ? <PillBadge variant="danger">Banned</PillBadge> : <PillBadge variant="success">Active</PillBadge>,
        },
        {
            key: '_actions',
            header: '',
            width: 240,
            render: (row) => {
                const scouter = row as unknown as AdminScouter;
                return (
                    <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                        <Button size="sm" variant="ghost" onClick={() => setSelectedId(scouter._id)} style={{ fontSize: 11 }}>
                            View
                        </Button>
                        <Button size="sm" variant="primary" onClick={() => setSubTarget(scouter)} style={{ fontSize: 11 }}>
                            Edit Sub
                        </Button>
                        <Button size="sm" variant="warning" onClick={() => handleToggleBan(scouter)} style={{ fontSize: 11 }}>
                            {scouter.isBanned ? 'Unban' : 'Ban'}
                        </Button>
                        <Button size="sm" variant="danger" onClick={() => setDeleteTarget(scouter)} style={{ fontSize: 11 }}>
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
                <MetricTile label="Total Scouters" value={total} valueColor="var(--color-primary)" icon="🔭" />
                <MetricTile label="Active Subs (page)" value={activeSubs} valueColor="var(--color-success)" icon="💳" />
                <MetricTile label="Expiring ≤ 30d" value={expiring} valueColor="var(--color-warning)" icon="⏰" />
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
                rows={scouters as unknown as Record<string, unknown>[]}
                loading={loading}
                keyExtractor={(row) => String(row._id)}
                emptyMessage="No scouters found"
            />

            <Pagination page={page} total={total} limit={20} onChange={setPage} />

            {/* Detail panel */}
            {selectedId && (
                <ScouterDetailPanel scouterId={selectedId} onClose={() => setSelectedId(null)} />
            )}

            {/* Subscription edit modal */}
            {subTarget && (
                <SubscriptionModal
                    scouter={subTarget}
                    onClose={() => setSubTarget(null)}
                    onSaved={refetch}
                />
            )}

            {/* Confirm delete */}
            <ConfirmDialog
                open={!!deleteTarget}
                title="Delete Scouter"
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
            display: 'flex', flexDirection: 'column', gap: 4,
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
    width: 480, maxWidth: '95vw', height: '100vh',
    background: 'var(--color-surface)', borderLeft: '1px solid var(--color-border)',
    padding: 28, overflowY: 'auto', boxShadow: '-8px 0 40px rgba(0,0,0,0.4)',
};
const modalOverlay: React.CSSProperties = {
    position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.65)', zIndex: 1000,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
};
const modalBox: React.CSSProperties = {
    background: 'var(--color-surface)',
    border: '1px solid var(--color-border)',
    borderRadius: 18,
    padding: 28,
    width: 400,
    maxWidth: '95vw',
    boxShadow: '0 20px 60px rgba(0,0,0,0.6)',
};
const selectStyle: React.CSSProperties = {
    background: 'var(--color-surface2)', border: '1px solid rgba(39,49,74,0.9)',
    borderRadius: 'var(--radius-input)', color: 'var(--color-text)', padding: '10px 14px', fontSize: 13, cursor: 'pointer',
};
const inputStyle: React.CSSProperties = {
    width: '100%', background: 'var(--color-surface2)', border: '1px solid var(--color-border)',
    borderRadius: 10, color: 'var(--color-text)', padding: '10px 12px', fontSize: 13,
};
const labelStyle: React.CSSProperties = {
    display: 'block', fontSize: 11, fontWeight: 700, color: 'var(--color-text-muted)',
    textTransform: 'uppercase', letterSpacing: '0.8px', marginBottom: 6,
};
const avatarStyle: React.CSSProperties = {
    width: 34, height: 34, borderRadius: '50%',
    background: 'linear-gradient(135deg, #1D63FF, #B7F408)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontWeight: 900, fontSize: 14, flexShrink: 0,
};
const sectionTitle: React.CSSProperties = {
    fontSize: 10, fontWeight: 800, color: 'var(--color-text-muted)',
    textTransform: 'uppercase', letterSpacing: '1.4px', marginBottom: 12,
};
