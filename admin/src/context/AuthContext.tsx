import { createContext, useContext, useState, useCallback, type ReactNode } from 'react';
import { adminLogin } from '../api/auth';

const TOKEN_KEY = 'admin_token';

interface AuthContextValue {
  token: string | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(() => localStorage.getItem(TOKEN_KEY));

  const login = useCallback(async (email: string, password: string) => {
    const res = await adminLogin(email, password);
    localStorage.setItem(TOKEN_KEY, res.accessToken);
    setToken(res.accessToken);
  }, []);

  const logout = useCallback(() => {
    localStorage.removeItem(TOKEN_KEY);
    setToken(null);
  }, []);

  return <AuthContext.Provider value={{ token, login, logout }}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
