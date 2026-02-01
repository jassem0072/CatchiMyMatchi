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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ReportsService = void 0;
const common_1 = require("@nestjs/common");
const mongoose_1 = require("@nestjs/mongoose");
const mongoose_2 = require("mongoose");
const videos_service_1 = require("../videos/videos.service");
const reports_schema_1 = require("./reports.schema");
let ReportsService = class ReportsService {
    constructor(reportModel, videos) {
        this.reportModel = reportModel;
        this.videos = videos;
    }
    async create(scouterId, input) {
        if (!input.playerId)
            throw new common_1.BadRequestException('playerId is required');
        let analysisSnapshot = null;
        if (input.videoId) {
            const v = await this.videos.getById(input.videoId);
            if (v && v.ownerId && v.ownerId !== input.playerId) {
                throw new common_1.BadRequestException('videoId does not belong to playerId');
            }
            analysisSnapshot = (v && v.lastAnalysis) || null;
        }
        const created = await this.reportModel.create({
            scouterId,
            playerId: input.playerId,
            videoId: input.videoId || null,
            title: input.title || '',
            notes: input.notes || '',
            analysisSnapshot,
            cardSnapshot: input.cardSnapshot || null,
        });
        return created.toObject();
    }
    async list(scouterId, playerId) {
        const q = { scouterId };
        if (playerId)
            q.playerId = playerId;
        return this.reportModel.find(q).sort({ createdAt: -1 }).lean();
    }
    async get(scouterId, id) {
        const r = await this.reportModel.findOne({ _id: id, scouterId }).lean();
        if (!r)
            throw new common_1.NotFoundException('Report not found');
        return r;
    }
};
exports.ReportsService = ReportsService;
exports.ReportsService = ReportsService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, mongoose_1.InjectModel)(reports_schema_1.Report.name)),
    __metadata("design:paramtypes", [mongoose_2.Model,
        videos_service_1.VideosService])
], ReportsService);
