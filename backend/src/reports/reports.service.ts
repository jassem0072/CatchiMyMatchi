import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { VideosService } from '../videos/videos.service';
import { Report, ReportDocument } from './reports.schema';

@Injectable()
export class ReportsService {
  constructor(
    @InjectModel(Report.name) private readonly reportModel: Model<ReportDocument>,
    private readonly videos: VideosService,
  ) {}

  async create(scouterId: string, input: { playerId: string; videoId?: string; title?: string; notes?: string; cardSnapshot?: any }) {
    if (!input.playerId) throw new BadRequestException('playerId is required');

    let analysisSnapshot: Record<string, unknown> | null = null;
    if (input.videoId) {
      const v: any = await this.videos.getById(input.videoId);
      if (v && v.ownerId && v.ownerId !== input.playerId) {
        throw new BadRequestException('videoId does not belong to playerId');
      }
      analysisSnapshot = (v && v.lastAnalysis) || null;
    }

    const created = await this.reportModel.create({
      scouterId,
      playerId: input.playerId,
      videoId: input.videoId || null,
      title: input.title || '',
      notes: input.notes || '',
      analysisSnapshot,
      cardSnapshot: input.cardSnapshot || null,
    });

    return created.toObject();
  }

  async list(scouterId: string, playerId?: string) {
    const q: any = { scouterId };
    if (playerId) q.playerId = playerId;
    return this.reportModel.find(q).sort({ createdAt: -1 }).lean();
  }

  async get(scouterId: string, id: string) {
    const r = await this.reportModel.findOne({ _id: id, scouterId }).lean();
    if (!r) throw new NotFoundException('Report not found');
    return r;
  }
}
