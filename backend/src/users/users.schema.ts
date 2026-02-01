import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type UserDocument = HydratedDocument<User>;

export type UserRole = 'player' | 'scouter';

@Schema({ timestamps: true })
export class User {
  @Prop({ required: true, unique: true, lowercase: true, trim: true })
  email!: string;

  @Prop({ required: true })
  passwordHash!: string;

  @Prop({ required: true, enum: ['player', 'scouter'], default: 'player' })
  role!: UserRole;

  @Prop({ default: '' })
  displayName!: string;

  @Prop({ default: '', index: true })
  googleSub!: string;

  @Prop({ default: '' })
  position!: string;

  @Prop({ default: '' })
  nation!: string;

  @Prop({ default: '' })
  portraitFile!: string;

  @Prop({ type: Buffer, default: null })
  portraitData!: Buffer | null;

  @Prop({ default: '' })
  portraitContentType!: string;

  @Prop({ default: '' })
  resetPasswordTokenHash!: string;

  @Prop({ type: Date, default: null })
  resetPasswordExpiresAt!: Date | null;
}

export const UserSchema = SchemaFactory.createForClass(User);
