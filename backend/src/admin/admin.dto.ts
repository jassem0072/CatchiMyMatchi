import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class AdminUserQueryDto {
  @ApiPropertyOptional() page?: number;
  @ApiPropertyOptional() limit?: number;
  @ApiPropertyOptional() search?: string;
  @ApiPropertyOptional({ enum: ['player', 'scouter', 'admin'] }) role?: string;
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
  @ApiProperty({ enum: ['player', 'scouter', 'admin'] }) role!: 'player' | 'scouter' | 'admin';
}
