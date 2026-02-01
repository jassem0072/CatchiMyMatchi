import * as fs from 'node:fs';
import * as path from 'node:path';

import axios from 'axios';
import FormData from 'form-data';
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { Video, VideoDocument } from './videos.schema';

export type AnalysisSelection = {
  t0: number;
  x: number;
  y: number;
  w: number;
  h: number;
};

export type AnalyzeOptions = {
  selection: AnalysisSelection;
  samplingFps?: number;
  calibration?: Record<string, unknown> | null;
};

@Injectable()
export class VideosService {
  constructor(@InjectModel(Video.name) private readonly videoModel: Model<VideoDocument>) {}

  private uploadsRoot(): string {
    const uploadDir = process.env.UPLOAD_DIR || 'uploads';
    return path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
  }

  async createFromUpload(file: Express.Multer.File, ownerId?: string | null): Promise<Video> {
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

  async list(): Promise<Video[]> {
    return this.videoModel.find().sort({ createdAt: -1 }).lean();
  }

  async listByOwner(ownerId: string): Promise<Video[]> {
    return this.videoModel.find({ ownerId }).sort({ createdAt: -1 }).lean();
  }

  async getById(id: string): Promise<Video> {
    const v = await this.videoModel.findById(id).lean();
    if (!v) throw new NotFoundException('Video not found');
    return v;
  }

  async getDocById(id: string): Promise<VideoDocument> {
    const v = await this.videoModel.findById(id);
    if (!v) throw new NotFoundException('Video not found');
    return v;
  }

  async getAbsolutePath(video: Video): Promise<string> {
    const root = this.uploadsRoot();

    // Prefer relativePath so we can relocate uploadDir safely
    const abs = path.isAbsolute(video.relativePath)
      ? video.relativePath
      : path.join(process.cwd(), video.relativePath);

    // Basic safety: must exist
    if (!fs.existsSync(abs)) {
      // Try fallback: join upload root + filename
      const alt = path.join(root, video.filename);
      if (!fs.existsSync(alt)) throw new NotFoundException('Video file missing on disk');
      return alt;
    }

    return abs;
  }

  async analyzeVideo(id: string, options: AnalyzeOptions): Promise<Record<string, unknown>> {
    if (!options?.selection) throw new BadRequestException('selection is required');

    const aiUrl = process.env.AI_SERVICE_URL || 'http://127.0.0.1:8001';
    const videoDoc = await this.getDocById(id);
    const filePath = await this.getAbsolutePath(videoDoc);

    const form = new FormData();
    form.append('file', fs.createReadStream(filePath));
    form.append('chunkIndex', '0');
    form.append('samplingFps', String(options.samplingFps ?? 3));
    form.append('selection', JSON.stringify(options.selection));
    if (options.calibration) {
      form.append('calibration', JSON.stringify(options.calibration));
    }

    const response = await axios.post(`${aiUrl}/process-upload`, form, {
      headers: form.getHeaders(),
      maxBodyLength: Infinity,
      maxContentLength: Infinity,
    });

    videoDoc.lastAnalysis = response.data;
    videoDoc.lastAnalysisAt = new Date();
    await videoDoc.save();

    return response.data as Record<string, unknown>;
  }
}
