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
exports.FavoritesService = void 0;
const common_1 = require("@nestjs/common");
const mongoose_1 = require("@nestjs/mongoose");
const mongoose_2 = require("mongoose");
const favorites_schema_1 = require("./favorites.schema");
let FavoritesService = class FavoritesService {
    constructor(favModel) {
        this.favModel = favModel;
    }
    async add(scouterId, playerId) {
        if (!playerId)
            throw new common_1.BadRequestException('playerId is required');
        try {
            const created = await this.favModel.create({ scouterId, playerId });
            return created.toObject();
        }
        catch {
            // ignore duplicate
            const existing = await this.favModel.findOne({ scouterId, playerId }).lean();
            if (!existing)
                throw new common_1.BadRequestException('Failed to add favorite');
            return existing;
        }
    }
    async remove(scouterId, playerId) {
        await this.favModel.deleteOne({ scouterId, playerId });
        return { ok: true };
    }
    async list(scouterId) {
        return this.favModel.find({ scouterId }).sort({ createdAt: -1 }).lean();
    }
    async isFavorite(scouterId, playerId) {
        const f = await this.favModel.findOne({ scouterId, playerId }).lean();
        return Boolean(f);
    }
};
exports.FavoritesService = FavoritesService;
exports.FavoritesService = FavoritesService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, mongoose_1.InjectModel)(favorites_schema_1.Favorite.name)),
    __metadata("design:paramtypes", [mongoose_2.Model])
], FavoritesService);
