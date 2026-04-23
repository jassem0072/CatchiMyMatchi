import { BadRequestException, Body, Controller, Get, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { UsersService } from '../users/users.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AuthService } from './auth.service';
import {
  AdminGoogleLoginDto,
  AuthTokenResponse,
  ChangeAuthPasswordDto,
  ForgotPasswordDto,
  ForgotPasswordResponse,
  GoogleAuthDto,
  GoogleWebAuthDto,
  LoginDto,
  OkResponse,
  RegisterDto,
  RegisterAdminRequestDto,
  ResetPasswordDto,
  UpdateAuthProfileDto,
} from './auth.dto';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';
import type { RequestUser } from './request-user';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly users: UsersService,
  ) {}

  @Post('register')
  async register(@Body() dto: RegisterDto) {
    return this.auth.register({
      email: dto.email,
      password: dto.password,
      role: 'player',
      displayName: dto.displayName,
      position: dto.position,
      nation: dto.nation,
    });
  }

  @Post('signup')
  async signup(@Body() dto: RegisterDto) {
    return this.register(dto);
  }

  @Post('register-expert')
  async registerExpert(@Body() dto: RegisterDto) {
    return this.auth.registerExpert({
      email: dto.email,
      password: dto.password,
      displayName: dto.displayName,
      position: dto.position,
      nation: dto.nation,
    });
  }

  @Post('request-admin-access')
  async requestAdminAccess(@Body() dto: RegisterAdminRequestDto) {
    return this.auth.requestAdminAccess({
      email: dto.email,
      password: dto.password,
      displayName: dto.displayName,
    });
  }

  @Post('login')
  async login(@Body() dto: LoginDto): Promise<AuthTokenResponse> {
    return this.auth.login(dto.email, dto.password);
  }

  @Post('signin')
  async signin(@Body() dto: LoginDto): Promise<AuthTokenResponse> {
    return this.login(dto);
  }

  @Post('google')
  async google(@Body() dto: GoogleAuthDto): Promise<AuthTokenResponse> {
    return this.auth.loginWithGoogle({
      idToken: dto.idToken,
      accessToken: dto.accessToken,
      role: 'player',
      displayName: dto.displayName,
    });
  }

  @Post('google-web')
  async googleWeb(@Body() dto: GoogleWebAuthDto): Promise<AuthTokenResponse> {
    return this.auth.loginWithGoogleWeb({
      email: dto.email,
      displayName: dto.displayName,
      role: (dto.role as any) || 'player',
    });
  }

  @Post('admin-google-login')
  async adminGoogleLogin(@Body() dto: AdminGoogleLoginDto): Promise<AuthTokenResponse> {
    return this.auth.adminLoginWithGoogle({
      idToken: dto.idToken,
      accessToken: dto.accessToken,
      displayName: dto.displayName,
    });
  }

  @Post('forgot-password')
  async forgotPassword(@Body() dto: ForgotPasswordDto): Promise<ForgotPasswordResponse> {
    return this.auth.requestPasswordReset(dto.email);
  }

  @Post('reset-password')
  async resetPassword(@Body() dto: ResetPasswordDto): Promise<OkResponse> {
    await this.auth.resetPassword(dto.email, dto.token, dto.newPassword);
    return { ok: true };
  }

  @Post('verify-code')
  async verifyCode(@Body() body: { email: string; code: string }): Promise<AuthTokenResponse> {
    if (!body.email) throw new BadRequestException('email is required');
    if (!body.code) throw new BadRequestException('code is required');
    return this.auth.verifyEmailCode(body.email, body.code);
  }

  @Post('resend-code')
  async resendCode(@Body() body: { email: string }) {
    if (!body.email) throw new BadRequestException('email is required');
    return this.auth.resendVerificationCode(body.email);
  }

  @Post('admin-login')
  async adminLogin(@Body() dto: LoginDto): Promise<AuthTokenResponse> {
    return this.auth.adminLogin(dto.email, dto.password);
  }

  @Post('bootstrap-admin')
  async bootstrapAdmin(
    @Body() body: { email: string; password: string; token: string; displayName?: string },
  ): Promise<AuthTokenResponse> {
    if (!body.email) throw new BadRequestException('email is required');
    if (!body.password) throw new BadRequestException('password is required');
    if (!body.token) throw new BadRequestException('token is required');
    return this.auth.bootstrapAdmin(body);
  }

  @Get('me')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  async me(@Req() req: { user?: RequestUser }) {
    const u = req.user;
    if (!u) return null;
    const db = await this.users.getById(u.sub);
    const { passwordHash, ...safe } = db as any;
    return safe;
  }

  @Patch('me')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'expert')
  async updateMe(
    @Req() req: { user?: RequestUser },
    @Body() dto: UpdateAuthProfileDto,
  ) {
    const u = req.user;
    if (!u) throw new BadRequestException('Not authenticated');
    return this.users.updateProfile(u.sub, {
      displayName: dto.displayName,
      position: dto.position,
      nation: dto.nation,
      dateOfBirth: dto.dateOfBirth,
      height: dto.height,
      playerIdNumber: dto.playerIdNumber,
    });
  }

  @Patch('me/password')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'expert')
  async updateMyPassword(
    @Req() req: { user?: RequestUser },
    @Body() dto: ChangeAuthPasswordDto,
  ): Promise<OkResponse> {
    const u = req.user;
    if (!u) throw new BadRequestException('Not authenticated');
    if (!dto.currentPassword || !dto.newPassword) {
      throw new BadRequestException('currentPassword and newPassword are required');
    }
    await this.users.changePassword(u.sub, dto.currentPassword, dto.newPassword);
    return { ok: true };
  }
}
