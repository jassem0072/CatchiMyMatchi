import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomUUID } from 'node:crypto';

import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Param,
  Post,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import type { Request, Response } from 'express';

import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { RequestUser } from '../auth/request-user';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';

import { ChallengesService, CHALLENGE_DEFS } from '../challenges/challenges.service';
import { FavoritesService } from '../favorites/favorites.service';
import { NotificationsService } from '../notifications/notifications.service';
import { UsersService } from '../users/users.service';

import { AnalyzeOptions, VideosService } from './videos.service';

function uploadsRoot(): string {
  const uploadDir = process.env.UPLOAD_DIR || 'uploads';
  return path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
}

@ApiTags('videos')
@Controller('videos')
export class VideosController {
  constructor(
    private readonly videosService: VideosService,
    private readonly challengesSvc: ChallengesService,
    private readonly notifSvc: NotificationsService,
    private readonly favSvc: FavoritesService,
    private readonly usersSvc: UsersService,
  ) {}

  @Post()
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req: Request, _file: Express.Multer.File, cb: (error: Error | null, destination: string) => void) => {
          const root = uploadsRoot();
          fs.mkdirSync(root, { recursive: true });
          cb(null, root);
        },
        filename: (_req: Request, file: Express.Multer.File, cb: (error: Error | null, filename: string) => void) => {
          const ext = path.extname(file.originalname || '') || '.mp4';
          cb(null, `${randomUUID()}${ext}`);
        },
      }),
      limits: {
        fileSize: 1024 * 1024 * 1024, // 1GB
      },
    }),
  )
  async upload(@UploadedFile() file: Express.Multer.File) {
    return this.videosService.createFromUpload(file, null);
  }

  @Get()
  async list() {
    return this.videosService.list();
  }

  @Get(':id')
  async get(@Param('id') id: string) {
    return this.videosService.getById(id);
  }

  @Post(':id/analyze')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('scouter', 'player')
  async analyze(@Param('id') id: string, @Body() body: AnalyzeOptions, @Req() req: { user?: RequestUser }) {
    const user = req.user!;
    let isTaggedPlayer = false;
    if (user.role === 'player') {
      const v = await this.videosService.getById(id);
      const isOwner = v.ownerId && v.ownerId === user.sub;
      const isTagged = Array.isArray(v.taggedPlayers) && v.taggedPlayers.includes(user.sub);
      if (!isOwner && !isTagged) throw new ForbiddenException('Not allowed to analyze this video');
      isTaggedPlayer = !isOwner && isTagged;
    }

    if (isTaggedPlayer) {
      // Tagged player: store analysis per-player without overwriting owner's
      const result = await this.videosService.analyzeVideoForPlayer(id, user.sub, body);
      this.checkChallengesAfterAnalysis(user.sub, result).catch(() => {});
      return result;
    }

    const result = await this.videosService.analyzeVideo(id, body);

    // ── Auto-check challenges (fire-and-forget) ──
    this.checkChallengesAfterAnalysis(user.sub, result).catch(() => {});

    return result;
  }

  /** Check & update challenges after a successful analysis */
  private async checkChallengesAfterAnalysis(
    userId: string,
    analysisResult: Record<string, unknown>,
  ) {
    const userDoc = await this.usersSvc.getById(userId);
    const playerName = userDoc?.displayName || 'A player';

    // Helper to notify scouters following this player
    const notifyFollowers = async (chalTitleEN: string, chalTitleFR: string) => {
      try {
        // Get all scouters who favorited this player
        // We need to query favorites where playerId = userId
        const favs = await this.favSvc.listByPlayer(userId);
        for (const f of favs) {
          await this.notifSvc.notifyScouterPlayerChallenge(
            f.scouterId,
            playerName,
            chalTitleEN,
            chalTitleFR,
          );
        }
      } catch {
        // ignore
      }
    };

    // 1. Analyst challenge — increment by 1 per analysis
    const analystRes = await this.challengesSvc.incrementProgress(userId, 'analyst', 1);
    if (analystRes.newlyCompleted) {
      const def = CHALLENGE_DEFS.find((d) => d.key === 'analyst')!;
      await this.notifSvc.notifyChallengeCompleted(userId, def.titleEN, def.titleFR);
      await notifyFollowers(def.titleEN, def.titleFR);
    }

    // 2. Speed Demon — check max speed in analysis
    try {
      const positions = (analysisResult as any)?.positions;
      if (Array.isArray(positions) && positions.length > 1) {
        let maxKmh = 0;
        for (const p of positions) {
          const speed = p.speed_kmh ?? p.speedKmh ?? 0;
          if (speed > maxKmh) maxKmh = speed;
        }
        if (maxKmh >= 30) {
          const speedRes = await this.challengesSvc.setProgress(userId, 'speed_demon', 1);
          if (speedRes.newlyCompleted) {
            const def = CHALLENGE_DEFS.find((d) => d.key === 'speed_demon')!;
            await this.notifSvc.notifyChallengeCompleted(userId, def.titleEN, def.titleFR);
            await notifyFollowers(def.titleEN, def.titleFR);
          }
        }
      }
    } catch {
      // ignore
    }

    // 3. Marathon Runner — accumulate total distance
    try {
      const summary = (analysisResult as any)?.summary;
      const totalDistKm = (summary?.total_distance_m ?? 0) / 1000;
      if (totalDistKm > 0) {
        // We need cumulative, so get current progress and add
        const marathonRes = await this.challengesSvc.incrementProgress(
          userId,
          'marathon_runner',
          Math.round(totalDistKm),
        );
        if (marathonRes.newlyCompleted) {
          const def = CHALLENGE_DEFS.find((d) => d.key === 'marathon_runner')!;
          await this.notifSvc.notifyChallengeCompleted(userId, def.titleEN, def.titleFR);
          await notifyFollowers(def.titleEN, def.titleFR);
        }
      }
    } catch {
      // ignore
    }

    // 4. Sprint King — count sprints (speed > 24 km/h segments)
    try {
      const positions = (analysisResult as any)?.positions;
      if (Array.isArray(positions)) {
        let sprintCount = 0;
        let inSprint = false;
        for (const p of positions) {
          const speed = p.speed_kmh ?? p.speedKmh ?? 0;
          if (speed >= 24 && !inSprint) {
            sprintCount++;
            inSprint = true;
          } else if (speed < 20) {
            inSprint = false;
          }
        }
        if (sprintCount > 0) {
          const sprintRes = await this.challengesSvc.incrementProgress(userId, 'sprint_king', sprintCount);
          if (sprintRes.newlyCompleted) {
            const def = CHALLENGE_DEFS.find((d) => d.key === 'sprint_king')!;
            await this.notifSvc.notifyChallengeCompleted(userId, def.titleEN, def.titleFR);
            await notifyFollowers(def.titleEN, def.titleFR);
          }
        }
      }
    } catch {
      // ignore
    }

    // 5. Notify analysis ready
    try {
      const video = await this.videosService.getById('');
    } catch {
      // ignore – we already returned the result
    }
    await this.notifSvc.notifyAnalysisReady(userId, 'Video Analysis');
  }

  @Post(':id/montage')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('scouter', 'player')
  async generateMontage(
    @Param('id') id: string,
    @Req() req: { user?: RequestUser },
    @Body() body: { playerId?: string },
  ) {
    const user = req.user!;
    const playerId = user.role === 'player' ? user.sub : (body?.playerId ?? undefined);
    return this.videosService.generateMontage(id, playerId);
  }

  @Get(':id/montage/stream')
  async streamMontage(@Param('id') id: string, @Req() req: Request, @Res() res: Response) {
    const video = await this.videosService.getById(id);
    if (!video.montageRelativePath) {
      res.status(404).json({ message: 'No montage generated yet for this video.' });
      return;
    }

    const filePath = video.montageRelativePath;
    if (!fs.existsSync(filePath)) {
      res.status(404).json({ message: 'Montage file not found on disk.' });
      return;
    }

    const stat = fs.statSync(filePath);
    const fileSize = stat.size;
    const range = req.headers.range;

    res.setHeader('Content-Type', 'video/mp4');
    res.setHeader('Accept-Ranges', 'bytes');
    res.setHeader('Content-Disposition', `inline; filename="${video.montageFilename || 'montage.mp4'}"`);

    if (!range) {
      res.setHeader('Content-Length', fileSize);
      fs.createReadStream(filePath).pipe(res);
      return;
    }

    const match = /^bytes=(\d+)-(\d*)$/.exec(range);
    if (!match) { res.status(416).end(); return; }

    const start = Number(match[1]);
    const end = match[2] ? Number(match[2]) : fileSize - 1;

    if (Number.isNaN(start) || Number.isNaN(end) || start >= fileSize || end >= fileSize) {
      res.status(416).end();
      return;
    }

    const chunkSize = end - start + 1;
    res.status(206);
    res.setHeader('Content-Range', `bytes ${start}-${end}/${fileSize}`);
    res.setHeader('Content-Length', chunkSize);
    fs.createReadStream(filePath, { start, end }).pipe(res);
  }

  @Get(':id/stream')
  async stream(@Param('id') id: string, @Req() req: Request, @Res() res: Response) {
    const video = await this.videosService.getById(id);
    const filePath = await this.videosService.getAbsolutePath(video);

    const stat = fs.statSync(filePath);
    const fileSize = stat.size;
    const range = req.headers.range;

    res.setHeader('Content-Type', video.mimeType || 'video/mp4');
    res.setHeader('Accept-Ranges', 'bytes');

    if (!range) {
      res.setHeader('Content-Length', fileSize);
      fs.createReadStream(filePath).pipe(res);
      return;
    }

    const match = /^bytes=(\d+)-(\d*)$/.exec(range);
    if (!match) {
      res.status(416).end();
      return;
    }

    const start = Number(match[1]);
    const end = match[2] ? Number(match[2]) : fileSize - 1;

    if (Number.isNaN(start) || Number.isNaN(end) || start >= fileSize || end >= fileSize) {
      res.status(416).end();
      return;
    }

    const chunkSize = end - start + 1;
    res.status(206);
    res.setHeader('Content-Range', `bytes ${start}-${end}/${fileSize}`);
    res.setHeader('Content-Length', chunkSize);

    fs.createReadStream(filePath, { start, end }).pipe(res);
  }
}
