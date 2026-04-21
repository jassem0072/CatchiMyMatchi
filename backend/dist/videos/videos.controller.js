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
Object.defineProperty(exports, "__esModule", { value: true });
exports.VideosController = void 0;
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
const videos_service_1 = require("./videos.service");
function uploadsRoot() {
    const uploadDir = process.env.UPLOAD_DIR || 'uploads';
    return path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
}
let VideosController = class VideosController {
    constructor(videosService) {
        this.videosService = videosService;
    }
    async upload(file) {
        return this.videosService.createFromUpload(file, null);
    }
    async list() {
        return this.videosService.list();
    }
    async get(id) {
        return this.videosService.getById(id);
    }
    async analyze(id, body, req) {
        const user = req.user;
        if (user.role === 'player') {
            const v = await this.videosService.getById(id);
            if (!v.ownerId || v.ownerId !== user.sub)
                throw new common_1.ForbiddenException('Not allowed to analyze this video');
        }
        return this.videosService.analyzeVideo(id, body);
    }
    async stream(id, req, res) {
        const video = await this.videosService.getById(id);
        const filePath = await this.videosService.getAbsolutePath(video);
        const stat = fs.statSync(filePath);
        const fileSize = stat.size;
        const range = req.headers.range;
        res.setHeader('Content-Type', video.mimeType || 'video/mp4');
        res.setHeader('Accept-Ranges', 'bytes');
        if (!range) {
            res.setHeader('Content-Length', fileSize);
            fs.createReadStream(filePath).pipe(res);
            return;
        }
        const match = /^bytes=(\d+)-(\d*)$/.exec(range);
        if (!match) {
            res.status(416).end();
            return;
        }
        const start = Number(match[1]);
        const end = match[2] ? Number(match[2]) : fileSize - 1;
        if (Number.isNaN(start) || Number.isNaN(end) || start >= fileSize || end >= fileSize) {
            res.status(416).end();
            return;
        }
        const chunkSize = end - start + 1;
        res.status(206);
        res.setHeader('Content-Range', `bytes ${start}-${end}/${fileSize}`);
        res.setHeader('Content-Length', chunkSize);
        fs.createReadStream(filePath, { start, end }).pipe(res);
    }
};
exports.VideosController = VideosController;
__decorate([
    (0, common_1.Post)(),
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
            fileSize: 1024 * 1024 * 1024, // 1GB
        },
    })),
    __param(0, (0, common_1.UploadedFile)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], VideosController.prototype, "upload", null);
__decorate([
    (0, common_1.Get)(),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], VideosController.prototype, "list", null);
__decorate([
    (0, common_1.Get)(':id'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], VideosController.prototype, "get", null);
__decorate([
    (0, common_1.Post)(':id/analyze'),
    (0, swagger_1.ApiBearerAuth)(),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, roles_guard_1.RolesGuard),
    (0, roles_decorator_1.Roles)('scouter', 'player'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, Object]),
    __metadata("design:returntype", Promise)
], VideosController.prototype, "analyze", null);
__decorate([
    (0, common_1.Get)(':id/stream'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, common_1.Req)()),
    __param(2, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, Object]),
    __metadata("design:returntype", Promise)
], VideosController.prototype, "stream", null);
exports.VideosController = VideosController = __decorate([
    (0, swagger_1.ApiTags)('videos'),
    (0, common_1.Controller)('videos'),
    __metadata("design:paramtypes", [videos_service_1.VideosService])
], VideosController);
