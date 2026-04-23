export const TOKEN_KEY = 'admin_token';
export const ROLE_KEY = 'admin_viewer_role';

export type ViewerRole = 'admin' | 'expert';

export function readStoredToken(): string | null {
  return localStorage.getItem(TOKEN_KEY) || sessionStorage.getItem(TOKEN_KEY);
}

export function readStoredRole(): ViewerRole {
  const stored = localStorage.getItem(ROLE_KEY) || sessionStorage.getItem(ROLE_KEY);
  return stored === 'expert' ? 'expert' : 'admin';
}

export function persistAuth(input: {
  token: string;
  role: ViewerRole;
  rememberMe: boolean;
}): void {
  if (input.rememberMe) {
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(ROLE_KEY);
    localStorage.setItem(TOKEN_KEY, input.token);
    localStorage.setItem(ROLE_KEY, input.role);
    return;
  }

  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(ROLE_KEY);
  sessionStorage.setItem(TOKEN_KEY, input.token);
  sessionStorage.setItem(ROLE_KEY, input.role);
}

export function clearAuthStorage(): void {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(ROLE_KEY);
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(ROLE_KEY);
}
