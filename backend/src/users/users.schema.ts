import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type UserDocument = HydratedDocument<User>;

export type UserRole = 'player' | 'scouter' | 'admin';
export type SubscriptionTier = 'basic' | 'premium' | 'elite';

@Schema({ timestamps: true })
export class User {
  @Prop({ required: true, unique: true, lowercase: true, trim: true })
  email!: string;

  @Prop({ required: true })
  passwordHash!: string;

  @Prop({ required: true, enum: ['player', 'scouter', 'admin'], default: 'player' })
  role!: UserRole;

  @Prop({ default: '' })
  displayName!: string;

  @Prop({ default: '', index: true })
  googleSub!: string;

  @Prop({ default: '' })
  position!: string;

  @Prop({ default: '' })
  nation!: string;

  @Prop({ type: Date, default: null })
  dateOfBirth!: Date | null;

  @Prop({ type: Number, default: null })
  height!: number | null;

  @Prop({ default: '' })
  portraitFile!: string;

  @Prop({ type: Buffer, default: null })
  portraitData!: Buffer | null;

  @Prop({ default: '' })
  portraitContentType!: string;

  @Prop({ type: Buffer, default: null })
  badgeData!: Buffer | null;

  @Prop({ default: '' })
  badgeContentType!: string;

  @Prop({ default: false })
  badgeVerified!: boolean;

  @Prop({ default: false })
  emailVerified!: boolean;

  @Prop({ default: '' })
  emailVerificationToken!: string;

  @Prop({ default: '' })
  resetPasswordTokenHash!: string;

  @Prop({ type: Date, default: null })
  resetPasswordExpiresAt!: Date | null;

  @Prop({ default: '' })
  stripePaymentIntentId!: string;

  @Prop({ type: Date, default: null })
  upgradedAt!: Date | null;

  @Prop({ type: String, enum: ['basic', 'premium', 'elite'], default: null })
  subscriptionTier!: SubscriptionTier | null;

  @Prop({ type: Date, default: null })
  subscriptionExpiresAt!: Date | null;

  @Prop({ type: Date, default: null })
  basicExpiresAt!: Date | null;

  @Prop({ type: Date, default: null })
  premiumExpiresAt!: Date | null;

  @Prop({ type: Date, default: null })
  eliteExpiresAt!: Date | null;

  @Prop({ default: false })
  isBanned!: boolean;
}

export const UserSchema = SchemaFactory.createForClass(User);
