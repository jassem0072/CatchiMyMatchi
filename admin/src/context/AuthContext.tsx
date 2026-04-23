import { createContext, useContext, useState, useCallback, type ReactNode } from 'react';
import { adminGoogleLogin, adminLogin, getAuthMe } from '../api/auth';
import type { UserRole } from '../types';
import { clearAuthStorage, persistAuth, readStoredRole, readStoredToken } from '../authStorage';

interface AuthContextValue {
  token: string | null;
  role: Extract<UserRole, 'admin' | 'expert'>;
  login: (email: string, password: string, rememberMe: boolean) => Promise<Extract<UserRole, 'admin' | 'expert'>>;
  loginWithGoogle: (
    payload: { idToken?: string; accessToken?: string; displayName?: string },
    rememberMe: boolean,
  ) => Promise<Extract<UserRole, 'admin' | 'expert'>>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState<string | null>(() => readStoredToken());
  const [role, setRole] = useState<Extract<UserRole, 'admin' | 'expert'>>(() => readStoredRole());

  const login = useCallback(async (email: string, password: string, rememberMe: boolean) => {
    const res = await adminLogin(email, password);
    const me = await getAuthMe(res.accessToken);
    const nextRole: Extract<UserRole, 'admin' | 'expert'> = me.role === 'expert' ? 'expert' : 'admin';
    persistAuth({ token: res.accessToken, role: nextRole, rememberMe });
    setToken(res.accessToken);
    setRole(nextRole);
    return nextRole;
  }, []);

  const loginWithGoogle = useCallback(async (
    payload: { idToken?: string; accessToken?: string; displayName?: string },
    rememberMe: boolean,
  ) => {
    const res = await adminGoogleLogin(payload);
    const me = await getAuthMe(res.accessToken);
    const nextRole: Extract<UserRole, 'admin' | 'expert'> = me.role === 'expert' ? 'expert' : 'admin';
    persistAuth({ token: res.accessToken, role: nextRole, rememberMe });
    setToken(res.accessToken);
    setRole(nextRole);
    return nextRole;
  }, []);

  const logout = useCallback(() => {
    clearAuthStorage();
    setToken(null);
    setRole('admin');
  }, []);

  return <AuthContext.Provider value={{ token, role, login, loginWithGoogle, logout }}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
