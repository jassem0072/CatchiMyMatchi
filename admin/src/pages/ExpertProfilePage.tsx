import { useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { GlassCard } from '../components/ui/GlassCard';
import { Button } from '../components/ui/Button';
import { useApi } from '../hooks/useApi';
import { getExpertEarnings } from '../api/expert';

export function ExpertProfilePage() {
  const navigate = useNavigate();
  const fetcher = useCallback(() => getExpertEarnings(), []);
  const { data, loading, error } = useApi(fetcher, []);

  return (
    <div style={{ display: 'grid', gap: 16 }}>
      <GlassCard>
        <div>
          <div style={{ fontSize: 18, fontWeight: 900, marginBottom: 6 }}>Expert Profile</div>
          <div style={{ color: 'var(--color-text-muted)', fontSize: 13 }}>
            You earn EUR 30 for each player you verify.
          </div>
        </div>
      </GlassCard>

      {loading && <GlassCard>Loading earnings...</GlassCard>}
      {error && <GlassCard><span style={{ color: 'var(--color-danger)' }}>{error}</span></GlassCard>}

      {data && (
        <>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(180px,1fr))', gap: 12 }}>
            <GlassCard>
              <div style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>Verified Players</div>
              <div style={{ fontSize: 26, fontWeight: 900 }}>{data.verifiedPlayers}</div>
            </GlassCard>
            <GlassCard>
              <div style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>Pending Payout</div>
              <div style={{ fontSize: 26, fontWeight: 900 }}>EUR {data.pendingUsd}</div>
            </GlassCard>
            <GlassCard>
              <div style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>Already Paid</div>
              <div style={{ fontSize: 26, fontWeight: 900 }}>EUR {data.paidUsd}</div>
            </GlassCard>
          </div>

          <GlassCard>
            <div style={{ fontSize: 15, fontWeight: 800, marginBottom: 8 }}>Billing and Invoices</div>
            <div style={{ color: 'var(--color-text-muted)', fontSize: 13, marginBottom: 12 }}>
              Manage payout requests using PayPal or bank transfer billing details. ScoutAI never asks for full card details.
            </div>
            <Button variant="primary" onClick={() => navigate('/billing-invoices')}>
              Open Billing and Invoices
            </Button>
          </GlassCard>
        </>
      )}
    </div>
  );
}
