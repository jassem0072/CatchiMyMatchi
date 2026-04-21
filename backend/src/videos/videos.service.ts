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

  async deleteByOwner(ownerId: string): Promise<number> {
    const videos = await this.videoModel.find({ ownerId }).lean();
    for (const v of videos) {
      try {
        const abs = path.isAbsolute(v.relativePath)
          ? v.relativePath
          : path.join(process.cwd(), v.relativePath);
        if (fs.existsSync(abs)) fs.unlinkSync(abs);
      } catch {
        // ignore missing files
      }
    }
    const result = await this.videoModel.deleteMany({ ownerId });
    return result.deletedCount || 0;
  }

  async analyzeVideo(id: string, options: AnalyzeOptions): Promise<Record<string, unknown>> {
    if (!options?.selection) throw new BadRequestException('selection is required');

    const aiUrl = process.env.AI_SERVICE_URL || 'http://127.0.0.1:8001';
    const videoDoc = await this.getDocById(id);
    const filePath = await this.getAbsolutePath(videoDoc);

    const form = new FormData();
    form.append('file', fs.createReadStream(filePath));
    form.append('chunkIndex', '0');
    form.append('samplingFps', String(options.samplingFps ?? 2));
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

  async analyzeVideoForPlayer(id: string, playerId: string, options: AnalyzeOptions): Promise<Record<string, unknown>> {
    if (!options?.selection) throw new BadRequestException('selection is required');

    const aiUrl = process.env.AI_SERVICE_URL || 'http://127.0.0.1:8001';
    const videoDoc = await this.getDocById(id);
    const filePath = await this.getAbsolutePath(videoDoc);

    const form = new FormData();
    form.append('file', fs.createReadStream(filePath));
    form.append('chunkIndex', '0');
    form.append('samplingFps', String(options.samplingFps ?? 2));
    form.append('selection', JSON.stringify(options.selection));
    if (options.calibration) {
      form.append('calibration', JSON.stringify(options.calibration));
    }

    const response = await axios.post(`${aiUrl}/process-upload`, form, {
      headers: form.getHeaders(),
      maxBodyLength: Infinity,
      maxContentLength: Infinity,
    });

    if (!videoDoc.playerAnalyses) videoDoc.playerAnalyses = {};
    videoDoc.playerAnalyses[playerId] = response.data;
    videoDoc.markModified('playerAnalyses');
    await videoDoc.save();

    return response.data as Record<string, unknown>;
  }

  async listTaggedFor(playerId: string): Promise<Video[]> {
    return this.videoModel.find({ taggedPlayers: playerId }).sort({ createdAt: -1 }).lean();
  }

  async updateTagsAndVisibility(
    videoId: string,
    ownerId: string,
    taggedPlayers: string[],
    visibility: string,
    taggedTeams: string[],
  ): Promise<Video> {
    const doc = await this.getDocById(videoId);
    if (doc.ownerId !== ownerId) throw new BadRequestException('Not the owner of this video');
    doc.taggedPlayers = taggedPlayers;
    doc.taggedTeams = taggedTeams;
    doc.visibility = visibility;
    await doc.save();
    return doc.toObject();
  }

  async updateVisibility(videoId: string, visibility: string): Promise<Video> {
    const doc = await this.getDocById(videoId);
    doc.visibility = visibility;
    await doc.save();
    return doc.toObject();
  }

  async listByTeamTag(teamId: string): Promise<Video[]> {
    return this.videoModel.find({ taggedTeams: teamId }).sort({ createdAt: -1 }).lean();
  }

  /**
   * Generate a highlight reel montage from the video's analysis data.
   * Calls the separate ai_montage microservice (port 8002).
   * Clips are selected from sprint events in the positions data.
   */
  async generateMontage(id: string, playerId?: string): Promise<Record<string, unknown>> {
    const videoDoc = await this.getDocById(id);
    const filePath = await this.getAbsolutePath(videoDoc);

    // ── Pick the best available analysis ──
    // Priority: 1) playerAnalyses[playerId]  2) any playerAnalyses entry with most positions
    // 3) lastAnalysis
    let analysis: Record<string, unknown> | null | undefined = null;

    const allPlayerAnalyses = videoDoc.playerAnalyses ?? {};

    if (playerId && allPlayerAnalyses[playerId]) {
      // Exact match by playerId
      analysis = allPlayerAnalyses[playerId] as Record<string, unknown>;
    } else if (Object.keys(allPlayerAnalyses).length > 0) {
      // No exact match — pick the playerAnalyses entry with the most positions (richest data)
      let bestCount = -1;
      for (const entry of Object.values(allPlayerAnalyses)) {
        const positions = (entry as any)?.positions;
        const count = Array.isArray(positions) ? positions.length : 0;
        if (count > bestCount) {
          bestCount = count;
          analysis = entry as Record<string, unknown>;
        }
      }
    }

    // Fall back to lastAnalysis if no playerAnalyses available
    if (!analysis) {
      analysis = videoDoc.lastAnalysis as Record<string, unknown> | null | undefined;
    }

    if (!analysis) {
      throw new BadRequestException('No analysis data found. Please analyse the video first.');
    }

    const positions: Array<Record<string, unknown>> = Array.isArray((analysis as any).positions)
      ? (analysis as any).positions
      : [];

    const clips = this._selectHighlightClips(positions, (analysis as any).metrics);

    if (clips.length === 0) {
      throw new BadRequestException('No highlight moments found in analysis data.');
    }

    const montageUrl = process.env.MONTAGE_SERVICE_URL || 'http://localhost:8002';
    const uploadDir = process.env.UPLOAD_DIR || path.join(process.cwd(), 'uploads');

    const payload = {
      videoPath: filePath,
      clips,
      outputDir: uploadDir,
      videoId: id,
    };

    let result: Record<string, unknown>;
    try {
      const response = await axios.post(`${montageUrl}/generate-montage`, payload, {
        timeout: 5 * 60 * 1000,
      });
      result = response.data as Record<string, unknown>;
    } catch (err: any) {
      const detail = err?.response?.data?.detail || err?.message || 'Montage service error';
      throw new BadRequestException(`Montage generation failed: ${detail}`);
    }

    const outFile = result.outputFilename as string;
    if (outFile) {
      videoDoc.montageFilename = outFile;
      videoDoc.montageRelativePath = result.outputPath as string;
      videoDoc.montageGeneratedAt = new Date();
      await videoDoc.save();
    }

    return {
      ...result,
      clipCount: clips.length,
      streamUrl: `/videos/${id}/montage/stream`,
    };
  }

  private _selectHighlightClips(
    positions: Array<Record<string, unknown>>,
    metrics?: Record<string, unknown>,
  ): Array<{ start: number; end: number; label: string }> {
    const clips: Array<{ start: number; end: number; label: string }> = [];

    // Larger buffers = longer clips = longer highlight reel
    const PRE_BUFFER = 3.5;
    const POST_BUFFER = 3.0;
    const MIN_SPRINT_DURATION = 0.5;

    // ── Step 1: compute per-frame pixel speed from cx/cy/t ──
    // Positions have { t, cx, cy } — no speed_kmh. We compute relative speed in px/s.
    const speeds: number[] = [];
    if (positions && positions.length >= 2) {
      for (let i = 1; i < positions.length; i++) {
        const prev = positions[i - 1];
        const cur = positions[i];
        const dt = ((cur['t'] as number) ?? 0) - ((prev['t'] as number) ?? 0);
        if (dt <= 0) { speeds.push(0); continue; }
        const dx = ((cur['cx'] as number) ?? 0) - ((prev['cx'] as number) ?? 0);
        const dy = ((cur['cy'] as number) ?? 0) - ((prev['cy'] as number) ?? 0);
        speeds.push(Math.sqrt(dx * dx + dy * dy) / dt);
      }
    }

    // ── Step 2: top 40% speed = "active moment" (was 25% — now wider to get more clips)
    if (speeds.length >= 4) {
      const sorted = [...speeds].sort((a, b) => a - b);
      // Use 60th percentile as threshold so top 40% qualify as highlights
      const sprintThreshold = sorted[Math.floor(sorted.length * 0.60)];
      // Must be meaningfully above the resting threshold (20th percentile)
      const restThreshold = sorted[Math.floor(sorted.length * 0.20)];
      const effectiveThreshold = Math.max(sprintThreshold, restThreshold + 0.1);

      let inSprint = false;
      let sprintStart = 0;
      let peakSpeed = 0;

      for (let i = 0; i < speeds.length; i++) {
        const t = (positions[i + 1]?.['t'] as number) ?? 0;
        const spd = speeds[i];

        if (!inSprint && spd >= effectiveThreshold) {
          inSprint = true;
          sprintStart = (positions[i]?.['t'] as number) ?? t;
          peakSpeed = spd;
        } else if (inSprint && spd >= effectiveThreshold) {
          if (spd > peakSpeed) peakSpeed = spd;
        } else if (inSprint && (spd < effectiveThreshold * 0.5 || i === speeds.length - 1)) {
          const sprintEnd = t;
          const dur = sprintEnd - sprintStart;
          if (dur >= MIN_SPRINT_DURATION) {
            clips.push({
              start: Math.max(0, sprintStart - PRE_BUFFER),
              end: sprintEnd + POST_BUFFER,
              label: 'Sprint',
            });
          }
          inSprint = false;
          peakSpeed = 0;
        }
      }
    }

    // ── Step 3: acceleration peaks from metrics (already timestamps in seconds) ──
    const accelPeaks: number[] = Array.isArray(metrics?.['accelPeaks'])
      ? (metrics!['accelPeaks'] as number[])
      : [];
    for (const peakT of accelPeaks) {
      const covered = clips.some((c) => peakT >= c.start && peakT <= c.end);
      if (!covered) {
        clips.push({
          start: Math.max(0, peakT - 3.0),
          end: peakT + 3.5,
          label: 'Acceleration Peak',
        });
      }
    }

    // ── Step 4: always ensure at least 6 evenly-spaced clips ──
    // This guarantees a meaningful highlight reel even for static or slow videos
    if (positions.length >= 2) {
      const totalDuration = (positions[positions.length - 1]?.['t'] as number) ?? 60;
      const TARGET_CLIPS = 6;
      if (clips.length < TARGET_CLIPS) {
        const needed = TARGET_CLIPS - clips.length;
        const step = totalDuration / (needed + 1);
        for (let i = 1; i <= needed; i++) {
          const mid = step * i;
          const covered = clips.some((c) => mid >= c.start && mid <= c.end);
          if (!covered) {
            clips.push({
              start: Math.max(0, mid - 3.5),
              end: mid + 3.5,
              label: `Action ${i}`,
            });
          }
        }
      }
    }

    // ── Step 5: sort, merge overlapping, cap at 15 clips ──
    clips.sort((a, b) => a.start - b.start);
    const merged: typeof clips = [];
    for (const c of clips) {
      if (merged.length && c.start <= merged[merged.length - 1].end + 1.0) {
        merged[merged.length - 1].end = Math.max(merged[merged.length - 1].end, c.end);
      } else {
        merged.push({ ...c });
      }
    }

    return merged.slice(0, 15);
  }
}

