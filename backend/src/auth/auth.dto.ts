import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

import type { UserRole } from '../users/users.schema';

export class RegisterDto {
  @ApiProperty()
  email!: string;

  @ApiProperty()
  password!: string;

  @ApiPropertyOptional({ enum: ['player', 'scouter'] })
  role?: UserRole;

  @ApiPropertyOptional()
  displayName?: string;

  @ApiPropertyOptional()
  position?: string;

  @ApiPropertyOptional()
  nation?: string;
}

export class LoginDto {
  @ApiProperty()
  email!: string;

  @ApiProperty()
  password!: string;
}

export class ForgotPasswordDto {
  @ApiProperty()
  email!: string;
}

export class ForgotPasswordResponse {
  @ApiProperty()
  ok!: boolean;
}

export class ResetPasswordDto {
  @ApiProperty()
  email!: string;

  @ApiProperty({ description: 'Reset token obtained from forgot-password step' })
  token!: string;

  @ApiProperty({ description: 'New password (min 6 chars)' })
  newPassword!: string;
}

export class OkResponse {
  @ApiProperty()
  ok!: boolean;
}

export class GoogleAuthDto {
  @ApiPropertyOptional({ description: 'Google ID token from client (google_sign_in)' })
  idToken?: string;

  @ApiPropertyOptional({ description: 'Google access token from client (fallback when idToken is not available)' })
  accessToken?: string;

  @ApiPropertyOptional({ enum: ['player', 'scouter'], description: 'Optional role for first-time users' })
  role?: UserRole;

  @ApiPropertyOptional({ description: 'Optional display name override for first-time users' })
  displayName?: string;
}

export class AuthTokenResponse {
  @ApiProperty()
  accessToken!: string;
}
