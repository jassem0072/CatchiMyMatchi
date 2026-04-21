import { useState, type FormEvent } from 'react';
import { broadcastNotification } from '../api/notifications';
import { GlassCard } from '../components/ui/GlassCard';
import { Button } from '../components/ui/Button';

export function NotificationsPage() {
  const [titleEN, setTitleEN] = useState('');
  const [titleFR, setTitleFR] = useState('');
  const [bodyEN, setBodyEN] = useState('');
  const [bodyFR, setBodyFR] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ sent: number } | null>(null);
  const [error, setError] = useState('');

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    setResult(null);
    setLoading(true);
    try {
      const res = await broadcastNotification({ titleEN, titleFR, bodyEN, bodyFR });
      setResult(res);
      setTitleEN('');
      setTitleFR('');
      setBodyEN('');
      setBodyFR('');
    } catch (err: unknown) {
      setError((err as any)?.response?.data?.message || 'Broadcast failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div style={{ maxWidth: 640 }}>
      <p style={{ color: 'var(--color-text-muted)', marginBottom: 24, lineHeight: 1.7 }}>
        Send a notification to <strong style={{ color: 'var(--color-text)' }}>all users</strong> in the platform (both EN and FR content required).
      </p>

      <GlassCard>
        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
            <div>
              <label style={labelStyle}>Title (English)</label>
              <input
                type="text"
                value={titleEN}
                onChange={(e) => setTitleEN(e.target.value)}
                required
                placeholder="Announcement"
                style={inputStyle}
              />
            </div>
            <div>
              <label style={labelStyle}>Title (Français)</label>
              <input
                type="text"
                value={titleFR}
                onChange={(e) => setTitleFR(e.target.value)}
                required
                placeholder="Annonce"
                style={inputStyle}
              />
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
            <div>
              <label style={labelStyle}>Body (English)</label>
              <textarea
                value={bodyEN}
                onChange={(e) => setBodyEN(e.target.value)}
                rows={4}
                placeholder="Message content…"
                style={{ ...inputStyle, resize: 'vertical' }}
              />
            </div>
            <div>
              <label style={labelStyle}>Body (Français)</label>
              <textarea
                value={bodyFR}
                onChange={(e) => setBodyFR(e.target.value)}
                rows={4}
                placeholder="Contenu du message…"
                style={{ ...inputStyle, resize: 'vertical' }}
              />
            </div>
          </div>

          {error && (
            <div style={{ background: 'rgba(255,77,79,0.1)', border: '1px solid rgba(255,77,79,0.4)', borderRadius: 10, padding: '10px 14px', fontSize: 13, color: 'var(--color-danger)' }}>
              {error}
            </div>
          )}

          {result && (
            <div style={{ background: 'rgba(50,213,131,0.1)', border: '1px solid rgba(50,213,131,0.4)', borderRadius: 10, padding: '12px 16px', fontSize: 14, color: 'var(--color-success)', fontWeight: 600 }}>
              ✓ Notification sent to {result.sent} users
            </div>
          )}

          <Button
            type="submit"
            variant="primary"
            disabled={loading}
            style={{ alignSelf: 'flex-start', minWidth: 200, height: 46 }}
          >
            {loading ? 'Broadcasting…' : '📢 Broadcast to All Users'}
          </Button>
        </form>
      </GlassCard>
    </div>
  );
}

const labelStyle: React.CSSProperties = {
  display: 'block',
  fontSize: 11,
  fontWeight: 800,
  color: 'var(--color-text-muted)',
  textTransform: 'uppercase',
  letterSpacing: '1.2px',
  marginBottom: 8,
};

const inputStyle: React.CSSProperties = {
  width: '100%',
  background: 'var(--color-surface2)',
  border: '1px solid rgba(39,49,74,0.9)',
  borderRadius: 'var(--radius-input)',
  color: 'var(--color-text)',
  padding: '10px 14px',
  fontSize: 14,
};
