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
exports.VideosService = void 0;
const fs = __importStar(require("node:fs"));
const path = __importStar(require("node:path"));
const axios_1 = __importDefault(require("axios"));
const form_data_1 = __importDefault(require("form-data"));
const common_1 = require("@nestjs/common");
const mongoose_1 = require("@nestjs/mongoose");
const mongoose_2 = require("mongoose");
const videos_schema_1 = require("./videos.schema");
let VideosService = class VideosService {
    constructor(videoModel) {
        this.videoModel = videoModel;
    }
    uploadsRoot() {
        const uploadDir = process.env.UPLOAD_DIR || 'uploads';
        return path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
    }
    async createFromUpload(file, ownerId) {
        const relativePath = path.relative(process.cwd(), file.path).replace(/\\/g, '/');
        const created = await this.videoModel.create({
            ownerId: ownerId || null,
            filename: file.filename,
            originalName: file.originalname,
            mimeType: file.mimetype,
            size: file.size,
            relativePath,
        });
        return created.toObject();
    }
    async list() {
        return this.videoModel.find().sort({ createdAt: -1 }).lean();
    }
    async listByOwner(ownerId) {
        return this.videoModel.find({ ownerId }).sort({ createdAt: -1 }).lean();
    }
    async getById(id) {
        const v = await this.videoModel.findById(id).lean();
        if (!v)
            throw new common_1.NotFoundException('Video not found');
        return v;
    }
    async getDocById(id) {
        const v = await this.videoModel.findById(id);
        if (!v)
            throw new common_1.NotFoundException('Video not found');
        return v;
    }
    async getAbsolutePath(video) {
        const root = this.uploadsRoot();
        // Prefer relativePath so we can relocate uploadDir safely
        const abs = path.isAbsolute(video.relativePath)
            ? video.relativePath
            : path.join(process.cwd(), video.relativePath);
        // Basic safety: must exist
        if (!fs.existsSync(abs)) {
            // Try fallback: join upload root + filename
            const alt = path.join(root, video.filename);
            if (!fs.existsSync(alt))
                throw new common_1.NotFoundException('Video file missing on disk');
            return alt;
        }
        return abs;
    }
    async analyzeVideo(id, options) {
        if (!options?.selection)
            throw new common_1.BadRequestException('selection is required');
        const aiUrl = process.env.AI_SERVICE_URL || 'http://127.0.0.1:8001';
        const videoDoc = await this.getDocById(id);
        const filePath = await this.getAbsolutePath(videoDoc);
        const form = new form_data_1.default();
        form.append('file', fs.createReadStream(filePath));
        form.append('chunkIndex', '0');
        form.append('samplingFps', String(options.samplingFps ?? 3));
        form.append('selection', JSON.stringify(options.selection));
        if (options.calibration) {
            form.append('calibration', JSON.stringify(options.calibration));
        }
        const response = await axios_1.default.post(`${aiUrl}/process-upload`, form, {
            headers: form.getHeaders(),
            maxBodyLength: Infinity,
            maxContentLength: Infinity,
        });
        videoDoc.lastAnalysis = response.data;
        videoDoc.lastAnalysisAt = new Date();
        await videoDoc.save();
        return response.data;
    }
};
exports.VideosService = VideosService;
exports.VideosService = VideosService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, mongoose_1.InjectModel)(videos_schema_1.Video.name)),
    __metadata("design:paramtypes", [mongoose_2.Model])
], VideosService);
