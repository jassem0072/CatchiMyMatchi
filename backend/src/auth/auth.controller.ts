import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { UsersService } from '../users/users.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AuthService } from './auth.service';
import {
  AuthTokenResponse,
  ForgotPasswordDto,
  ForgotPasswordResponse,
  GoogleAuthDto,
  LoginDto,
  OkResponse,
  RegisterDto,
  ResetPasswordDto,
} from './auth.dto';
import type { RequestUser } from './request-user';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly users: UsersService,
  ) {}

  @Post('register')
  async register(@Body() dto: RegisterDto): Promise<AuthTokenResponse> {
    const role = dto.role || 'player';
    return this.auth.register({
      email: dto.email,
      password: dto.password,
      role,
      displayName: dto.displayName,
      position: dto.position,
      nation: dto.nation,
    });
  }

  @Post('signup')
  async signup(@Body() dto: RegisterDto): Promise<AuthTokenResponse> {
    return this.register(dto);
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
      role: dto.role,
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
}
