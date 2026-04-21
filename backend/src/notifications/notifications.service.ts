import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import {
  Notification,
  NotificationDocument,
} from './notifications.schema';

@Injectable()
export class NotificationsService {
  constructor(
    @InjectModel(Notification.name) private readonly model: Model<NotificationDocument>,
  ) {}

  async create(data: Partial<Notification>): Promise<Notification> {
    const doc = await this.model.create(data);
    return doc.toObject();
  }

  async list(userId: string, limit = 50): Promise<Notification[]> {
    return this.model
      .find({ userId })
      .sort({ createdAt: -1 })
      .limit(limit)
      .lean();
  }

  async unreadCount(userId: string): Promise<number> {
    return this.model.countDocuments({ userId, read: false });
  }

  async markRead(userId: string, notificationId: string): Promise<void> {
    await this.model.updateOne({ _id: notificationId, userId }, { read: true });
  }

  async markAllRead(userId: string): Promise<void> {
    await this.model.updateMany({ userId, read: false }, { read: true });
  }

  // ──── Convenience creators ────

  async notifyChallengeCompleted(
    userId: string,
    challengeTitleEN: string,
    challengeTitleFR: string,
  ): Promise<Notification> {
    return this.create({
      userId,
      type: 'challenge_completed',
      titleEN: 'Challenge Completed! 🏆',
      titleFR: 'Défi terminé ! 🏆',
      bodyEN: `You completed the "${challengeTitleEN}" challenge!`,
      bodyFR: `Vous avez terminé le défi "${challengeTitleFR}" !`,
      data: { challengeTitleEN },
    });
  }

  /** Notify a scouter that a player they follow completed a challenge */
  async notifyScouterPlayerChallenge(
    scouterId: string,
    playerName: string,
    challengeTitleEN: string,
    challengeTitleFR: string,
  ): Promise<Notification> {
    return this.create({
      userId: scouterId,
      type: 'player_challenge',
      titleEN: `${playerName} completed a challenge!`,
      titleFR: `${playerName} a terminé un défi !`,
      bodyEN: `${playerName} completed "${challengeTitleEN}".`,
      bodyFR: `${playerName} a terminé "${challengeTitleFR}".`,
      data: { playerName, challengeTitleEN },
    });
  }

  async notifyAnalysisReady(userId: string, videoName: string): Promise<Notification> {
    return this.create({
      userId,
      type: 'analysis_ready',
      titleEN: 'Analysis Ready',
      titleFR: 'Analyse prête',
      bodyEN: `Your analysis for "${videoName}" is ready.`,
      bodyFR: `L'analyse de "${videoName}" est prête.`,
      data: { videoName },
    });
  }

  async notifyVideoTag(
    taggedUserId: string,
    uploaderName: string,
    videoId: string,
    videoName: string,
  ): Promise<Notification> {
    return this.create({
      userId: taggedUserId,
      type: 'video_tag',
      titleEN: 'You were tagged in a video!',
      titleFR: 'Vous avez été tagué dans une vidéo !',
      bodyEN: `${uploaderName} tagged you in "${videoName}".`,
      bodyFR: `${uploaderName} vous a tagué dans "${videoName}".`,
      data: { videoId, uploaderName, videoName },
    });
  }

  async notifyFavorited(playerId: string, scouterName: string): Promise<Notification> {
    return this.create({
      userId: playerId,
      type: 'favorited',
      titleEN: 'New follower!',
      titleFR: 'Nouveau suiveur !',
      bodyEN: `${scouterName} added you to favorites.`,
      bodyFR: `${scouterName} vous a ajouté en favoris.`,
      data: { scouterName },
    });
  }

  /** Notify a player that a scouter wants a specific video */
  async notifyVideoRequest(
    playerId: string,
    scouterId: string,
    scouterName: string,
    message: string,
  ): Promise<Notification> {
    return this.create({
      userId: playerId,
      type: 'video_request',
      titleEN: '📹 Video Request from a Scout',
      titleFR: '📹 Demande de vidéo d\'un Scout',
      bodyEN: message,
      bodyFR: message,
      data: { scouterId, message },
    });
  }
}
