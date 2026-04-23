import * as fs from "node:fs";
import * as path from "node:path";

import axios from "axios";
import FormData from "form-data";
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { InjectModel } from "@nestjs/mongoose";
import { Model } from "mongoose";

import { Video, VideoDocument } from "./videos.schema";

export type AnalysisSelection = {
  t0: number;
  x: number;
  y: number;
  w: number;
  h: number;
  normX?: number;
  normY?: number;
};

export type AnalyzeOptions = {
  selection: AnalysisSelection;
  samplingFps?: number;
  calibration?: Record<string, unknown> | null;
};

export type MontageStatus = {
  exists: boolean;
  outputFilename: string | null;
  outputPath: string | null;
  generatedAt: Date | null;
  streamUrl: string;
};

@Injectable()
export class VideosService {
  constructor(
    @InjectModel(Video.name) private readonly videoModel: Model<VideoDocument>,
  ) {}

  private isLikelyMontageName(name?: string | null): boolean {
    if (!name) return false;
    return /(montage|highlight|highlights|reel|clips?)/i.test(name);
  }

  private async resolveSourceAsMontagePath(
    video: Video,
  ): Promise<string | null> {
    const looksLikeMontage =
      this.isLikelyMontageName(video.originalName) ||
      this.isLikelyMontageName(video.filename);
    if (!looksLikeMontage) return null;
    try {
      const src = await this.getAbsolutePath(video);
      return fs.existsSync(src) ? src : null;
    } catch {
      return null;
    }
  }

  private async detectMontageWithAi(
    sourcePath: string,
  ): Promise<{ isMontage: boolean; confidence: number }> {
    const montageUrl =
      process.env.MONTAGE_SERVICE_URL || "http://localhost:8002";
    try {
      const response = await axios.post(
        `${montageUrl}/detect-montage`,
        { videoPath: sourcePath },
        { timeout: 2 * 60 * 1000 },
      );
      const data = response.data as {
        isMontage?: unknown;
        confidence?: unknown;
      };
      return {
        isMontage: data?.isMontage === true,
        confidence: typeof data?.confidence === "number" ? data.confidence : 0,
      };
    } catch {
      return { isMontage: false, confidence: 0 };
    }
  }

  private resolveMontagePath(
    video: Pick<Video, "montageRelativePath" | "montageFilename">,
  ): string | null {
    const candidates: string[] = [];

    if (video.montageRelativePath) {
      if (path.isAbsolute(video.montageRelativePath)) {
        candidates.push(video.montageRelativePath);
      } else {
        candidates.push(path.join(process.cwd(), video.montageRelativePath));
      }
    }

    if (video.montageFilename) {
      candidates.push(path.join(this.uploadsRoot(), video.montageFilename));
    }

    for (const candidate of candidates) {
      if (fs.existsSync(candidate)) return candidate;
    }

    return null;
  }

  private uploadsRoot(): string {
    const uploadDir = process.env.UPLOAD_DIR || "uploads";
    return path.isAbsolute(uploadDir)
      ? uploadDir
      : path.join(process.cwd(), uploadDir);
  }

  async createFromUpload(
    file: Express.Multer.File,
    ownerId?: string | null,
  ): Promise<Video> {
    const relativePath = path
      .relative(process.cwd(), file.path)
      .replace(/\\/g, "/");
    const isMontageUpload =
      this.isLikelyMontageName(file.originalname) ||
      this.isLikelyMontageName(file.filename);
    const montagePath = path.isAbsolute(file.path)
      ? file.path
      : path.join(process.cwd(), file.path);

    const created = await this.videoModel.create({
      ownerId: ownerId || null,
      filename: file.filename,
      originalName: file.originalname,
      mimeType: file.mimetype,
      size: file.size,
      relativePath,
      montageFilename: isMontageUpload ? file.originalname : null,
      montageRelativePath: isMontageUpload ? montagePath : null,
      montageGeneratedAt: isMontageUpload ? new Date() : undefined,
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
    if (!v) throw new NotFoundException("Video not found");
    return v;
  }

  async getDocById(id: string): Promise<VideoDocument> {
    const v = await this.videoModel.findById(id);
    if (!v) throw new NotFoundException("Video not found");
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
      if (!fs.existsSync(alt))
        throw new NotFoundException("Video file missing on disk");
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

  async deleteForUser(
    videoId: string,
    userId: string,
  ): Promise<{ deletedVideo: boolean; clearedPlayerAnalysis: boolean }> {
    const videoDoc = await this.getDocById(videoId);
    const isOwner = videoDoc.ownerId === userId;

    if (isOwner) {
      // Owner delete: remove video record and all persisted files.
      try {
        const abs = await this.getAbsolutePath(videoDoc.toObject() as Video);
        if (fs.existsSync(abs)) fs.unlinkSync(abs);
      } catch {
        // Ignore missing source files.
      }

      if (videoDoc.montageRelativePath) {
        try {
          const montageAbs = path.isAbsolute(videoDoc.montageRelativePath)
            ? videoDoc.montageRelativePath
            : path.join(process.cwd(), videoDoc.montageRelativePath);
          if (fs.existsSync(montageAbs)) fs.unlinkSync(montageAbs);
        } catch {
          // Ignore missing montage files.
        }
      }

      await videoDoc.deleteOne();
      return { deletedVideo: true, clearedPlayerAnalysis: false };
    }

    const isTagged =
      Array.isArray(videoDoc.taggedPlayers) &&
      videoDoc.taggedPlayers.includes(userId);
    if (!isTagged) {
      throw new BadRequestException("Not allowed to delete this video");
    }

    // Tagged player delete: clear only their own analysis/selection data.
    let changed = false;
    if (videoDoc.playerAnalyses && userId in videoDoc.playerAnalyses) {
      delete videoDoc.playerAnalyses[userId];
      videoDoc.markModified("playerAnalyses");
      changed = true;
    }
    if (videoDoc.playerSelections && userId in videoDoc.playerSelections) {
      delete videoDoc.playerSelections[userId];
      videoDoc.markModified("playerSelections");
      changed = true;
    }

    if (changed) await videoDoc.save();
    return { deletedVideo: false, clearedPlayerAnalysis: changed };
  }

  async analyzeVideo(
    id: string,
    options: AnalyzeOptions,
  ): Promise<Record<string, unknown>> {
    if (!options?.selection)
      throw new BadRequestException("selection is required");

    const aiUrl = process.env.AI_SERVICE_URL || "http://127.0.0.1:8001";
    const videoDoc = await this.getDocById(id);
    const filePath = await this.getAbsolutePath(videoDoc);

    const form = new FormData();
    form.append("file", fs.createReadStream(filePath));
    form.append("chunkIndex", "0");
    form.append("samplingFps", String(options.samplingFps ?? 4));
    form.append("selection", JSON.stringify(options.selection));
    if (options.calibration) {
      form.append("calibration", JSON.stringify(options.calibration));
    }

    const response = await axios.post(`${aiUrl}/process-upload`, form, {
      headers: form.getHeaders(),
      maxBodyLength: Infinity,
      maxContentLength: Infinity,
    });

    videoDoc.lastAnalysis = response.data;
    videoDoc.lastAnalysisAt = new Date();
    // Store player selection so montage can use it
    const sel = options.selection;
    if (!videoDoc.playerSelections) videoDoc.playerSelections = {};
    const selKey = videoDoc.ownerId ?? "owner";
    videoDoc.playerSelections[selKey] = {
      frameTime: sel.t0,
      normX: sel.normX ?? (sel.x + sel.w / 2) / 1920,
      normY: sel.normY ?? (sel.y + sel.h / 2) / 1080,
    };
    videoDoc.markModified("playerSelections");
    await videoDoc.save();

    return response.data as Record<string, unknown>;
  }

  async analyzeVideoForPlayer(
    id: string,
    playerId: string,
    options: AnalyzeOptions,
  ): Promise<Record<string, unknown>> {
    if (!options?.selection)
      throw new BadRequestException("selection is required");

    const aiUrl = process.env.AI_SERVICE_URL || "http://127.0.0.1:8001";
    const videoDoc = await this.getDocById(id);
    const filePath = await this.getAbsolutePath(videoDoc);

    const form = new FormData();
    form.append("file", fs.createReadStream(filePath));
    form.append("chunkIndex", "0");
    form.append("samplingFps", String(options.samplingFps ?? 4));
    form.append("selection", JSON.stringify(options.selection));
    if (options.calibration) {
      form.append("calibration", JSON.stringify(options.calibration));
    }

    const response = await axios.post(`${aiUrl}/process-upload`, form, {
      headers: form.getHeaders(),
      maxBodyLength: Infinity,
      maxContentLength: Infinity,
    });

    if (!videoDoc.playerAnalyses) videoDoc.playerAnalyses = {};
    videoDoc.playerAnalyses[playerId] = response.data;
    videoDoc.markModified("playerAnalyses");
    // Store player selection so montage can use it
    const sel = options.selection;
    if (!videoDoc.playerSelections) videoDoc.playerSelections = {};
    videoDoc.playerSelections[playerId] = {
      frameTime: sel.t0,
      normX: sel.normX ?? (sel.x + sel.w / 2) / 1920,
      normY: sel.normY ?? (sel.y + sel.h / 2) / 1080,
    };
    videoDoc.markModified("playerSelections");
    await videoDoc.save();

    return response.data as Record<string, unknown>;
  }

  async listTaggedFor(playerId: string): Promise<Video[]> {
    return this.videoModel
      .find({ taggedPlayers: playerId })
      .sort({ createdAt: -1 })
      .lean();
  }

  async updateTagsAndVisibility(
    videoId: string,
    ownerId: string,
    taggedPlayers: string[],
    visibility: string,
    taggedTeams: string[],
  ): Promise<Video> {
    const doc = await this.getDocById(videoId);
    if (doc.ownerId !== ownerId)
      throw new BadRequestException("Not the owner of this video");
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
    return this.videoModel
      .find({ taggedTeams: teamId })
      .sort({ createdAt: -1 })
      .lean();
  }

  /**
   * Generate a highlight reel montage from the video's analysis data.
   * Calls the separate ai_montage microservice (port 8002).
   * Clips are selected from sprint events in the positions data.
   */
  async getMontageStatus(id: string): Promise<MontageStatus> {
    const videoDoc = await this.getDocById(id);

    // Absolute path of the SOURCE video — used to detect false-positive saves
    let sourceAbs: string | null = null;
    try {
      sourceAbs = await this.getAbsolutePath(videoDoc);
    } catch {
      sourceAbs = null;
    }

    // resolveMontagePath returns a path only if the montage file actually exists on disk
    const montagePath = this.resolveMontagePath(videoDoc);

    if (montagePath) {
      // Guard: if the "montage" path is the same file as the source video it is a
      // false-positive left over from the old detectMontageWithAi logic.
      // Clear that stale data and report no montage.
      if (sourceAbs && montagePath === sourceAbs) {
        videoDoc.montageFilename = null;
        videoDoc.montageRelativePath = null;
        videoDoc.montageGeneratedAt = undefined;
        await videoDoc.save();
        return {
          exists: false,
          outputFilename: null,
          outputPath: null,
          generatedAt: null,
          streamUrl: `/videos/${id}/montage/stream`,
        };
      }

      return {
        exists: true,
        outputFilename:
          videoDoc.montageFilename ??
          videoDoc.originalName ??
          path.basename(montagePath),
        outputPath: montagePath,
        generatedAt: videoDoc.montageGeneratedAt ?? null,
        streamUrl: `/videos/${id}/montage/stream`,
      };
    }

    // Name-based check: only treat the source as a montage if its own filename
    // explicitly looks like a montage (e.g. "highlight_reel.mp4").
    // We intentionally do NOT call detectMontageWithAi here — it produced
    // too many false positives on broadcast match footage.
    const nameBasedPath = await this.resolveSourceAsMontagePath(videoDoc);
    if (nameBasedPath && nameBasedPath !== sourceAbs) {
      return {
        exists: true,
        outputFilename:
          videoDoc.montageFilename ??
          videoDoc.originalName ??
          path.basename(nameBasedPath),
        outputPath: nameBasedPath,
        generatedAt: videoDoc.montageGeneratedAt ?? null,
        streamUrl: `/videos/${id}/montage/stream`,
      };
    }

    return {
      exists: false,
      outputFilename: null,
      outputPath: null,
      generatedAt: videoDoc.montageGeneratedAt ?? null,
      streamUrl: `/videos/${id}/montage/stream`,
    };
  }

  /**
   * Detect whether a video's CONTENT is already a highlight reel / montage.
   * Calls the AI detection service (/detect-montage) using scene-cut analysis.
   * NEVER saves anything to the database — this is a pure read/detect operation.
   */
  async detectVideoType(id: string): Promise<Record<string, unknown>> {
    const video = await this.getDocById(id);
    const filePath = await this.getAbsolutePath(video);

    const montageUrl =
      process.env.MONTAGE_SERVICE_URL || "http://localhost:8002";
    try {
      const response = await axios.post(
        `${montageUrl}/detect-montage`,
        { videoPath: filePath },
        { timeout: 3 * 60 * 1000 },
      );
      // Return as-is — DO NOT touch the video document
      return response.data as Record<string, unknown>;
    } catch (err: any) {
      const detail =
        err?.response?.data?.detail ||
        err?.message ||
        "Detection service unavailable";
      throw new BadRequestException(`Video type detection failed: ${detail}`);
    }
  }

  async getMontageStreamInfo(
    id: string,
  ): Promise<{ filePath: string | null; filename: string | null }> {
    const video = await this.getById(id);
    const fallbackPath = await this.resolveSourceAsMontagePath(video);
    return {
      filePath: this.resolveMontagePath(video) ?? fallbackPath,
      filename: video.montageFilename ?? video.originalName ?? null,
    };
  }

  async generateMontage(
    id: string,
    playerId?: string,
    options?: { forceRegenerate?: boolean },
  ): Promise<Record<string, unknown>> {
    const videoDoc = await this.getDocById(id);
    const filePath = await this.getAbsolutePath(videoDoc);
    const shouldForce = Boolean(options?.forceRegenerate);
    const montageUrl =
      process.env.MONTAGE_SERVICE_URL || "http://localhost:8002";
    const uploadDir =
      process.env.UPLOAD_DIR || path.join(process.cwd(), "uploads");
    let montageWarning: string | null = null;

    // ── 1. Return already-generated montage (fast path) ──────────────────────
    const existingPath = this.resolveMontagePath(videoDoc);
    if (!shouldForce && existingPath) {
      return {
        outputPath: existingPath,
        outputFilename: videoDoc.montageFilename ?? path.basename(existingPath),
        duration: 0,
        clipCount: 0,
        alreadyGenerated: true,
        streamUrl: `/videos/${id}/montage/stream`,
      };
    }

    // ── 2. Try YOLO-based player+ball montage if player selection is stored ───
    const playerSelections =
      ((videoDoc as any).playerSelections as
        | Record<string, { frameTime: number; normX: number; normY: number }>
        | undefined) ?? {};

    let selection: {
      frameTime: number;
      normX: number;
      normY: number;
    } | null = null;
    if (playerId && playerSelections[playerId]) {
      selection = playerSelections[playerId];
    } else if (Object.keys(playerSelections).length > 0) {
      selection = Object.values(playerSelections)[0] ?? null;
    }

    if (selection) {
      // Attempt 1 is optimized for speed. Attempt 2 is more tolerant to recover
      // from hard-to-see or tiny-ball footage before falling back to analysis clips.
      const yoloAttempts: Array<Record<string, number>> = [
        {
          clipPaddingBefore: 2.2,
          clipPaddingAfter: 3.2,
          minEventGap: 1.6,
          maxClips: 60,
          analysisStride: 8,
          ballProximityFactor: 2.4,
          detectionConfidence: 0.22,
        },
        {
          clipPaddingBefore: 2.0,
          clipPaddingAfter: 3.0,
          minEventGap: 1.4,
          maxClips: 80,
          analysisStride: 6,
          ballProximityFactor: 3.0,
          detectionConfidence: 0.16,
        },
      ];

      let lastYolo422Detail: string | null = null;
      for (const attempt of yoloAttempts) {
        const yoloPayload = {
          videoPath: filePath,
          outputDir: uploadDir,
          videoId: id,
          playerSelection: {
            frameTime: selection.frameTime,
            position: { x: selection.normX, y: selection.normY },
          },
          ...attempt,
        };
        try {
          const response = await axios.post(
            `${montageUrl}/create-player-montage`,
            yoloPayload,
            {
              timeout: 30 * 60 * 1000, // 30 min — YOLO analysis of a full match takes time
            },
          );
          const result = response.data as Record<string, unknown>;
          const outFile = result.outputFilename as string;
          if (outFile) {
            videoDoc.montageFilename = outFile;
            videoDoc.montageRelativePath = result.outputPath as string;
            videoDoc.montageGeneratedAt = new Date();
            await videoDoc.save();
          }
          return {
            ...result,
            alreadyGenerated: false,
            streamUrl: `/videos/${id}/montage/stream`,
          };
        } catch (err: any) {
          if (err?.response?.status === 422) {
            lastYolo422Detail = String(
              err?.response?.data?.detail ??
                "No ball-touch moments found for this player.",
            );
            continue;
          }
          // Any other error (timeout, connection refused, etc.) — fall through to clip-based approach
          break;
        }
      }

      if (lastYolo422Detail) {
        montageWarning = `Player montage fallback: ${lastYolo422Detail}`;
      }
    }

    // ── 3. Filename-only montage check (NO AI detection — avoids false positives) ──
    if (!shouldForce && this.isLikelyMontageName(videoDoc.originalName)) {
      videoDoc.montageFilename =
        videoDoc.montageFilename ?? videoDoc.originalName;
      videoDoc.montageRelativePath = videoDoc.montageRelativePath ?? filePath;
      videoDoc.montageGeneratedAt = videoDoc.montageGeneratedAt ?? new Date();
      await videoDoc.save();
      return {
        outputPath: videoDoc.montageRelativePath,
        outputFilename: videoDoc.montageFilename,
        duration: 0,
        clipCount: 0,
        alreadyGenerated: true,
        streamUrl: `/videos/${id}/montage/stream`,
      };
    }

    // ── 4. Fallback: clip-based approach from stored analysis positions ────────
    let analysis: Record<string, unknown> | null | undefined = null;
    const allPlayerAnalyses = videoDoc.playerAnalyses ?? {};

    if (playerId && allPlayerAnalyses[playerId]) {
      analysis = allPlayerAnalyses[playerId] as Record<string, unknown>;
    } else if (Object.keys(allPlayerAnalyses).length > 0) {
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
    if (!analysis) {
      analysis = videoDoc.lastAnalysis as
        | Record<string, unknown>
        | null
        | undefined;
    }

    if (!analysis) {
      if (shouldForce && existingPath) {
        return {
          outputPath: existingPath,
          outputFilename:
            videoDoc.montageFilename ?? path.basename(existingPath),
          duration: 0,
          clipCount: 0,
          alreadyGenerated: true,
          regenerationSkipped: true,
          message: montageWarning ?? "No analysis data found. Existing montage returned instead.",
          streamUrl: `/videos/${id}/montage/stream`,
        };
      }
      throw new BadRequestException(
        montageWarning ??
          "No analysis data found. Please analyse the video first by identifying the player.",
      );
    }

    const positions: Array<Record<string, unknown>> = Array.isArray(
      (analysis as any).positions,
    )
      ? (analysis as any).positions
      : [];

    const clips = this._selectHighlightClips(
      positions,
      (analysis as any).metrics,
    );
    if (clips.length === 0) {
      throw new BadRequestException(
        "No highlight moments found in the analysis data.",
      );
    }

    const clipPayload = {
      videoPath: filePath,
      clips,
      outputDir: uploadDir,
      videoId: id,
    };
    let result: Record<string, unknown>;
    try {
      const response = await axios.post(
        `${montageUrl}/generate-montage`,
        clipPayload,
        {
          timeout: 5 * 60 * 1000,
        },
      );
      result = response.data as Record<string, unknown>;
    } catch (err: any) {
      const detail =
        err?.response?.data?.detail || err?.message || "Montage service error";
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
      alreadyGenerated: false,
      ...(montageWarning ? { warning: montageWarning } : {}),
      streamUrl: `/videos/${id}/montage/stream`,
    };
  }

  private _selectHighlightClips(
    positions: Array<Record<string, unknown>>,
    metrics?: Record<string, unknown>,
  ): Array<{ start: number; end: number; label: string }> {
    const clips: Array<{ start: number; end: number; label: string }> = [];

    // Larger buffers = longer clips = longer highlight reel
    const PRE_BUFFER = 5.0;
    const POST_BUFFER = 6.0;
    const MIN_SPRINT_DURATION = 0.4;
    const TOUCH_PRE_BUFFER = 3.5;
    const TOUCH_POST_BUFFER = 4.0;

    // ── Step 1: compute per-frame pixel speed from cx/cy/t ──
    // Positions have { t, cx, cy } — no speed_kmh. We compute relative speed in px/s.
    const speeds: number[] = [];
    const times: number[] = [];
    const dirs: number[] = [];
    if (positions && positions.length >= 2) {
      for (let i = 1; i < positions.length; i++) {
        const prev = positions[i - 1];
        const cur = positions[i];
        const dt = ((cur["t"] as number) ?? 0) - ((prev["t"] as number) ?? 0);
        const t = (cur["t"] as number) ?? 0;
        times.push(t);
        if (dt <= 0) {
          speeds.push(0);
          dirs.push(0);
          continue;
        }
        const dx = ((cur["cx"] as number) ?? 0) - ((prev["cx"] as number) ?? 0);
        const dy = ((cur["cy"] as number) ?? 0) - ((prev["cy"] as number) ?? 0);
        speeds.push(Math.sqrt(dx * dx + dy * dy) / dt);
        dirs.push(Math.atan2(dy, dx));
      }
    }

    // ── Step 1b: detect player touch-like moments (acceleration + direction changes) ──
    // This approximates ball touches from tracked player motion without explicit ball tracking.
    if (speeds.length >= 5) {
      const sortedSpeeds = [...speeds].sort((a, b) => a - b);
      const restSpeed =
        sortedSpeeds[Math.floor(sortedSpeeds.length * 0.2)] ?? 0;
      const moveSpeed = Math.max(
        restSpeed + 0.1,
        sortedSpeeds[Math.floor(sortedSpeeds.length * 0.45)] ?? restSpeed,
      );

      const touchScores: Array<{ t: number; score: number }> = [];
      for (let i = 2; i < speeds.length - 1; i++) {
        const dt = Math.max(1e-6, (times[i] ?? 0) - (times[i - 1] ?? 0));
        const accel = Math.abs((speeds[i] - speeds[i - 1]) / dt);

        let dtheta = Math.abs((dirs[i] ?? 0) - (dirs[i - 1] ?? 0));
        while (dtheta > Math.PI) dtheta -= Math.PI * 2;
        dtheta = Math.abs(dtheta);
        const turnDeg = (dtheta * 180) / Math.PI;

        if ((speeds[i] ?? 0) < moveSpeed) continue;
        if (turnDeg < 18 && accel < 0.3) continue;

        const score =
          turnDeg / 35 +
          accel * 0.9 +
          ((speeds[i] ?? 0) / Math.max(moveSpeed, 1e-6)) * 0.2;
        const prevScore = touchScores.length
          ? touchScores[touchScores.length - 1].score
          : -1;
        const prevT = touchScores.length
          ? touchScores[touchScores.length - 1].t
          : -1000;
        const t = times[i] ?? 0;

        // Keep local maxima and avoid duplicate nearby touch points.
        if (t - prevT < 1.2) {
          if (score > prevScore)
            touchScores[touchScores.length - 1] = { t, score };
        } else {
          touchScores.push({ t, score });
        }
      }

      touchScores.sort((a, b) => b.score - a.score);
      for (const tp of touchScores.slice(0, 10)) {
        const covered = clips.some((c) => tp.t >= c.start && tp.t <= c.end);
        if (!covered) {
          clips.push({
            start: Math.max(0, tp.t - TOUCH_PRE_BUFFER),
            end: tp.t + TOUCH_POST_BUFFER,
            label: "Ball Touch (AI est.)",
          });
        }
      }
    }

    // ── Step 2: top 40% speed = "active moment" (was 25% — now wider to get more clips)
    if (speeds.length >= 4) {
      const sorted = [...speeds].sort((a, b) => a - b);
      // Use 60th percentile as threshold so top 40% qualify as highlights
      const sprintThreshold = sorted[Math.floor(sorted.length * 0.6)];
      // Must be meaningfully above the resting threshold (20th percentile)
      const restThreshold = sorted[Math.floor(sorted.length * 0.2)];
      const effectiveThreshold = Math.max(sprintThreshold, restThreshold + 0.1);

      let inSprint = false;
      let sprintStart = 0;
      let peakSpeed = 0;

      for (let i = 0; i < speeds.length; i++) {
        const t = (positions[i + 1]?.["t"] as number) ?? 0;
        const spd = speeds[i];

        if (!inSprint && spd >= effectiveThreshold) {
          inSprint = true;
          sprintStart = (positions[i]?.["t"] as number) ?? t;
          peakSpeed = spd;
        } else if (inSprint && spd >= effectiveThreshold) {
          if (spd > peakSpeed) peakSpeed = spd;
        } else if (
          inSprint &&
          (spd < effectiveThreshold * 0.5 || i === speeds.length - 1)
        ) {
          const sprintEnd = t;
          const dur = sprintEnd - sprintStart;
          if (dur >= MIN_SPRINT_DURATION) {
            clips.push({
              start: Math.max(0, sprintStart - PRE_BUFFER),
              end: sprintEnd + POST_BUFFER,
              label: "Sprint",
            });
          }
          inSprint = false;
          peakSpeed = 0;
        }
      }
    }

    // ── Step 3: acceleration peaks from metrics (already timestamps in seconds) ──
    const accelPeaks: number[] = Array.isArray(metrics?.["accelPeaks"])
      ? (metrics!["accelPeaks"] as number[])
      : [];
    for (const peakT of accelPeaks) {
      const covered = clips.some((c) => peakT >= c.start && peakT <= c.end);
      if (!covered) {
        clips.push({
          start: Math.max(0, peakT - 3.0),
          end: peakT + 3.5,
          label: "Acceleration Peak",
        });
      }
    }

    // ── Step 4: always ensure at least 6 evenly-spaced clips ──
    // Keep a small fallback set if touch/sprint signals are sparse.
    if (positions.length >= 2) {
      const totalDuration =
        (positions[positions.length - 1]?.["t"] as number) ?? 60;
      const TARGET_CLIPS = 4;
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
        merged[merged.length - 1].end = Math.max(
          merged[merged.length - 1].end,
          c.end,
        );
      } else {
        merged.push({ ...c });
      }
    }

    // ── Ensure minimum montage length by adding evenly-spaced coverage clips ──
    const MIN_MONTAGE_CLIPS = 12;
    const videoEnd = times.length > 0 ? (times[times.length - 1] ?? 0) : 0;
    if (merged.length < MIN_MONTAGE_CLIPS && videoEnd > 30) {
      const needed = MIN_MONTAGE_CLIPS - merged.length;
      const step = videoEnd / (needed + 1);
      for (let i = 1; i <= needed; i++) {
        const mid = step * i;
        const cs = Math.max(0, mid - PRE_BUFFER);
        const ce = Math.min(videoEnd, mid + POST_BUFFER);
        const overlaps = merged.some(
          (c) => c.start <= ce + 1 && c.end >= cs - 1,
        );
        if (!overlaps) {
          merged.push({ start: cs, end: ce, label: "coverage" });
        }
      }
      merged.sort((a, b) => a.start - b.start);
    }

    return merged.slice(0, 15);
  }
}
