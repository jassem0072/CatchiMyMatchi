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
    @Body() body: { displayName?: string; position?: string; nation?: string; dateOfBirth?: string; height?: number },
  ) {
    const me = req.user!;
    return this.users.updateProfile(me.sub, {
      displayName: body.displayName,
      position: body.position,
      nation: body.nation,
      dateOfBirth: body.dateOfBirth,
      height: body.height,
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

    return {
      checkoutUrl: session.url,
      sessionId: session.id,
    };
  }

  @Post('pay-and-upgrade')
  async payAndUpgrade(
    @Req() req: { user?: RequestUser },
    @Body() body: { cardNumber?: string; expMonth?: number; expYear?: number; cvc?: string; tier?: string },
  ) {
    const me = req.user!;
    const user = await this.users.getById(me.sub);

    if (!body.cardNumber || !body.expMonth || !body.expYear || !body.cvc) {
      throw new BadRequestException('Card details are required');
    }

    const tierKey = body.tier || 'basic';
    const tierInfo = TIER_PRICES[tierKey];
    if (!tierInfo) throw new BadRequestException('Invalid tier. Choose basic, premium, or elite.');

    let paymentId = `dev_${Date.now()}`;

    // If Stripe is configured, process real payment
    const stripeKey = process.env.STRIPE_SECRET_KEY || '';
    if (stripeKey) {
      const stripe = getStripe();
      const cardNum = body.cardNumber.replace(/\s/g, '');

      // Map well-known test card numbers to Stripe test tokens
      // (raw card data APIs require special PCI certification)
      const testCardTokens: Record<string, string> = {
        '4242424242424242': 'tok_visa',
        '4000056655665556': 'tok_visa_debit',
        '5555555555554444': 'tok_mastercard',
        '5200828282828210': 'tok_mastercard_debit',
        '378282246310005':  'tok_amex',
        '6011111111111117': 'tok_discover',
        '3056930009020004': 'tok_diners',
        '3566002020360505': 'tok_jcb',
        '6200000000000005': 'tok_unionpay',
      };

      let paymentMethodId: string;
      const testToken = testCardTokens[cardNum];

      if (testToken) {
        // Use Stripe's pre-built test token
        const pm = await stripe.paymentMethods.create({
          type: 'card',
          card: { token: testToken },
        } as any);
        paymentMethodId = pm.id;
      } else {
        // For real / non-test card numbers, try the Tokens API
        try {
          const token = await stripe.tokens.create({
            card: {
              number: cardNum,
              exp_month: String(body.expMonth),
              exp_year: String(body.expYear),
              cvc: body.cvc,
            },
          } as any);
          const pm = await stripe.paymentMethods.create({
            type: 'card',
            card: { token: token.id },
          });
          paymentMethodId = pm.id;
        } catch (err: any) {
          throw new BadRequestException(
            err?.message || 'Card processing failed. Use a Stripe test card (e.g. 4242 4242 4242 4242).',
          );
        }
      }

      const paymentIntent = await stripe.paymentIntents.create({
        amount: tierInfo.cents,
        currency: 'eur',
        payment_method: paymentMethodId,
        confirm: true,
        automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
        metadata: { userId: me.sub, purpose: 'scouter_upgrade', tier: tierKey },
      });

      if (paymentIntent.status !== 'succeeded') {
        throw new BadRequestException('Payment failed. Please check your card details.');
      }
      paymentId = paymentIntent.id;
    }

    // Delete user's videos only when transitioning from player to scouter
    const deletedVideos = user.role === 'player' ? await this.videos.deleteByOwner(me.sub) : [];

    // Upgrade user
    const updated = await this.users.upgradeToScouter(me.sub, paymentId, tierInfo.tier);
    const token = this.auth.issueTokenPublic(updated._id.toString(), updated.email, updated.role);
    return { status: 'upgraded', deletedVideos, ...token };
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
}
