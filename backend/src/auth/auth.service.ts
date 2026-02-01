import bcrypt from 'bcryptjs';
import axios from 'axios';
import { createHash, randomBytes } from 'node:crypto';
import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
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
      ? `${appBaseUrl.replace(/\/$/, '')}/#/forgot-password?email=${encodeURIComponent(input.to)}&token=${encodeURIComponent(input.token)}`
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

  async register(input: {
    email: string;
    password: string;
    role: UserRole;
    displayName?: string;
    position?: string;
    nation?: string;
  }): Promise<{ accessToken: string }> {
    const created = await this.users.createUser(input);
    return this.issueToken(created._id.toString(), created.email, created.role);
  }

  async login(email: string, password: string): Promise<{ accessToken: string }> {
    const user = await this.users.findByEmail(email);
    if (!user) throw new UnauthorizedException('Invalid credentials');

    const ok = await bcrypt.compare(password || '', user.passwordHash);
    if (!ok) throw new UnauthorizedException('Invalid credentials');

    return this.issueToken(user._id.toString(), user.email, user.role);
  }

  async loginWithGoogle(input: {
    idToken?: string;
    accessToken?: string;
    role?: UserRole;
    displayName?: string;
  }): Promise<{ accessToken: string }> {
    const idToken = (input.idToken || '').trim();
    const accessToken = (input.accessToken || '').trim();
    if (!idToken && !accessToken) throw new BadRequestException('idToken or accessToken is required');

    const allowedAudiences = (process.env.GOOGLE_CLIENT_IDS || process.env.GOOGLE_CLIENT_ID || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);

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

      // tokeninfo doesn't always return email/name; fetch from userinfo as fallback.
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
          // ignore; we'll validate required fields below
        }
      }
    }

    if (!sub) throw new UnauthorizedException('Invalid Google token');
    if (!email) throw new UnauthorizedException('Google account has no email');
    if (allowedAudiences.length > 0 && !allowedAudiences.includes(aud)) {
      throw new UnauthorizedException('Invalid Google token audience');
    }

    const createdOrUpdated = await this.users.createOrUpdateGoogleUser({
      email,
      googleSub: sub,
      displayName: input.displayName || name,
      role: input.role,
    });

    return this.issueToken(createdOrUpdated._id.toString(), createdOrUpdated.email, createdOrUpdated.role);
  }

  private issueToken(sub: string, email: string, role: UserRole): { accessToken: string } {
    const accessToken = this.jwt.sign({ sub, email, role });
    if (!accessToken) throw new BadRequestException('Failed to issue token');
    return { accessToken };
  }
}
