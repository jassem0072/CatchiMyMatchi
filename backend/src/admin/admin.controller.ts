import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { AdminService } from './admin.service';
import {
  AdminUserQueryDto,
  BroadcastNotificationDto,
  SetVideoVisibilityDto,
  UpdateSubscriptionDto,
  UpdateUserRoleDto,
} from './admin.dto';

@ApiTags('admin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('admin')
@Controller('admin')
export class AdminController {
  constructor(private readonly admin: AdminService) { }

  // ── Users ──
  @Get('users')
  getUsers(@Query() query: AdminUserQueryDto) {
    return this.admin.listUsers(query);
  }

  @Delete('users/:id')
  deleteUser(@Param('id') id: string) {
    return this.admin.deleteUser(id);
  }

  @Patch('users/:id/ban')
  banUser(@Param('id') id: string) {
    return this.admin.banUser(id, true);
  }

  @Patch('users/:id/unban')
  unbanUser(@Param('id') id: string) {
    return this.admin.banUser(id, false);
  }

  @Patch('users/:id/role')
  updateUserRole(@Param('id') id: string, @Body() dto: UpdateUserRoleDto) {
    return this.admin.updateUserRole(id, dto.role);
  }

  @Patch('users/:id/subscription')
  updateSubscription(@Param('id') id: string, @Body() dto: UpdateSubscriptionDto) {
    return this.admin.updateSubscription(id, dto);
  }

  // ── Videos ──
  @Get('videos')
  getVideos(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.admin.listVideos(Number(page) || 1, Number(limit) || 20);
  }

  @Delete('videos/:id')
  deleteVideo(@Param('id') id: string) {
    return this.admin.deleteVideo(id);
  }

  @Patch('videos/:id/visibility')
  setVideoVisibility(@Param('id') id: string, @Body() dto: SetVideoVisibilityDto) {
    return this.admin.setVideoVisibility(id, dto.visibility);
  }

  // ── Stats ──
  @Get('stats')
  getStats() {
    return this.admin.getStats();
  }

  // ── Analytics ──
  @Get('analytics')
  getAnalytics() {
    return this.admin.getAdminAnalytics();
  }

  // ── Players ──
  @Get('players')
  getPlayers(@Query() query: AdminUserQueryDto) {
    return this.admin.listPlayers(query);
  }

  @Get('players/:id')
  getPlayerDetail(@Param('id') id: string) {
    return this.admin.getPlayerDetail(id);
  }

  // ── Scouters ──
  @Get('scouters')
  getScouters(@Query() query: AdminUserQueryDto) {
    return this.admin.listScouters(query);
  }

  @Get('scouters/:id')
  getScouterDetail(@Param('id') id: string) {
    return this.admin.getScouterDetail(id);
  }

  // ── Reports ──
  @Get('reports')
  getReports(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.admin.listAllReports(Number(page) || 1, Number(limit) || 20);
  }

  // ── Notifications ──
  @Post('notifications/broadcast')
  broadcastNotification(@Body() dto: BroadcastNotificationDto) {
    return this.admin.broadcastNotification(dto);
  }
}
