import { Injectable, NotFoundException } from '@nestjs/common';

import { FavoritesService } from '../favorites/favorites.service';
import { UsersService } from '../users/users.service';
import { VideosService } from '../videos/videos.service';

@Injectable()
export class PlayersService {
  constructor(
    private readonly users: UsersService,
    private readonly videos: VideosService,
    private readonly favorites: FavoritesService,
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
}
