import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type TeamDocument = HydratedDocument<Team>;

@Schema({ timestamps: true })
export class Team {
  @Prop({ required: true, index: true })
  ownerId!: string;

  @Prop({ required: true })
  name!: string;

  /** Array of user IDs who are confirmed members (includes owner) */
  @Prop({ type: [String], default: [] })
  members!: string[];

  /** Pending invitation user IDs */
  @Prop({ type: [String], default: [] })
  pendingInvites!: string[];
}

export const TeamSchema = SchemaFactory.createForClass(Team);
TeamSchema.index({ ownerId: 1 });
TeamSchema.index({ members: 1 });
TeamSchema.index({ pendingInvites: 1 });
