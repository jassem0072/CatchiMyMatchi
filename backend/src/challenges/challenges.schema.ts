import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type ChallengeProgressDocument = HydratedDocument<ChallengeProgress>;

/**
 * Each row tracks one user's progress on one challenge.
 * `challengeKey` is a fixed string like 'first_upload', 'speed_demon', etc.
 */
@Schema({ timestamps: true })
export class ChallengeProgress {
  @Prop({ required: true, index: true })
  userId!: string;

  @Prop({ required: true })
  challengeKey!: string;

  @Prop({ default: 0 })
  progress!: number;

  @Prop({ required: true })
  target!: number;

  @Prop({ default: false })
  completed!: boolean;

  @Prop({ type: Date, default: null })
  completedAt!: Date | null;
}

export const ChallengeProgressSchema = SchemaFactory.createForClass(ChallengeProgress);
ChallengeProgressSchema.index({ userId: 1, challengeKey: 1 }, { unique: true });
