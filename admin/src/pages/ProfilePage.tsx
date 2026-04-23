import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { getAuthMe, updateAuthMe, updateAuthPassword } from '../api/auth';
import type { ExpertEarningsSummary } from '../api/expert';
import { getExpertEarnings } from '../api/expert';
import { useAuth } from '../context/AuthContext';
import { useApi } from '../hooks/useApi';
import { GlassCard } from '../components/ui/GlassCard';
import { Button } from '../components/ui/Button';

export function ProfilePage() {
  const { role } = useAuth();
  const navigate = useNavigate();

  const { data, loading, error, refetch } = useApi(() => getAuthMe(), []);

  const [displayName, setDisplayName] = useState('');
  const [position, setPosition] = useState('');
  const [nation, setNation] = useState('');
  const [dateOfBirth, setDateOfBirth] = useState('');
  const [height, setHeight] = useState('');
  const [playerIdNumber, setPlayerIdNumber] = useState('');
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileError, setProfileError] = useState('');
  const [profileSuccess, setProfileSuccess] = useState('');
  const [showProfileForm, setShowProfileForm] = useState(false);

  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [passwordSaving, setPasswordSaving] = useState(false);
  const [passwordError, setPasswordError] = useState('');
  const [passwordSuccess, setPasswordSuccess] = useState('');
  const [showPasswordForm, setShowPasswordForm] = useState(false);

  const [expertData, setExpertData] = useState<ExpertEarningsSummary | null>(null);
  const [expertLoading, setExpertLoading] = useState(false);
  const [expertError, setExpertError] = useState('');

  useEffect(() => {
    if (!data) return;
    setDisplayName(data.displayName || '');
    setPosition(data.position || '');
    setNation(data.nation || '');
    setDateOfBirth(data.dateOfBirth ? String(data.dateOfBirth).slice(0, 10) : '');
    setHeight(data.height === null || data.height === undefined ? '' : String(data.height));
    setPlayerIdNumber(data.playerIdNumber || '');
  }, [data]);

  useEffect(() => {
    if (role !== 'expert') return;
    let active = true;
    setExpertLoading(true);
    setExpertError('');
    getExpertEarnings()
      .then((res) => {
        if (!active) return;
        setExpertData(res);
      })
      .catch((err: unknown) => {
        if (!active) return;
        const msg =
          (err as any)?.response?.data?.message ||
          (err as any)?.message ||
          'Unable to load expert earnings';
        setExpertError(msg);
      })
      .finally(() => {
        if (!active) return;
        setExpertLoading(false);
      });

    return () => {
      active = false;
    };
  }, [role]);

  const email = useMemo(() => data?.email || '', [data?.email]);

  async function saveProfile(e: FormEvent) {
    e.preventDefault();
    setProfileError('');
    setProfileSuccess('');
    setProfileSaving(true);
    try {
      await updateAuthMe({
        displayName: displayName.trim(),
        position: position.trim(),
        nation: nation.trim(),
        dateOfBirth: dateOfBirth || undefined,
        height: height ? Number(height) : undefined,
        playerIdNumber: playerIdNumber.trim(),
      });
      setProfileSuccess('Profile updated successfully.');
      refetch();
    } catch (err: unknown) {
      const msg =
        (err as any)?.response?.data?.message ||
        (err as any)?.message ||
        'Unable to update profile';
      setProfileError(msg);
    } finally {
      setProfileSaving(false);
    }
  }

  async function savePassword(e: FormEvent) {
    e.preventDefault();
    setPasswordError('');
    setPasswordSuccess('');
    if (newPassword.length < 6) {
      setPasswordError('New password must be at least 6 characters.');
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordError('Passwords do not match.');
      return;
    }

    setPasswordSaving(true);
    try {
      await updateAuthPassword({ currentPassword, newPassword });
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      setPasswordSuccess('Password changed successfully.');
    } catch (err: unknown) {
      const msg =
        (err as any)?.response?.data?.message ||
        (err as any)?.message ||
        'Unable to change password';
      setPasswordError(msg);
    } finally {
      setPasswordSaving(false);
    }
  }

  return (
    <div style={{ display: 'grid', gap: 16 }}>
      <GlassCard style={heroCardStyle}>
        <div style={{ display: 'grid', gap: 6 }}>
          <div style={{ fontSize: 18, fontWeight: 900 }}>{role === 'expert' ? 'Expert Profile' : 'Admin Profile'}</div>
          <div style={{ color: 'var(--color-text-muted)', fontSize: 13 }}>
            Manage your account details and security settings.
          </div>
          {email && (
            <div style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>
              Signed in as {email}
            </div>
          )}
        </div>
      </GlassCard>

      {loading && <GlassCard>Loading profile...</GlassCard>}
      {error && <GlassCard><span style={{ color: 'var(--color-danger)' }}>{error}</span></GlassCard>}

      {data && (
        <>
          {role === 'expert' && (
            <GlassCard>
              <div style={{ display: 'grid', gap: 12 }}>
                <div style={{ fontSize: 15, fontWeight: 800 }}>Expert Earnings</div>
                {expertLoading && <div style={{ color: 'var(--color-text-muted)' }}>Loading earnings...</div>}
                {expertError && <div style={{ color: 'var(--color-danger)' }}>{expertError}</div>}
                {expertData && (
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(180px,1fr))', gap: 12 }}>
                    <div style={metricStyle}>
                      <div style={metricLabelStyle}>Verified Players</div>
                      <div style={metricValueStyle}>{expertData.verifiedPlayers}</div>
                    </div>
                    <div style={metricStyle}>
                      <div style={metricLabelStyle}>Pending Payout</div>
                      <div style={metricValueStyle}>EUR {expertData.pendingUsd}</div>
                    </div>
                    <div style={metricStyle}>
                      <div style={metricLabelStyle}>Already Paid</div>
                      <div style={metricValueStyle}>EUR {expertData.paidUsd}</div>
                    </div>
                  </div>
                )}
                <div>
                  <Button variant="primary" onClick={() => navigate('/billing-invoices')}>
                    Open Billing and Invoices
                  </Button>
                </div>
              </div>
            </GlassCard>
          )}

          <GlassCard style={sectionCardStyle}>
            <button
              type="button"
              onClick={() => setShowProfileForm((prev) => !prev)}
              style={sectionHeaderButtonStyle}
            >
              <div>
                <div style={sectionTitleStyle}>Account Information</div>
                <div style={sectionSubtitleStyle}>Click to edit your personal and profile details.</div>
              </div>
              <span style={sectionChevronStyle(showProfileForm)}>{showProfileForm ? 'Hide' : 'Open'}</span>
            </button>

            {showProfileForm && (
              <form onSubmit={saveProfile} style={{ display: 'grid', gap: 14, marginTop: 16 }}>
                <div style={{ display: 'grid', gap: 6 }}>
                  <label style={labelStyle}>Display Name</label>
                  <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} style={inputStyle} />
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(220px,1fr))', gap: 12 }}>
                  <div style={{ display: 'grid', gap: 6 }}>
                    <label style={labelStyle}>Position</label>
                    <input value={position} onChange={(e) => setPosition(e.target.value)} style={inputStyle} />
                  </div>
                  <div style={{ display: 'grid', gap: 6 }}>
                    <label style={labelStyle}>Nation</label>
                    <input value={nation} onChange={(e) => setNation(e.target.value)} style={inputStyle} />
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(220px,1fr))', gap: 12 }}>
                  <div style={{ display: 'grid', gap: 6 }}>
                    <label style={labelStyle}>Date of Birth</label>
                    <input type="date" value={dateOfBirth} onChange={(e) => setDateOfBirth(e.target.value)} style={inputStyle} />
                  </div>
                  <div style={{ display: 'grid', gap: 6 }}>
                    <label style={labelStyle}>Height (cm)</label>
                    <input
                      type="number"
                      min={0}
                      step={1}
                      value={height}
                      onChange={(e) => setHeight(e.target.value)}
                      style={inputStyle}
                    />
                  </div>
                </div>

                <div style={{ display: 'grid', gap: 6 }}>
                  <label style={labelStyle}>Player ID Number</label>
                  <input value={playerIdNumber} onChange={(e) => setPlayerIdNumber(e.target.value)} style={inputStyle} />
                </div>

                {profileError && <div style={errorStyle}>{profileError}</div>}
                {profileSuccess && <div style={successStyle}>{profileSuccess}</div>}

                <div>
                  <Button type="submit" disabled={profileSaving}>
                    {profileSaving ? 'Saving...' : 'Save Profile'}
                  </Button>
                </div>
              </form>
            )}
          </GlassCard>

          <GlassCard style={sectionCardStyle}>
            <button
              type="button"
              onClick={() => setShowPasswordForm((prev) => !prev)}
              style={sectionHeaderButtonStyle}
            >
              <div>
                <div style={sectionTitleStyle}>Change Password</div>
                <div style={sectionSubtitleStyle}>Click to manage your account security.</div>
              </div>
              <span style={sectionChevronStyle(showPasswordForm)}>{showPasswordForm ? 'Hide' : 'Open'}</span>
            </button>

            {showPasswordForm && (
              <form onSubmit={savePassword} style={{ display: 'grid', gap: 14, marginTop: 16 }}>
                <div style={{ display: 'grid', gap: 6 }}>
                  <label style={labelStyle}>Current Password</label>
                  <input
                    type="password"
                    autoComplete="current-password"
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    style={inputStyle}
                    required
                  />
                </div>

                <div style={{ display: 'grid', gap: 6 }}>
                  <label style={labelStyle}>New Password</label>
                  <input
                    type="password"
                    autoComplete="new-password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    style={inputStyle}
                    required
                  />
                </div>

                <div style={{ display: 'grid', gap: 6 }}>
                  <label style={labelStyle}>Confirm New Password</label>
                  <input
                    type="password"
                    autoComplete="new-password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    style={inputStyle}
                    required
                  />
                </div>

                {passwordError && <div style={errorStyle}>{passwordError}</div>}
                {passwordSuccess && <div style={successStyle}>{passwordSuccess}</div>}

                <div>
                  <Button type="submit" disabled={passwordSaving}>
                    {passwordSaving ? 'Updating...' : 'Change Password'}
                  </Button>
                </div>
              </form>
            )}
          </GlassCard>
        </>
      )}
    </div>
  );
}

const heroCardStyle: React.CSSProperties = {
  background: 'linear-gradient(135deg, rgba(18, 27, 43, 0.92), rgba(15, 23, 38, 0.98))',
  border: '1px solid rgba(29,99,255,0.25)',
};

const sectionCardStyle: React.CSSProperties = {
  background: 'linear-gradient(180deg, rgba(18,27,43,0.94), rgba(12,20,34,0.96))',
};

const sectionHeaderButtonStyle: React.CSSProperties = {
  width: '100%',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  gap: 12,
  textAlign: 'left',
  background: 'transparent',
  border: 'none',
  color: 'var(--color-text)',
  padding: 0,
};

const sectionTitleStyle: React.CSSProperties = {
  fontSize: 16,
  fontWeight: 800,
};

const sectionSubtitleStyle: React.CSSProperties = {
  color: 'var(--color-text-muted)',
  fontSize: 12,
  marginTop: 3,
};

function sectionChevronStyle(open: boolean): React.CSSProperties {
  return {
    fontSize: 12,
    fontWeight: 800,
    letterSpacing: '0.5px',
    textTransform: 'uppercase',
    color: open ? 'var(--color-accent)' : 'var(--color-primary)',
    padding: '7px 10px',
    borderRadius: 999,
    border: open ? '1px solid rgba(183,244,8,0.4)' : '1px solid rgba(29,99,255,0.45)',
    background: open ? 'rgba(183,244,8,0.12)' : 'rgba(29,99,255,0.14)',
  };
}

const labelStyle: React.CSSProperties = {
  display: 'block',
  fontSize: 11,
  fontWeight: 800,
  color: 'var(--color-text-muted)',
  textTransform: 'uppercase',
  letterSpacing: '1.1px',
};

const inputStyle: React.CSSProperties = {
  width: '100%',
  background: 'var(--color-surface2)',
  border: '1px solid rgba(39,49,74,0.9)',
  borderRadius: 'var(--radius-input)',
  color: 'var(--color-text)',
  padding: '11px 14px',
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

const metricStyle: React.CSSProperties = {
  border: '1px solid var(--color-border)',
  borderRadius: 12,
  padding: 14,
  background: 'var(--color-surface2)',
};

const metricLabelStyle: React.CSSProperties = {
  color: 'var(--color-text-muted)',
  fontSize: 12,
};

const metricValueStyle: React.CSSProperties = {
  fontSize: 24,
  fontWeight: 900,
  marginTop: 6,
};
