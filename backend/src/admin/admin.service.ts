import * as fs from 'node:fs';
import * as path from 'node:path';
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { User, UserDocument } from '../users/users.schema';
import { Video, VideoDocument } from '../videos/videos.schema';
import { Report, ReportDocument } from '../reports/reports.schema';
import { Notification, NotificationDocument } from '../notifications/notifications.schema';
import type { AdminUserQueryDto, BroadcastNotificationDto, UpdateSubscriptionDto } from './admin.dto';

@Injectable()
export class AdminService {
  constructor(
    @InjectModel(User.name) private readonly userModel: Model<UserDocument>,
    @InjectModel(Video.name) private readonly videoModel: Model<VideoDocument>,
    @InjectModel(Report.name) private readonly reportModel: Model<ReportDocument>,
    @InjectModel(Notification.name) private readonly notifModel: Model<NotificationDocument>,
  ) {}

  // ── Users ──────────────────────────────────────────────────────────────

  async listUsers(query: AdminUserQueryDto): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(query.limit) || 20));
    const skip = (page - 1) * limit;

    const filter: Record<string, any> = {};
    if (query.role) filter.role = query.role;
    if (query.search) {
      const re = { $regex: query.search, $options: 'i' };
      filter.$or = [{ email: re }, { displayName: re }];
    }

    const [data, total] = await Promise.all([
      this.userModel
        .find(filter)
        .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      this.userModel.countDocuments(filter),
    ]);

    return { data, total, page, limit };
  }

  async deleteUser(id: string): Promise<void> {
    const result = await this.userModel.findByIdAndDelete(id);
    if (!result) throw new NotFoundException('User not found');
  }

  async banUser(id: string, isBanned: boolean): Promise<any> {
    const user = await this.userModel
      .findByIdAndUpdate(id, { isBanned }, { new: true })
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async updateUserRole(id: string, role: 'player' | 'scouter' | 'admin'): Promise<any> {
    const user = await this.userModel
      .findByIdAndUpdate(id, { role }, { new: true })
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  // ── Videos ──────────────────────────────────────────────────────────────

  async listVideos(page = 1, limit = 20): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const p = Math.max(1, page);
    const l = Math.min(100, Math.max(1, limit));
    const skip = (p - 1) * l;

    const [rawVideos, total] = await Promise.all([
      this.videoModel.find().sort({ createdAt: -1 }).skip(skip).limit(l).lean(),
      this.videoModel.countDocuments(),
    ]);

    // Populate owner display names
    const ownerIds = [...new Set(rawVideos.map((v: any) => v.ownerId).filter(Boolean))];
    const owners = ownerIds.length
      ? await this.userModel.find({ _id: { $in: ownerIds } }).select('_id displayName email').lean()
      : [];
    const ownerMap: Record<string, string> = {};
    for (const o of owners as any[]) {
      ownerMap[String(o._id)] = o.displayName || o.email || String(o._id);
    }

    const data = rawVideos.map((v: any) => ({
      ...v,
      ownerDisplayName: v.ownerId ? (ownerMap[String(v.ownerId)] ?? 'Unknown') : 'Anonymous',
    }));

    return { data, total, page: p, limit: l };
  }

  async deleteVideo(id: string): Promise<void> {
    const video = await this.videoModel.findByIdAndDelete(id);
    if (!video) throw new NotFoundException('Video not found');

    // Try to remove the file from disk
    if ((video as any).relativePath) {
      const uploadDir = process.env.UPLOAD_DIR || 'uploads';
      const uploadsRoot = path.isAbsolute(uploadDir)
        ? uploadDir
        : path.join(process.cwd(), uploadDir);
      const filePath = path.join(uploadsRoot, (video as any).relativePath);
      if (fs.existsSync(filePath)) {
        try { fs.unlinkSync(filePath); } catch { /* ignore */ }
      }
    }
  }

  async setVideoVisibility(id: string, visibility: 'public' | 'private'): Promise<any> {
    const video = await this.videoModel
      .findByIdAndUpdate(id, { visibility }, { new: true })
      .lean();
    if (!video) throw new NotFoundException('Video not found');
    return video;
  }

  // ── Stats ──────────────────────────────────────────────────────────────

  async getStats(): Promise<Record<string, any>> {
    const now = new Date();
    const twelveMonthsAgo = new Date(now);
    twelveMonthsAgo.setMonth(twelveMonthsAgo.getMonth() - 11);
    twelveMonthsAgo.setDate(1);
    twelveMonthsAgo.setHours(0, 0, 0, 0);

    const [
      totalPlayers,
      totalScouterss,
      totalVideos,
      analyzedVideos,
      registrationsByMonth,
      subscriptionDist,
    ] = await Promise.all([
      this.userModel.countDocuments({ role: 'player' }),
      this.userModel.countDocuments({ role: 'scouter' }),
      this.videoModel.countDocuments(),
      this.videoModel.countDocuments({ lastAnalysis: { $ne: null } }),
      this.userModel.aggregate([
        { $match: { createdAt: { $gte: twelveMonthsAgo } } },
        {
          $group: {
            _id: { year: { $year: '$createdAt' }, month: { $month: '$createdAt' } },
            count: { $sum: 1 },
          },
        },
        { $sort: { '_id.year': 1, '_id.month': 1 } },
      ]),
      this.userModel.aggregate([
        { $match: { subscriptionTier: { $ne: null } } },
        { $group: { _id: '$subscriptionTier', count: { $sum: 1 } } },
      ]),
    ]);

    const monthLabels = [];
    for (let i = 0; i < 12; i++) {
      const d = new Date(twelveMonthsAgo);
      d.setMonth(d.getMonth() + i);
      monthLabels.push({ year: d.getFullYear(), month: d.getMonth() + 1 });
    }

    const regMap: Record<string, number> = {};
    for (const r of registrationsByMonth) {
      regMap[`${r._id.year}-${r._id.month}`] = r.count;
    }

    const registrations = monthLabels.map((m) => ({
      label: `${m.year}-${String(m.month).padStart(2, '0')}`,
      count: regMap[`${m.year}-${m.month}`] ?? 0,
    }));

    const subscriptions: Record<string, number> = { basic: 0, premium: 0, elite: 0 };
    for (const s of subscriptionDist) {
      if (s._id) subscriptions[s._id] = s.count;
    }

    return {
      totalPlayers,
      totalScouterss,
      totalVideos,
      analyzedVideos,
      registrations,
      subscriptions,
    };
  }

  // ── Players (admin) ─────────────────────────────────────────────────────

  async listPlayers(query: AdminUserQueryDto): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(query.limit) || 20));
    const skip = (page - 1) * limit;

    const filter: Record<string, any> = { role: 'player' };
    if ((query as any).subscriptionTier) filter.subscriptionTier = (query as any).subscriptionTier;
    if (query.search) {
      const re = { $regex: query.search, $options: 'i' };
      filter.$or = [{ email: re }, { displayName: re }];
    }

    const [players, total] = await Promise.all([
      this.userModel
        .find(filter)
        .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      this.userModel.countDocuments(filter),
    ]);

    // Enrich with video & report counts
    const playerIds = (players as any[]).map((p: any) => String(p._id));
    const [videoCounts, reportCounts] = await Promise.all([
      this.videoModel.aggregate([
        { $match: { ownerId: { $in: playerIds } } },
        { $group: { _id: '$ownerId', count: { $sum: 1 } } },
      ]),
      this.reportModel.aggregate([
        { $match: { playerId: { $in: playerIds } } },
        { $group: { _id: '$playerId', count: { $sum: 1 } } },
      ]),
    ]);

    const videoMap: Record<string, number> = {};
    for (const v of videoCounts) videoMap[String(v._id)] = v.count;
    const reportMap: Record<string, number> = {};
    for (const r of reportCounts) reportMap[String(r._id)] = r.count;

    const data = (players as any[]).map((p: any) => ({
      ...p,
      videoCount: videoMap[String(p._id)] ?? 0,
      reportCount: reportMap[String(p._id)] ?? 0,
    }));

    return { data, total, page, limit };
  }

  async getPlayerDetail(id: string): Promise<any> {
    const player = await this.userModel
      .findById(id)
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!player || (player as any).role !== 'player') throw new NotFoundException('Player not found');

    const [videos, reports] = await Promise.all([
      this.videoModel.find({ ownerId: String(id) }).sort({ createdAt: -1 }).lean(),
      this.reportModel.find({ playerId: String(id) }).sort({ createdAt: -1 }).lean(),
    ]);

    // Aggregate performance metrics from analyzed videos
    const analyzed = (videos as any[]).filter((v: any) => v.lastAnalysis);
    let totalDist = 0, sumAvg = 0, maxSpeed = 0, totalSprints = 0;
    for (const v of analyzed) {
      const m = v.lastAnalysis?.metrics || v.lastAnalysis;
      if (!m) continue;
      totalDist += m.distanceMeters ?? 0;
      sumAvg += m.avgSpeedKmh ?? 0;
      if ((m.maxSpeedKmh ?? 0) > maxSpeed) maxSpeed = m.maxSpeedKmh;
      totalSprints += m.sprintCount ?? 0;
    }
    const analytics = {
      totalVideos: videos.length,
      analyzedVideos: analyzed.length,
      totalDistanceMeters: Math.round(totalDist * 100) / 100,
      avgSpeedKmh: analyzed.length ? Math.round((sumAvg / analyzed.length) * 100) / 100 : 0,
      maxSpeedKmh: Math.round(maxSpeed * 100) / 100,
      totalSprints,
      reportsAboutPlayer: reports.length,
    };

    return { player, videos, reports, analytics };
  }

  // ── Scouters (admin) ─────────────────────────────────────────────────────

  async listScouters(query: AdminUserQueryDto): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(query.limit) || 20));
    const skip = (page - 1) * limit;

    const filter: Record<string, any> = { role: 'scouter' };
    if ((query as any).subscriptionTier) filter.subscriptionTier = (query as any).subscriptionTier;
    if (query.search) {
      const re = { $regex: query.search, $options: 'i' };
      filter.$or = [{ email: re }, { displayName: re }];
    }

    const [scouters, total] = await Promise.all([
      this.userModel
        .find(filter)
        .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      this.userModel.countDocuments(filter),
    ]);

    const scouterIds = (scouters as any[]).map((s: any) => String(s._id));
    const reportCounts = await this.reportModel.aggregate([
      { $match: { scouterId: { $in: scouterIds } } },
      { $group: { _id: '$scouterId', count: { $sum: 1 } } },
    ]);
    const reportMap: Record<string, number> = {};
    for (const r of reportCounts) reportMap[String(r._id)] = r.count;

    const now = new Date();
    const data = (scouters as any[]).map((s: any) => ({
      ...s,
      reportCount: reportMap[String(s._id)] ?? 0,
      isExpired: s.subscriptionExpiresAt ? new Date(s.subscriptionExpiresAt) < now : false,
      expiresInDays: s.subscriptionExpiresAt
        ? Math.ceil((new Date(s.subscriptionExpiresAt).getTime() - now.getTime()) / 86400000)
        : null,
    }));

    return { data, total, page, limit };
  }

  async getScouterDetail(id: string): Promise<any> {
    const scouter = await this.userModel
      .findById(id)
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!scouter || (scouter as any).role !== 'scouter') throw new NotFoundException('Scouter not found');

    const reports = await this.reportModel.find({ scouterId: String(id) }).sort({ createdAt: -1 }).lean();

    // Enrich reports with player names
    const playerIds = [...new Set((reports as any[]).map((r: any) => r.playerId))];
    const players = playerIds.length
      ? await this.userModel.find({ _id: { $in: playerIds } }).select('_id displayName email').lean()
      : [];
    const playerMap: Record<string, string> = {};
    for (const p of players as any[]) playerMap[String(p._id)] = p.displayName || p.email;

    const enrichedReports = (reports as any[]).map((r: any) => ({
      ...r,
      playerDisplayName: playerMap[String(r.playerId)] ?? 'Unknown',
    }));

    const now = new Date();
    const isExpired = (scouter as any).subscriptionExpiresAt
      ? new Date((scouter as any).subscriptionExpiresAt) < now
      : false;

    return { scouter, reports: enrichedReports, isExpired };
  }

  // ── Subscription management ───────────────────────────────────────────────

  async updateSubscription(id: string, dto: UpdateSubscriptionDto): Promise<any> {
    const update: Record<string, any> = {};
    if (dto.tier !== undefined) update.subscriptionTier = dto.tier;
    if (dto.expiresAt !== undefined) update.subscriptionExpiresAt = dto.expiresAt ? new Date(dto.expiresAt) : null;

    const user = await this.userModel
      .findByIdAndUpdate(id, update, { new: true })
      .select('-passwordHash -portraitData -badgeData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  // ── Analytics overview ────────────────────────────────────────────────────

  async getAdminAnalytics(): Promise<any> {
    const now = new Date();
    const thirtyDaysFromNow = new Date(now.getTime() + 30 * 86400000);

    const [
      activeSubscriptions,
      expiringSoon,
      bannedUsers,
      totalReports,
      topScouters,
      topPlayers,
      revenueByTier,
    ] = await Promise.all([
      this.userModel.countDocuments({ subscriptionTier: { $ne: null }, subscriptionExpiresAt: { $gt: now } }),
      this.userModel.countDocuments({
        subscriptionTier: { $ne: null },
        subscriptionExpiresAt: { $gt: now, $lte: thirtyDaysFromNow },
      }),
      this.userModel.countDocuments({ isBanned: true }),
      this.reportModel.countDocuments(),
      // Top 5 scouters by report count
      this.reportModel.aggregate([
        { $group: { _id: '$scouterId', reportCount: { $sum: 1 } } },
        { $sort: { reportCount: -1 } },
        { $limit: 5 },
      ]),
      // Top 5 players by report count (most scouted)
      this.reportModel.aggregate([
        { $group: { _id: '$playerId', reportCount: { $sum: 1 } } },
        { $sort: { reportCount: -1 } },
        { $limit: 5 },
      ]),
      // Revenue breakdown by tier
      this.userModel.aggregate([
        { $match: { subscriptionTier: { $ne: null } } },
        { $group: { _id: '$subscriptionTier', count: { $sum: 1 } } },
      ]),
    ]);

    // Resolve display names for top scouters
    const scouterIds = topScouters.map((s: any) => s._id);
    const scouterDocs = scouterIds.length
      ? await this.userModel.find({ _id: { $in: scouterIds } }).select('_id displayName email').lean()
      : [];
    const scouterNameMap: Record<string, string> = {};
    for (const s of scouterDocs as any[]) scouterNameMap[String(s._id)] = s.displayName || s.email;

    // Resolve display names for top players
    const playerIds = topPlayers.map((p: any) => p._id);
    const playerDocs = playerIds.length
      ? await this.userModel.find({ _id: { $in: playerIds } }).select('_id displayName email position').lean()
      : [];
    const playerNameMap: Record<string, any> = {};
    for (const p of playerDocs as any[]) playerNameMap[String(p._id)] = p;

    const revenueMap: Record<string, number> = { basic: 0, premium: 0, elite: 0 };
    const pricingMap: Record<string, number> = { basic: 1000, premium: 5000, elite: 10000 };
    for (const r of revenueByTier) if (r._id) revenueMap[r._id] = r.count;

    const revenueTotal = Object.entries(revenueMap).reduce(
      (sum, [tier, count]) => sum + (pricingMap[tier] ?? 0) * count, 0
    );

    return {
      activeSubscriptions,
      expiringSoon,
      bannedUsers,
      totalReports,
      revenueByTier: revenueMap,
      revenueTotal,
      topScouters: topScouters.map((s: any) => ({
        _id: s._id,
        displayName: scouterNameMap[String(s._id)] ?? 'Unknown',
        reportCount: s.reportCount,
      })),
      topPlayers: topPlayers.map((p: any) => ({
        _id: p._id,
        displayName: playerNameMap[String(p._id)]?.displayName || playerNameMap[String(p._id)]?.email || 'Unknown',
        position: playerNameMap[String(p._id)]?.position || '—',
        reportCount: p.reportCount,
      })),
    };
  }

  // ── Reports ──────────────────────────────────────────────────────────────

  async listAllReports(page = 1, limit = 20): Promise<{ data: any[]; total: number; page: number; limit: number }> {
    const p = Math.max(1, page);
    const l = Math.min(100, Math.max(1, limit));
    const skip = (p - 1) * l;

    const [data, total] = await Promise.all([
      this.reportModel.find().sort({ createdAt: -1 }).skip(skip).limit(l).lean(),
      this.reportModel.countDocuments(),
    ]);

    return { data, total, page: p, limit: l };
  }

  // ── Notifications ──────────────────────────────────────────────────────

  async broadcastNotification(dto: BroadcastNotificationDto): Promise<{ sent: number }> {
    const users = await this.userModel.find({}).select('_id').lean();
    if (!users.length) return { sent: 0 };

    const docs = users.map((u: any) => ({
      userId: String(u._id),
      type: 'admin_broadcast',
      titleEN: dto.titleEN,
      titleFR: dto.titleFR,
      bodyEN: dto.bodyEN || '',
      bodyFR: dto.bodyFR || '',
      data: {},
      read: false,
    }));

    await this.notifModel.insertMany(docs);
    return { sent: docs.length };
  }
}
