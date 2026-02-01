"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PlayersModule = void 0;
const common_1 = require("@nestjs/common");
const favorites_module_1 = require("../favorites/favorites.module");
const users_module_1 = require("../users/users.module");
const videos_module_1 = require("../videos/videos.module");
const players_controller_1 = require("./players.controller");
const players_service_1 = require("./players.service");
let PlayersModule = class PlayersModule {
};
exports.PlayersModule = PlayersModule;
exports.PlayersModule = PlayersModule = __decorate([
    (0, common_1.Module)({
        imports: [users_module_1.UsersModule, videos_module_1.VideosModule, favorites_module_1.FavoritesModule],
        controllers: [players_controller_1.PlayersController],
        providers: [players_service_1.PlayersService],
    })
], PlayersModule);
