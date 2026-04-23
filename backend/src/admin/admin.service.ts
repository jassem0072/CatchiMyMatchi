import * as fs from 'node:fs';
import * as path from 'node:path';
import { BadRequestException, ForbiddenException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import nodemailer, { type Transporter } from 'nodemailer';

import { User, UserDocument } from '../users/users.schema';
import { Video, VideoDocument } from '../videos/videos.schema';
import { Report, ReportDocument } from '../reports/reports.schema';
import { Notification, NotificationDocument } from '../notifications/notifications.schema';
import {
  BillingTransaction,
  type BillingTransactionDocument,
  type BillingTransactionDirection,
  type BillingTransactionStatus,
  type BillingTransactionType,
} from '../billing/billing-transaction.schema';
import type {
  AdminUserQueryDto,
  BillingTransactionQueryDto,
  BroadcastNotificationDto,
  UpdateSubscriptionDto,
} from './admin.dto';

type VerificationStatus = 'not_requested' | 'pending_expert' | 'verified' | 'rejected';
type PreContractStatus = 'none' | 'draft' | 'approved' | 'cancelled';

type ExpertPayoutInvoice = {
  invoiceId: string;
  amountEur: number;
  claimedPlayers: number;
  requestedAt: string;
  expectedPaymentAt: string;
  payoutProvider: 'paypal' | 'bank_transfer' | 'legacy_card';
  payoutDestinationMasked: string;
  transactionReference: string;
  status: 'requested' | 'processing' | 'paid';
};

type PlayerWorkflow = {
  sentVideoRequests: number;
  verificationStatus: VerificationStatus;
  scouterDecision: 'pending' | 'approved' | 'cancelled';
  expertDecision: 'pending' | 'approved' | 'cancelled';
  expertReport: string;
  fixedPrice: number;
  preContractStatus: PreContractStatus;
  contractDraft: {
    clubName: string;
    clubOfficialName: string;
    startDate: string;
    endDate: string;
    currency: string;
    salaryPeriod: 'monthly' | 'weekly';
    fixedBaseSalary: number;
    signingOnFee: number;
    marketValue: number;
    bonusPerAppearance: number;
    bonusGoalOrCleanSheet: number;
    bonusTeamTrophy: number;
    releaseClauseAmount: number;
    terminationForCauseText: string;
    scouterIntermediaryId: string;
  };
  scouterSignedContract: boolean;
  scouterSignedAt: string | null;
  scouterSignatureName: string;
  scouterSignatureImageBase64: string;
  scouterSignatureImageContentType: string;
  scouterSignatureImageFileName: string;
  contractSignedByPlayer: boolean;
  contractSignedAt: string | null;
  playerSignatureImageBase64: string;
  playerSignatureImageContentType: string;
  playerSignatureImageFileName: string;
  scouterPlatformFeePaid: boolean;
  scouterPlatformFeePaidAt: string | null;
  onlineSessionCompleted: boolean;
  onlineSessionCompletedAt: string | null;
  contractCompleted: boolean;
  updatedAt: string;
  expertReviewerUserId?: string;
  expertVerificationFeeUsd?: number;
  expertFeePaid?: boolean;
  expertFeePaidAt?: string | null;
};

@Injectable()
export class AdminService {
  private static readonly PROTECTED_ADMIN_EMAIL = 'testadmin@example.com';
  private static readonly PAYOUT_ADMIN_EMAIL = 'scoutai@gmail.com';
  private readonly logger = new Logger(AdminService.name);
  private mailer: Transporter | null = null;

  constructor(
    @InjectModel(User.name) private readonly userModel: Model<UserDocument>,
    @InjectModel(Video.name) private readonly videoModel: Model<VideoDocument>,
    @InjectModel(Report.name) private readonly reportModel: Model<ReportDocument>,
    @InjectModel(Notification.name) private readonly notifModel: Model<NotificationDocument>,
    @InjectModel(BillingTransaction.name) private readonly billingTxModel: Model<BillingTransactionDocument>,
  ) {}

  private isProtectedAdminEmail(email?: string | null): boolean {
    return (email ?? '').trim().toLowerCase() === AdminService.PROTECTED_ADMIN_EMAIL;
  }

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

  private resolveEmailBrandLogoPath(): string | null {
    const explicitPath = String(process.env.EMAIL_BRAND_LOGO_PATH || '').trim();
    const candidatePaths = [
      explicitPath,
      path.join(process.cwd(), 'assets', 'branding', 'scoutai_logo.png'),
    ].filter(Boolean);

    for (const candidate of candidatePaths) {
      if (fs.existsSync(candidate)) return candidate;
    }

    return null;
  }

  private buildBrandedEmailHtml(input: {
    title: string;
    subtitle: string;
    intro: string;
    rows: string[];
    highlight: string;
    note?: string;
    logoCid?: string;
  }): string {
    const rowsHtml = input.rows
      .map((row) => `<tr><td style="padding:8px 0;color:#1f2a37;font-size:14px;line-height:1.45;">${row}</td></tr>`)
      .join('');

    const logoImageHtml = input.logoCid
      ? `<img src="cid:${input.logoCid}" alt="ScoutAI" style="height:52px;width:52px;display:block;border-radius:12px;" />`
      : `<div style="height:52px;width:52px;border-radius:12px;background:#1D63FF;color:#ffffff;font-size:11px;font-weight:800;display:flex;align-items:center;justify-content:center;">SA</div>`;

    const logoHtml = `
      <table role="presentation" cellpadding="0" cellspacing="0">
        <tr>
          <td style="vertical-align:middle;padding-right:14px;">${logoImageHtml}</td>
          <td style="vertical-align:middle;">
            <div style="color:#ffffff;font-size:64px;line-height:1;font-family:'Segoe Script','Brush Script MT',cursive;font-weight:700;letter-spacing:1px;">ScoutAI</div>
          </td>
        </tr>
      </table>
    `;

    return `
      <div style="margin:0;padding:28px;background:#f3f6fb;font-family:Segoe UI,Arial,sans-serif;color:#0f172a;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:700px;margin:0 auto;background:#ffffff;border:1px solid #e4eaf3;border-radius:14px;overflow:hidden;">
          <tr>
            <td style="padding:22px 24px;background:#0d1b3a;">${logoHtml}</td>
          </tr>
          <tr>
            <td style="padding:24px;">
              <div style="font-size:22px;font-weight:800;color:#0f172a;margin-bottom:4px;">${input.title}</div>
              <div style="font-size:13px;color:#64748b;margin-bottom:18px;">${input.subtitle}</div>
              <div style="font-size:15px;color:#1f2a37;line-height:1.6;margin-bottom:14px;">${input.intro}</div>
              <div style="margin:0 0 16px 0;padding:12px 14px;border-radius:10px;background:#e9fdf0;border:1px solid #b9efcf;color:#11643f;font-size:14px;font-weight:700;">
                ${input.highlight}
              </div>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #eef2f7;padding-top:8px;">
                ${rowsHtml}
              </table>
              <div style="margin-top:18px;font-size:12px;color:#64748b;line-height:1.5;">${input.note || 'ScoutAI Finance Team'}</div>
            </td>
          </tr>
        </table>
      </div>
    `;
  }

  private escapeHtml(value: string): string {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private buildAdminPayoutEmailHtml(input: {
    userId: string;
    amountEur: number;
    invoiceId: string;
    payoutProvider: string;
    transactionReference: string;
    accountHolderName: string;
    bankName: string;
    bankAccountOrIban: string;
    swiftBic?: string;
    logoCid?: string;
  }): string {
    const logoImageHtml = input.logoCid
      ? `<img src="cid:${input.logoCid}" alt="ScoutAI" style="height:52px;width:52px;display:block;border-radius:12px;" />`
      : `<div style="height:52px;width:52px;border-radius:12px;background:#1D63FF;color:#ffffff;font-size:11px;font-weight:800;display:flex;align-items:center;justify-content:center;">SA</div>`;

    const detailRow = (label: string, value: string) => `
      <tr>
        <td style="padding:10px 0;color:#64748b;font-size:13px;width:220px;vertical-align:top;">${this.escapeHtml(label)}</td>
        <td style="padding:10px 0;color:#0f172a;font-size:14px;font-weight:600;">${this.escapeHtml(value)}</td>
      </tr>
    `;

    return `
      <div style="margin:0;padding:28px;background:#f3f6fb;font-family:Segoe UI,Arial,sans-serif;color:#0f172a;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:760px;margin:0 auto;background:#ffffff;border:1px solid #e4eaf3;border-radius:14px;overflow:hidden;">
          <tr>
            <td style="padding:22px 24px;background:#0d1b3a;">
              <table role="presentation" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="vertical-align:middle;padding-right:14px;">${logoImageHtml}</td>
                  <td style="vertical-align:middle;">
                    <div style="color:#ffffff;font-size:64px;line-height:1;font-family:'Segoe Script','Brush Script MT',cursive;font-weight:700;letter-spacing:1px;">ScoutAI</div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:24px;">
              <div style="font-size:22px;font-weight:800;color:#0f172a;margin-bottom:4px;">New Expert Payout Request</div>
              <div style="font-size:13px;color:#64748b;margin-bottom:18px;">Invoice ${this.escapeHtml(input.invoiceId)}</div>
              <div style="font-size:15px;color:#1f2a37;line-height:1.6;margin-bottom:14px;">
                This is an admin/internal payment instruction email. Full payout details are shown below so finance can execute payment.
              </div>
              <div style="margin:0 0 16px 0;padding:12px 14px;border-radius:10px;background:#fff7ed;border:1px solid #fed7aa;color:#9a3412;font-size:14px;font-weight:700;">
                Action required: execute this payout within 3 days.
              </div>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #eef2f7;">
                ${detailRow('User ID', input.userId)}
                ${detailRow('Amount', `EUR ${input.amountEur.toFixed(2)}`)}
                ${detailRow('Provider', input.payoutProvider)}
                ${detailRow('Transaction reference', input.transactionReference)}
                ${detailRow('Account holder (full)', input.accountHolderName)}
                ${detailRow('Bank name', input.bankName)}
                ${detailRow('Account / IBAN (full)', input.bankAccountOrIban)}
                ${input.swiftBic ? detailRow('SWIFT / BIC', input.swiftBic) : ''}
              </table>
              <div style="margin-top:18px;font-size:12px;color:#64748b;line-height:1.5;">Recipient mailbox: scoutai2026@gmail.com (admin payout processing)</div>
            </td>
          </tr>
        </table>
      </div>
    `;
  }

  private maskPayoutDestination(ref: string): string {
    const cleaned = String(ref || '').trim();
    if (!cleaned) return '';

    if (cleaned.includes('@')) {
      const [local, domain] = cleaned.split('@');
      if (!domain) return '***';
      const visibleLocal = local.length <= 2 ? '*' : `${local.slice(0, 2)}***`;
      return `${visibleLocal}@${domain}`;
    }

    if (cleaned.length <= 6) return `***${cleaned.slice(-2)}`;
    return `${cleaned.slice(0, 3)}***${cleaned.slice(-3)}`;
  }

  private normalizeTransactionReference(value: string | undefined, invoiceId: string): string {
    const raw = String(value || '').trim();
    if (!raw) return invoiceId;
    return raw.slice(0, 64);
  }

  private async sendExpertPayoutAcknowledgementEmail(input: {
    to: string;
    displayName: string;
    amountEur: number;
    invoiceId: string;
    payoutProvider: string;
    transactionReference: string;
    expectedPaymentAt: string;
  }): Promise<void> {
    const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
    if (!from) throw new BadRequestException('SMTP_FROM or SMTP_USER is required for payout emails');

    const expectedDate = new Date(input.expectedPaymentAt).toLocaleDateString('en-GB');
    const safeName = input.displayName || 'Expert';
    const amount = input.amountEur.toFixed(2);
    const logoCid = 'scoutai-brand-logo';
    const logoPath = this.resolveEmailBrandLogoPath();
    const attachments = logoPath
      ? [{ filename: 'scoutai_logo.png', path: logoPath, cid: logoCid }]
      : [];

    const html = this.buildBrandedEmailHtml({
      title: 'Payout Request Received',
      subtitle: `Invoice ${input.invoiceId}`,
      intro: `Hello ${safeName}, your payout request has been registered successfully.`,
      highlight: `You will get your money in 3 days (around ${expectedDate}).`,
      rows: [
        `Amount: EUR ${amount}`,
        `Provider: ${input.payoutProvider}`,
        `Transaction reference: ${input.transactionReference}`,
      ],
      note: 'If you need changes to billing details, contact ScoutAI support before payment processing.',
      logoCid: logoPath ? logoCid : undefined,
    });

    const mailer = this.getMailer();
    await mailer.sendMail({
      from,
      to: input.to,
      subject: `ScoutAI payout request received - ${input.invoiceId}`,
      text:
        `Hello ${safeName},\n\n` +
        `Your payout request has been received.\n` +
        `Invoice: ${input.invoiceId}\n` +
        `Amount: EUR ${amount}\n` +
        `Provider: ${input.payoutProvider}\n` +
        `Transaction reference: ${input.transactionReference}\n` +
        `Expected payment: in 3 days (around ${expectedDate}).\n\n` +
        `Thank you,\nScoutAI Finance Team`,
      html,
      attachments,
    });
  }

  private async sendAdminPayoutRequestEmail(input: {
    userId: string;
    amountEur: number;
    invoiceId: string;
    payoutProvider: string;
    payoutDestinationMasked: string;
    transactionReference: string;
    billingDetails: string;
    accountHolderName: string;
    bankName: string;
    bankAccountOrIban: string;
    swiftBic?: string;
  }): Promise<void> {
    const from = String(process.env.SMTP_FROM || process.env.SMTP_USER || '').trim();
    if (!from) throw new BadRequestException('SMTP_FROM or SMTP_USER is required for payout emails');

    const adminEmail = String(
      process.env.PAYOUT_ADMIN_EMAIL || process.env.SMTP_USER || AdminService.PAYOUT_ADMIN_EMAIL,
    ).trim();
    if (!adminEmail) throw new BadRequestException('PAYOUT_ADMIN_EMAIL is not configured');

    const logoCid = 'scoutai-brand-logo';
    const logoPath = this.resolveEmailBrandLogoPath();
    const attachments = logoPath
      ? [{ filename: 'scoutai_logo.png', path: logoPath, cid: logoCid }]
      : [];
    const html = this.buildAdminPayoutEmailHtml({
      userId: input.userId,
      amountEur: input.amountEur,
      invoiceId: input.invoiceId,
      payoutProvider: input.payoutProvider,
      transactionReference: input.transactionReference,
      accountHolderName: input.accountHolderName,
      bankName: input.bankName,
      bankAccountOrIban: input.bankAccountOrIban,
      swiftBic: input.swiftBic,
      logoCid: logoPath ? logoCid : undefined,
    });

    const mailer = this.getMailer();
    await mailer.sendMail({
      from,
      to: adminEmail,
      subject: `Payout request alert - ${input.invoiceId}`,
      text:
        `A new expert payout request was submitted.\n\n` +
        `User ID: ${input.userId}\n` +
        `Amount: EUR ${input.amountEur.toFixed(2)}\n` +
        `Invoice: ${input.invoiceId}\n` +
        `Provider: ${input.payoutProvider}\n` +
        `Destination (masked): ${input.payoutDestinationMasked}\n` +
        `Transaction reference: ${input.transactionReference}\n\n` +
        `Submitted billing details:\n${input.billingDetails}`,
      html,
      attachments,
    });
  }

  private coerceToBuffer(value: any): Buffer | null {
    if (!value) return null;
    if (Buffer.isBuffer(value)) return value;
    if (value instanceof Uint8Array) return Buffer.from(value);

    if (typeof value === 'object') {
      if (value.type === 'Buffer' && Array.isArray(value.data)) {
        return Buffer.from(value.data);
      }

      const bsontype = (value as any)._bsontype;
      if (bsontype === 'Binary' && typeof (value as any).value === 'function') {
        const v = (value as any).value(true);
        if (Buffer.isBuffer(v)) return v;
        if (v instanceof Uint8Array) return Buffer.from(v);
        if (Array.isArray(v)) return Buffer.from(v);
      }

      const buf = (value as any).buffer;
      if (Buffer.isBuffer(buf)) return buf;
      if (buf instanceof Uint8Array) return Buffer.from(buf);
    }

    try {
      return Buffer.from(value);
    } catch {
      return null;
    }
  }

  private defaultWorkflow(): PlayerWorkflow {
    return {
      sentVideoRequests: 0,
      verificationStatus: 'not_requested',
      scouterDecision: 'pending',
      expertDecision: 'pending',
      expertReport: '',
      fixedPrice: 0,
      preContractStatus: 'none',
      contractDraft: {
        clubName: '',
        clubOfficialName: '',
        startDate: '',
        endDate: '',
        currency: 'EUR',
        salaryPeriod: 'monthly',
        fixedBaseSalary: 0,
        signingOnFee: 0,
        marketValue: 0,
        bonusPerAppearance: 0,
        bonusGoalOrCleanSheet: 0,
        bonusTeamTrophy: 0,
        releaseClauseAmount: 0,
        terminationForCauseText: 'Termination for just cause may apply according to federation regulations.',
        scouterIntermediaryId: '',
      },
      scouterSignedContract: false,
      scouterSignedAt: null,
      scouterSignatureName: '',
      scouterSignatureImageBase64: '',
      scouterSignatureImageContentType: '',
      scouterSignatureImageFileName: '',
      contractSignedByPlayer: false,
      contractSignedAt: null,
      playerSignatureImageBase64: '',
      playerSignatureImageContentType: '',
      playerSignatureImageFileName: '',
      scouterPlatformFeePaid: false,
      scouterPlatformFeePaidAt: null,
      onlineSessionCompleted: false,
      onlineSessionCompletedAt: null,
      contractCompleted: false,
      updatedAt: new Date().toISOString(),
    };
  }

  private normalizeWorkflow(raw: any): PlayerWorkflow {
    const base = this.defaultWorkflow();
    if (!raw || typeof raw !== 'object') return base;
    const contractSignedByPlayer = Boolean(raw.contractSignedByPlayer);
    const onlineSessionCompleted = Boolean(raw.onlineSessionCompleted);
    const contractDraft = raw.contractDraft && typeof raw.contractDraft === 'object' ? raw.contractDraft : {};
    return {
      sentVideoRequests: Number(raw.sentVideoRequests) || 0,
      verificationStatus: (raw.verificationStatus as VerificationStatus) || base.verificationStatus,
      scouterDecision: (raw.scouterDecision as 'pending' | 'approved' | 'cancelled') || base.scouterDecision,
      expertDecision: (raw.expertDecision as 'pending' | 'approved' | 'cancelled') || base.expertDecision,
      expertReport: String(raw.expertReport || ''),
      fixedPrice: Number(raw.fixedPrice) || 0,
      preContractStatus: (raw.preContractStatus as PreContractStatus) || base.preContractStatus,
      contractDraft: {
        clubName: String(contractDraft.clubName || ''),
        clubOfficialName: String(contractDraft.clubOfficialName || ''),
        startDate: String(contractDraft.startDate || ''),
        endDate: String(contractDraft.endDate || ''),
        currency: String(contractDraft.currency || 'EUR'),
        salaryPeriod: contractDraft.salaryPeriod === 'weekly' ? 'weekly' : 'monthly',
        fixedBaseSalary: Number(contractDraft.fixedBaseSalary) || 0,
        signingOnFee: Number(contractDraft.signingOnFee) || 0,
        marketValue: Number(contractDraft.marketValue) || 0,
        bonusPerAppearance: Number(contractDraft.bonusPerAppearance) || 0,
        bonusGoalOrCleanSheet: Number(contractDraft.bonusGoalOrCleanSheet) || 0,
        bonusTeamTrophy: Number(contractDraft.bonusTeamTrophy) || 0,
        releaseClauseAmount: Number(contractDraft.releaseClauseAmount) || 0,
        terminationForCauseText: String(contractDraft.terminationForCauseText || base.contractDraft.terminationForCauseText),
        scouterIntermediaryId: String(contractDraft.scouterIntermediaryId || ''),
      },
      scouterSignedContract: Boolean(raw.scouterSignedContract),
      scouterSignedAt: raw.scouterSignedAt ? new Date(raw.scouterSignedAt).toISOString() : null,
      scouterSignatureName: String(raw.scouterSignatureName || ''),
      scouterSignatureImageBase64: String(raw.scouterSignatureImageBase64 || ''),
      scouterSignatureImageContentType: String(raw.scouterSignatureImageContentType || ''),
      scouterSignatureImageFileName: String(raw.scouterSignatureImageFileName || ''),
      contractSignedByPlayer,
      contractSignedAt: raw.contractSignedAt ? new Date(raw.contractSignedAt).toISOString() : null,
      playerSignatureImageBase64: String(raw.playerSignatureImageBase64 || ''),
      playerSignatureImageContentType: String(raw.playerSignatureImageContentType || ''),
      playerSignatureImageFileName: String(raw.playerSignatureImageFileName || ''),
      scouterPlatformFeePaid: Boolean(raw.scouterPlatformFeePaid),
      scouterPlatformFeePaidAt: raw.scouterPlatformFeePaidAt ? new Date(raw.scouterPlatformFeePaidAt).toISOString() : null,
      onlineSessionCompleted,
      onlineSessionCompletedAt: raw.onlineSessionCompletedAt ? new Date(raw.onlineSessionCompletedAt).toISOString() : null,
      contractCompleted: contractSignedByPlayer && onlineSessionCompleted,
      updatedAt: raw.updatedAt ? new Date(raw.updatedAt).toISOString() : base.updatedAt,
      expertReviewerUserId: raw.expertReviewerUserId ? String(raw.expertReviewerUserId) : '',
      expertVerificationFeeUsd: Number(raw.expertVerificationFeeUsd) || 0,
      expertFeePaid: Boolean(raw.expertFeePaid),
      expertFeePaidAt: raw.expertFeePaidAt ? new Date(raw.expertFeePaidAt).toISOString() : null,
    };
  }

  private async ensurePlayer(id: string): Promise<any> {
    const player = await this.userModel
      .findById(id)
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!player || (player as any).role !== 'player') throw new NotFoundException('Player not found');
    return player;
  }

  private async savePlayerWorkflow(id: string, workflow: PlayerWorkflow): Promise<PlayerWorkflow> {
    const persisted = {
      ...workflow,
      updatedAt: new Date().toISOString(),
    };

    const updated = await this.userModel
      .findByIdAndUpdate(id, { adminWorkflow: persisted }, { new: true })
      .select('_id role adminWorkflow')
      .lean();

    if (!updated || (updated as any).role !== 'player') throw new NotFoundException('Player not found');
    return this.normalizeWorkflow((updated as any).adminWorkflow);
  }

  // ── Users ──────────────────────────────────────────────────────────────

  async listUsers(query: AdminUserQueryDto): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(query.limit) || 20));
    const skip = (page - 1) * limit;

    const filter: Record<string, any> = {};
    if (query.role) filter.role = query.role;
    if (query.search) {
      const re = { $regex: query.search, $options: 'i' };
      filter.$or = [{ email: re }, { displayName: re }];
    }

    const [data, total] = await Promise.all([
      this.userModel
        .find(filter)
        .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      this.userModel.countDocuments(filter),
    ]);

    return { data, total, page, limit };
  }

  async deleteUser(id: string): Promise<void> {
    const user = await this.userModel.findById(id).select('email').lean();
    if (!user) throw new NotFoundException('User not found');
    if (this.isProtectedAdminEmail((user as any).email)) {
      throw new ForbiddenException('This admin account is protected and cannot be deleted');
    }

    const result = await this.userModel.findByIdAndDelete(id);
    if (!result) throw new NotFoundException('User not found');
  }

  async banUser(id: string, isBanned: boolean): Promise<any> {
    const existing = await this.userModel.findById(id).select('email').lean();
    if (!existing) throw new NotFoundException('User not found');
    if (this.isProtectedAdminEmail((existing as any).email)) {
      throw new ForbiddenException('This admin account is protected and cannot be banned');
    }

    const user = await this.userModel
      .findByIdAndUpdate(id, { isBanned }, { new: true })
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async updateUserRole(
    id: string,
    role: 'player' | 'scouter' | 'admin' | 'expert',
    actorEmail: string,
  ): Promise<any> {
    if (role === 'admin' && !this.isProtectedAdminEmail(actorEmail)) {
      throw new ForbiddenException('Only the main admin can create/promote admins');
    }

    const user = await this.userModel
      .findByIdAndUpdate(id, { role }, { new: true })
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async approveAdminAccessRequest(id: string, actorEmail: string): Promise<any> {
    if (!this.isProtectedAdminEmail(actorEmail)) {
      throw new ForbiddenException('Only the main admin can approve admin access requests');
    }

    const user = await this.userModel.findById(id).lean();
    if (!user) throw new NotFoundException('User not found');

    const status = (user as any).adminAccessRequestStatus || 'none';
    if (status !== 'pending') {
      throw new BadRequestException('No pending admin access request for this user');
    }

    const updated = await this.userModel
      .findByIdAndUpdate(
        id,
        {
          role: 'admin',
          adminAccessRequestStatus: 'approved',
          adminAccessApprovedAt: new Date(),
        },
        { new: true },
      )
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();

    if (!updated) throw new NotFoundException('User not found');
    return updated;
  }

  // ── Videos ──────────────────────────────────────────────────────────────

  async listVideos(page = 1, limit = 20): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const p = Math.max(1, page);
    const l = Math.min(100, Math.max(1, limit));
    const skip = (p - 1) * l;

    const [rawVideos, total] = await Promise.all([
      this.videoModel.find().sort({ createdAt: -1 }).skip(skip).limit(l).lean(),
      this.videoModel.countDocuments(),
    ]);

    // Populate owner display names
    const ownerIds = [...new Set(rawVideos.map((v: any) => v.ownerId).filter(Boolean))];
    const owners = ownerIds.length
      ? await this.userModel.find({ _id: { $in: ownerIds } }).select('_id displayName email').lean()
      : [];
    const ownerMap: Record<string, string> = {};
    for (const o of owners as any[]) {
      ownerMap[String(o._id)] = o.displayName || o.email || String(o._id);
    }

    const data = rawVideos.map((v: any) => ({
      ...v,
      ownerDisplayName: v.ownerId ? (ownerMap[String(v.ownerId)] ?? 'Unknown') : 'Anonymous',
    }));

    return { data, total, page: p, limit: l };
  }

  async deleteVideo(id: string): Promise<void> {
    const video = await this.videoModel.findByIdAndDelete(id);
    if (!video) throw new NotFoundException('Video not found');

    // Try to remove the file from disk
    if ((video as any).relativePath) {
      const uploadDir = process.env.UPLOAD_DIR || 'uploads';
      const uploadsRoot = path.isAbsolute(uploadDir)
        ? uploadDir
        : path.join(process.cwd(), uploadDir);
      const filePath = path.join(uploadsRoot, (video as any).relativePath);
      if (fs.existsSync(filePath)) {
        try { fs.unlinkSync(filePath); } catch { /* ignore */ }
      }
    }
  }

  async setVideoVisibility(id: string, visibility: 'public' | 'private'): Promise<any> {
    const video = await this.videoModel
      .findByIdAndUpdate(id, { visibility }, { new: true })
      .lean();
    if (!video) throw new NotFoundException('Video not found');
    return video;
  }

  // ── Stats ──────────────────────────────────────────────────────────────

  async getStats(): Promise<Record<string, any>> {
    const now = new Date();
    const twelveMonthsAgo = new Date(now);
    twelveMonthsAgo.setMonth(twelveMonthsAgo.getMonth() - 11);
    twelveMonthsAgo.setDate(1);
    twelveMonthsAgo.setHours(0, 0, 0, 0);

    const [
      totalPlayers,
      totalScouterss,
      totalVideos,
      analyzedVideos,
      registrationsByMonth,
      subscriptionDist,
    ] = await Promise.all([
      this.userModel.countDocuments({ role: 'player' }),
      this.userModel.countDocuments({ role: 'scouter' }),
      this.videoModel.countDocuments(),
      this.videoModel.countDocuments({ lastAnalysis: { $ne: null } }),
      this.userModel.aggregate([
        { $match: { createdAt: { $gte: twelveMonthsAgo } } },
        {
          $group: {
            _id: { year: { $year: '$createdAt' }, month: { $month: '$createdAt' } },
            count: { $sum: 1 },
          },
        },
        { $sort: { '_id.year': 1, '_id.month': 1 } },
      ]),
      this.userModel.aggregate([
        { $match: { subscriptionTier: { $ne: null } } },
        { $group: { _id: '$subscriptionTier', count: { $sum: 1 } } },
      ]),
    ]);

    const monthLabels = [];
    for (let i = 0; i < 12; i++) {
      const d = new Date(twelveMonthsAgo);
      d.setMonth(d.getMonth() + i);
      monthLabels.push({ year: d.getFullYear(), month: d.getMonth() + 1 });
    }

    const regMap: Record<string, number> = {};
    for (const r of registrationsByMonth) {
      regMap[`${r._id.year}-${r._id.month}`] = r.count;
    }

    const registrations = monthLabels.map((m) => ({
      label: `${m.year}-${String(m.month).padStart(2, '0')}`,
      count: regMap[`${m.year}-${m.month}`] ?? 0,
    }));

    const subscriptions: Record<string, number> = { basic: 0, premium: 0, elite: 0 };
    for (const s of subscriptionDist) {
      if (s._id) subscriptions[s._id] = s.count;
    }

    return {
      totalPlayers,
      totalScouterss,
      totalVideos,
      analyzedVideos,
      registrations,
      subscriptions,
    };
  }

  // ── Players (admin) ─────────────────────────────────────────────────────

  async listPlayers(query: AdminUserQueryDto): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(query.limit) || 20));
    const skip = (page - 1) * limit;

    const filter: Record<string, any> = { role: 'player' };
    if ((query as any).subscriptionTier) filter.subscriptionTier = (query as any).subscriptionTier;
    if (query.search) {
      const re = { $regex: query.search, $options: 'i' };
      filter.$or = [{ email: re }, { displayName: re }];
    }

    const [players, total] = await Promise.all([
      this.userModel
        .find(filter)
        .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      this.userModel.countDocuments(filter),
    ]);

    // Enrich with video & report counts
    const playerIds = (players as any[]).map((p: any) => String(p._id));
    const [videoCounts, reportCounts] = await Promise.all([
      this.videoModel.aggregate([
        { $match: { ownerId: { $in: playerIds } } },
        { $group: { _id: '$ownerId', count: { $sum: 1 } } },
      ]),
      this.reportModel.aggregate([
        { $match: { playerId: { $in: playerIds } } },
        { $group: { _id: '$playerId', count: { $sum: 1 } } },
      ]),
    ]);

    const videoMap: Record<string, number> = {};
    for (const v of videoCounts) videoMap[String(v._id)] = v.count;
    const reportMap: Record<string, number> = {};
    for (const r of reportCounts) reportMap[String(r._id)] = r.count;

    const data = (players as any[]).map((p: any) => ({
      ...p,
      videoCount: videoMap[String(p._id)] ?? 0,
      reportCount: reportMap[String(p._id)] ?? 0,
    }));

    return { data, total, page, limit };
  }

  async getPlayerDetail(id: string): Promise<any> {
    const player = await this.ensurePlayer(id);

    const [videos, reports] = await Promise.all([
      this.videoModel.find({ ownerId: String(id) }).sort({ createdAt: -1 }).lean(),
      this.reportModel.find({ playerId: String(id) }).sort({ createdAt: -1 }).lean(),
    ]);

    // Aggregate performance metrics from analyzed videos
    const analyzed = (videos as any[]).filter((v: any) => v.lastAnalysis);
    let totalDist = 0, sumAvg = 0, maxSpeed = 0, totalSprints = 0;
    for (const v of analyzed) {
      const m = v.lastAnalysis?.metrics || v.lastAnalysis;
      if (!m) continue;
      totalDist += m.distanceMeters ?? 0;
      sumAvg += m.avgSpeedKmh ?? 0;
      if ((m.maxSpeedKmh ?? 0) > maxSpeed) maxSpeed = m.maxSpeedKmh;
      totalSprints += m.sprintCount ?? 0;
    }
    const analytics = {
      totalVideos: videos.length,
      analyzedVideos: analyzed.length,
      totalDistanceMeters: Math.round(totalDist * 100) / 100,
      avgSpeedKmh: analyzed.length ? Math.round((sumAvg / analyzed.length) * 100) / 100 : 0,
      maxSpeedKmh: Math.round(maxSpeed * 100) / 100,
      totalSprints,
      reportsAboutPlayer: reports.length,
    };

    const workflow = this.normalizeWorkflow((player as any).adminWorkflow);
    return { player, videos, reports, analytics, workflow };
  }

  async getPlayerPortraitDocument(id: string): Promise<{ data: Buffer; contentType: string; fileName: string } | null> {
    const player: any = await this.userModel
      .findById(id)
      .select('role portraitData portraitContentType bulletinN3Data bulletinN3ContentType bulletinN3FileName')
      .lean();
    if (!player || player.role !== 'player') throw new NotFoundException('Player not found');
    const data = this.coerceToBuffer(player.bulletinN3Data) || this.coerceToBuffer(player.portraitData);
    if (!data || data.length === 0) return null;
    return {
      data,
      contentType: player.bulletinN3ContentType || player.portraitContentType || 'image/jpeg',
      fileName: player.bulletinN3FileName || 'bulletin-n3',
    };
  }

  async getPlayerBadgeDocument(id: string): Promise<{ data: Buffer; contentType: string; fileName: string } | null> {
    const player: any = await this.userModel
      .findById(id)
      .select('role badgeData badgeContentType medicalDiplomaData medicalDiplomaContentType medicalDiplomaFileName')
      .lean();
    if (!player || player.role !== 'player') throw new NotFoundException('Player not found');
    const data = this.coerceToBuffer(player.medicalDiplomaData) || this.coerceToBuffer(player.badgeData);
    if (!data || data.length === 0) return null;
    return {
      data,
      contentType: player.medicalDiplomaContentType || player.badgeContentType || 'image/jpeg',
      fileName: player.medicalDiplomaFileName || 'medical-diploma',
    };
  }

  async getPlayerIdDocument(id: string): Promise<{ data: Buffer; contentType: string; fileName: string } | null> {
    const player: any = await this.userModel
      .findById(id)
      .select('role playerIdDocumentData playerIdDocumentContentType playerIdDocumentFileName')
      .lean();
    if (!player || player.role !== 'player') throw new NotFoundException('Player not found');
    const data = this.coerceToBuffer(player.playerIdDocumentData);
    if (!data || data.length === 0) return null;
    return {
      data,
      contentType: player.playerIdDocumentContentType || 'application/octet-stream',
      fileName: player.playerIdDocumentFileName || 'player-id',
    };
  }

  async recordVideoRequest(id: string): Promise<{ workflow: PlayerWorkflow }> {
    const player = await this.ensurePlayer(id);
    const current = this.normalizeWorkflow((player as any).adminWorkflow);
    const workflow = await this.savePlayerWorkflow(id, {
      ...current,
      sentVideoRequests: current.sentVideoRequests + 1,
    });
    return { workflow };
  }

  async requestInfoVerification(id: string, requesterUserId = ''): Promise<{ workflow: PlayerWorkflow }> {
    const player = await this.ensurePlayer(id);
    const current = this.normalizeWorkflow((player as any).adminWorkflow);
    const workflow = await this.savePlayerWorkflow(id, {
      ...current,
      verificationStatus: 'pending_expert',
      scouterDecision: 'pending',
      expertDecision: 'pending',
      contractSignedByPlayer: false,
      contractSignedAt: null,
      onlineSessionCompleted: false,
      onlineSessionCompletedAt: null,
    });

    const experts = await this.userModel.find({ role: 'expert', isBanned: { $ne: true } }).select('_id').lean();
    if (experts.length > 0) {
      let requesterName = 'A scouter';
      if (requesterUserId) {
        const requester: any = await this.userModel.findById(requesterUserId).select('displayName email role').lean();
        if (requester) requesterName = String(requester.displayName || requester.email || requesterName);
      }
      const playerName = String((player as any).displayName || (player as any).email || 'Player');
      const docs = experts.map((expert: any) => ({
        userId: String(expert._id),
        type: 'expert_verification_requested',
        titleEN: 'Player verification requested',
        titleFR: 'Verification du joueur demandee',
        bodyEN: `${requesterName} requested expert verification for ${playerName}.`,
        bodyFR: `${requesterName} a demande une verification expert pour ${playerName}.`,
        data: {
          playerId: String(id),
          playerName,
          verificationStatus: 'pending_expert',
          requestedBy: requesterUserId || null,
          requestedAt: new Date().toISOString(),
        },
        read: false,
      }));
      await this.notifModel.insertMany(docs);
    }

    return { workflow };
  }

  async setExpertReview(
    id: string,
    decision: 'approved' | 'cancelled',
    report?: string,
    reviewerUserId = '',
  ): Promise<{ workflow: PlayerWorkflow }> {
    const player = await this.ensurePlayer(id);
    const current = this.normalizeWorkflow((player as any).adminWorkflow);

    const nextWorkflow: PlayerWorkflow = {
      ...current,
      expertDecision: decision,
      verificationStatus: decision === 'approved' ? 'verified' : 'rejected',
      expertReport: typeof report === 'string' ? report : current.expertReport,
      expertReviewerUserId: decision === 'approved' ? reviewerUserId : current.expertReviewerUserId,
      expertVerificationFeeUsd: decision === 'approved' ? 30 : current.expertVerificationFeeUsd,
      expertFeePaid: decision === 'approved' ? false : current.expertFeePaid,
      expertFeePaidAt: decision === 'approved' ? null : current.expertFeePaidAt,
    };

    const updated = await this.userModel
      .findByIdAndUpdate(
        id,
        {
          adminWorkflow: {
            ...nextWorkflow,
            updatedAt: new Date().toISOString(),
          },
          badgeVerified: decision === 'approved',
        },
        { new: true },
      )
      .select('_id role adminWorkflow')
      .lean();

    if (!updated || (updated as any).role !== 'player') throw new NotFoundException('Player not found');
    return { workflow: this.normalizeWorkflow((updated as any).adminWorkflow) };
  }

  async getExpertEarnings(expertUserId: string): Promise<{
    verifiedPlayers: number;
    paidPlayers: number;
    pendingPlayers: number;
    totalUsd: number;
    paidUsd: number;
    pendingUsd: number;
  }> {
    const includeLegacyUnassigned = true;
    const players = await this.userModel
      .find({
        role: 'player',
        $and: [
          {
            $or: [
              { 'adminWorkflow.expertDecision': 'approved' },
              { 'adminWorkflow.verificationStatus': 'verified' },
            ],
          },
          {
            $or: [
              { 'adminWorkflow.expertReviewerUserId': expertUserId },
              ...(includeLegacyUnassigned
                ? [
                    { 'adminWorkflow.expertReviewerUserId': { $exists: false } },
                    { 'adminWorkflow.expertReviewerUserId': '' },
                  ]
                : []),
            ],
          },
        ],
      })
      .select('adminWorkflow')
      .lean();

    const workflows = players.map((p: any) => this.normalizeWorkflow(p.adminWorkflow));
    const verifiedPlayers = workflows.length;
    const paidPlayers = workflows.filter((w) => w.expertFeePaid === true).length;
    const pendingPlayers = verifiedPlayers - paidPlayers;
    const totalUsd = verifiedPlayers * 30;
    const paidUsd = paidPlayers * 30;
    const pendingUsd = pendingPlayers * 30;

    return { verifiedPlayers, paidPlayers, pendingPlayers, totalUsd, paidUsd, pendingUsd };
  }

  async recordBillingTransaction(input: {
    userId: string;
    direction: BillingTransactionDirection;
    type: BillingTransactionType;
    amountEur: number;
    status: BillingTransactionStatus;
    reference: string;
    provider?: string;
    metadata?: Record<string, unknown>;
  }): Promise<void> {
    await this.billingTxModel.create({
      userId: input.userId,
      direction: input.direction,
      type: input.type,
      amountEur: Number(input.amountEur) || 0,
      currency: 'EUR',
      status: input.status,
      reference: String(input.reference || '').trim(),
      provider: String(input.provider || '').trim(),
      metadata: input.metadata || {},
    });
  }

  async listBillingTransactions(query: BillingTransactionQueryDto): Promise<{
    data: Array<{
      id: string;
      userId: string;
      direction: BillingTransactionDirection;
      type: BillingTransactionType;
      amountEur: number;
      currency: string;
      status: BillingTransactionStatus;
      reference: string;
      provider: string;
      metadata: Record<string, unknown>;
      createdAt: string;
      updatedAt: string;
    }>;
    total: number;
    page: number;
    limit: number;
  }> {
    const page = Math.max(1, Number(query?.page) || 1);
    const limit = Math.min(200, Math.max(1, Number(query?.limit) || 20));
    const skip = (page - 1) * limit;

    const filter: Record<string, unknown> = {};
    if (query?.userId) filter.userId = String(query.userId).trim();
    if (query?.direction) filter.direction = query.direction;
    if (query?.type) filter.type = query.type;

    const [rows, total] = await Promise.all([
      this.billingTxModel.find(filter).sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
      this.billingTxModel.countDocuments(filter),
    ]);

    return {
      data: rows.map((row: any) => ({
        id: String(row._id),
        userId: String(row.userId || ''),
        direction: row.direction,
        type: row.type,
        amountEur: Number(row.amountEur) || 0,
        currency: String(row.currency || 'EUR'),
        status: row.status,
        reference: String(row.reference || ''),
        provider: String(row.provider || ''),
        metadata: (row.metadata || {}) as Record<string, unknown>,
        createdAt: row.createdAt ? new Date(row.createdAt).toISOString() : new Date().toISOString(),
        updatedAt: row.updatedAt ? new Date(row.updatedAt).toISOString() : new Date().toISOString(),
      })),
      total,
      page,
      limit,
    };
  }

  async getExpertPayoutInvoices(expertUserId: string): Promise<ExpertPayoutInvoice[]> {
    const expert = await this.userModel
      .findById(expertUserId)
      .select('expertPayoutInvoices')
      .lean();

    if (!expert) throw new NotFoundException('Expert not found');

    const invoicesRaw = Array.isArray((expert as any).expertPayoutInvoices)
      ? ((expert as any).expertPayoutInvoices as Array<Record<string, unknown>>)
      : [];

    const invoices: ExpertPayoutInvoice[] = invoicesRaw.map((invoice) => {
      const legacyCardLast4 = String(invoice.payoutCardLast4 || '').trim();
      const payoutProviderRaw = String(invoice.payoutProvider || '').trim();
      const payoutProvider = payoutProviderRaw === 'stripe_connect' ? 'bank_transfer' : payoutProviderRaw;
      return {
        invoiceId: String(invoice.invoiceId || ''),
        amountEur: Number(invoice.amountEur) || 0,
        claimedPlayers: Number(invoice.claimedPlayers) || 0,
        requestedAt: new Date(String(invoice.requestedAt || new Date().toISOString())).toISOString(),
        expectedPaymentAt: new Date(String(invoice.expectedPaymentAt || new Date().toISOString())).toISOString(),
        payoutProvider: (payoutProvider as ExpertPayoutInvoice['payoutProvider']) || (legacyCardLast4 ? 'legacy_card' : 'bank_transfer'),
        payoutDestinationMasked: String(invoice.payoutDestinationMasked || (legacyCardLast4 ? `****${legacyCardLast4}` : 'n/a')),
        transactionReference: String(invoice.transactionReference || invoice.invoiceId || ''),
        status: (String(invoice.status || 'requested') as ExpertPayoutInvoice['status']) || 'requested',
      };
    });

    return invoices.sort((a, b) => {
      const aTs = new Date(a.requestedAt).getTime();
      const bTs = new Date(b.requestedAt).getTime();
      return bTs - aTs;
    });
  }

  async claimExpertEarnings(
    expertUserId: string,
    payment?: {
      payoutProvider?: 'paypal' | 'bank_transfer';
      accountHolderName?: string;
      bankName?: string;
      bankAccountOrIban?: string;
      swiftBic?: string;
      payoutAccountRef?: string;
      transactionReference?: string;
    },
  ): Promise<{
    claimedPlayers: number;
    claimedUsd: number;
    message: string;
  }> {
    const payoutProvider = String(payment?.payoutProvider || '').trim() as 'paypal' | 'bank_transfer';
    const accountHolderName = String(payment?.accountHolderName || '').trim();
    const bankName = String(payment?.bankName || '').trim();
    const bankAccountOrIban = String(payment?.bankAccountOrIban || payment?.payoutAccountRef || '').trim();
    const swiftBic = String(payment?.swiftBic || '').trim();
    const transactionReferenceInput = String(payment?.transactionReference || '').trim();

    if (!['paypal', 'bank_transfer'].includes(payoutProvider)) {
      throw new BadRequestException('Valid payout provider is required');
    }
    if (!accountHolderName || accountHolderName.length < 3) {
      throw new BadRequestException('Account holder name is required');
    }
    if (!bankName || bankName.length < 2) {
      throw new BadRequestException('Bank name is required');
    }
    if (!bankAccountOrIban || bankAccountOrIban.length < 4) {
      throw new BadRequestException('Bank account or IBAN is required');
    }

    const includeLegacyUnassigned = true;
    const players = await this.userModel
      .find({
        role: 'player',
        'adminWorkflow.expertFeePaid': { $ne: true },
        $and: [
          {
            $or: [
              { 'adminWorkflow.expertDecision': 'approved' },
              { 'adminWorkflow.verificationStatus': 'verified' },
            ],
          },
          {
            $or: [
              { 'adminWorkflow.expertReviewerUserId': expertUserId },
              ...(includeLegacyUnassigned
                ? [
                    { 'adminWorkflow.expertReviewerUserId': { $exists: false } },
                    { 'adminWorkflow.expertReviewerUserId': '' },
                  ]
                : []),
            ],
          },
        ],
      })
      .select('_id adminWorkflow')
      .lean();

    const now = new Date().toISOString();

    const claimedPlayers = players.length;
    const claimedUsd = claimedPlayers * 30;
    const claimedEur = claimedUsd;
    const expectedPaymentDate = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString();
    const invoiceId = `INV-EXP-${Date.now()}`;
    const payoutDestinationMasked = this.maskPayoutDestination(bankAccountOrIban);
    const transactionReference = this.normalizeTransactionReference(transactionReferenceInput, invoiceId);
    const billingDetails = [
      `Account holder: ${accountHolderName}`,
      `Bank name: ${bankName}`,
      `Account / IBAN: ${bankAccountOrIban}`,
      ...(swiftBic ? [`SWIFT/BIC: ${swiftBic}`] : []),
      `Provider: ${payoutProvider}`,
    ].join('\n');

    await this.userModel.findByIdAndUpdate(expertUserId, {
      expertPayoutUpdatedAt: now,
      $push: {
        expertPayoutInvoices: {
          invoiceId,
          amountEur: claimedEur,
          claimedPlayers,
          requestedAt: now,
          expectedPaymentAt: expectedPaymentDate,
          payoutProvider,
          payoutDestinationMasked,
          transactionReference,
          status: 'requested',
        },
      },
    });

    await this.recordBillingTransaction({
      userId: expertUserId,
      direction: 'payout',
      type: 'expert_payout_request',
      amountEur: claimedEur,
      status: 'requested',
      reference: transactionReference,
      provider: payoutProvider,
      metadata: {
        invoiceId,
        payoutDestinationMasked,
        accountHolderName,
        bankName,
        swiftBic,
        claimedPlayers,
        expectedPaymentAt: expectedPaymentDate,
      },
    });

    const expert = await this.userModel.findById(expertUserId).select('email displayName').lean();
    const expertEmail = String((expert as any)?.email || '').trim();
    const adminEmail = String(
      process.env.PAYOUT_ADMIN_EMAIL || process.env.SMTP_USER || AdminService.PAYOUT_ADMIN_EMAIL,
    ).trim();

    let emailDeliveryOk = true;
    let emailDeliveryError = '';
    try {
      if (!expertEmail) {
        throw new BadRequestException('Expert account has no email address');
      }

      await this.sendExpertPayoutAcknowledgementEmail({
        to: expertEmail,
        displayName: String((expert as any)?.displayName || 'Expert').trim(),
        amountEur: claimedEur,
        invoiceId,
        payoutProvider,
        transactionReference,
        expectedPaymentAt: expectedPaymentDate,
      });

      await this.sendAdminPayoutRequestEmail({
        userId: expertUserId,
        amountEur: claimedEur,
        invoiceId,
        payoutProvider,
        payoutDestinationMasked,
        transactionReference,
        billingDetails,
        accountHolderName,
        bankName,
        bankAccountOrIban,
        swiftBic,
      });
    } catch (error: any) {
      emailDeliveryOk = false;
      emailDeliveryError = String(error?.message || 'Unknown SMTP error');
      this.logger.error(`Payout email delivery failed for invoice ${invoiceId}: ${emailDeliveryError}`);
    }

    await this.recordBillingTransaction({
      userId: expertUserId,
      direction: 'payout',
      type: 'expert_payout_request',
      amountEur: 0,
      status: emailDeliveryOk ? 'succeeded' : 'failed',
      reference: `${transactionReference}-email`,
      provider: 'smtp',
      metadata: {
        invoiceId,
        adminEmail,
        expertEmail,
        emailDeliveryError,
      },
    });

    return {
      claimedPlayers,
      claimedUsd,
      message: emailDeliveryOk
        ? `Billing details submitted. Invoice ${invoiceId} email sent to admin (${adminEmail}) and expert (${expertEmail}). You will get your money in 3 days.`
        : `Billing details saved with invoice ${invoiceId}, but email delivery failed: ${emailDeliveryError}`,
    };
  }

  async setScouterDecision(id: string, decision: 'approved' | 'cancelled'): Promise<{ workflow: PlayerWorkflow }> {
    const player = await this.ensurePlayer(id);
    const current = this.normalizeWorkflow((player as any).adminWorkflow);
    const workflow = await this.savePlayerWorkflow(id, {
      ...current,
      scouterDecision: decision,
    });
    return { workflow };
  }

  async updatePreContract(
    id: string,
    dto: {
      fixedPrice?: number;
      status?: 'none' | 'draft' | 'approved' | 'cancelled';
      clubName?: string;
      clubOfficialName?: string;
      startDate?: string;
      endDate?: string;
      currency?: string;
      salaryPeriod?: 'monthly' | 'weekly';
      fixedBaseSalary?: number;
      signingOnFee?: number;
      marketValue?: number;
      bonusPerAppearance?: number;
      bonusGoalOrCleanSheet?: number;
      bonusTeamTrophy?: number;
      releaseClauseAmount?: number;
      terminationForCauseText?: string;
      scouterIntermediaryId?: string;
      markPlatformFeePaid?: boolean;
      cardNumber?: string;
      expMonth?: number;
      expYear?: number;
      cvc?: string;
      scouterSignNow?: boolean;
      scouterSignatureImageBase64?: string;
      scouterSignatureImageContentType?: string;
      scouterSignatureImageFileName?: string;
    },
    actorUserId = '',
  ): Promise<{ workflow: PlayerWorkflow; signatureClauseAmount: number }> {
    const player = await this.ensurePlayer(id);
    const current = this.normalizeWorkflow((player as any).adminWorkflow);

    const nextFixedPrice = dto.fixedPrice !== undefined ? Math.max(0, Number(dto.fixedPrice) || 0) : current.fixedPrice;
    const fixedPriceChanged = Math.abs(nextFixedPrice - current.fixedPrice) > 0.0001;
    const nextStatus = dto.status ?? current.preContractStatus;
    if ((nextStatus === 'approved' || dto.markPlatformFeePaid === true) && current.verificationStatus !== 'verified') {
      throw new BadRequestException('Expert verification must be approved before contract signing/payment');
    }
    const nextDraft: PlayerWorkflow['contractDraft'] = {
      ...current.contractDraft,
      ...(dto.clubName !== undefined ? { clubName: String(dto.clubName || '').trim() } : {}),
      ...(dto.clubOfficialName !== undefined ? { clubOfficialName: String(dto.clubOfficialName || '').trim() } : {}),
      ...(dto.startDate !== undefined ? { startDate: String(dto.startDate || '') } : {}),
      ...(dto.endDate !== undefined ? { endDate: String(dto.endDate || '') } : {}),
      ...(dto.currency !== undefined ? { currency: String(dto.currency || 'EUR').toUpperCase() } : {}),
      ...(dto.salaryPeriod !== undefined
        ? { salaryPeriod: (dto.salaryPeriod === 'weekly' ? 'weekly' : 'monthly') as 'monthly' | 'weekly' }
        : {}),
      ...(dto.fixedBaseSalary !== undefined ? { fixedBaseSalary: Math.max(0, Number(dto.fixedBaseSalary) || 0) } : {}),
      ...(dto.signingOnFee !== undefined ? { signingOnFee: Math.max(0, Number(dto.signingOnFee) || 0) } : {}),
      ...(dto.marketValue !== undefined ? { marketValue: Math.max(0, Number(dto.marketValue) || 0) } : {}),
      ...(dto.bonusPerAppearance !== undefined ? { bonusPerAppearance: Math.max(0, Number(dto.bonusPerAppearance) || 0) } : {}),
      ...(dto.bonusGoalOrCleanSheet !== undefined ? { bonusGoalOrCleanSheet: Math.max(0, Number(dto.bonusGoalOrCleanSheet) || 0) } : {}),
      ...(dto.bonusTeamTrophy !== undefined ? { bonusTeamTrophy: Math.max(0, Number(dto.bonusTeamTrophy) || 0) } : {}),
      ...(dto.releaseClauseAmount !== undefined ? { releaseClauseAmount: Math.max(0, Number(dto.releaseClauseAmount) || 0) } : {}),
      ...(dto.terminationForCauseText !== undefined ? { terminationForCauseText: String(dto.terminationForCauseText || '') } : {}),
      ...(dto.scouterIntermediaryId !== undefined ? { scouterIntermediaryId: String(dto.scouterIntermediaryId || '') } : {}),
    };
    if (!nextDraft.scouterIntermediaryId && actorUserId) {
      nextDraft.scouterIntermediaryId = actorUserId;
    }

    let actorName = '';
    if (actorUserId) {
      const actor: any = await this.userModel.findById(actorUserId).select('displayName email').lean();
      if (actor) actorName = String(actor.displayName || actor.email || '');
    }
    const scouterSignedNow = dto.scouterSignNow === true
      ? true
      : dto.scouterSignNow === false
        ? false
        : (nextStatus === 'approved' ? true : current.scouterSignedContract);
    const scouterSignedAt = scouterSignedNow
      ? (current.scouterSignedAt || new Date().toISOString())
      : null;
    const nextScouterSignatureImageBase64 = dto.scouterSignatureImageBase64 !== undefined
      ? String(dto.scouterSignatureImageBase64 || '').trim()
      : current.scouterSignatureImageBase64;
    const nextScouterSignatureImageContentType = dto.scouterSignatureImageContentType !== undefined
      ? String(dto.scouterSignatureImageContentType || '').trim().toLowerCase()
      : current.scouterSignatureImageContentType;
    const nextScouterSignatureImageFileName = dto.scouterSignatureImageFileName !== undefined
      ? String(dto.scouterSignatureImageFileName || '').trim()
      : current.scouterSignatureImageFileName;

    if (scouterSignedNow) {
      const isImage = nextScouterSignatureImageContentType.startsWith('image/');
      if (!nextScouterSignatureImageBase64 || !isImage) {
        throw new BadRequestException('Scouter handwritten signature image is required before contract approval');
      }
    }

    let scouterPlatformFeePaid = current.scouterPlatformFeePaid;
    let scouterPlatformFeePaidAt = current.scouterPlatformFeePaidAt;
    if (nextStatus !== 'approved') {
      scouterPlatformFeePaid = false;
      scouterPlatformFeePaidAt = null;
    } else {
      if (fixedPriceChanged) {
        scouterPlatformFeePaid = false;
        scouterPlatformFeePaidAt = null;
      }
      if (dto.markPlatformFeePaid === true) {
        if (nextFixedPrice <= 0) {
          throw new BadRequestException('Fixed contract price is required before paying platform fee');
        }
        const cardNumber = String(dto.cardNumber || '').replace(/\s/g, '');
        const expMonth = Number(dto.expMonth) || 0;
        const expYear = Number(dto.expYear) || 0;
        const cvc = String(dto.cvc || '').trim();
        if (cardNumber.length < 13 || expMonth < 1 || expMonth > 12 || expYear < 2024 || cvc.length < 3) {
          throw new BadRequestException('Valid Stripe-style card details are required to pay platform fee');
        }
        scouterPlatformFeePaid = true;
        scouterPlatformFeePaidAt = new Date().toISOString();
      }
    }

    const workflow = await this.savePlayerWorkflow(id, {
      ...current,
      fixedPrice: nextFixedPrice,
      preContractStatus: nextStatus,
      contractDraft: nextDraft,
      scouterSignedContract: scouterSignedNow,
      scouterSignedAt,
      scouterSignatureName: scouterSignedNow ? (actorName || current.scouterSignatureName) : current.scouterSignatureName,
      scouterSignatureImageBase64: nextScouterSignatureImageBase64,
      scouterSignatureImageContentType: nextScouterSignatureImageContentType,
      scouterSignatureImageFileName: nextScouterSignatureImageFileName,
      contractSignedByPlayer: nextStatus === 'approved' ? current.contractSignedByPlayer : false,
      contractSignedAt: nextStatus === 'approved' ? current.contractSignedAt : null,
      playerSignatureImageBase64: nextStatus === 'approved' ? current.playerSignatureImageBase64 : '',
      playerSignatureImageContentType: nextStatus === 'approved' ? current.playerSignatureImageContentType : '',
      playerSignatureImageFileName: nextStatus === 'approved' ? current.playerSignatureImageFileName : '',
      scouterPlatformFeePaid,
      scouterPlatformFeePaidAt,
      onlineSessionCompleted: nextStatus === 'approved' ? current.onlineSessionCompleted : false,
      onlineSessionCompletedAt: nextStatus === 'approved' ? current.onlineSessionCompletedAt : null,
    });

    if (nextStatus === 'approved') {
      await this.notifModel.create({
        userId: String(id),
        type: 'contract_signature_required',
        titleEN: 'Contract ready for your signature',
        titleFR: 'Contrat pret pour votre signature',
        bodyEN: 'The scouter finalized your contract draft. Open your workflow and sign online.',
        bodyFR: 'Le scouter a finalise votre contrat. Ouvrez votre workflow et signez en ligne.',
        data: {
          fixedPrice: nextFixedPrice,
          platformFeePercent: 3,
          expertVerificationFeeUsd: 30,
          contractDraft: nextDraft,
        },
        read: false,
      });
    }

    return {
      workflow,
      signatureClauseAmount: Math.round(nextFixedPrice * 0.03 * 100) / 100,
    };
  }

  async getPlayerWorkflowForPlayer(playerId: string): Promise<{ workflow: PlayerWorkflow; signatureClauseAmount: number }> {
    const player = await this.ensurePlayer(playerId);
    const workflow = this.normalizeWorkflow((player as any).adminWorkflow);
    return {
      workflow,
      signatureClauseAmount: Math.round(workflow.fixedPrice * 0.03 * 100) / 100,
    };
  }

  async signPlayerPreContract(
    playerId: string,
    payload?: {
      signatureImageBase64?: string;
      signatureImageContentType?: string;
      signatureImageFileName?: string;
    },
  ): Promise<{ workflow: PlayerWorkflow; signatureClauseAmount: number }> {
    const player = await this.ensurePlayer(playerId);
    const current = this.normalizeWorkflow((player as any).adminWorkflow);

    if (current.preContractStatus !== 'approved') {
      throw new BadRequestException('Pre-contract must be approved before player signature');
    }

    const playerSignatureImageBase64 = String(payload?.signatureImageBase64 || '').trim();
    const playerSignatureImageContentType = String(payload?.signatureImageContentType || '').trim().toLowerCase();
    const playerSignatureImageFileName = String(payload?.signatureImageFileName || '').trim();
    if (!playerSignatureImageBase64 || !playerSignatureImageContentType.startsWith('image/')) {
      throw new BadRequestException('Player handwritten signature image is required');
    }

    const nowIso = new Date().toISOString();
    const workflow = await this.savePlayerWorkflow(playerId, {
      ...current,
      contractSignedByPlayer: true,
      contractSignedAt: nowIso,
      playerSignatureImageBase64,
      playerSignatureImageContentType,
      playerSignatureImageFileName,
    });

    const scouterUserId = String(current.contractDraft?.scouterIntermediaryId || '').trim();
    if (scouterUserId && scouterUserId !== String(playerId)) {
      await this.notifModel.create({
        userId: scouterUserId,
        type: 'contract_player_signed',
        titleEN: 'Player signed the contract',
        titleFR: 'Le joueur a signe le contrat',
        bodyEN: 'The player completed their online signature. You can review and export the final contract PDF.',
        bodyFR: 'Le joueur a complete sa signature en ligne. Vous pouvez verifier et exporter le PDF final du contrat.',
        data: {
          playerId,
          fixedPrice: workflow.fixedPrice,
          platformFeePercent: 3,
          contractSignedAt: workflow.contractSignedAt,
        },
        read: false,
      });
    }

    return {
      workflow,
      signatureClauseAmount: Math.round(workflow.fixedPrice * 0.03 * 100) / 100,
    };
  }

  async completePlayerOnlineSession(playerId: string): Promise<{ workflow: PlayerWorkflow; signatureClauseAmount: number }> {
    const player = await this.ensurePlayer(playerId);
    const current = this.normalizeWorkflow((player as any).adminWorkflow);

    if (current.preContractStatus !== 'approved') {
      throw new BadRequestException('Pre-contract must be approved before online session completion');
    }
    if (!current.contractSignedByPlayer) {
      throw new BadRequestException('Player must sign the pre-contract before completing session');
    }

    const nowIso = new Date().toISOString();
    const workflow = await this.savePlayerWorkflow(playerId, {
      ...current,
      onlineSessionCompleted: true,
      onlineSessionCompletedAt: nowIso,
    });

    return {
      workflow,
      signatureClauseAmount: Math.round(workflow.fixedPrice * 0.03 * 100) / 100,
    };
  }

  // ── Scouters (admin) ─────────────────────────────────────────────────────

  async listScouters(query: AdminUserQueryDto): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(query.limit) || 20));
    const skip = (page - 1) * limit;

    const filter: Record<string, any> = { role: 'scouter' };
    if ((query as any).subscriptionTier) filter.subscriptionTier = (query as any).subscriptionTier;
    if (query.search) {
      const re = { $regex: query.search, $options: 'i' };
      filter.$or = [{ email: re }, { displayName: re }];
    }

    const [scouters, total] = await Promise.all([
      this.userModel
        .find(filter)
        .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      this.userModel.countDocuments(filter),
    ]);

    const scouterIds = (scouters as any[]).map((s: any) => String(s._id));
    const reportCounts = await this.reportModel.aggregate([
      { $match: { scouterId: { $in: scouterIds } } },
      { $group: { _id: '$scouterId', count: { $sum: 1 } } },
    ]);
    const reportMap: Record<string, number> = {};
    for (const r of reportCounts) reportMap[String(r._id)] = r.count;

    const now = new Date();
    const data = (scouters as any[]).map((s: any) => ({
      ...s,
      reportCount: reportMap[String(s._id)] ?? 0,
      isExpired: s.subscriptionExpiresAt ? new Date(s.subscriptionExpiresAt) < now : false,
      expiresInDays: s.subscriptionExpiresAt
        ? Math.ceil((new Date(s.subscriptionExpiresAt).getTime() - now.getTime()) / 86400000)
        : null,
    }));

    return { data, total, page, limit };
  }

  async getScouterDetail(id: string): Promise<any> {
    const scouter = await this.userModel
      .findById(id)
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!scouter || (scouter as any).role !== 'scouter') throw new NotFoundException('Scouter not found');

    const reports = await this.reportModel.find({ scouterId: String(id) }).sort({ createdAt: -1 }).lean();

    // Enrich reports with player names
    const playerIds = [...new Set((reports as any[]).map((r: any) => r.playerId))];
    const players = playerIds.length
      ? await this.userModel.find({ _id: { $in: playerIds } }).select('_id displayName email').lean()
      : [];
    const playerMap: Record<string, string> = {};
    for (const p of players as any[]) playerMap[String(p._id)] = p.displayName || p.email;

    const enrichedReports = (reports as any[]).map((r: any) => ({
      ...r,
      playerDisplayName: playerMap[String(r.playerId)] ?? 'Unknown',
    }));

    const now = new Date();
    const isExpired = (scouter as any).subscriptionExpiresAt
      ? new Date((scouter as any).subscriptionExpiresAt) < now
      : false;

    return { scouter, reports: enrichedReports, isExpired };
  }

  // ── Subscription management ───────────────────────────────────────────────

  async updateSubscription(id: string, dto: UpdateSubscriptionDto): Promise<any> {
    const update: Record<string, any> = {};
    if (dto.tier !== undefined) update.subscriptionTier = dto.tier;
    if (dto.expiresAt !== undefined) update.subscriptionExpiresAt = dto.expiresAt ? new Date(dto.expiresAt) : null;

    const user = await this.userModel
      .findByIdAndUpdate(id, update, { new: true })
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  // ── Analytics overview ────────────────────────────────────────────────────

  async getAdminAnalytics(): Promise<any> {
    const now = new Date();
    const thirtyDaysFromNow = new Date(now.getTime() + 30 * 86400000);

    const [
      activeSubscriptions,
      expiringSoon,
      bannedUsers,
      totalReports,
      topScouters,
      topPlayers,
      revenueByTier,
    ] = await Promise.all([
      this.userModel.countDocuments({ subscriptionTier: { $ne: null }, subscriptionExpiresAt: { $gt: now } }),
      this.userModel.countDocuments({
        subscriptionTier: { $ne: null },
        subscriptionExpiresAt: { $gt: now, $lte: thirtyDaysFromNow },
      }),
      this.userModel.countDocuments({ isBanned: true }),
      this.reportModel.countDocuments(),
      // Top 5 scouters by report count
      this.reportModel.aggregate([
        { $group: { _id: '$scouterId', reportCount: { $sum: 1 } } },
        { $sort: { reportCount: -1 } },
        { $limit: 5 },
      ]),
      // Top 5 players by report count (most scouted)
      this.reportModel.aggregate([
        { $group: { _id: '$playerId', reportCount: { $sum: 1 } } },
        { $sort: { reportCount: -1 } },
        { $limit: 5 },
      ]),
      // Revenue breakdown by tier
      this.userModel.aggregate([
        { $match: { subscriptionTier: { $ne: null } } },
        { $group: { _id: '$subscriptionTier', count: { $sum: 1 } } },
      ]),
    ]);

    // Resolve display names for top scouters
    const scouterIds = topScouters.map((s: any) => s._id);
    const scouterDocs = scouterIds.length
      ? await this.userModel.find({ _id: { $in: scouterIds } }).select('_id displayName email').lean()
      : [];
    const scouterNameMap: Record<string, string> = {};
    for (const s of scouterDocs as any[]) scouterNameMap[String(s._id)] = s.displayName || s.email;

    // Resolve display names for top players
    const playerIds = topPlayers.map((p: any) => p._id);
    const playerDocs = playerIds.length
      ? await this.userModel.find({ _id: { $in: playerIds } }).select('_id displayName email position').lean()
      : [];
    const playerNameMap: Record<string, any> = {};
    for (const p of playerDocs as any[]) playerNameMap[String(p._id)] = p;

    const revenueMap: Record<string, number> = { basic: 0, premium: 0, elite: 0 };
    const pricingMap: Record<string, number> = { basic: 1000, premium: 5000, elite: 10000 };
    for (const r of revenueByTier) if (r._id) revenueMap[r._id] = r.count;

    const revenueTotal = Object.entries(revenueMap).reduce(
      (sum, [tier, count]) => sum + (pricingMap[tier] ?? 0) * count, 0
    );

    return {
      activeSubscriptions,
      expiringSoon,
      bannedUsers,
      totalReports,
      revenueByTier: revenueMap,
      revenueTotal,
      topScouters: topScouters.map((s: any) => ({
        _id: s._id,
        displayName: scouterNameMap[String(s._id)] ?? 'Unknown',
        reportCount: s.reportCount,
      })),
      topPlayers: topPlayers.map((p: any) => ({
        _id: p._id,
        displayName: playerNameMap[String(p._id)]?.displayName || playerNameMap[String(p._id)]?.email || 'Unknown',
        position: playerNameMap[String(p._id)]?.position || '—',
        reportCount: p.reportCount,
      })),
    };
  }

  // ── Reports ──────────────────────────────────────────────────────────────

  async listAllReports(page = 1, limit = 20): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const p = Math.max(1, page);
    const l = Math.min(100, Math.max(1, limit));
    const skip = (p - 1) * l;

    const [rawReports, total] = await Promise.all([
      this.reportModel.find().sort({ createdAt: -1 }).skip(skip).limit(l).lean(),
      this.reportModel.countDocuments(),
    ]);

    const userIds = [...new Set(
      rawReports.flatMap((r: any) => [String(r.scouterId), String(r.playerId)]).filter(Boolean),
    )];

    const users = userIds.length
      ? await this.userModel.find({ _id: { $in: userIds } }).select('_id displayName email').lean()
      : [];

    const userMap: Record<string, { displayName?: string; email?: string }> = {};
    for (const u of users as any[]) {
      userMap[String(u._id)] = { displayName: u.displayName, email: u.email };
    }

    const data = rawReports.map((r: any) => {
      const scouter = userMap[String(r.scouterId)];
      const player = userMap[String(r.playerId)];
      return {
        ...r,
        scouterDisplayName: scouter?.displayName || scouter?.email || String(r.scouterId),
        playerDisplayName: player?.displayName || player?.email || String(r.playerId),
      };
    });

    return { data, total, page: p, limit: l };
  }

  // ── Notifications ──────────────────────────────────────────────────────

  async broadcastNotification(dto: BroadcastNotificationDto): Promise<{ sent: number }> {
    const users = await this.userModel.find({}).select('_id').lean();
    if (!users.length) return { sent: 0 };

    const docs = users.map((u: any) => ({
      userId: String(u._id),
      type: 'admin_broadcast',
      titleEN: dto.titleEN,
      titleFR: dto.titleFR,
      bodyEN: dto.bodyEN || '',
      bodyFR: dto.bodyFR || '',
      data: {},
      read: false,
    }));

    await this.notifModel.insertMany(docs);
    return { sent: docs.length };
  }

  /** Admin triggers: notify an expert that their latest invoice is ready to download */
  async notifyExpertInvoiceReady(expertId: string): Promise<{ sent: boolean; invoiceId: string; amountEur: number }> {
    const expert = await this.userModel
      .findById(expertId)
      .select('role expertPayoutInvoices displayName email')
      .lean();

    if (!expert || (expert as any).role !== 'expert') {
      throw new NotFoundException('Expert not found');
    }

    const invoicesRaw = Array.isArray((expert as any).expertPayoutInvoices)
      ? ((expert as any).expertPayoutInvoices as Array<Record<string, unknown>>)
      : [];

    if (invoicesRaw.length === 0) {
      throw new BadRequestException('This expert has no invoices yet. They must submit billing details first.');
    }

    // Sort by requestedAt descending, notify about the latest invoice
    const sorted = [...invoicesRaw].sort((a, b) => {
      return new Date(String(b.requestedAt)).getTime() - new Date(String(a.requestedAt)).getTime();
    });
    const latest = sorted[0];
    const invoiceId = String(latest.invoiceId || '');
    const amountEur = Number(latest.amountEur) || 0;

    await this.notifModel.create({
      userId: String(expertId),
      type: 'invoice_ready',
      titleEN: '🧾 Your Invoice is Ready',
      titleFR: '🧾 Votre facture est prête',
      bodyEN: `Invoice ${invoiceId} (EUR ${amountEur.toFixed(2)}) is ready. Open Billing & Invoices to download your PDF.`,
      bodyFR: `La facture ${invoiceId} (EUR ${amountEur.toFixed(2)}) est prête. Ouvrez Facturation & Factures pour télécharger votre PDF.`,
      data: { invoiceId, amountEur },
      read: false,
    });

    return { sent: true, invoiceId, amountEur };
  }
}
