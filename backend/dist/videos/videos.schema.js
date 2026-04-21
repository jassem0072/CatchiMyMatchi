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
exports.VideoSchema = exports.Video = void 0;
const mongoose_1 = require("@nestjs/mongoose");
let Video = class Video {
};
exports.Video = Video;
__decorate([
    (0, mongoose_1.Prop)({ type: String, default: null, index: true }),
    __metadata("design:type", Object)
], Video.prototype, "ownerId", void 0);
__decorate([
    (0, mongoose_1.Prop)({ required: true }),
    __metadata("design:type", String)
], Video.prototype, "filename", void 0);
__decorate([
    (0, mongoose_1.Prop)({ required: true }),
    __metadata("design:type", String)
], Video.prototype, "originalName", void 0);
__decorate([
    (0, mongoose_1.Prop)({ required: true }),
    __metadata("design:type", String)
], Video.prototype, "mimeType", void 0);
__decorate([
    (0, mongoose_1.Prop)({ required: true }),
    __metadata("design:type", Number)
], Video.prototype, "size", void 0);
__decorate([
    (0, mongoose_1.Prop)({ required: true }),
    __metadata("design:type", String)
], Video.prototype, "relativePath", void 0);
__decorate([
    (0, mongoose_1.Prop)({ type: Object, default: null }),
    __metadata("design:type", Object)
], Video.prototype, "lastAnalysis", void 0);
__decorate([
    (0, mongoose_1.Prop)(),
    __metadata("design:type", Date)
], Video.prototype, "lastAnalysisAt", void 0);
exports.Video = Video = __decorate([
    (0, mongoose_1.Schema)({ timestamps: true })
], Video);
exports.VideoSchema = mongoose_1.SchemaFactory.createForClass(Video);
exports.VideoSchema.index({ ownerId: 1, createdAt: -1 });
