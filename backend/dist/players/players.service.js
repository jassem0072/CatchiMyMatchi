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
Object.defineProperty(exports, "__esModule", { value: true });
exports.PlayersService = void 0;
const common_1 = require("@nestjs/common");
const favorites_service_1 = require("../favorites/favorites.service");
const users_service_1 = require("../users/users.service");
const videos_service_1 = require("../videos/videos.service");
let PlayersService = class PlayersService {
    constructor(users, videos, favorites) {
        this.users = users;
        this.videos = videos;
        this.favorites = favorites;
    }
    extractLastMetrics(lastAnalysis) {
        if (!lastAnalysis)
            return null;
        const metrics = lastAnalysis.metrics || lastAnalysis;
        if (!metrics || typeof metrics !== 'object')
            return null;
        return {
            distanceMeters: Number.isFinite(metrics.distanceMeters) ? metrics.distanceMeters : null,
            avgSpeedKmh: Number.isFinite(metrics.avgSpeedKmh) ? metrics.avgSpeedKmh : null,
            maxSpeedKmh: Number.isFinite(metrics.maxSpeedKmh) ? metrics.maxSpeedKmh : null,
            sprintCount: Number.isFinite(metrics.sprintCount) ? metrics.sprintCount : null,
            accelPeaks: Array.isArray(metrics.accelPeaks) ? metrics.accelPeaks : [],
        };
    }
    async list(scouterId) {
        const players = await this.users.listPlayers();
        const favs = scouterId ? await this.favorites.list(scouterId) : [];
        const favSet = new Set(favs.map((f) => f.playerId));
        return players.map((p) => ({
            ...p,
            isFavorite: favSet.has(p._id.toString()),
        }));
    }
    async getPlayer(playerId, scouterId) {
        const p = await this.users.getById(playerId);
        if (p.role !== 'player')
            throw new common_1.NotFoundException('Player not found');
        const isFavorite = scouterId ? await this.favorites.isFavorite(scouterId, playerId) : false;
        const { passwordHash, ...safe } = p;
        return { ...safe, isFavorite };
    }
    async getPlayerVideos(playerId) {
        return this.videos.listByOwner(playerId);
    }
    async getPlayerPortrait(playerId) {
        const p = await this.users.getById(playerId);
        if (p.role !== 'player')
            throw new common_1.NotFoundException('Player not found');
        return this.users.getPortraitForUserOrMigrateFromFile(playerId);
    }
    async dashboard(playerId, scouterId) {
        const player = await this.getPlayer(playerId, scouterId);
        const videos = await this.videos.listByOwner(playerId);
        const videosWithMetrics = videos.map((v) => ({
            ...v,
            lastMetrics: this.extractLastMetrics(v.lastAnalysis),
        }));
        return {
            player,
            videos: videosWithMetrics,
        };
    }
};
exports.PlayersService = PlayersService;
exports.PlayersService = PlayersService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [users_service_1.UsersService,
        videos_service_1.VideosService,
        favorites_service_1.FavoritesService])
], PlayersService);
