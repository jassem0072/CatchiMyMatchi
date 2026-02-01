import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type ReportDocument = HydratedDocument<Report>;

@Schema({ timestamps: true })
export class Report {
  @Prop({ required: true, index: true })
  scouterId!: string;

  @Prop({ required: true, index: true })
  playerId!: string;

  @Prop({ type: String, default: null })
  videoId?: string | null;

  @Prop({ default: '' })
  title!: string;

  @Prop({ default: '' })
  notes!: string;

  @Prop({ type: Object, default: null })
  analysisSnapshot?: Record<string, unknown> | null;

  @Prop({ type: Object, default: null })
  cardSnapshot?: Record<string, unknown> | null;
}

export const ReportSchema = SchemaFactory.createForClass(Report);
