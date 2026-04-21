import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';

import { CHALLENGE_DEFS, ChallengesService } from '../challenges/challenges.service';
import { FavoritesService } from '../favorites/favorites.service';
import { UsersService } from '../users/users.service';
import { VideosService } from '../videos/videos.service';

@Injectable()
export class PlayersService {
  constructor(
    private readonly users: UsersService,
    private readonly videos: VideosService,
    private readonly favorites: FavoritesService,
    private readonly challenges: ChallengesService,
  ) {}

  private extractLastMetrics(lastAnalysis: any): any {
    if (!lastAnalysis) return null;
    const metrics = lastAnalysis.metrics || lastAnalysis;
    if (!metrics || typeof metrics !== 'object') return null;
    return {
      distanceMeters: Number.isFinite(metrics.distanceMeters) ? metrics.distanceMeters : null,
      avgSpeedKmh: Number.isFinite(metrics.avgSpeedKmh) ? metrics.avgSpeedKmh : null,
      maxSpeedKmh: Number.isFinite(metrics.maxSpeedKmh) ? metrics.maxSpeedKmh : null,
      sprintCount: Number.isFinite(metrics.sprintCount) ? metrics.sprintCount : null,
      accelPeaks: Array.isArray(metrics.accelPeaks) ? metrics.accelPeaks : [],
    };
  }

  async list(scouterId: string) {
    const players = await this.users.listPlayers();
    const favs = scouterId ? await this.favorites.list(scouterId) : [];
    const favSet = new Set(favs.map((f) => f.playerId));

    return players.map((p: any) => ({
      ...p,
      isFavorite: favSet.has(p._id.toString()),
    }));
  }

  async getPlayer(playerId: string, scouterId: string) {
    const p: any = await this.users.getById(playerId);
    if (p.role !== 'player') throw new NotFoundException('Player not found');
    const isFavorite = scouterId ? await this.favorites.isFavorite(scouterId, playerId) : false;
    const { passwordHash, ...safe } = p;

    // Filter private data based on scouter's subscription tier and expiry
    if (scouterId) {
      const scouter: any = await this.users.getById(scouterId);
      const now = new Date();
      const isExpired = scouter.subscriptionExpiresAt && scouter.subscriptionExpiresAt < now;
      
      // If subscription expired, treat as no subscription (hide all data)
      if (isExpired) {
        throw new BadRequestException('Subscription expired. Please renew to access player data.');
      }
      
      const tier = scouter.subscriptionTier || 'basic';

      // Basic tier: hide private data (dateOfBirth, height, position, nation)
      if (tier === 'basic') {
        delete safe.dateOfBirth;
        delete safe.height;
        delete safe.position;
        delete safe.nation;
      }
      // Premium and elite: full access to all player data
    }

    return { ...safe, isFavorite };
  }

  async getPlayerVideos(playerId: string) {
    return this.videos.listByOwner(playerId);
  }

  async getPlayerPortrait(playerId: string) {
    const p: any = await this.users.getById(playerId);
    if (p.role !== 'player') throw new NotFoundException('Player not found');
    return this.users.getPortraitForUserOrMigrateFromFile(playerId);
  }

  async getPlayerChallenges(playerId: string) {
    const p: any = await this.users.getById(playerId);
    if (p.role !== 'player') throw new NotFoundException('Player not found');

    const rows = await this.challenges.getAll(playerId);
    return CHALLENGE_DEFS.map((def) => {
      const row = rows.find((r) => r.challengeKey === def.key);
      const progress = row?.progress ?? 0;
      const completed = row?.completed ?? false;
      return {
        key: def.key,
        icon: def.icon,
        title: def.titleEN,
        titleEN: def.titleEN,
        titleFR: def.titleFR,
        description: def.descEN,
        descEN: def.descEN,
        descFR: def.descFR,
        progress,
        target: def.target,
        completed,
        completedAt: row?.completedAt ?? null,
        status: completed ? 'completed' : (progress > 0 ? 'in_progress' : 'pending'),
      };
    });
  }

  async dashboard(playerId: string, scouterId: string) {
    const player = await this.getPlayer(playerId, scouterId);
    const videos: any[] = await this.videos.listByOwner(playerId);
    const videosWithMetrics = videos.map((v) => ({
      ...v,
      lastMetrics: this.extractLastMetrics((v as any).lastAnalysis),
    }));
    return {
      player,
      videos: videosWithMetrics,
    };
  }

  /** Aggregate metrics across all analyzed videos for a player. */
  private aggregatePlayerMetrics(videos: any[]): any {
    const analyzed = videos
      .map((v) => this.extractLastMetrics(v.lastAnalysis))
      .filter((m) => m !== null);

    if (analyzed.length === 0) {
      return {
        totalDistanceMeters: 0,
        avgSpeedKmh: 0,
        maxSpeedKmh: 0,
        totalSprints: 0,
        totalAccelPeaks: 0,
        analyzedVideos: 0,
        totalVideos: videos.length,
      };
    }

    let totalDist = 0;
    let sumAvg = 0;
    let maxSpeed = 0;
    let totalSprints = 0;
    let totalAccel = 0;

    for (const m of analyzed) {
      totalDist += m.distanceMeters ?? 0;
      sumAvg += m.avgSpeedKmh ?? 0;
      if ((m.maxSpeedKmh ?? 0) > maxSpeed) maxSpeed = m.maxSpeedKmh;
      totalSprints += m.sprintCount ?? 0;
      totalAccel += Array.isArray(m.accelPeaks) ? m.accelPeaks.length : 0;
    }

    return {
      totalDistanceMeters: Math.round(totalDist * 100) / 100,
      avgSpeedKmh: Math.round((sumAvg / analyzed.length) * 100) / 100,
      maxSpeedKmh: Math.round(maxSpeed * 100) / 100,
      totalSprints,
      totalAccelPeaks: totalAccel,
      analyzedVideos: analyzed.length,
      totalVideos: videos.length,
    };
  }

  /** Compare two players side by side. */
  async compare(playerIdA: string, playerIdB: string, scouterId: string) {
    const [playerA, playerB] = await Promise.all([
      this.getPlayer(playerIdA, scouterId),
      this.getPlayer(playerIdB, scouterId),
    ]);

    const [videosA, videosB] = await Promise.all([
      this.videos.listByOwner(playerIdA),
      this.videos.listByOwner(playerIdB),
    ]);

    const metricsA = this.aggregatePlayerMetrics(videosA as any[]);
    const metricsB = this.aggregatePlayerMetrics(videosB as any[]);

    // Build per-video metrics lists
    const videoMetricsA = (videosA as any[]).map((v) => ({
      videoId: v._id?.toString(),
      originalName: v.originalName,
      metrics: this.extractLastMetrics(v.lastAnalysis),
    })).filter((v) => v.metrics !== null);

    const videoMetricsB = (videosB as any[]).map((v) => ({
      videoId: v._id?.toString(),
      originalName: v.originalName,
      metrics: this.extractLastMetrics(v.lastAnalysis),
    })).filter((v) => v.metrics !== null);

    return {
      playerA: { info: playerA, aggregated: metricsA, videos: videoMetricsA },
      playerB: { info: playerB, aggregated: metricsB, videos: videoMetricsB },
    };
  }
}
