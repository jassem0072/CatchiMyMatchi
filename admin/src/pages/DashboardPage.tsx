import { getStats } from '../api/stats';
import { getAnalytics } from '../api/analytics';
import { useApi } from '../hooks/useApi';
import { MetricTile } from '../components/ui/MetricTile';
import { GlassCard } from '../components/ui/GlassCard';
import { RegistrationsLineChart } from '../charts/RegistrationsLineChart';
import { RoleDonutChart } from '../charts/RoleDonutChart';
import { SubscriptionBarChart } from '../charts/SubscriptionBarChart';
import type { AdminAnalytics } from '../types';

export function DashboardPage() {
  const { data: stats, loading, error } = useApi(() => getStats(), []);
  const { data: analytics } = useApi(() => getAnalytics(), []);

  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 300, color: 'var(--color-text-muted)' }}>
        Loading stats…
      </div>
    );
  }

  if (error) {
    return <div style={{ color: 'var(--color-danger)', padding: 20 }}>Error: {error}</div>;
  }

  const a = analytics as AdminAnalytics | null;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
      {/* ── Row 1: Core KPI tiles ── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 16 }}>
        <MetricTile label="Total Players" value={stats?.totalPlayers ?? 0} valueColor="var(--color-primary)" icon="⚽" />
        <MetricTile label="Total Scouters" value={stats?.totalScouterss ?? 0} valueColor="var(--color-accent)" icon="🔭" />
        <MetricTile label="Total Videos" value={stats?.totalVideos ?? 0} valueColor="var(--color-text)" icon="🎬" />
        <MetricTile label="Analyses Run" value={stats?.analyzedVideos ?? 0} valueColor="var(--color-success)" icon="📊" />
      </div>

      {/* ── Row 2: Extra KPI tiles from analytics ── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 16 }}>
        <MetricTile label="Active Subs" value={a?.activeSubscriptions ?? 0} valueColor="var(--color-success)" icon="💳" />
        <MetricTile label="Expiring ≤ 30d" value={a?.expiringSoon ?? 0} valueColor="var(--color-warning)" icon="⏰" />
        <MetricTile label="Banned Users" value={a?.bannedUsers ?? 0} valueColor="var(--color-danger)" icon="🚫" />
        <MetricTile label="Total Reports" value={a?.totalReports ?? 0} valueColor="var(--color-text)" icon="📋" />
      </div>

      {/* ── Row 3: Revenue summary ── */}
      {a && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 16 }}>
          <RevenueCard tier="Basic" count={a.revenueByTier.basic} price={1000} color="var(--color-text-muted)" />
          <RevenueCard tier="Premium" count={a.revenueByTier.premium} price={5000} color="var(--color-primary)" />
          <RevenueCard tier="Elite" count={a.revenueByTier.elite} price={10000} color="var(--color-accent)" />
          <div style={revTotalCard}>
            <div style={{ fontSize: 11, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '1px', marginBottom: 8 }}>Total Revenue</div>
            <div style={{ fontSize: 26, fontWeight: 900, color: 'var(--color-accent)' }}>
              €{a.revenueTotal.toLocaleString()}
            </div>
            <div style={{ fontSize: 11, color: 'var(--color-text-muted)', marginTop: 4 }}>all-time subscriptions</div>
          </div>
        </div>
      )}

      {/* ── Row 4: Charts ── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: 16 }}>
        <GlassCard>
          <h3 style={sectionTitle}>Monthly Registrations</h3>
          <RegistrationsLineChart data={stats?.registrations ?? []} />
        </GlassCard>
        <GlassCard>
          <h3 style={sectionTitle}>User Roles Distribution</h3>
          <RoleDonutChart players={stats?.totalPlayers ?? 0} scouterss={stats?.totalScouterss ?? 0} />
        </GlassCard>
      </div>

      <GlassCard style={{ maxWidth: 480 }}>
        <h3 style={sectionTitle}>Subscription Tiers</h3>
        <SubscriptionBarChart subscriptions={stats?.subscriptions ?? { basic: 0, premium: 0, elite: 0 }} />
      </GlassCard>

      {/* ── Row 5: Top performers ── */}
      {a && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 16 }}>
          <GlassCard>
            <h3 style={sectionTitle}>🔭 Top Scouters (by reports)</h3>
            <LeaderTable
              rows={a.topScouters.map((s) => ({ name: s.displayName, value: s.reportCount, label: 'reports' }))}
              accentColor="var(--color-primary)"
            />
          </GlassCard>
          <GlassCard>
            <h3 style={sectionTitle}>⚽ Most Scouted Players</h3>
            <LeaderTable
              rows={a.topPlayers.map((p) => ({ name: p.displayName, sub: p.position, value: p.reportCount, label: 'reports' }))}
              accentColor="var(--color-accent)"
            />
          </GlassCard>
        </div>
      )}
    </div>
  );
}

// ── Sub-components ──────────────────────────────────────────────────────────

function RevenueCard({ tier, count, price, color }: { tier: string; count: number; price: number; color: string }) {
  return (
    <div style={{
      background: 'var(--color-surface2)', border: '1px solid var(--color-border)',
      borderRadius: 'var(--radius-card)', padding: '18px 20px',
    }}>
      <div style={{ fontSize: 11, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '1px', marginBottom: 6 }}>
        {tier}
      </div>
      <div style={{ fontSize: 22, fontWeight: 900, color }}>{count} subs</div>
      <div style={{ fontSize: 12, color: 'var(--color-text-muted)', marginTop: 4 }}>
        €{(count * price).toLocaleString()}
      </div>
    </div>
  );
}

function LeaderTable({
  rows,
  accentColor,
}: {
  rows: { name: string; sub?: string; value: number; label: string }[];
  accentColor: string;
}) {
  if (!rows.length) return <div style={{ color: 'var(--color-text-muted)', fontSize: 13 }}>No data yet</div>;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {rows.map((row, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{
            width: 24, height: 24, borderRadius: '50%', background: accentColor,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 11, fontWeight: 900, color: '#000', flexShrink: 0,
          }}>
            {i + 1}
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--color-text)' }}>{row.name}</div>
            {row.sub && <div style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>{row.sub}</div>}
          </div>
          <div style={{ fontSize: 13, fontWeight: 700, color: accentColor }}>
            {row.value} <span style={{ fontWeight: 400, color: 'var(--color-text-muted)', fontSize: 11 }}>{row.label}</span>
          </div>
        </div>
      ))}
    </div>
  );
}

// ── Styles ──────────────────────────────────────────────────────────────────

const sectionTitle: React.CSSProperties = {
  fontSize: 12, fontWeight: 800, color: 'var(--color-text-muted)',
  textTransform: 'uppercase', letterSpacing: '1.4px', marginBottom: 16,
};

const revTotalCard: React.CSSProperties = {
  background: 'linear-gradient(135deg, rgba(29,99,255,0.15), rgba(183,244,8,0.12))',
  border: '1px solid rgba(183,244,8,0.25)',
  borderRadius: 'var(--radius-card)',
  padding: '18px 20px',
};
