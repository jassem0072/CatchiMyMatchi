import { NavLink } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

const NAV_ITEMS = [
  { to: '/dashboard', label: 'Dashboard', icon: '⬛' },
  { to: '/users', label: 'Users', icon: '👥' },
  { to: '/players', label: 'Players', icon: '⚽' },
  { to: '/scouters', label: 'Scouters', icon: '🔭' },
  { to: '/videos', label: 'Videos', icon: '🎬' },
  { to: '/reports', label: 'Reports', icon: '📋' },
  { to: '/notifications', label: 'Notifications', icon: '🔔' },
];

export function Sidebar() {
  const { logout } = useAuth();

  return (
    <aside
      style={{
        width: 240,
        minHeight: '100vh',
        background: 'var(--color-surface)',
        borderRight: '1px solid var(--color-border)',
        display: 'flex',
        flexDirection: 'column',
        padding: '0 0 24px',
        flexShrink: 0,
      }}
    >
      {/* Logo */}
      <div
        style={{
          padding: '28px 24px 24px',
          borderBottom: '1px solid var(--color-border)',
          marginBottom: 8,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div
            style={{
              width: 36, height: 36,
              background: 'linear-gradient(135deg, #38BDF8, #1D63FF, #B7F408)',
              borderRadius: 10,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 18,
            }}
          >
            ⚡
          </div>
          <div>
            <div style={{ fontSize: 14, fontWeight: 900, color: 'var(--color-text)' }}>ScoutAI</div>
            <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--color-accent)', letterSpacing: '1.5px', textTransform: 'uppercase' }}>Admin</div>
          </div>
        </div>
      </div>

      {/* Nav */}
      <nav style={{ flex: 1, padding: '8px 12px' }}>
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            style={({ isActive }) => ({
              display: 'flex',
              alignItems: 'center',
              gap: 12,
              padding: '10px 12px',
              borderRadius: 12,
              marginBottom: 2,
              fontSize: 13,
              fontWeight: isActive ? 700 : 500,
              color: isActive ? 'var(--color-text)' : 'var(--color-text-muted)',
              background: isActive ? 'rgba(29,99,255,0.15)' : 'transparent',
              border: isActive ? '1px solid rgba(29,99,255,0.3)' : '1px solid transparent',
              textDecoration: 'none',
              transition: 'all 0.15s',
            })}
          >
            <span style={{ fontSize: 15, width: 20, textAlign: 'center' }}>{item.icon}</span>
            {item.label}
          </NavLink>
        ))}
      </nav>

      {/* Logout */}
      <div style={{ padding: '0 12px' }}>
        <button
          onClick={logout}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            padding: '10px 12px',
            borderRadius: 12,
            fontSize: 13,
            fontWeight: 500,
            color: 'var(--color-danger)',
            background: 'transparent',
            border: 'none',
            cursor: 'pointer',
            width: '100%',
            transition: 'background 0.15s',
          }}
          onMouseEnter={(e) => { e.currentTarget.style.background = 'rgba(255,77,79,0.08)'; }}
          onMouseLeave={(e) => { e.currentTarget.style.background = 'transparent'; }}
        >
          <span style={{ fontSize: 15, width: 20, textAlign: 'center' }}>🚪</span>
          Logout
        </button>
      </div>
    </aside>
  );
}
