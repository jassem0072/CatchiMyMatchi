import { useState, type FormEvent } from 'react';
import { GoogleLogin, type CredentialResponse } from '@react-oauth/google';
import { Link } from 'react-router-dom';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { registerExpert, requestAdminAccess } from '../api/auth';
import { GlassCard } from '../components/ui/GlassCard';
import { Button } from '../components/ui/Button';

export function LoginPage() {
  const { login, loginWithGoogle } = useAuth();
  const navigate = useNavigate();
  const [mode, setMode] = useState<'login' | 'expert-signup' | 'admin-request'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [rememberMe, setRememberMe] = useState(false);
  const [displayName, setDisplayName] = useState('');
  const [position, setPosition] = useState('');
  const [nation, setNation] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [loading, setLoading] = useState(false);
  const googleEnabled = Boolean(import.meta.env.VITE_GOOGLE_CLIENT_ID);

  async function handleGoogleSuccess(credentialResponse: CredentialResponse) {
    const idToken = String(credentialResponse.credential || '').trim();
    if (!idToken) {
      setError('Google sign-in failed. Missing credential token.');
      return;
    }

    setError('');
    setSuccess('');
    setLoading(true);
    try {
      const role = await loginWithGoogle(
        { idToken },
        rememberMe,
      );
      navigate(role === 'expert' ? '/profile' : '/dashboard', { replace: true });
    } catch (err: unknown) {
      const msg =
        (err as any)?.response?.data?.message ||
        (err as any)?.message ||
        'Google sign-in failed';
      setError(msg);
    } finally {
      setLoading(false);
    }
  }

  function handleGoogleError() {
    setError('Google sign-in failed. Try again.');
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    setSuccess('');
    setLoading(true);
    try {
      if (mode === 'login') {
        const role = await login(email, password, rememberMe);
        navigate(role === 'expert' ? '/profile' : '/dashboard', { replace: true });
      } else if (mode === 'expert-signup') {
        await registerExpert({
          email,
          password,
          displayName,
          position,
          nation,
        });
        setSuccess('Expert account created. You can sign in now.');
        setMode('login');
      } else {
        await requestAdminAccess({
          email,
          password,
          displayName,
        });
        setSuccess('Admin request sent. Wait for approval from testadmin@example.com.');
        setMode('login');
      }
    } catch (err: unknown) {
      const msg =
        (err as any)?.response?.data?.message ||
        (err as any)?.message ||
        (mode === 'login' ? 'Login failed' : 'Request failed');
      setError(msg);
    } finally {
      setLoading(false);
    }
  }

  function switchMode(nextMode: 'login' | 'expert-signup' | 'admin-request') {
    setMode(nextMode);
    setError('');
    setSuccess('');
  }

  function handleGoogleLogin() {
    if (!googleEnabled) {
      setError('Google sign-in is not configured. Set VITE_GOOGLE_CLIENT_ID in admin env.');
      return false;
    }
    return true;
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
            {mode === 'login' ? 'Sign in with your account' : mode === 'expert-signup' ? 'Create an expert account' : 'Request admin access'}
          </p>
        </div>

        <GlassCard>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8, marginBottom: 14 }}>
            <Button type="button" variant={mode === 'login' ? 'primary' : 'ghost'} onClick={() => switchMode('login')}>Login</Button>
            <Button type="button" variant={mode === 'expert-signup' ? 'primary' : 'ghost'} onClick={() => switchMode('expert-signup')}>Sign Up Expert</Button>
            <Button type="button" variant={mode === 'admin-request' ? 'primary' : 'ghost'} onClick={() => switchMode('admin-request')}>Request Admin</Button>
          </div>
          <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            {mode !== 'login' && (
              <div>
                <label style={{ display: 'block', fontSize: 11, fontWeight: 800, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '1.2px', marginBottom: 8 }}>
                  Display Name
                </label>
                <input
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  required
                  placeholder="Your name"
                  style={inputStyle}
                />
              </div>
            )}
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
            {mode === 'login' && (
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--color-text-muted)' }}>
                  <input
                    type="checkbox"
                    checked={rememberMe}
                    onChange={(e) => setRememberMe(e.target.checked)}
                    style={{ width: 14, height: 14 }}
                  />
                  Remember me
                </label>
                <Link to="/forgot-password" style={{ fontSize: 13 }}>Forgot password?</Link>
              </div>
            )}
            {mode === 'expert-signup' && (
              <>
                <div>
                  <label style={{ display: 'block', fontSize: 11, fontWeight: 800, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '1.2px', marginBottom: 8 }}>
                    Position
                  </label>
                  <input
                    type="text"
                    value={position}
                    onChange={(e) => setPosition(e.target.value)}
                    placeholder="Coach / Analyst"
                    style={inputStyle}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: 11, fontWeight: 800, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '1.2px', marginBottom: 8 }}>
                    Nation
                  </label>
                  <input
                    type="text"
                    value={nation}
                    onChange={(e) => setNation(e.target.value)}
                    placeholder="FR"
                    style={inputStyle}
                  />
                </div>
              </>
            )}
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
            {success && (
              <div
                style={{
                  background: 'rgba(183,244,8,0.12)',
                  border: '1px solid rgba(183,244,8,0.4)',
                  borderRadius: 10,
                  padding: '10px 14px',
                  fontSize: 13,
                  color: 'var(--color-accent)',
                }}
              >
                {success}
              </div>
            )}
            <Button
              type="submit"
              variant="primary"
              disabled={loading}
              style={{ width: '100%', marginTop: 4, height: 48 }}
            >
              {loading ? 'Processing…' : mode === 'login' ? 'Sign In' : mode === 'expert-signup' ? 'Create Expert Account' : 'Send Admin Request'}
            </Button>

            {mode === 'login' && (
              <>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <div style={{ flex: 1, height: 1, background: 'var(--color-border)' }} />
                  <span style={{ fontSize: 12, color: 'var(--color-text-muted)' }}>or</span>
                  <div style={{ flex: 1, height: 1, background: 'var(--color-border)' }} />
                </div>
                {googleEnabled ? (
                  <div style={{ display: 'flex', justifyContent: 'center' }}>
                    <GoogleLogin
                      onSuccess={handleGoogleSuccess}
                      onError={handleGoogleError}
                      text="signin_with"
                      shape="pill"
                      theme="filled_black"
                      size="large"
                      width="340"
                    />
                  </div>
                ) : (
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() => { handleGoogleLogin(); }}
                    disabled={loading}
                    style={{ width: '100%', height: 46, borderColor: 'rgba(255,255,255,0.2)' }}
                  >
                    Google Sign-In Not Configured
                  </Button>
                )}
              </>
            )}
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
