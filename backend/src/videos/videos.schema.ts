import { Prop, Schema, SchemaFactory } from "@nestjs/mongoose";
import { HydratedDocument } from "mongoose";

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

  /** Per-player analysis results keyed by playerId (for tagged players) */
  @Prop({ type: Object, default: {} })
  playerAnalyses?: Record<string, Record<string, unknown>>;

  /** Player screen-selection used during analysis, keyed by playerId.
   *  Each entry: { frameTime: number; normX: number; normY: number } */
  @Prop({ type: Object, default: {} })
  playerSelections?: Record<
    string,
    { frameTime: number; normX: number; normY: number }
  >;

  /** IDs of teammates tagged in this video */
  @Prop({ type: [String], default: [] })
  taggedPlayers!: string[];

  /** IDs of teams tagged in this video */
  @Prop({ type: [String], default: [] })
  taggedTeams!: string[];

  /** 'public' = visible to scouts, 'private' = only owner & tagged players */
  @Prop({ default: "public", enum: ["public", "private"] })
  visibility!: string;

  /** Montage highlight reel filename (stored in uploads dir) */
  @Prop({ type: String, default: null })
  montageFilename?: string | null;

  /** Relative path to the montage file */
  @Prop({ type: String, default: null })
  montageRelativePath?: string | null;

  /** When the montage was generated */
  @Prop()
  montageGeneratedAt?: Date;
}

export const VideoSchema = SchemaFactory.createForClass(Video);
VideoSchema.index({ ownerId: 1, createdAt: -1 });
