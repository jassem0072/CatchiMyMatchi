import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type NotificationDocument = HydratedDocument<Notification>;

@Schema({ timestamps: true })
export class Notification {
  @Prop({ required: true, index: true })
  userId!: string;

  /**
   * Types:
   * - challenge_completed  (player completed a challenge)
   * - player_challenge     (scouter: a followed player completed a challenge)
   * - analysis_ready       (analysis finished)
   * - favorited            (player was favorited by a scouter)
   */
  @Prop({ required: true })
  type!: string;

  @Prop({ required: true })
  titleEN!: string;

  @Prop({ required: true })
  titleFR!: string;

  @Prop({ default: '' })
  bodyEN!: string;

  @Prop({ default: '' })
  bodyFR!: string;

  @Prop({ type: Object, default: {} })
  data!: Record<string, unknown>;

  @Prop({ default: false })
  read!: boolean;
}

export const NotificationSchema = SchemaFactory.createForClass(Notification);
NotificationSchema.index({ userId: 1, createdAt: -1 });
