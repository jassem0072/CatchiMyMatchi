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
exports.MeController = void 0;
const fs = __importStar(require("node:fs"));
const path = __importStar(require("node:path"));
const node_crypto_1 = require("node:crypto");
const common_1 = require("@nestjs/common");
const platform_express_1 = require("@nestjs/platform-express");
const multer_1 = require("multer");
const swagger_1 = require("@nestjs/swagger");
const jwt_auth_guard_1 = require("../auth/jwt-auth.guard");
const roles_decorator_1 = require("../auth/roles.decorator");
const roles_guard_1 = require("../auth/roles.guard");
const auth_service_1 = require("../auth/auth.service");
const users_service_1 = require("../users/users.service");
const videos_service_1 = require("../videos/videos.service");
const stripe_1 = __importDefault(require("stripe"));
const UPGRADE_PRICE_CENTS = 4000; // $40.00
function getStripe() {
    const key = process.env.STRIPE_SECRET_KEY || '';
    if (!key)
        throw new common_1.BadRequestException('Stripe is not configured');
    return new stripe_1.default(key, { apiVersion: '2025-04-30.basil' });
}
function normalizePortraitContentType(file) {
    const ct = (file.mimetype || '').toLowerCase();
    if (ct.startsWith('image/'))
        return ct;
    const ext = path.extname(file.originalname || '').toLowerCase();
    if (ext === '.png')
        return 'image/png';
    if (ext === '.webp')
        return 'image/webp';
    if (ext === '.gif')
        return 'image/gif';
    if (ext === '.jpg' || ext === '.jpeg')
        return 'image/jpeg';
    return 'image/jpeg';
}
function uploadsRoot() {
    const uploadDir = process.env.UPLOAD_DIR || 'uploads';
    return path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
}
let MeController = class MeController {
    constructor(videos, users, auth) {
        this.videos = videos;
        this.users = users;
        this.auth = auth;
    }
    async createUpgradePayment(req) {
        const me = req.user;
        // Verify the user is still a player
        const user = await this.users.getById(me.sub);
        if (user.role === 'scouter')
            throw new common_1.BadRequestException('Already a scouter');
        const stripe = getStripe();
        const paymentIntent = await stripe.paymentIntents.create({
            amount: UPGRADE_PRICE_CENTS,
            currency: 'usd',
            metadata: {
                userId: me.sub,
                purpose: 'scouter_upgrade',
            },
        });
        return {
            clientSecret: paymentIntent.client_secret,
            paymentIntentId: paymentIntent.id,
            publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
        };
    }
    async upgradeToScouter(req, body) {
        const me = req.user;
        const paymentIntentId = body?.paymentIntentId;
        if (!paymentIntentId)
            throw new common_1.BadRequestException('paymentIntentId is required');
        // Verify the payment with Stripe
        const stripe = getStripe();
        const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
        if (paymentIntent.status !== 'succeeded') {
            throw new common_1.BadRequestException(`Payment not completed. Status: ${paymentIntent.status}`);
        }
        if (paymentIntent.amount !== UPGRADE_PRICE_CENTS) {
            throw new common_1.BadRequestException('Invalid payment amount');
        }
        if (paymentIntent.metadata?.userId !== me.sub) {
            throw new common_1.BadRequestException('Payment does not belong to this user');
        }
        const updated = await this.users.upgradeToScouter(me.sub, paymentIntentId);
        const token = this.auth.issueTokenPublic(updated._id.toString(), updated.email, updated.role);
        return token;
    }
    async myVideos(req) {
        const me = req.user;
        return this.videos.listByOwner(me.sub);
    }
    async uploadMyVideo(req, file) {
        const me = req.user;
        return this.videos.createFromUpload(file, me.sub);
    }
    async uploadPortrait(req, file) {
        if (!file)
            throw new common_1.BadRequestException('file is required');
        const me = req.user;
        console.log('[me/portrait] upload start', {
            userId: me.sub,
            originalname: file.originalname,
            mimetype: file.mimetype,
            size: file.size ?? file.buffer?.length ?? 0,
        });
        if (!file.buffer || file.buffer.length === 0)
            throw new common_1.BadRequestException('file is required');
        const contentType = normalizePortraitContentType(file);
        const updated = await this.users.setPortraitData(me.sub, file.buffer, contentType);
        const { passwordHash, ...safe } = updated;
        console.log('[me/portrait] upload saved', { userId: me.sub, contentType, bytes: file.buffer.length });
        return safe;
    }
    async getPortrait(req, res) {
        const me = req.user;
        const portrait = await this.users.getPortraitForUserOrMigrateFromFile(me.sub);
        if (!portrait)
            throw new common_1.NotFoundException('Portrait not found');
        const data = portrait.data;
        const bytes = Buffer.isBuffer(data)
            ? data.length
            : data instanceof Uint8Array
                ? data.byteLength
                : typeof data?.length === 'number'
                    ? data.length
                    : typeof data?.length === 'function'
                        ? data.length()
                        : 0;
        console.log('[me/portrait] get', { userId: me.sub, contentType: portrait.contentType, bytes });
        res.setHeader('Content-Type', portrait.contentType || 'image/jpeg');
        res.setHeader('Cache-Control', 'no-store');
        return res.send(Buffer.isBuffer(data) ? data : Buffer.from(data));
    }
};
exports.MeController = MeController;
__decorate([
    (0, common_1.Post)('create-upgrade-payment'),
    __param(0, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], MeController.prototype, "createUpgradePayment", null);
__decorate([
    (0, common_1.Post)('upgrade'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], MeController.prototype, "upgradeToScouter", null);
__decorate([
    (0, common_1.Get)('videos'),
    __param(0, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], MeController.prototype, "myVideos", null);
__decorate([
    (0, common_1.Post)('videos'),
    (0, common_1.UseInterceptors)((0, platform_express_1.FileInterceptor)('file', {
        storage: (0, multer_1.diskStorage)({
            destination: (_req, _file, cb) => {
                const root = uploadsRoot();
                fs.mkdirSync(root, { recursive: true });
                cb(null, root);
            },
            filename: (_req, file, cb) => {
                const ext = path.extname(file.originalname || '') || '.mp4';
                cb(null, `${(0, node_crypto_1.randomUUID)()}${ext}`);
            },
        }),
        limits: {
            fileSize: 1024 * 1024 * 1024,
        },
    })),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.UploadedFile)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], MeController.prototype, "uploadMyVideo", null);
__decorate([
    (0, common_1.Post)('portrait'),
    (0, swagger_1.ApiConsumes)('multipart/form-data'),
    (0, swagger_1.ApiBody)({
        schema: {
            type: 'object',
            properties: {
                file: { type: 'string', format: 'binary' },
            },
            required: ['file'],
        },
    }),
    (0, common_1.UseInterceptors)((0, platform_express_1.FileInterceptor)('file', {
        storage: (0, multer_1.memoryStorage)(),
        limits: {
            fileSize: 10 * 1024 * 1024,
        },
    })),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.UploadedFile)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], MeController.prototype, "uploadPortrait", null);
__decorate([
    (0, common_1.Get)('portrait'),
    __param(0, (0, common_1.Req)()),
    __param(1, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], MeController.prototype, "getPortrait", null);
exports.MeController = MeController = __decorate([
    (0, swagger_1.ApiTags)('me'),
    (0, swagger_1.ApiBearerAuth)(),
    (0, common_1.Controller)('me'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, roles_guard_1.RolesGuard),
    (0, roles_decorator_1.Roles)('player', 'scouter'),
    __metadata("design:paramtypes", [videos_service_1.VideosService,
        users_service_1.UsersService,
        auth_service_1.AuthService])
], MeController);
