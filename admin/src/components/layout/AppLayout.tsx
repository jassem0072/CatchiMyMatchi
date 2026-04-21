import { Outlet } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { Header } from './Header';

export function AppLayout() {
  return (
    <div style={{ display: 'flex', minHeight: '100vh' }}>
      <Sidebar />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <Header />
        <main
          style={{
            flex: 1,
            overflowY: 'auto',
            padding: '28px',
          }}
        >
          <Outlet />
        </main>
      </div>
    </div>
  );
}
