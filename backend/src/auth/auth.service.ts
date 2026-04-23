import bcrypt from 'bcryptjs';
import axios from 'axios';
import { createHash, randomBytes } from 'node:crypto';
import { BadRequestException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import nodemailer, { type Transporter } from 'nodemailer';

import { UsersService } from '../users/users.service';
import type { UserRole } from '../users/users.schema';

@Injectable()
export class AuthService {
  constructor(
    private readonly users: UsersService,
    private readonly jwt: JwtService,
  ) {}

  private mailer: Transporter | null = null;

  private getMailer(): Transporter {
    if (this.mailer) return this.mailer;

    const host = String(process.env.SMTP_HOST || '').trim();
    const user = String(process.env.SMTP_USER || '').trim();
    const pass = String(process.env.SMTP_PASS || '').trim();
    const port = Number(process.env.SMTP_PORT || '587') || 587;
    if (!host || !user || !pass) throw new BadRequestException('Email service not configured');

    this.mailer = nodemailer.createTransport({
      host,
      port,
      secure: port === 465,
      auth: { user, pass },
    });
    return this.mailer;
  }

  private async sendPasswordResetEmail(input: { to: string; token: string; expiresAt: Date }): Promise<void> {
    const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
    if (!from) throw new BadRequestException('Email service not configured');

    const appBaseUrl = String(process.env.APP_BASE_URL || '').trim();
    const link = appBaseUrl
      ? `${appBaseUrl.replace(/\/$/, '')}/reset-password?email=${encodeURIComponent(input.to)}&token=${encodeURIComponent(input.token)}`
      : '';
    if (!link) throw new BadRequestException('APP_BASE_URL not configured');

    const text =
      `You requested a ScoutAI password reset.\n\n` +
      `To confirm and reset your password, open this link:\n\n` +
      `${link}\n\n` +
      `This link expires at: ${input.expiresAt.toISOString()}\n`;

    const html =
      `<p>You requested a ScoutAI password reset.</p>` +
      `<p><b>To confirm and reset your password, open this link:</b></p>` +
      `<p><a href="${link}">${link}</a></p>` +
      `<p>This link expires at: <b>${input.expiresAt.toISOString()}</b></p>`;

    const mailer = this.getMailer();
    await mailer.sendMail({
      from,
      to: input.to,
      subject: 'ScoutAI password reset',
      text,
      html,
    });
  }

  private hashResetToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  async requestPasswordReset(email: string): Promise<{ ok: boolean }> {
    const e = (email || '').trim().toLowerCase();
    if (!e) throw new BadRequestException('email is required');

    // Ensure we never return tokens in API responses.
    // Also enforce that SMTP is configured, otherwise this flow isn't secure.
    this.getMailer();

    const raw = randomBytes(20).toString('hex');
    const ttlMinutes = Number(process.env.RESET_PASSWORD_TOKEN_TTL_MINUTES || '15') || 15;
    const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
    const tokenHash = this.hashResetToken(raw);

    const ok = await this.users.setResetPasswordTokenByEmail(e, tokenHash, expiresAt);

    if (ok) {
      await this.sendPasswordResetEmail({ to: e, token: raw, expiresAt });
    }

    return { ok: true };
  }

  async resetPassword(email: string, token: string, newPassword: string): Promise<void> {
    const e = (email || '').trim().toLowerCase();
    const t = (token || '').trim();
    if (!e) throw new BadRequestException('email is required');
    if (!t) throw new BadRequestException('token is required');
    await this.users.resetPasswordByToken(e, this.hashResetToken(t), newPassword);
  }

  private generateCode(): string {
    const n = Math.floor(100000 + Math.random() * 900000);
    return String(n);
  }

  private async sendVerificationCode(input: { to: string; code: string }): Promise<void> {
    const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
    if (!from) throw new BadRequestException('Email service not configured (SMTP_FROM)');

    const text =
      `Welcome to ScoutAI!\n\n` +
      `Your verification code is: ${input.code}\n\n` +
      `Enter this code in the app to verify your email.\n\n` +
      `If you did not create this account, you can ignore this email.\n`;

    const html =
      `<div style="font-family:Arial,sans-serif;max-width:500px;margin:0 auto;padding:24px;background:#0d1b2a;border-radius:12px;color:#fff;">` +
      `<h2 style="color:#3b82f6;text-align:center;">Welcome to ScoutAI!</h2>` +
      `<p style="text-align:center;">Your verification code is:</p>` +
      `<div style="text-align:center;margin:24px 0;">` +
      `<span style="display:inline-block;padding:16px 40px;background:#1e293b;border:2px solid #3b82f6;border-radius:12px;font-size:32px;font-weight:bold;letter-spacing:12px;color:#3b82f6;">${input.code}</span>` +
      `</div>` +
      `<p style="color:#94a3b8;font-size:12px;text-align:center;">Enter this code in the app to activate your account.</p>` +
      `</div>`;

    const mailer = this.getMailer();
    await mailer.sendMail({
      from,
      to: input.to,
      subject: 'ScoutAI - Your verification code',
      text,
      html,
    });
  }

  async register(input: {
    email: string;
    password: string;
    role: UserRole;
    displayName?: string;
    position?: string;
    nation?: string;
  }): Promise<{ email: string }> {
    const created = await this.users.createUser(input);
    return { email: created.email };
  }

  async registerExpert(input: {
    email: string;
    password: string;
    displayName?: string;
    position?: string;
    nation?: string;
  }): Promise<{ email: string }> {
    const created = await this.users.createUser({
      email: input.email,
      password: input.password,
      role: 'expert',
      displayName: input.displayName,
      position: input.position,
      nation: input.nation,
    });
    return { email: created.email };
  }

  async requestAdminAccess(input: {
    email: string;
    password: string;
    displayName?: string;
  }): Promise<{ email: string; status: 'pending' }> {
    const created = await this.users.createAdminAccessRequest({
      email: input.email,
      password: input.password,
      displayName: input.displayName,
    });
    return { email: created.email, status: 'pending' };
  }

  async resendVerificationCode(email: string): Promise<{ ok: boolean }> {
    const e = (email || '').trim().toLowerCase();
    if (!e) throw new BadRequestException('email is required');
    const user = await this.users.findByEmail(e);
    if (!user) throw new BadRequestException('User not found');

    const code = this.generateCode();
    await this.users.setEmailVerificationToken(user._id.toString(), code);
    await this.sendVerificationCode({ to: user.email, code });

    return { ok: true };
  }

  async verifyEmailCode(email: string, code: string): Promise<{ accessToken: string }> {
    const e = (email || '').trim().toLowerCase();
    const c = (code || '').trim();
    if (!e) throw new BadRequestException('email is required');
    if (!c) throw new BadRequestException('code is required');

    const user = await this.users.findByEmail(e);
    if (!user) throw new BadRequestException('User not found');
    if (user.emailVerificationToken !== c) {
      throw new BadRequestException('Invalid verification code');
    }

    user.emailVerified = true;
    user.emailVerificationToken = '';
    await user.save();

    return this.issueToken(user._id.toString(), user.email, user.role);
  }

  async login(email: string, password: string): Promise<{ accessToken: string }> {
    const user = await this.users.findByEmail(email);
    if (!user) throw new UnauthorizedException('Invalid credentials');

    const ok = await bcrypt.compare(password || '', user.passwordHash);
    if (!ok) throw new UnauthorizedException('Invalid credentials');

    if ((user as any).isBanned) throw new ForbiddenException('Account suspended');

    const code = this.generateCode();
    await this.users.setEmailVerificationToken(user._id.toString(), code);
    await this.sendVerificationCode({ to: user.email, code });

    throw new UnauthorizedException('Verification code sent. Please verify your email with the 6-digit code to continue.');
  }

  async adminLogin(email: string, password: string): Promise<{ accessToken: string }> {
    const user = await this.users.findByEmail(email);
    if (!user) throw new UnauthorizedException('Invalid credentials');

    const ok = await bcrypt.compare(password || '', user.passwordHash);
    if (!ok) throw new UnauthorizedException('Invalid credentials');

    if (user.role !== 'admin' && user.role !== 'expert') {
      throw new ForbiddenException('Admin or expert access required');
    }
    if ((user as any).isBanned) throw new ForbiddenException('Account suspended');

    return this.issueToken(user._id.toString(), user.email, user.role);
  }

  private getAllowedGoogleAudiences(): string[] {
    return (process.env.GOOGLE_CLIENT_IDS || process.env.GOOGLE_CLIENT_ID || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
  }

  private async resolveGoogleIdentity(input: {
    idToken?: string;
    accessToken?: string;
  }): Promise<{ sub: string; email: string; name: string }> {
    const idToken = (input.idToken || '').trim();
    const accessToken = (input.accessToken || '').trim();
    if (!idToken && !accessToken) throw new BadRequestException('idToken or accessToken is required');

    let sub = '';
    let email = '';
    let aud = '';
    let name = '';

    if (idToken) {
      const tokenInfoUrl = `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`;
      let info: any;
      try {
        const res = await axios.get(tokenInfoUrl, { timeout: 8000 });
        info = res.data;
      } catch {
        throw new UnauthorizedException('Invalid Google token');
      }

      sub = String(info?.sub || '').trim();
      email = String(info?.email || '').trim().toLowerCase();
      aud = String(info?.aud || info?.audience || info?.issued_to || '').trim();
      name = String(info?.name || '').trim();
    } else {
      const tokenInfoUrl = `https://oauth2.googleapis.com/tokeninfo?access_token=${encodeURIComponent(accessToken)}`;
      let info: any;
      try {
        const res = await axios.get(tokenInfoUrl, { timeout: 8000 });
        info = res.data;
      } catch {
        throw new UnauthorizedException('Invalid Google token');
      }

      aud = String(info?.aud || info?.audience || info?.issued_to || '').trim();
      sub = String(info?.user_id || info?.sub || '').trim();
      email = String(info?.email || '').trim().toLowerCase();

      // Access-token tokeninfo may omit email/name, so fallback to userinfo.
      if (!email || !sub) {
        try {
          const res = await axios.get('https://openidconnect.googleapis.com/v1/userinfo', {
            timeout: 8000,
            headers: { Authorization: `Bearer ${accessToken}` },
          });
          const ui = res.data;
          if (!sub) sub = String(ui?.sub || '').trim();
          if (!email) email = String(ui?.email || '').trim().toLowerCase();
          name = String(ui?.name || '').trim();
        } catch {
          // Ignore fallback failures; required fields are validated below.
        }
      }
    }

    if (!sub) throw new UnauthorizedException('Invalid Google token');
    if (!email) throw new UnauthorizedException('Google account has no email');

    const allowedAudiences = this.getAllowedGoogleAudiences();
    if (allowedAudiences.length > 0 && !allowedAudiences.includes(aud)) {
      throw new UnauthorizedException('Invalid Google token audience');
    }

    return { sub, email, name };
  }

  async adminLoginWithGoogle(input: {
    idToken?: string;
    accessToken?: string;
    displayName?: string;
  }): Promise<{ accessToken: string }> {
    const identity = await this.resolveGoogleIdentity(input);

    const user = await this.users.findByEmail(identity.email);
    if (!user) throw new UnauthorizedException('Account not found');

    if (user.role !== 'admin' && user.role !== 'expert') {
      throw new ForbiddenException('Admin or expert access required');
    }
    if ((user as any).isBanned) throw new ForbiddenException('Account suspended');

    const linked = await this.users.findByGoogleSub(identity.sub);
    if (linked && linked._id.toString() !== user._id.toString()) {
      throw new ForbiddenException('Google account already linked to another user');
    }

    let shouldSave = false;
    if (!user.googleSub || user.googleSub !== identity.sub) {
      user.googleSub = identity.sub;
      shouldSave = true;
    }
    if (!user.emailVerified) {
      user.emailVerified = true;
      shouldSave = true;
    }

    const nextDisplayName = (input.displayName || identity.name || '').trim();
    if (!user.displayName && nextDisplayName) {
      user.displayName = nextDisplayName;
      shouldSave = true;
    }

    if (shouldSave) {
      await user.save();
    }

    return this.issueToken(user._id.toString(), user.email, user.role);
  }

  async loginWithGoogle(input: {
    idToken?: string;
    accessToken?: string;
    role?: UserRole;
    displayName?: string;
  }): Promise<{ accessToken: string }> {
    const identity = await this.resolveGoogleIdentity(input);

    const createdOrUpdated = await this.users.createOrUpdateGoogleUser({
      email: identity.email,
      googleSub: identity.sub,
      displayName: input.displayName || identity.name,
      role: input.role,
    });

    if (!createdOrUpdated.emailVerified) {
      createdOrUpdated.emailVerified = true;
      await createdOrUpdated.save();
    }

    return this.issueToken(createdOrUpdated._id.toString(), createdOrUpdated.email, createdOrUpdated.role);
  }

  async loginWithGoogleWeb(input: {
    email: string;
    displayName?: string;
    role?: UserRole;
  }): Promise<{ accessToken: string }> {
    const email = (input.email || '').trim().toLowerCase();
    if (!email) throw new BadRequestException('email is required');

    // Check if user already exists
    const existing = await this.users.findByEmail(email);
    if (existing) {
      // Auto-verify email for Google users
      if (!existing.emailVerified) {
        existing.emailVerified = true;
        await existing.save();
      }
      return this.issueToken(existing._id.toString(), existing.email, existing.role);
    }

    // New user — create with Google
    const role = input.role || 'player';
    const created = await this.users.createOrUpdateGoogleUser({
      email,
      googleSub: `web_${email}`,
      displayName: input.displayName || '',
      role: role as UserRole,
    });

    // Auto-verify email for Google users
    created.emailVerified = true;
    await created.save();

    return this.issueToken(created._id.toString(), created.email, created.role);
  }

  async bootstrapAdmin(input: {
    email: string;
    password: string;
    token: string;
    displayName?: string;
  }): Promise<{ accessToken: string }> {
    const bootstrapToken = (process.env.ADMIN_BOOTSTRAP_TOKEN || '').trim();
    if (!bootstrapToken) throw new ForbiddenException('Bootstrap not configured');
    if (input.token !== bootstrapToken) throw new ForbiddenException('Invalid bootstrap token');

    const existingAdmin = await this.users.findByEmail(input.email);
    if (existingAdmin && existingAdmin.role === 'admin') {
      throw new BadRequestException('Admin already exists');
    }

    const user = await this.users.createUser({
      email: input.email,
      password: input.password,
      role: 'admin',
      displayName: input.displayName || 'Admin',
    });

    // Mark as verified immediately
    const dbUser = await this.users.findByEmail(user.email);
    if (dbUser) {
      dbUser.emailVerified = true;
      dbUser.emailVerificationToken = '';
      await dbUser.save();
      return this.issueToken(dbUser._id.toString(), dbUser.email, dbUser.role);
    }

    throw new BadRequestException('Bootstrap failed');
  }

  private issueToken(sub: string, email: string, role: UserRole): { accessToken: string } {
    const accessToken = this.jwt.sign({ sub, email, role });
    if (!accessToken) throw new BadRequestException('Failed to issue token');
    return { accessToken };
  }

  /** Public wrapper so other controllers (e.g. upgrade) can issue a fresh token. */
  issueTokenPublic(sub: string, email: string, role: UserRole): { accessToken: string } {
    return this.issueToken(sub, email, role);
  }
}
