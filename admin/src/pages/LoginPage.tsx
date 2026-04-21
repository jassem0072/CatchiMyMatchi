import { useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { GlassCard } from '../components/ui/GlassCard';
import { Button } from '../components/ui/Button';

export function LoginPage() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await login(email, password);
      navigate('/dashboard', { replace: true });
    } catch (err: unknown) {
      const msg =
        (err as any)?.response?.data?.message ||
        (err as any)?.message ||
        'Login failed';
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
        backgroundImage: 'radial-gradient(ellipse at 20% 10%, rgba(29,99,255,0.12) 0%, transparent 60%)',
      }}
    >
      <div style={{ width: '100%', maxWidth: 400 }}>
        {/* Logo */}
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div
            style={{
              width: 64, height: 64,
              background: 'linear-gradient(135deg, #38BDF8, #1D63FF, #B7F408)',
              borderRadius: 18,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              margin: '0 auto 16px',
              fontSize: 28,
              boxShadow: '0 8px 32px rgba(29,99,255,0.35)',
            }}
          >
            ⚡
          </div>
          <h1 style={{ fontSize: 24, fontWeight: 900 }}>ScoutAI Admin</h1>
          <p style={{ fontSize: 13, color: 'var(--color-text-muted)', marginTop: 6 }}>
            Administrator access only
          </p>
        </div>

        <GlassCard>
          <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            <div>
              <label style={{ display: 'block', fontSize: 11, fontWeight: 800, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '1.2px', marginBottom: 8 }}>
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                placeholder="admin@example.com"
                style={inputStyle}
              />
            </div>
            <div>
              <label style={{ display: 'block', fontSize: 11, fontWeight: 800, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '1.2px', marginBottom: 8 }}>
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                autoComplete="current-password"
                placeholder="••••••••"
                style={inputStyle}
              />
            </div>
            {error && (
              <div
                style={{
                  background: 'rgba(255,77,79,0.1)',
                  border: '1px solid rgba(255,77,79,0.4)',
                  borderRadius: 10,
                  padding: '10px 14px',
                  fontSize: 13,
                  color: 'var(--color-danger)',
                }}
              >
                {error}
              </div>
            )}
            <Button
              type="submit"
              variant="primary"
              disabled={loading}
              style={{ width: '100%', marginTop: 4, height: 48 }}
            >
              {loading ? 'Signing in…' : 'Sign In'}
            </Button>
          </form>
        </GlassCard>
      </div>
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: '100%',
  background: 'var(--color-surface2)',
  border: '1px solid rgba(39,49,74,0.9)',
  borderRadius: 'var(--radius-input)',
  color: 'var(--color-text)',
  padding: '12px 16px',
  fontSize: 14,
};
