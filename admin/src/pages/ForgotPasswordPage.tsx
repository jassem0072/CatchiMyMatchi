import { useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { requestPasswordReset } from '../api/auth';
import { GlassCard } from '../components/ui/GlassCard';
import { Button } from '../components/ui/Button';

export function ForgotPasswordPage() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [email, setEmail] = useState(params.get('email') || '');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  useEffect(() => {
    const token = params.get('token');
    const qEmail = params.get('email');
    if (token && qEmail) {
      navigate(`/reset-password?email=${encodeURIComponent(qEmail)}&token=${encodeURIComponent(token)}`, { replace: true });
    }
  }, [navigate, params]);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    setSuccess('');
    setLoading(true);
    try {
      await requestPasswordReset(email.trim());
      setSuccess('If this email exists, a reset link has been sent. Check your inbox.');
    } catch (err: unknown) {
      const msg =
        (err as any)?.response?.data?.message ||
        (err as any)?.message ||
        'Unable to process request';
      setError(msg);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        background: 'var(--color-bg)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 16,
      }}
    >
      <div style={{ width: '100%', maxWidth: 420 }}>
        <GlassCard>
          <div style={{ marginBottom: 16 }}>
            <h1 style={{ fontSize: 22, fontWeight: 900, marginBottom: 6 }}>Forgot Password</h1>
            <p style={{ color: 'var(--color-text-muted)', fontSize: 13 }}>
              Enter your account email and we will send a secure reset link.
            </p>
          </div>

          <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div>
              <label style={labelStyle}>Email</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
                required
                placeholder="admin@example.com"
                style={inputStyle}
              />
            </div>

            {error && <div style={errorStyle}>{error}</div>}
            {success && <div style={successStyle}>{success}</div>}

            <Button type="submit" disabled={loading} style={{ width: '100%', height: 46 }}>
              {loading ? 'Sending...' : 'Send Reset Link'}
            </Button>

            <div style={{ textAlign: 'center', fontSize: 13 }}>
              <Link to="/login">Back to login</Link>
            </div>
          </form>
        </GlassCard>
      </div>
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
  padding: '12px 16px',
  fontSize: 14,
};

const errorStyle: React.CSSProperties = {
  background: 'rgba(255,77,79,0.1)',
  border: '1px solid rgba(255,77,79,0.4)',
  borderRadius: 10,
  padding: '10px 14px',
  fontSize: 13,
  color: 'var(--color-danger)',
};

const successStyle: React.CSSProperties = {
  background: 'rgba(183,244,8,0.12)',
  border: '1px solid rgba(183,244,8,0.4)',
  borderRadius: 10,
  padding: '10px 14px',
  fontSize: 13,
  color: 'var(--color-accent)',
};
