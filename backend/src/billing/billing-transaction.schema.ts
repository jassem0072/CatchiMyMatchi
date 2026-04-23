import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type BillingTransactionDocument = HydratedDocument<BillingTransaction>;

export type BillingTransactionDirection = 'payment' | 'payout';
export type BillingTransactionStatus = 'requested' | 'processing' | 'succeeded' | 'failed';
export type BillingTransactionType = 'subscription_payment' | 'expert_payout_request';

@Schema({ timestamps: true, collection: 'billing_transactions' })
export class BillingTransaction {
  @Prop({ required: true, index: true })
  userId!: string;

  @Prop({ required: true, enum: ['payment', 'payout'], index: true })
  direction!: BillingTransactionDirection;

  @Prop({ required: true, enum: ['subscription_payment', 'expert_payout_request'], index: true })
  type!: BillingTransactionType;

  @Prop({ required: true })
  amountEur!: number;

  @Prop({ required: true, default: 'EUR' })
  currency!: string;

  @Prop({ required: true, enum: ['requested', 'processing', 'succeeded', 'failed'], index: true })
  status!: BillingTransactionStatus;

  @Prop({ required: true, index: true })
  reference!: string;

  @Prop({ default: '' })
  provider!: string;

  @Prop({ type: Object, default: {} })
  metadata!: Record<string, unknown>;
}

export const BillingTransactionSchema = SchemaFactory.createForClass(BillingTransaction);
BillingTransactionSchema.index({ userId: 1, createdAt: -1 });
BillingTransactionSchema.index({ type: 1, createdAt: -1 });
