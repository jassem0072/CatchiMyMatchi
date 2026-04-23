import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomUUID } from 'node:crypto';

import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage, memoryStorage } from 'multer';
import type { Request, Response } from 'express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import type { RequestUser } from '../auth/request-user';
import { AuthService } from '../auth/auth.service';
import { ChallengesService, CHALLENGE_DEFS } from '../challenges/challenges.service';
import { NotificationsService } from '../notifications/notifications.service';
import { TeamsService } from '../teams/teams.service';
import { UsersService } from '../users/users.service';
import { VideosService } from '../videos/videos.service';
import { AdminService } from '../admin/admin.service';

import Stripe from 'stripe';

// Scouter tier pricing in cents (€)
const TIER_PRICES: Record<string, { cents: number; label: string; tier: 'basic' | 'premium' | 'elite' }> = {
  basic:   { cents: 19900, label: 'Basic — €199', tier: 'basic' },
  premium: { cents: 29900, label: 'Premium — €299', tier: 'premium' },
  elite:   { cents: 44900, label: 'Elite — €449', tier: 'elite' },
};

function getStripe(): Stripe {
  const key = process.env.STRIPE_SECRET_KEY || '';
  if (!key) throw new BadRequestException('Stripe is not configured');
  return new Stripe(key, { apiVersion: '2025-04-30.basil' as any });
}

function normalizePortraitContentType(file: Express.Multer.File): string {
  const ct = (file.mimetype || '').toLowerCase();
  if (ct.startsWith('image/')) return ct;

  const ext = path.extname(file.originalname || '').toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.webp') return 'image/webp';
  if (ext === '.gif') return 'image/gif';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  return 'image/jpeg';
}

function normalizePlayerDocumentContentType(file: Express.Multer.File): string {
  const ct = (file.mimetype || '').toLowerCase();
  if (ct.startsWith('image/')) return ct;
  if (ct === 'application/pdf') return 'application/pdf';
  if (ct === 'application/msword') return 'application/msword';
  if (ct === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }

  const ext = path.extname(file.originalname || '').toLowerCase();
  if (ext === '.pdf') return 'application/pdf';
  if (ext === '.doc') return 'application/msword';
  if (ext === '.docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  if (ext === '.png') return 'image/png';
  if (ext === '.webp') return 'image/webp';
  if (ext === '.gif') return 'image/gif';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  throw new BadRequestException('Unsupported file type. Allowed: image, pdf, doc, docx');
}

function uploadsRoot(): string {
  const uploadDir = process.env.UPLOAD_DIR || 'uploads';
  return path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
}

@ApiTags('me')
@ApiBearerAuth()
@Controller('me')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('player', 'scouter')
export class MeController {
  constructor(
    private readonly videos: VideosService,
    private readonly users: UsersService,
    private readonly auth: AuthService,
    private readonly challengesSvc: ChallengesService,
    private readonly notifSvc: NotificationsService,
    private readonly teamsSvc: TeamsService,
    private readonly adminSvc: AdminService,
  ) {}

  /** GET /me — return authenticated user profile */
  @Get()
  async getProfile(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    const db = await this.users.getById(me.sub);
    const { passwordHash, ...safe } = db as any;
    return safe;
  }

  /** PATCH /me — update displayName, position, nation, dateOfBirth, height */
  @Patch()
  async updateProfile(
    @Req() req: { user?: RequestUser },
    @Body() body: { displayName?: string; position?: string; nation?: string; dateOfBirth?: string; height?: number; playerIdNumber?: string },
  ) {
    const me = req.user!;
    return this.users.updateProfile(me.sub, {
      displayName: body.displayName,
      position: body.position,
      nation: body.nation,
      dateOfBirth: body.dateOfBirth,
      height: body.height,
      playerIdNumber: body.playerIdNumber,
    });
  }

  /** GET /me/player-workflow — returns the player's pre-contract workflow status */
  @Get('player-workflow')
  @Roles('player')
  async getPlayerWorkflow(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    return this.adminSvc.getPlayerWorkflowForPlayer(me.sub);
  }

  /** POST /me/player-workflow/sign-pre-contract — player signs approved pre-contract online */
  @Post('player-workflow/sign-pre-contract')
  @Roles('player')
  async signPreContract(
    @Req() req: { user?: RequestUser },
    @Body()
    body: {
      signatureImageBase64?: string;
      signatureImageContentType?: string;
      signatureImageFileName?: string;
    },
  ) {
    const me = req.user!;
    return this.adminSvc.signPlayerPreContract(me.sub, body);
  }

  /** POST /me/player-workflow/complete-online-session — marks online player session as completed */
  @Post('player-workflow/complete-online-session')
  @Roles('player')
  async completeOnlineSession(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    return this.adminSvc.completePlayerOnlineSession(me.sub);
  }

  /** POST /me/communication-quiz — persist latest communication quiz summary */
  @Post('communication-quiz')
  async saveCommunicationQuiz(
    @Req() req: { user?: RequestUser },
    @Body()
    body: {
      language?: string;
      score?: number;
      totalQuestions?: number;
      readinessBand?: string;
      communicationStyle?: string;
      captaincySummary?: string;
    },
  ) {
    const me = req.user!;
    if (!body.language || body.score === undefined || body.totalQuestions === undefined || !body.readinessBand) {
      throw new BadRequestException('language, score, totalQuestions and readinessBand are required');
    }

    return this.users.updateCommunicationQuiz(me.sub, {
      language: body.language,
      score: body.score,
      totalQuestions: body.totalQuestions,
      readinessBand: body.readinessBand,
      communicationStyle: body.communicationStyle,
      captaincySummary: body.captaincySummary,
    });
  }

  /** PATCH /me/password — change password */
  @Patch('password')
  async changePassword(
    @Req() req: { user?: RequestUser },
    @Body() body: { currentPassword?: string; newPassword?: string },
  ) {
    const me = req.user!;
    if (!body.currentPassword || !body.newPassword) {
      throw new BadRequestException('currentPassword and newPassword are required');
    }
    await this.users.changePassword(me.sub, body.currentPassword, body.newPassword);
    return { ok: true };
  }

  /** DELETE /me — delete the authenticated user account */
  @Delete()
  async deleteAccount(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    // Delete user's videos first
    await this.videos.deleteByOwner(me.sub);
    await this.users.deleteUser(me.sub);
    return { ok: true };
  }

  @Post('checkout')
  async createCheckoutSession(
    @Req() req: { user?: RequestUser },
    @Body() body: { returnUrl?: string; tier?: string },
  ) {
    const me = req.user!;
    const user = await this.users.getById(me.sub);

    const tierKey = body.tier || 'basic';
    const tierInfo = TIER_PRICES[tierKey];
    if (!tierInfo) throw new BadRequestException('Invalid tier. Choose basic, premium, or elite.');

    const stripe = getStripe();
    const appBaseUrl = (body?.returnUrl || process.env.APP_BASE_URL || 'http://localhost:3000').replace(/\/$/, '');

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: ['card'],
      line_items: [
        {
          price_data: {
            currency: 'eur',
            unit_amount: tierInfo.cents,
            product_data: {
              name: `ScoutAI — Scouter ${tierInfo.tier.charAt(0).toUpperCase() + tierInfo.tier.slice(1)}`,
              description: tierInfo.label,
            },
          },
          quantity: 1,
        },
      ],
      metadata: {
        userId: me.sub,
        purpose: 'scouter_upgrade',
        tier: tierKey,
      },
      success_url: `${appBaseUrl}/#/profile?upgrade=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${appBaseUrl}/#/profile?upgrade=cancelled`,
    });

    await this.adminSvc.recordBillingTransaction({
      userId: me.sub,
      direction: 'payment',
      type: 'subscription_payment',
      amountEur: tierInfo.cents / 100,
      status: 'requested',
      reference: session.id,
      provider: 'stripe_checkout',
      metadata: {
        tier: tierKey,
        checkoutSessionId: session.id,
      },
    });

    return {
      checkoutUrl: session.url,
      sessionId: session.id,
    };
  }

  @Post('pay-and-upgrade')
  async payAndUpgrade(
    @Req() _req: { user?: RequestUser },
    @Body() _body: Record<string, unknown>,
  ) {
    throw new BadRequestException(
      'Manual card entry is disabled for PCI-DSS compliance. Use /me/checkout and then /me/upgrade-status.',
    );
  }

  @Get('upgrade-status')
  async upgradeStatus(
    @Req() req: { user?: RequestUser },
    @Query('sessionId') sessionId: string,
  ) {
    const me = req.user!;
    if (!sessionId) throw new BadRequestException('sessionId is required');

    const stripe = getStripe();
    const session = await stripe.checkout.sessions.retrieve(sessionId);

    if (session.metadata?.userId !== me.sub) {
      throw new BadRequestException('Session does not belong to this user');
    }

    if (session.payment_status !== 'paid') {
      return { status: 'pending', paymentStatus: session.payment_status };
    }

    // Payment confirmed — upgrade user
    const paymentIntentId = typeof session.payment_intent === 'string'
      ? session.payment_intent
      : (session.payment_intent as any)?.id || sessionId;

    const tier = (session.metadata?.tier as 'basic' | 'premium' | 'elite') || 'basic';

    // Delete user's videos only when transitioning from player to scouter
    const currentUser = await this.users.getById(me.sub);
    const deletedVideos = currentUser.role === 'player' ? await this.videos.deleteByOwner(me.sub) : [];

    const updated = await this.users.upgradeToScouter(me.sub, paymentIntentId, tier);

    const amountEur = Number(session.amount_total || 0) > 0
      ? Number(session.amount_total || 0) / 100
      : (TIER_PRICES[tier]?.cents || 0) / 100;

    await this.adminSvc.recordBillingTransaction({
      userId: me.sub,
      direction: 'payment',
      type: 'subscription_payment',
      amountEur,
      status: 'succeeded',
      reference: paymentIntentId,
      provider: 'stripe_checkout',
      metadata: {
        sessionId,
        tier,
        paymentStatus: session.payment_status,
      },
    });

    const token = this.auth.issueTokenPublic(updated._id.toString(), updated.email, updated.role);
    return { status: 'upgraded', deletedVideos, ...token };
  }

  @Get('videos')
  async myVideos(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    // Own videos
    const own = (await this.videos.listByOwner(me.sub)).map((v: any) => ({
      ...v,
      isTagged: false,
    }));
    // Videos where I'm tagged
    const tagged = await this.videos.listTaggedFor(me.sub);
    const enriched = await Promise.all(
      tagged.map(async (v: any) => {
        let uploaderName = 'Unknown';
        try {
          const owner = await this.users.getById(v.ownerId);
          uploaderName = (owner as any).displayName || (owner as any).email || 'Unknown';
        } catch {}
        // Inject tagged player's own analysis (if they analyzed themselves)
        const myAnalysis = v.playerAnalyses?.[me.sub] ?? null;
        return {
          ...v,
          lastAnalysis: myAnalysis,
          isTagged: true,
          uploaderName,
        };
      }),
    );
    return [...own, ...enriched];
  }

  /** GET /me/videos/:id — single video with correct analysis for current user */
  @Get('videos/:id')
  async myVideoById(
    @Req() req: { user?: RequestUser },
    @Param('id') videoId: string,
  ) {
    const me = req.user!;
    const v: any = await this.videos.getById(videoId);
    const isOwner = v.ownerId === me.sub;
    const isTagged = Array.isArray(v.taggedPlayers) && v.taggedPlayers.includes(me.sub);
    if (!isOwner && !isTagged) {
      throw new NotFoundException('Video not found');
    }
    if (isTagged && !isOwner) {
      let uploaderName = 'Unknown';
      try {
        const owner = await this.users.getById(v.ownerId);
        uploaderName = (owner as any).displayName || (owner as any).email || 'Unknown';
      } catch {}
      const myAnalysis = v.playerAnalyses?.[me.sub] ?? null;
      return { ...v, lastAnalysis: myAnalysis, isTagged: true, uploaderName };
    }
    return { ...v, isTagged: false };
  }

  /** DELETE /me/videos/:id — owner deletes full video, tagged player deletes own analysis */
  @Delete('videos/:id')
  async deleteMyVideo(
    @Req() req: { user?: RequestUser },
    @Param('id') videoId: string,
  ) {
    const me = req.user!;
    const result = await this.videos.deleteForUser(videoId, me.sub);
    return {
      ok: true,
      ...result,
    };
  }

  @Post('videos')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (
          _req: Request,
          _file: Express.Multer.File,
          cb: (error: Error | null, destination: string) => void,
        ) => {
          const root = uploadsRoot();
          fs.mkdirSync(root, { recursive: true });
          cb(null, root);
        },
        filename: (
          _req: Request,
          file: Express.Multer.File,
          cb: (error: Error | null, filename: string) => void,
        ) => {
          const ext = path.extname(file.originalname || '') || '.mp4';
          cb(null, `${randomUUID()}${ext}`);
        },
      }),
      limits: {
        fileSize: 1024 * 1024 * 1024,
      },
    }),
  )
  async uploadMyVideo(@Req() req: { user?: RequestUser }, @UploadedFile() file: Express.Multer.File) {
    const me = req.user!;
    const result = await this.videos.createFromUpload(file, me.sub);

    // Fire-and-forget: first_upload challenge
    this.challengesSvc.incrementProgress(me.sub, 'first_upload', 1).then(async (r) => {
      if (r.newlyCompleted) {
        const def = CHALLENGE_DEFS.find((d) => d.key === 'first_upload')!;
        await this.notifSvc.notifyChallengeCompleted(me.sub, def.titleEN, def.titleFR);
      }
    }).catch(() => {});

    return result;
  }

  /** PATCH /me/videos/:id/tags — tag teammates & set visibility */
  @Patch('videos/:id/tags')
  async updateVideoTags(
    @Req() req: { user?: RequestUser },
    @Param('id') videoId: string,
    @Body() body: { taggedPlayers?: string[]; taggedTeams?: string[]; visibility?: string },
  ) {
    const me = req.user!;
    const playerTags = new Set<string>(body.taggedPlayers || []);

    // Expand team IDs to member IDs
    for (const teamId of (body.taggedTeams || [])) {
      try {
        const team = await this.teamsSvc.getById(teamId);
        for (const memberId of team.members) {
          if (memberId !== me.sub) playerTags.add(memberId);
        }
      } catch {}
    }

    const tags = Array.from(playerTags);

    // Validate all tagged players are teammates
    for (const playerId of tags) {
      const isMate = await this.teamsSvc.areTeammates(me.sub, playerId);
      if (!isMate) {
        throw new BadRequestException(`Player ${playerId} is not in any of your teams`);
      }
    }

    const updated = await this.videos.updateTagsAndVisibility(
      videoId,
      me.sub,
      tags,
      body.visibility || 'public',
      body.taggedTeams || [],
    );

    // Send notifications to tagged players (fire-and-forget)
    if (tags.length > 0) {
      const uploader = await this.users.getById(me.sub);
      const uploaderName = (uploader as any).displayName || (uploader as any).email || 'Someone';
      const videoName = (updated as any).originalName || 'a video';
      for (const playerId of tags) {
        this.notifSvc.notifyVideoTag(playerId, uploaderName, videoId, videoName).catch(() => {});
      }
    }

    return updated;
  }

  /** PATCH /me/videos/:id/visibility — let owner or tagged player toggle visibility */
  @Patch('videos/:id/visibility')
  async updateVideoVisibility(
    @Req() req: { user?: RequestUser },
    @Param('id') videoId: string,
    @Body() body: { visibility?: string },
  ) {
    const me = req.user!;
    const video = await this.videos.getById(videoId);
    const isOwner = video.ownerId === me.sub;
    const isTagged = Array.isArray(video.taggedPlayers) && video.taggedPlayers.includes(me.sub);
    if (!isOwner && !isTagged) {
      throw new BadRequestException('Not allowed to change visibility on this video');
    }
    const newVis = body.visibility === 'private' ? 'private' : 'public';
    return this.videos.updateVisibility(videoId, newVis);
  }

  @Post('badge')
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
      required: ['file'],
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: {
        fileSize: 10 * 1024 * 1024,
      },
    }),
  )
  async uploadBadge(@Req() req: { user?: RequestUser }, @UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('file is required');
    const me = req.user!;
    if (!file.buffer || file.buffer.length === 0) throw new BadRequestException('file is required');
    const contentType = normalizePortraitContentType(file);
    const updated = await this.users.setBadgeData(me.sub, file.buffer, contentType);
    const { passwordHash, ...safe } = updated as any;
    return safe;
  }

  @Get('badge')
  async getBadge(@Req() req: { user?: RequestUser }, @Res() res: Response) {
    const me = req.user!;
    const badge = await this.users.getBadgeForUser(me.sub);
    if (!badge) return res.status(204).end();
    const data: any = badge.data as any;
    res.setHeader('Content-Type', badge.contentType || 'image/jpeg');
    res.setHeader('Cache-Control', 'no-store');
    return res.send(Buffer.isBuffer(data) ? data : Buffer.from(data));
  }

  @Post('verify-badge')
  async verifyBadge(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    const updated = await this.users.verifyBadge(me.sub);
    const { passwordHash, ...safe } = updated as any;
    return safe;
  }

  @Post('portrait')
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
      required: ['file'],
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: {
        fileSize: 10 * 1024 * 1024,
      },
    }),
  )
  async uploadPortrait(@Req() req: { user?: RequestUser }, @UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('file is required');
    const me = req.user!;
    console.log('[me/portrait] upload start', {
      userId: me.sub,
      originalname: file.originalname,
      mimetype: file.mimetype,
      size: (file as any).size ?? file.buffer?.length ?? 0,
    });
    if (!file.buffer || file.buffer.length === 0) throw new BadRequestException('file is required');
    const contentType = normalizePortraitContentType(file);
    const updated = await this.users.setPortraitData(me.sub, file.buffer, contentType);
    const { passwordHash, ...safe } = updated as any;
    console.log('[me/portrait] upload saved', { userId: me.sub, contentType, bytes: file.buffer.length });
    return safe;
  }

  @Get('portrait')
  async getPortrait(@Req() req: { user?: RequestUser }, @Res() res: Response) {
    const me = req.user!;
    const portrait = await this.users.getPortraitForUserOrMigrateFromFile(me.sub);
    if (!portrait) return res.status(204).end();
    const data: any = portrait.data as any;
    const bytes = Buffer.isBuffer(data)
      ? data.length
      : data instanceof Uint8Array
        ? data.byteLength
        : typeof data?.length === 'number'
          ? data.length
          : typeof data?.length === 'function'
            ? data.length()
            : 0;
    console.log('[me/portrait] get', { userId: me.sub, contentType: portrait.contentType, bytes });
    res.setHeader('Content-Type', portrait.contentType || 'image/jpeg');
    res.setHeader('Cache-Control', 'no-store');
    return res.send(Buffer.isBuffer(data) ? data : Buffer.from(data));
  }

  @Post('player-documents/medical-diploma')
  @Roles('player')
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
      required: ['file'],
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: {
        fileSize: 10 * 1024 * 1024,
      },
    }),
  )
  async uploadMedicalDiploma(@Req() req: { user?: RequestUser }, @UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('file is required');
    const me = req.user!;
    if (!file.buffer || file.buffer.length === 0) throw new BadRequestException('file is required');
    const contentType = normalizePlayerDocumentContentType(file);
    const updated = await this.users.setMedicalDiplomaData(me.sub, file.buffer, contentType, file.originalname || 'medical-diploma');
    const { passwordHash, ...safe } = updated as any;
    return safe;
  }

  @Get('player-documents/medical-diploma')
  @Roles('player')
  async getMedicalDiploma(@Req() req: { user?: RequestUser }, @Res() res: Response) {
    const me = req.user!;
    const doc = await this.users.getMedicalDiplomaForUser(me.sub);
    if (!doc) return res.status(204).end();
    const data: any = doc.data as any;
    res.setHeader('Content-Type', doc.contentType || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(doc.fileName || 'medical-diploma')}"`);
    res.setHeader('Cache-Control', 'no-store');
    return res.send(Buffer.isBuffer(data) ? data : Buffer.from(data));
  }

  @Post('player-documents/bulletin-n3')
  @Roles('player')
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
      required: ['file'],
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: {
        fileSize: 10 * 1024 * 1024,
      },
    }),
  )
  async uploadBulletinN3(@Req() req: { user?: RequestUser }, @UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('file is required');
    const me = req.user!;
    if (!file.buffer || file.buffer.length === 0) throw new BadRequestException('file is required');
    const contentType = normalizePlayerDocumentContentType(file);
    const updated = await this.users.setBulletinN3Data(me.sub, file.buffer, contentType, file.originalname || 'bulletin-n3');
    const { passwordHash, ...safe } = updated as any;
    return safe;
  }

  @Get('player-documents/bulletin-n3')
  @Roles('player')
  async getBulletinN3(@Req() req: { user?: RequestUser }, @Res() res: Response) {
    const me = req.user!;
    const doc = await this.users.getBulletinN3ForUser(me.sub);
    if (!doc) return res.status(204).end();
    const data: any = doc.data as any;
    res.setHeader('Content-Type', doc.contentType || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(doc.fileName || 'bulletin-n3')}"`);
    res.setHeader('Cache-Control', 'no-store');
    return res.send(Buffer.isBuffer(data) ? data : Buffer.from(data));
  }

  @Post('player-documents/player-id')
  @Roles('player')
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
      required: ['file'],
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: {
        fileSize: 10 * 1024 * 1024,
      },
    }),
  )
  async uploadPlayerIdDocument(@Req() req: { user?: RequestUser }, @UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('file is required');
    const me = req.user!;
    if (!file.buffer || file.buffer.length === 0) throw new BadRequestException('file is required');
    const contentType = normalizePlayerDocumentContentType(file);
    const updated = await this.users.setPlayerIdDocumentData(me.sub, file.buffer, contentType, file.originalname || 'player-id');
    const { passwordHash, ...safe } = updated as any;
    return safe;
  }

  @Get('player-documents/player-id')
  @Roles('player')
  async getPlayerIdDocument(@Req() req: { user?: RequestUser }, @Res() res: Response) {
    const me = req.user!;
    const doc = await this.users.getPlayerIdDocumentForUser(me.sub);
    if (!doc) return res.status(204).end();
    const data: any = doc.data as any;
    res.setHeader('Content-Type', doc.contentType || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(doc.fileName || 'player-id')}"`);
    res.setHeader('Cache-Control', 'no-store');
    return res.send(Buffer.isBuffer(data) ? data : Buffer.from(data));
  }
}
