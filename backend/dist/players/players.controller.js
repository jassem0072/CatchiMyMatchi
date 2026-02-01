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
exports.PlayersController = void 0;
const common_1 = require("@nestjs/common");
const swagger_1 = require("@nestjs/swagger");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const roles_decorator_1 = require("../auth/roles.decorator");
const roles_guard_1 = require("../auth/roles.guard");
const players_service_1 = require("./players.service");
let PlayersController = class PlayersController {
    constructor(players) {
        this.players = players;
    }
    async list(req) {
        const me = req.user;
        return this.players.list(me.sub);
    }
    async get(req, playerId) {
        const me = req.user;
        return this.players.getPlayer(playerId, me.sub);
    }
    async videos(playerId) {
        return this.players.getPlayerVideos(playerId);
    }
    async dashboard(req, playerId) {
        const me = req.user;
        return this.players.dashboard(playerId, me.sub);
    }
};
exports.PlayersController = PlayersController;
__decorate([
    (0, common_1.Get)(),
    __param(0, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], PlayersController.prototype, "list", null);
__decorate([
    (0, common_1.Get)(':playerId'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Param)('playerId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], PlayersController.prototype, "get", null);
__decorate([
    (0, common_1.Get)(':playerId/videos'),
    __param(0, (0, common_1.Param)('playerId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], PlayersController.prototype, "videos", null);
__decorate([
    (0, common_1.Get)(':playerId/dashboard'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Param)('playerId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], PlayersController.prototype, "dashboard", null);
exports.PlayersController = PlayersController = __decorate([
    (0, swagger_1.ApiTags)('players'),
    (0, swagger_1.ApiBearerAuth)(),
    (0, common_1.Controller)('players'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, roles_guard_1.RolesGuard),
    (0, roles_decorator_1.Roles)('scouter'),
    __metadata("design:paramtypes", [players_service_1.PlayersService])
], PlayersController);
