import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type VideoDocument = HydratedDocument<Video>;

@Schema({ timestamps: true })
export class Video {
  @Prop({ type: String, default: null, index: true })
  ownerId?: string | null;

  @Prop({ required: true })
  filename!: string;

  @Prop({ required: true })
  originalName!: string;

  @Prop({ required: true })
  mimeType!: string;

  @Prop({ required: true })
  size!: number;

  @Prop({ required: true })
  relativePath!: string;

  @Prop({ type: Object, default: null })
  lastAnalysis?: Record<string, unknown> | null;

  @Prop()
  lastAnalysisAt?: Date;
}

export const VideoSchema = SchemaFactory.createForClass(Video);
VideoSchema.index({ ownerId: 1, createdAt: -1 });
