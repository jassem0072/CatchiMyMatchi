import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class RegisterDto {
  @ApiProperty()
  email!: string;

  @ApiProperty()
  password!: string;

  @ApiPropertyOptional()
  displayName?: string;

  @ApiPropertyOptional()
  position?: string;

  @ApiPropertyOptional()
  nation?: string;
}

export class RegisterAdminRequestDto {
  @ApiProperty()
  email!: string;

  @ApiProperty()
  password!: string;

  @ApiPropertyOptional()
  displayName?: string;
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

  @ApiPropertyOptional({ description: 'Optional display name override for first-time users' })
  displayName?: string;
}

export class GoogleWebAuthDto {
  @ApiProperty({ description: 'Google-verified email from GIS sign-in on web' })
  email!: string;

  @ApiPropertyOptional({ description: 'Display name from Google account' })
  displayName?: string;

  @ApiPropertyOptional({ description: 'Role for new users (player or scouter)' })
  role?: string;
}

export class AdminGoogleLoginDto {
  @ApiPropertyOptional({ description: 'Google ID token from GIS sign-in on web' })
  idToken?: string;

  @ApiPropertyOptional({ description: 'Google access token fallback' })
  accessToken?: string;

  @ApiPropertyOptional({ description: 'Optional display name override for first-time linkage' })
  displayName?: string;
}

export class UpdateAuthProfileDto {
  @ApiPropertyOptional()
  displayName?: string;

  @ApiPropertyOptional()
  position?: string;

  @ApiPropertyOptional()
  nation?: string;

  @ApiPropertyOptional()
  dateOfBirth?: string;

  @ApiPropertyOptional()
  height?: number;

  @ApiPropertyOptional()
  playerIdNumber?: string;
}

export class ChangeAuthPasswordDto {
  @ApiProperty()
  currentPassword!: string;

  @ApiProperty()
  newPassword!: string;
}

export class AuthTokenResponse {
  @ApiProperty()
  accessToken!: string;
}
