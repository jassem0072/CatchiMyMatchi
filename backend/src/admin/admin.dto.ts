import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class AdminUserQueryDto {
  @ApiPropertyOptional() page?: number;
  @ApiPropertyOptional() limit?: number;
  @ApiPropertyOptional() search?: string;
  @ApiPropertyOptional({ enum: ['player', 'scouter', 'admin', 'expert'] }) role?: string;
}

export class BroadcastNotificationDto {
  @ApiProperty() titleEN!: string;
  @ApiProperty() titleFR!: string;
  @ApiPropertyOptional() bodyEN?: string;
  @ApiPropertyOptional() bodyFR?: string;
}

export class SetVideoVisibilityDto {
  @ApiProperty({ enum: ['public', 'private'] }) visibility!: 'public' | 'private';
}

export class UpdateSubscriptionDto {
  @ApiPropertyOptional({ enum: ['basic', 'premium', 'elite'] }) tier?: 'basic' | 'premium' | 'elite' | null;
  @ApiPropertyOptional() expiresAt?: string | null;
}

export class UpdateUserRoleDto {
  @ApiProperty({ enum: ['player', 'scouter', 'admin', 'expert'] }) role!: 'player' | 'scouter' | 'admin' | 'expert';
}

export class ExpertReviewDto {
  @ApiProperty({ enum: ['approved', 'cancelled'] }) decision!: 'approved' | 'cancelled';
  @ApiPropertyOptional() report?: string;
}

export class ScouterDecisionDto {
  @ApiProperty({ enum: ['approved', 'cancelled'] }) decision!: 'approved' | 'cancelled';
}

export class ClaimEarningsDto {
  @ApiProperty({ enum: ['paypal', 'bank_transfer'] })
  payoutProvider!: 'paypal' | 'bank_transfer';

  @ApiProperty({ description: 'Account holder full name used for payout billing.' })
  accountHolderName!: string;

  @ApiProperty({ description: 'Bank name for payout billing.' })
  bankName!: string;

  @ApiPropertyOptional({ description: 'IBAN or bank account number used for payout.' })
  bankAccountOrIban?: string;

  @ApiPropertyOptional({ description: 'SWIFT / BIC code for international bank transfers.' })
  swiftBic?: string;

  @ApiPropertyOptional({
    description: 'Legacy safe payout destination reference (for example Stripe account ID or PayPal payout email).',
  })
  payoutAccountRef?: string;

  @ApiPropertyOptional({
    description: 'Optional provider transaction/reference ID. Do not include card numbers.',
  })
  transactionReference?: string;
}

export class BillingTransactionQueryDto {
  @ApiPropertyOptional() page?: number;
  @ApiPropertyOptional() limit?: number;
  @ApiPropertyOptional() userId?: string;
  @ApiPropertyOptional({ enum: ['payment', 'payout'] }) direction?: 'payment' | 'payout';
  @ApiPropertyOptional({ enum: ['subscription_payment', 'expert_payout_request'] })
  type?: 'subscription_payment' | 'expert_payout_request';
}

export class PreContractDto {
  @ApiPropertyOptional() fixedPrice?: number;
  @ApiPropertyOptional({ enum: ['none', 'draft', 'approved', 'cancelled'] })
  status?: 'none' | 'draft' | 'approved' | 'cancelled';
  @ApiPropertyOptional() markPlatformFeePaid?: boolean;
  @ApiPropertyOptional() cardNumber?: string;
  @ApiPropertyOptional() expMonth?: number;
  @ApiPropertyOptional() expYear?: number;
  @ApiPropertyOptional() cvc?: string;

  @ApiPropertyOptional() clubName?: string;
  @ApiPropertyOptional() clubOfficialName?: string;
  @ApiPropertyOptional() startDate?: string;
  @ApiPropertyOptional() endDate?: string;
  @ApiPropertyOptional() currency?: string;
  @ApiPropertyOptional() salaryPeriod?: 'monthly' | 'weekly';
  @ApiPropertyOptional() fixedBaseSalary?: number;
  @ApiPropertyOptional() signingOnFee?: number;
  @ApiPropertyOptional() marketValue?: number;
  @ApiPropertyOptional() bonusPerAppearance?: number;
  @ApiPropertyOptional() bonusGoalOrCleanSheet?: number;
  @ApiPropertyOptional() bonusTeamTrophy?: number;
  @ApiPropertyOptional() releaseClauseAmount?: number;
  @ApiPropertyOptional() terminationForCauseText?: string;
  @ApiPropertyOptional() scouterIntermediaryId?: string;
  @ApiPropertyOptional() scouterSignNow?: boolean;
  @ApiPropertyOptional() scouterSignatureImageBase64?: string;
  @ApiPropertyOptional() scouterSignatureImageContentType?: string;
  @ApiPropertyOptional() scouterSignatureImageFileName?: string;
}
