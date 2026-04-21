import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { ChallengeProgress, ChallengeProgressDocument } from './challenges.schema';

/** Static definition of every challenge in the app */
export interface ChallengeDef {
  key: string;
  target: number;
  icon: string;
  titleEN: string;
  titleFR: string;
  descEN: string;
  descFR: string;
}

export const CHALLENGE_DEFS: ChallengeDef[] = [
  {
    key: 'first_upload',
    target: 1,
    icon: 'upload_file',
    titleEN: 'First Upload',
    titleFR: 'Premier envoi',
    descEN: 'Upload your first video for analysis',
    descFR: "Envoyer votre première vidéo d'analyse",
  },
  {
    key: 'speed_demon',
    target: 1,
    icon: 'speed',
    titleEN: 'Speed Demon',
    titleFR: 'Démon de la vitesse',
    descEN: 'Reach a top speed of 30 km/h',
    descFR: 'Atteindre une vitesse maximale de 30 km/h',
  },
  {
    key: 'marathon_runner',
    target: 50,
    icon: 'directions_run',
    titleEN: 'Marathon Runner',
    titleFR: 'Marathonien',
    descEN: 'Cover 50 km total across all matches',
    descFR: '50 km parcourus au total',
  },
  {
    key: 'sprint_king',
    target: 100,
    icon: 'bolt',
    titleEN: 'Sprint King',
    titleFR: 'Roi du sprint',
    descEN: 'Complete 100 sprints total',
    descFR: '100 sprints au total',
  },
  {
    key: 'analyst',
    target: 10,
    icon: 'videocam',
    titleEN: 'Analyst',
    titleFR: 'Analyste',
    descEN: 'Analyze 10 match videos',
    descFR: '10 vidéos analysées',
  },
  {
    key: 'rising_star',
    target: 5,
    icon: 'star',
    titleEN: 'Rising Star',
    titleFR: 'Étoile montante',
    descEN: 'Get favorited by 5 scouters',
    descFR: 'Être suivi par 5 recruteurs',
  },
];

@Injectable()
export class ChallengesService {
  constructor(
    @InjectModel(ChallengeProgress.name) private readonly model: Model<ChallengeProgressDocument>,
  ) {}

  /** Get all challenge progress for a user, bootstrapping any missing rows */
  async getAll(userId: string): Promise<ChallengeProgress[]> {
    let rows = await this.model.find({ userId }).lean();

    // Bootstrap missing challenge rows
    const existing = new Set(rows.map((r) => r.challengeKey));
    const missing = CHALLENGE_DEFS.filter((d) => !existing.has(d.key));
    if (missing.length) {
      const inserts = missing.map((d) => ({
        userId,
        challengeKey: d.key,
        progress: 0,
        target: d.target,
        completed: false,
        completedAt: null,
      }));
      await this.model.insertMany(inserts, { ordered: false }).catch(() => {});
      rows = await this.model.find({ userId }).lean();
    }
    return rows;
  }

  /**
   * Increment (or set) progress for one challenge.
   * Returns the updated doc + whether the challenge was NEWLY completed.
   */
  async incrementProgress(
    userId: string,
    challengeKey: string,
    delta: number,
  ): Promise<{ doc: ChallengeProgress; newlyCompleted: boolean }> {
    const def = CHALLENGE_DEFS.find((d) => d.key === challengeKey);
    if (!def) throw new Error(`Unknown challenge: ${challengeKey}`);

    // Upsert row
    let doc = await this.model.findOneAndUpdate(
      { userId, challengeKey },
      { $setOnInsert: { target: def.target, completed: false, completedAt: null } },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    );
    if (!doc) throw new Error('challenge upsert failed');

    if (doc.completed) return { doc: doc.toObject(), newlyCompleted: false };

    doc.progress = Math.min(doc.progress + delta, def.target);
    const justCompleted = doc.progress >= def.target && !doc.completed;
    if (justCompleted) {
      doc.completed = true;
      doc.completedAt = new Date();
    }
    await doc.save();
    return { doc: doc.toObject(), newlyCompleted: justCompleted };
  }

  /** Direct set for challenges like "speed_demon" or "rising_star" */
  async setProgress(
    userId: string,
    challengeKey: string,
    value: number,
  ): Promise<{ doc: ChallengeProgress; newlyCompleted: boolean }> {
    const def = CHALLENGE_DEFS.find((d) => d.key === challengeKey);
    if (!def) throw new Error(`Unknown challenge: ${challengeKey}`);

    let doc = await this.model.findOneAndUpdate(
      { userId, challengeKey },
      { $setOnInsert: { target: def.target, completed: false, completedAt: null } },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    );
    if (!doc) throw new Error('challenge upsert failed');

    if (doc.completed) return { doc: doc.toObject(), newlyCompleted: false };

    doc.progress = Math.min(value, def.target);
    const justCompleted = doc.progress >= def.target;
    if (justCompleted) {
      doc.completed = true;
      doc.completedAt = new Date();
    }
    await doc.save();
    return { doc: doc.toObject(), newlyCompleted: justCompleted };
  }

  /** Count how many scouters have favorited a player (for rising_star) */
  async countFavoriters(playerId: string): Promise<number> {
    // We'll call this from a higher-level service that injects FavoritesModel
    // For now this is a helper placeholder
    return 0;
  }
}
