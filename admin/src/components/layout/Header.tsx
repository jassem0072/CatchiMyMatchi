import { useLocation } from 'react-router-dom';

const PAGE_TITLES: Record<string, string> = {
  '/dashboard':     'Dashboard',
  '/users':         'User Management',
  '/videos':        'Video Management',
  '/reports':       'Reports',
  '/notifications': 'Notifications',
};

export function Header() {
  const { pathname } = useLocation();
  const title = PAGE_TITLES[pathname] || 'Admin Panel';

  return (
    <header
      style={{
        height: 60,
        borderBottom: '1px solid var(--color-border)',
        display: 'flex',
        alignItems: 'center',
        padding: '0 28px',
        background: 'rgba(18,27,43,0.7)',
        backdropFilter: 'blur(8px)',
        position: 'sticky',
        top: 0,
        zIndex: 100,
      }}
    >
      <h1 style={{ fontSize: 16, fontWeight: 800, color: 'var(--color-text)' }}>{title}</h1>
      <div style={{ flex: 1 }} />
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          background: 'var(--color-surface2)',
          border: '1px solid var(--color-border)',
          borderRadius: 'var(--radius-pill)',
          padding: '6px 14px',
          fontSize: 12,
          fontWeight: 700,
          color: 'var(--color-accent)',
        }}
      >
        ⚡ Admin
      </div>
    </header>
  );
}
