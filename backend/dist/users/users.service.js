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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.UsersService = void 0;
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const common_1 = require("@nestjs/common");
const mongoose_1 = require("@nestjs/mongoose");
const mongoose_2 = require("mongoose");
const users_schema_1 = require("./users.schema");
let UsersService = class UsersService {
    constructor(userModel) {
        this.userModel = userModel;
    }
    async createUser(input) {
        const email = (input.email || '').trim().toLowerCase();
        if (!email)
            throw new common_1.BadRequestException('email is required');
        if (!input.password || input.password.length < 6)
            throw new common_1.BadRequestException('password must be at least 6 chars');
        const existing = await this.userModel.findOne({ email }).lean();
        if (existing)
            throw new common_1.BadRequestException('email already in use');
        const passwordHash = await bcryptjs_1.default.hash(input.password, 10);
        const created = await this.userModel.create({
            email,
            passwordHash,
            role: input.role,
            displayName: input.displayName || '',
            position: input.position || '',
            nation: input.nation || '',
        });
        return created;
    }
    async findByEmail(email) {
        const e = (email || '').trim().toLowerCase();
        if (!e)
            return null;
        return this.userModel.findOne({ email: e });
    }
    async getById(id) {
        const u = await this.userModel.findById(id).lean();
        if (!u)
            throw new common_1.NotFoundException('User not found');
        return u;
    }
    async listPlayers() {
        return this.userModel
            .find({ role: 'player' })
            .select('-passwordHash')
            .sort({ createdAt: -1 })
            .lean();
    }
};
exports.UsersService = UsersService;
exports.UsersService = UsersService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, mongoose_1.InjectModel)(users_schema_1.User.name)),
    __metadata("design:paramtypes", [mongoose_2.Model])
], UsersService);
