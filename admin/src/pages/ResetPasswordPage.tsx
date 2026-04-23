import { useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { resetPassword } from '../api/auth';
import { GlassCard } from '../components/ui/GlassCard';
import { Button } from '../components/ui/Button';

export function ResetPasswordPage() {
  const [params] = useSearchParams();
  const email = (params.get('email') || '').trim();
  const token = (params.get('token') || '').trim();

  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    setSuccess('');

    if (!email || !token) {
      setError('Invalid or expired reset link. Please request a new one.');
      return;
    }
    if (!newPassword || newPassword.length < 6) {
      setError('Password must be at least 6 characters.');
      return;
    }
    if (newPassword !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    setLoading(true);
    try {
      await resetPassword({ email, token, newPassword });
      setSuccess('Password updated successfully. You can sign in now.');
      setNewPassword('');
      setConfirmPassword('');
    } catch (err: unknown) {
      const msg =
        (err as any)?.response?.data?.message ||
        (err as any)?.message ||
        'Unable to reset password';
      setError(msg);
    } finally {
      setLoading(false);
    }
  }

  const missingParams = !email || !token;

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
            <h1 style={{ fontSize: 22, fontWeight: 900, marginBottom: 6 }}>Reset Password</h1>
            <p style={{ color: 'var(--color-text-muted)', fontSize: 13 }}>
              Set a new password for <strong>{email || 'your account'}</strong>.
            </p>
          </div>

          <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div>
              <label style={labelStyle}>New Password</label>
              <input
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                autoComplete="new-password"
                required
                disabled={missingParams}
                placeholder="At least 6 characters"
                style={inputStyle}
              />
            </div>

            <div>
              <label style={labelStyle}>Confirm Password</label>
              <input
                type="password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                autoComplete="new-password"
                required
                disabled={missingParams}
                placeholder="Repeat new password"
                style={inputStyle}
              />
            </div>

            {error && <div style={errorStyle}>{error}</div>}
            {success && <div style={successStyle}>{success}</div>}
            {missingParams && <div style={errorStyle}>Missing reset token or email in URL.</div>}

            <Button type="submit" disabled={loading || missingParams} style={{ width: '100%', height: 46 }}>
              {loading ? 'Updating...' : 'Update Password'}
            </Button>

            <div style={{ textAlign: 'center', fontSize: 13 }}>
              <Link to="/forgot-password">Request another reset link</Link>
            </div>
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
