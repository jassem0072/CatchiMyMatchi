"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
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
const fs = __importStar(require("node:fs"));
const path = __importStar(require("node:path"));
const node_crypto_1 = require("node:crypto");
const common_1 = require("@nestjs/common");
const mongoose_1 = require("@nestjs/mongoose");
const mongoose_2 = require("mongoose");
const users_schema_1 = require("./users.schema");
let UsersService = class UsersService {
    constructor(userModel) {
        this.userModel = userModel;
    }
    coerceToBuffer(value) {
        if (!value)
            return null;
        if (Buffer.isBuffer(value))
            return value;
        if (value instanceof Uint8Array)
            return Buffer.from(value);
        if (typeof value === 'object') {
            if (value.type === 'Buffer' && Array.isArray(value.data)) {
                return Buffer.from(value.data);
            }
            const bsontype = value._bsontype;
            if (bsontype === 'Binary' && typeof value.value === 'function') {
                const v = value.value(true);
                if (Buffer.isBuffer(v))
                    return v;
                if (v instanceof Uint8Array)
                    return Buffer.from(v);
                if (Array.isArray(v))
                    return Buffer.from(v);
            }
            const buf = value.buffer;
            if (Buffer.isBuffer(buf))
                return buf;
            if (buf instanceof Uint8Array)
                return Buffer.from(buf);
        }
        try {
            return Buffer.from(value);
        }
        catch {
            return null;
        }
    }
    async findByGoogleSub(googleSub) {
        const sub = (googleSub || '').trim();
        if (!sub)
            return null;
        return this.userModel.findOne({ googleSub: sub });
    }
    async createOrUpdateGoogleUser(input) {
        const email = (input.email || '').trim().toLowerCase();
        const googleSub = (input.googleSub || '').trim();
        if (!email)
            throw new common_1.BadRequestException('email is required');
        if (!googleSub)
            throw new common_1.BadRequestException('googleSub is required');
        const existing = await this.userModel.findOne({ $or: [{ email }, { googleSub }] });
        if (existing) {
            const updated = await this.userModel.findByIdAndUpdate(existing._id, {
                email,
                googleSub,
                ...(input.displayName && input.displayName.trim()
                    ? { displayName: input.displayName.trim() }
                    : {}),
            }, { new: true });
            if (!updated)
                throw new common_1.NotFoundException('User not found');
            return updated;
        }
        if (!input.role)
            throw new common_1.BadRequestException('role is required');
        const passwordHash = await bcryptjs_1.default.hash((0, node_crypto_1.randomUUID)(), 10);
        const created = await this.userModel.create({
            email,
            passwordHash,
            role: input.role,
            displayName: input.displayName || '',
            position: '',
            nation: '',
            googleSub,
        });
        return created;
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
    async setResetPasswordTokenByEmail(email, tokenHash, expiresAt) {
        const u = await this.findByEmail(email);
        if (!u)
            return false;
        u.resetPasswordTokenHash = tokenHash;
        u.resetPasswordExpiresAt = expiresAt;
        await u.save();
        return true;
    }
    async resetPasswordByToken(email, tokenHash, newPassword) {
        const password = newPassword || '';
        if (password.length < 6)
            throw new common_1.BadRequestException('password must be at least 6 chars');
        const u = await this.findByEmail(email);
        if (!u)
            throw new common_1.BadRequestException('Invalid reset token');
        const expected = (u.resetPasswordTokenHash || '').trim();
        const expiresAt = u.resetPasswordExpiresAt ? new Date(u.resetPasswordExpiresAt) : null;
        if (!expected || expected !== tokenHash)
            throw new common_1.BadRequestException('Invalid reset token');
        if (!expiresAt || expiresAt.getTime() < Date.now())
            throw new common_1.BadRequestException('Reset token expired');
        u.passwordHash = await bcryptjs_1.default.hash(password, 10);
        u.resetPasswordTokenHash = '';
        u.resetPasswordExpiresAt = null;
        await u.save();
    }
    async getById(id) {
        const u = await this.userModel
            .findById(id)
            .select('-portraitData -resetPasswordTokenHash -resetPasswordExpiresAt')
            .lean();
        if (!u)
            throw new common_1.NotFoundException('User not found');
        return u;
    }
    async getPortraitForUser(id) {
        const u = await this.userModel
            .findById(id)
            .select('portraitData portraitContentType')
            .lean();
        if (!u)
            throw new common_1.NotFoundException('User not found');
        const data = this.coerceToBuffer(u.portraitData);
        if (!data || data.length === 0)
            return null;
        return {
            data,
            contentType: u.portraitContentType || 'image/jpeg',
        };
    }
    async getPortraitForUserOrMigrateFromFile(id) {
        const fromDb = await this.getPortraitForUser(id);
        if (fromDb)
            return fromDb;
        const u = await this.userModel.findById(id).select('portraitFile').lean();
        if (!u)
            throw new common_1.NotFoundException('User not found');
        const portraitFile = u.portraitFile || '';
        if (!portraitFile)
            return null;
        const uploadDir = process.env.UPLOAD_DIR || 'uploads';
        const uploadsRoot = path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
        const portraitsRoot = path.join(uploadsRoot, 'portraits');
        const filePath = path.join(portraitsRoot, portraitFile);
        if (!fs.existsSync(filePath))
            return null;
        const data = fs.readFileSync(filePath);
        const ext = path.extname(portraitFile).toLowerCase();
        const contentType = ext === '.png'
            ? 'image/png'
            : ext === '.webp'
                ? 'image/webp'
                : ext === '.gif'
                    ? 'image/gif'
                    : 'image/jpeg';
        await this.setPortraitData(id, data, contentType);
        return { data, contentType };
    }
    async setPortraitFile(id, portraitFile) {
        const u = await this.userModel.findByIdAndUpdate(id, { portraitFile }, { new: true }).lean();
        if (!u)
            throw new common_1.NotFoundException('User not found');
        return u;
    }
    async setPortraitData(id, portraitData, portraitContentType) {
        const u = await this.userModel
            .findByIdAndUpdate(id, {
            portraitData,
            portraitContentType,
            portraitFile: '',
        }, { new: true })
            .select('-portraitData')
            .lean();
        if (!u)
            throw new common_1.NotFoundException('User not found');
        return u;
    }
    async upgradeToScouter(userId, paymentIntentId) {
        const user = await this.userModel.findById(userId);
        if (!user)
            throw new common_1.NotFoundException('User not found');
        if (user.role === 'scouter')
            throw new common_1.BadRequestException('Already a scouter');
        user.role = 'scouter';
        user.stripePaymentIntentId = paymentIntentId;
        user.upgradedAt = new Date();
        await user.save();
        return user;
    }
    async listPlayers() {
        return this.userModel
            .find({ role: 'player' })
            .select('-passwordHash -portraitData -resetPasswordTokenHash -resetPasswordExpiresAt')
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
