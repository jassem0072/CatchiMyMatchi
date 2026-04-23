import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

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
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { diskStorage } from "multer";
import type { Request, Response } from "express";

import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";

import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import type { RequestUser } from "../auth/request-user";
import { Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";

import {
  ChallengesService,
  CHALLENGE_DEFS,
} from "../challenges/challenges.service";
import { FavoritesService } from "../favorites/favorites.service";
import { NotificationsService } from "../notifications/notifications.service";
import { UsersService } from "../users/users.service";

import { AnalyzeOptions, VideosService } from "./videos.service";

function uploadsRoot(): string {
  const uploadDir = process.env.UPLOAD_DIR || "uploads";
  return path.isAbsolute(uploadDir)
    ? uploadDir
    : path.join(process.cwd(), uploadDir);
}

@ApiTags("videos")
@Controller("videos")
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
    FileInterceptor("file", {
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
          const ext = path.extname(file.originalname || "") || ".mp4";
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

  @Get(":id/detect")
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles("scouter", "player")
  async detectVideoType(@Param("id") id: string) {
    return this.videosService.detectVideoType(id);
  }

  @Get(":id")
  async get(@Param("id") id: string) {
    return this.videosService.getById(id);
  }

  @Post(":id/analyze")
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles("scouter", "player")
  async analyze(
    @Param("id") id: string,
    @Body() body: AnalyzeOptions,
    @Req() req: { user?: RequestUser },
  ) {
    const user = req.user!;
    let isTaggedPlayer = false;
    if (user.role === "player") {
      const v = await this.videosService.getById(id);
      const isOwner = v.ownerId && v.ownerId === user.sub;
      const isTagged =
        Array.isArray(v.taggedPlayers) && v.taggedPlayers.includes(user.sub);
      if (!isOwner && !isTagged)
        throw new ForbiddenException("Not allowed to analyze this video");
      isTaggedPlayer = !isOwner && isTagged;
    }

    if (isTaggedPlayer) {
      // Tagged player: store analysis per-player without overwriting owner's
      const result = await this.videosService.analyzeVideoForPlayer(
        id,
        user.sub,
        body,
      );
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
    const playerName = userDoc?.displayName || "A player";

    // Helper to notify scouters following this player
    const notifyFollowers = async (
      chalTitleEN: string,
      chalTitleFR: string,
    ) => {
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
    const analystRes = await this.challengesSvc.incrementProgress(
      userId,
      "analyst",
      1,
    );
    if (analystRes.newlyCompleted) {
      const def = CHALLENGE_DEFS.find((d) => d.key === "analyst")!;
      await this.notifSvc.notifyChallengeCompleted(
        userId,
        def.titleEN,
        def.titleFR,
      );
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
          const speedRes = await this.challengesSvc.setProgress(
            userId,
            "speed_demon",
            1,
          );
          if (speedRes.newlyCompleted) {
            const def = CHALLENGE_DEFS.find((d) => d.key === "speed_demon")!;
            await this.notifSvc.notifyChallengeCompleted(
              userId,
              def.titleEN,
              def.titleFR,
            );
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
          "marathon_runner",
          Math.round(totalDistKm),
        );
        if (marathonRes.newlyCompleted) {
          const def = CHALLENGE_DEFS.find((d) => d.key === "marathon_runner")!;
          await this.notifSvc.notifyChallengeCompleted(
            userId,
            def.titleEN,
            def.titleFR,
          );
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
          const sprintRes = await this.challengesSvc.incrementProgress(
            userId,
            "sprint_king",
            sprintCount,
          );
          if (sprintRes.newlyCompleted) {
            const def = CHALLENGE_DEFS.find((d) => d.key === "sprint_king")!;
            await this.notifSvc.notifyChallengeCompleted(
              userId,
              def.titleEN,
              def.titleFR,
            );
            await notifyFollowers(def.titleEN, def.titleFR);
          }
        }
      }
    } catch {
      // ignore
    }

    // 5. Notify analysis ready
    try {
      const video = await this.videosService.getById("");
    } catch {
      // ignore – we already returned the result
    }
    await this.notifSvc.notifyAnalysisReady(userId, "Video Analysis");
  }

  @Post(":id/montage")
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles("scouter", "player")
  async generateMontage(
    @Param("id") id: string,
    @Req() req: { user?: RequestUser },
    @Body() body: { playerId?: string; forceRegenerate?: boolean },
  ) {
    const user = req.user!;
    const playerId =
      user.role === "player" ? user.sub : (body?.playerId ?? undefined);
    return this.videosService.generateMontage(id, playerId, {
      forceRegenerate: body?.forceRegenerate,
    });
  }

  @Get(":id/montage/status")
  async montageStatus(@Param("id") id: string) {
    return this.videosService.getMontageStatus(id);
  }

  @Get(":id/montage/stream")
  async streamMontage(
    @Param("id") id: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const info = await this.videosService.getMontageStreamInfo(id);
    if (!info.filePath) {
      res
        .status(404)
        .json({ message: "No montage generated yet for this video." });
      return;
    }

    const filePath = info.filePath;
    if (!fs.existsSync(filePath)) {
      res.status(404).json({ message: "Montage file not found on disk." });
      return;
    }

    const stat = fs.statSync(filePath);
    const fileSize = stat.size;
    const range = req.headers.range;

    res.setHeader("Content-Type", "video/mp4");
    res.setHeader("Accept-Ranges", "bytes");
    res.setHeader(
      "Content-Disposition",
      `inline; filename="${info.filename || "montage.mp4"}"`,
    );

    if (!range) {
      res.setHeader("Content-Length", fileSize);
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

    if (
      Number.isNaN(start) ||
      Number.isNaN(end) ||
      start >= fileSize ||
      end >= fileSize
    ) {
      res.status(416).end();
      return;
    }

    const chunkSize = end - start + 1;
    res.status(206);
    res.setHeader("Content-Range", `bytes ${start}-${end}/${fileSize}`);
    res.setHeader("Content-Length", chunkSize);
    fs.createReadStream(filePath, { start, end }).pipe(res);
  }

  @Get(":id/positions")
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles("player", "scouter")
  async getPositions(
    @Param("id") id: string,
    @Req() req: { user?: RequestUser },
  ): Promise<{
    positions: any[];
    count: number;
    playerName: string;
    selectionT: number | null;
    selectionNcx: number | null;
    selectionNcy: number | null;
  }> {
    const video = await this.videosService.getById(id);
    const requesterId = req.user?.sub;
    const requesterRole = req.user?.role;
    const ownerId = (video as any).ownerId as string | undefined;
    const playerAnalyses = (video as any).playerAnalyses as
      | Record<string, any>
      | undefined;

    // Resolve a deterministic analysis source key.
    // Priority: requester's own analysis -> owner's base analysis -> best fallback.
    let sourceKey: string | null = null;
    let positions: any[] = [];

    const requesterOwnPositions =
      requesterId &&
      playerAnalyses &&
      Array.isArray((playerAnalyses[requesterId] as any)?.positions) &&
      (playerAnalyses[requesterId] as any).positions.length > 0
        ? ((playerAnalyses[requesterId] as any).positions as any[])
        : null;

    // For player users, never fall back to another player's analysis.
    // This guarantees the overlay follows only the analyzed player.
    if (requesterRole === "player") {
      if (requesterOwnPositions) {
        positions = requesterOwnPositions;
        sourceKey = requesterId ?? null;
      } else if (
        requesterId &&
        ownerId === requesterId &&
        Array.isArray((video as any).lastAnalysis?.positions) &&
        (video as any).lastAnalysis.positions.length > 0
      ) {
        positions = (video as any).lastAnalysis.positions;
        sourceKey = requesterId;
      }
    } else {
      if (requesterOwnPositions) {
        positions = requesterOwnPositions;
        sourceKey = requesterId ?? null;
      } else if (
        Array.isArray((video as any).lastAnalysis?.positions) &&
        (video as any).lastAnalysis.positions.length > 0
      ) {
        positions = (video as any).lastAnalysis.positions;
        sourceKey = ownerId ?? null;
      } else if (playerAnalyses && typeof playerAnalyses === "object") {
        let best: any[] = [];
        let bestKey: string | null = null;
        for (const [key, entry] of Object.entries(playerAnalyses)) {
          const pts = (entry as any)?.positions;
          if (Array.isArray(pts) && pts.length > best.length) {
            best = pts;
            bestKey = key;
          }
        }
        positions = best;
        sourceKey = bestKey;
      }
    }

    if (positions.length === 0) {
      return {
        positions: [],
        count: 0,
        playerName: "",
        selectionT: null,
        selectionNcx: null,
        selectionNcy: null,
      };
    }

    // 3. Sort by t (time in seconds) ascending
    positions = [...positions].sort((a, b) => (a.t ?? 0) - (b.t ?? 0));

    // 4. Resolve player display name from selected analysis source
    let playerName = "";
    try {
      const userDoc = await this.usersSvc.getById(sourceKey || ownerId || "");
      playerName = userDoc?.displayName || userDoc?.email || "";
    } catch {
      // ignore — playerName stays ""
    }

    // 5. Return selection point from playerSelections so the overlay shows
    //    at the exact moment + position the player was identified.
    let selectionT: number | null = null;
    let selectionNcx: number | null = null;
    let selectionNcy: number | null = null;
    try {
      const playerSelections = (video as any).playerSelections as
        | Record<string, { frameTime: number; normX: number; normY: number }>
        | undefined;
      if (playerSelections) {
        const sel =
          (sourceKey ? playerSelections[sourceKey] : undefined) ||
          (requesterId ? playerSelections[requesterId] : undefined) ||
          (ownerId ? playerSelections[ownerId] : undefined) ||
          Object.values(playerSelections)[0];
        if (sel) {
          selectionT = typeof sel.frameTime === "number" ? sel.frameTime : null;
          selectionNcx = typeof sel.normX === "number" ? sel.normX : null;
          selectionNcy = typeof sel.normY === "number" ? sel.normY : null;
        }
      }
    } catch {
      // ignore — selection stays null
    }

    // 6. Enforce a single target track in playback to avoid cross-player jumps.
    // Prefer the track closest to the selection moment (and selection position
    // when available). Fall back to the most frequent trackId.
    if (Array.isArray(positions) && positions.length > 1) {
      const trackPoints = positions.filter((p) => {
        const tid = (p as any)?.trackId;
        return typeof tid === "number" && Number.isFinite(tid);
      });

      if (trackPoints.length > 0) {
        let lockedTrackId: number | null = null;

        if (selectionT !== null) {
          const near = trackPoints.filter((p) => {
            const t = typeof (p as any)?.t === "number" ? (p as any).t : null;
            return t !== null && Math.abs(t - selectionT) <= 3.0;
          });

          const pickFrom = near.length > 0 ? near : trackPoints;
          if (selectionNcx !== null && selectionNcy !== null) {
            let bestScore = Number.POSITIVE_INFINITY;
            for (const p of pickFrom) {
              const t =
                typeof (p as any)?.t === "number"
                  ? Math.abs((p as any).t - selectionT)
                  : 99;
              const x =
                typeof (p as any)?.ncx === "number"
                  ? (p as any).ncx
                  : typeof (p as any)?.cx === "number"
                    ? (p as any).cx / 1920
                    : 0.5;
              const y =
                typeof (p as any)?.ncy === "number"
                  ? (p as any).ncy
                  : typeof (p as any)?.cy === "number"
                    ? (p as any).cy / 1080
                    : 0.5;
              const d2 = (x - selectionNcx) ** 2 + (y - selectionNcy) ** 2;
              const score = d2 * 4 + t;
              if (score < bestScore) {
                bestScore = score;
                lockedTrackId = (p as any).trackId as number;
              }
            }
          } else {
            let bestDt = Number.POSITIVE_INFINITY;
            for (const p of pickFrom) {
              const t = typeof (p as any)?.t === "number" ? (p as any).t : null;
              if (t === null) continue;
              const dt = Math.abs(t - selectionT);
              if (dt < bestDt) {
                bestDt = dt;
                lockedTrackId = (p as any).trackId as number;
              }
            }
          }
        }

        if (lockedTrackId === null) {
          const counts = new Map<number, number>();
          for (const p of trackPoints) {
            const tid = (p as any).trackId as number;
            counts.set(tid, (counts.get(tid) ?? 0) + 1);
          }
          let bestTid: number | null = null;
          let bestCount = -1;
          for (const [tid, c] of counts.entries()) {
            if (c > bestCount) {
              bestCount = c;
              bestTid = tid;
            }
          }
          lockedTrackId = bestTid;
        }

        if (lockedTrackId !== null) {
          const filtered = positions.filter((p) => {
            const tid = (p as any)?.trackId;
            return typeof tid === "number" && tid === lockedTrackId;
          });
          if (filtered.length > 0) {
            positions = filtered;
          }
        }
      }
    }

    return {
      positions,
      count: positions.length,
      playerName,
      selectionT,
      selectionNcx,
      selectionNcy,
    };
  }

  @Get(":id/stream")
  async stream(
    @Param("id") id: string,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const video = await this.videosService.getById(id);
    const filePath = await this.videosService.getAbsolutePath(video);

    const stat = fs.statSync(filePath);
    const fileSize = stat.size;
    const range = req.headers.range;

    res.setHeader("Content-Type", video.mimeType || "video/mp4");
    res.setHeader("Accept-Ranges", "bytes");

    if (!range) {
      res.setHeader("Content-Length", fileSize);
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

    if (
      Number.isNaN(start) ||
      Number.isNaN(end) ||
      start >= fileSize ||
      end >= fileSize
    ) {
      res.status(416).end();
      return;
    }

    const chunkSize = end - start + 1;
    res.status(206);
    res.setHeader("Content-Range", `bytes ${start}-${end}/${fileSize}`);
    res.setHeader("Content-Length", chunkSize);

    fs.createReadStream(filePath, { start, end }).pipe(res);
  }
}
