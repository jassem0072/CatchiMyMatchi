"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthService = void 0;
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const axios_1 = __importDefault(require("axios"));
const node_crypto_1 = require("node:crypto");
const common_1 = require("@nestjs/common");
const jwt_1 = require("@nestjs/jwt");
const nodemailer_1 = __importDefault(require("nodemailer"));
const users_service_1 = require("../users/users.service");
let AuthService = class AuthService {
    constructor(users, jwt) {
        this.users = users;
        this.jwt = jwt;
        this.mailer = null;
    }
    getMailer() {
        if (this.mailer)
            return this.mailer;
        const host = String(process.env.SMTP_HOST || '').trim();
        const user = String(process.env.SMTP_USER || '').trim();
        const pass = String(process.env.SMTP_PASS || '').trim();
        const port = Number(process.env.SMTP_PORT || '587') || 587;
        if (!host || !user || !pass)
            throw new common_1.BadRequestException('Email service not configured');
        this.mailer = nodemailer_1.default.createTransport({
            host,
            port,
            secure: port === 465,
            auth: { user, pass },
        });
        return this.mailer;
    }
    async sendPasswordResetEmail(input) {
        const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
        if (!from)
            throw new common_1.BadRequestException('Email service not configured');
        const appBaseUrl = String(process.env.APP_BASE_URL || '').trim();
        const link = appBaseUrl
            ? `${appBaseUrl.replace(/\/$/, '')}/#/forgot-password?email=${encodeURIComponent(input.to)}&token=${encodeURIComponent(input.token)}`
            : '';
        if (!link)
            throw new common_1.BadRequestException('APP_BASE_URL not configured');
        const text = `You requested a ScoutAI password reset.\n\n` +
            `To confirm and reset your password, open this link:\n\n` +
            `${link}\n\n` +
            `This link expires at: ${input.expiresAt.toISOString()}\n`;
        const html = `<p>You requested a ScoutAI password reset.</p>` +
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
    hashResetToken(token) {
        return (0, node_crypto_1.createHash)('sha256').update(token).digest('hex');
    }
    async requestPasswordReset(email) {
        const e = (email || '').trim().toLowerCase();
        if (!e)
            throw new common_1.BadRequestException('email is required');
        // Ensure we never return tokens in API responses.
        // Also enforce that SMTP is configured, otherwise this flow isn't secure.
        this.getMailer();
        const raw = (0, node_crypto_1.randomBytes)(20).toString('hex');
        const ttlMinutes = Number(process.env.RESET_PASSWORD_TOKEN_TTL_MINUTES || '15') || 15;
        const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
        const tokenHash = this.hashResetToken(raw);
        const ok = await this.users.setResetPasswordTokenByEmail(e, tokenHash, expiresAt);
        if (ok) {
            await this.sendPasswordResetEmail({ to: e, token: raw, expiresAt });
        }
        return { ok: true };
    }
    async resetPassword(email, token, newPassword) {
        const e = (email || '').trim().toLowerCase();
        const t = (token || '').trim();
        if (!e)
            throw new common_1.BadRequestException('email is required');
        if (!t)
            throw new common_1.BadRequestException('token is required');
        await this.users.resetPasswordByToken(e, this.hashResetToken(t), newPassword);
    }
    async register(input) {
        const created = await this.users.createUser(input);
        return this.issueToken(created._id.toString(), created.email, created.role);
    }
    async login(email, password) {
        const user = await this.users.findByEmail(email);
        if (!user)
            throw new common_1.UnauthorizedException('Invalid credentials');
        const ok = await bcryptjs_1.default.compare(password || '', user.passwordHash);
        if (!ok)
            throw new common_1.UnauthorizedException('Invalid credentials');
        return this.issueToken(user._id.toString(), user.email, user.role);
    }
    async loginWithGoogle(input) {
        const idToken = (input.idToken || '').trim();
        const accessToken = (input.accessToken || '').trim();
        if (!idToken && !accessToken)
            throw new common_1.BadRequestException('idToken or accessToken is required');
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
            let info;
            try {
                const res = await axios_1.default.get(tokenInfoUrl, { timeout: 8000 });
                info = res.data;
            }
            catch {
                throw new common_1.UnauthorizedException('Invalid Google token');
            }
            sub = String(info?.sub || '').trim();
            email = String(info?.email || '').trim().toLowerCase();
            aud = String(info?.aud || info?.audience || info?.issued_to || '').trim();
            name = String(info?.name || '').trim();
        }
        else {
            const tokenInfoUrl = `https://oauth2.googleapis.com/tokeninfo?access_token=${encodeURIComponent(accessToken)}`;
            let info;
            try {
                const res = await axios_1.default.get(tokenInfoUrl, { timeout: 8000 });
                info = res.data;
            }
            catch {
                throw new common_1.UnauthorizedException('Invalid Google token');
            }
            aud = String(info?.aud || info?.audience || info?.issued_to || '').trim();
            sub = String(info?.user_id || info?.sub || '').trim();
            email = String(info?.email || '').trim().toLowerCase();
            // tokeninfo doesn't always return email/name; fetch from userinfo as fallback.
            if (!email || !sub) {
                try {
                    const res = await axios_1.default.get('https://openidconnect.googleapis.com/v1/userinfo', {
                        timeout: 8000,
                        headers: { Authorization: `Bearer ${accessToken}` },
                    });
                    const ui = res.data;
                    if (!sub)
                        sub = String(ui?.sub || '').trim();
                    if (!email)
                        email = String(ui?.email || '').trim().toLowerCase();
                    name = String(ui?.name || '').trim();
                }
                catch {
                    // ignore; we'll validate required fields below
                }
            }
        }
        if (!sub)
            throw new common_1.UnauthorizedException('Invalid Google token');
        if (!email)
            throw new common_1.UnauthorizedException('Google account has no email');
        if (allowedAudiences.length > 0 && !allowedAudiences.includes(aud)) {
            throw new common_1.UnauthorizedException('Invalid Google token audience');
        }
        const createdOrUpdated = await this.users.createOrUpdateGoogleUser({
            email,
            googleSub: sub,
            displayName: input.displayName || name,
            role: input.role,
        });
        return this.issueToken(createdOrUpdated._id.toString(), createdOrUpdated.email, createdOrUpdated.role);
    }
    issueToken(sub, email, role) {
        const accessToken = this.jwt.sign({ sub, email, role });
        if (!accessToken)
            throw new common_1.BadRequestException('Failed to issue token');
        return { accessToken };
    }
    /** Public wrapper so other controllers (e.g. upgrade) can issue a fresh token. */
    issueTokenPublic(sub, email, role) {
        return this.issueToken(sub, email, role);
    }
};
exports.AuthService = AuthService;
exports.AuthService = AuthService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [users_service_1.UsersService,
        jwt_1.JwtService])
], AuthService);
