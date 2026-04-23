/**
 * LoginPage.test.tsx — Component tests for the login / signup / admin-request page
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { LoginPage } from '../../pages/LoginPage';

// ── Mocks ─────────────────────────────────────────────────────────────────────
const mockLogin = vi.fn();
const mockLoginWithGoogle = vi.fn();
const mockNavigate = vi.fn();

vi.mock('../context/AuthContext', () => ({
  useAuth: () => ({ login: mockLogin, loginWithGoogle: mockLoginWithGoogle }),
}));
vi.mock('../../context/AuthContext', () => ({
  useAuth: () => ({ login: mockLogin, loginWithGoogle: mockLoginWithGoogle }),
}));
vi.mock('react-router-dom', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-router-dom')>();
  return { ...actual, useNavigate: () => mockNavigate };
});
vi.mock('../../api/auth', () => ({
  registerExpert: vi.fn(),
  requestAdminAccess: vi.fn(),
}));
vi.mock('@react-oauth/google', () => ({
  GoogleLogin: () => <div data-testid="google-login-btn" />,
}));

import { registerExpert, requestAdminAccess } from '../../api/auth';
const mockRegisterExpert = registerExpert as ReturnType<typeof vi.fn>;
const mockRequestAdminAccess = requestAdminAccess as ReturnType<typeof vi.fn>;

function renderPage() {
  return render(<MemoryRouter><LoginPage /></MemoryRouter>);
}

// ── Tests ─────────────────────────────────────────────────────────────────────
describe('LoginPage — structure', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders ScoutAI Admin heading', () => {
    renderPage();
    expect(screen.getByText('ScoutAI Admin')).toBeInTheDocument();
  });

  it('renders Login, Sign Up Expert, Request Admin tabs', () => {
    renderPage();
    expect(screen.getByText('Login')).toBeInTheDocument();
    expect(screen.getByText('Sign Up Expert')).toBeInTheDocument();
    expect(screen.getByText('Request Admin')).toBeInTheDocument();
  });

  it('renders Email and Password fields in login mode', () => {
    renderPage();
    expect(screen.getByPlaceholderText('admin@example.com')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('••••••••')).toBeInTheDocument();
  });

  it('renders Sign In button in login mode', () => {
    renderPage();
    expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument();
  });

  it('renders Forgot password link', () => {
    renderPage();
    expect(screen.getByText('Forgot password?')).toBeInTheDocument();
  });

  it('renders Remember me checkbox', () => {
    renderPage();
    expect(screen.getByText('Remember me')).toBeInTheDocument();
  });
});

describe('LoginPage — login flow', () => {
  beforeEach(() => vi.clearAllMocks());

  it('calls login with email and password on submit', async () => {
    const user = userEvent.setup();
    mockLogin.mockResolvedValueOnce('admin');
    renderPage();

    await user.type(screen.getByPlaceholderText('admin@example.com'), 'a@b.com');
    await user.type(screen.getByPlaceholderText('••••••••'), 'secret');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    await waitFor(() => {
      expect(mockLogin).toHaveBeenCalledWith('a@b.com', 'secret', false);
    });
  });

  it('navigates to /dashboard after admin login', async () => {
    const user = userEvent.setup();
    mockLogin.mockResolvedValueOnce('admin');
    renderPage();

    await user.type(screen.getByPlaceholderText('admin@example.com'), 'a@b.com');
    await user.type(screen.getByPlaceholderText('••••••••'), 'pass');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    await waitFor(() => expect(mockNavigate).toHaveBeenCalledWith('/dashboard', { replace: true }));
  });

  it('navigates to /profile after expert login', async () => {
    const user = userEvent.setup();
    mockLogin.mockResolvedValueOnce('expert');
    renderPage();

    await user.type(screen.getByPlaceholderText('admin@example.com'), 'e@b.com');
    await user.type(screen.getByPlaceholderText('••••••••'), 'pass');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    await waitFor(() => expect(mockNavigate).toHaveBeenCalledWith('/profile', { replace: true }));
  });

  it('shows error message on login failure', async () => {
    const user = userEvent.setup();
    mockLogin.mockRejectedValueOnce({ response: { data: { message: 'Invalid credentials' } } });
    renderPage();

    await user.type(screen.getByPlaceholderText('admin@example.com'), 'x@x.com');
    await user.type(screen.getByPlaceholderText('••••••••'), 'wrong');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    await waitFor(() => expect(screen.getByText('Invalid credentials')).toBeInTheDocument());
  });
});

describe('LoginPage — expert signup mode', () => {
  beforeEach(() => vi.clearAllMocks());

  it('switches to expert signup mode and shows Display Name field', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByText('Sign Up Expert'));
    expect(screen.getByPlaceholderText('Your name')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Coach / Analyst')).toBeInTheDocument();
  });

  it('calls registerExpert and shows success message', async () => {
    const user = userEvent.setup();
    mockRegisterExpert.mockResolvedValueOnce({ email: 'ex@x.com' });
    renderPage();

    await user.click(screen.getByText('Sign Up Expert'));
    await user.type(screen.getByPlaceholderText('Your name'), 'Expert Name');
    await user.type(screen.getByPlaceholderText('admin@example.com'), 'ex@x.com');
    await user.type(screen.getByPlaceholderText('••••••••'), 'pw123');
    await user.click(screen.getByRole('button', { name: /create expert account/i }));

    await waitFor(() => {
      expect(mockRegisterExpert).toHaveBeenCalledWith(
        expect.objectContaining({ email: 'ex@x.com', displayName: 'Expert Name' }),
      );
      expect(screen.getByText('Expert account created. You can sign in now.')).toBeInTheDocument();
    });
  });
});

describe('LoginPage — admin request mode', () => {
  beforeEach(() => vi.clearAllMocks());

  it('switches to admin-request mode', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByText('Request Admin'));
    expect(screen.getByRole('button', { name: /send admin request/i })).toBeInTheDocument();
  });

  it('calls requestAdminAccess and shows success', async () => {
    const user = userEvent.setup();
    mockRequestAdminAccess.mockResolvedValueOnce({ email: 'a@b.com', status: 'pending' });
    renderPage();

    await user.click(screen.getByText('Request Admin'));
    await user.type(screen.getByPlaceholderText('Your name'), 'New Admin');
    await user.type(screen.getByPlaceholderText('admin@example.com'), 'a@b.com');
    await user.type(screen.getByPlaceholderText('••••••••'), 'pw123');
    await user.click(screen.getByRole('button', { name: /send admin request/i }));

    await waitFor(() => {
      expect(mockRequestAdminAccess).toHaveBeenCalled();
      expect(screen.getByText(/admin request sent/i)).toBeInTheDocument();
    });
  });
});
