import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type UserDocument = HydratedDocument<User>;

export type UserRole = 'player' | 'scouter' | 'admin' | 'expert';
export type SubscriptionTier = 'basic' | 'premium' | 'elite';

type ExpertPayoutInvoiceStatus = 'requested' | 'processing' | 'paid';

type ExpertPayoutInvoice = {
  invoiceId: string;
  amountEur: number;
  claimedPlayers: number;
  requestedAt: Date;
  expectedPaymentAt: Date;
  payoutProvider: 'paypal' | 'bank_transfer' | 'legacy_card';
  payoutDestinationMasked: string;
  transactionReference: string;
  status: ExpertPayoutInvoiceStatus;
};

@Schema({ timestamps: true })
export class User {
  @Prop({ required: true, unique: true, lowercase: true, trim: true })
  email!: string;

  @Prop({ required: true })
  passwordHash!: string;

  @Prop({ required: true, enum: ['player', 'scouter', 'admin', 'expert'], default: 'player' })
  role!: UserRole;

  @Prop({ type: Object, default: null })
  adminWorkflow!: {
    sentVideoRequests: number;
    verificationStatus: 'not_requested' | 'pending_expert' | 'verified' | 'rejected';
    scouterDecision: 'pending' | 'approved' | 'cancelled';
    expertDecision: 'pending' | 'approved' | 'cancelled';
    expertReport: string;
    fixedPrice: number;
    preContractStatus: 'none' | 'draft' | 'approved' | 'cancelled';
    contractSignedByPlayer: boolean;
    contractSignedAt: Date | null;
    onlineSessionCompleted: boolean;
    onlineSessionCompletedAt: Date | null;
    updatedAt: Date;
  } | null;

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
  playerIdNumber!: string;

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

  @Prop({ type: Buffer, default: null })
  medicalDiplomaData!: Buffer | null;

  @Prop({ default: '' })
  medicalDiplomaContentType!: string;

  @Prop({ default: '' })
  medicalDiplomaFileName!: string;

  @Prop({ type: Buffer, default: null })
  bulletinN3Data!: Buffer | null;

  @Prop({ default: '' })
  bulletinN3ContentType!: string;

  @Prop({ default: '' })
  bulletinN3FileName!: string;

  @Prop({ type: Buffer, default: null })
  playerIdDocumentData!: Buffer | null;

  @Prop({ default: '' })
  playerIdDocumentContentType!: string;

  @Prop({ default: '' })
  playerIdDocumentFileName!: string;

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

  @Prop({ enum: ['none', 'pending', 'approved', 'rejected'], default: 'none' })
  adminAccessRequestStatus!: 'none' | 'pending' | 'approved' | 'rejected';

  @Prop({ type: Date, default: null })
  adminAccessRequestedAt!: Date | null;

  @Prop({ type: Date, default: null })
  adminAccessApprovedAt!: Date | null;

  @Prop({ type: Object, default: null })
  communicationQuiz!: {
    language?: string;
    score?: number;
    totalQuestions?: number;
    scorePercent?: number;
    readinessBand?: string;
    communicationStyle?: string;
    captaincySummary?: string;
    languages?: string[];
    completedAt?: Date;
  } | null;

  @Prop({ type: Date, default: null })
  expertPayoutUpdatedAt!: Date | null;

  @Prop({ type: [Object], default: [] })
  expertPayoutInvoices!: ExpertPayoutInvoice[];
}

export const UserSchema = SchemaFactory.createForClass(User);
