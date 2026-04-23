import {
  Req,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import type { RequestUser } from '../auth/request-user';
import { AdminService } from './admin.service';
import {
  AdminUserQueryDto,
  BillingTransactionQueryDto,
  BroadcastNotificationDto,
  ExpertReviewDto,
  ClaimEarningsDto,
  PreContractDto,
  ScouterDecisionDto,
  SetVideoVisibilityDto,
  UpdateSubscriptionDto,
  UpdateUserRoleDto,
} from './admin.dto';

@ApiTags('admin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('admin', 'expert')
@Controller('admin')
export class AdminController {
  constructor(private readonly admin: AdminService) { }

  // ── Users ──
  @Get('users')
  @Roles('admin')
  getUsers(@Query() query: AdminUserQueryDto) {
    return this.admin.listUsers(query);
  }

  @Delete('users/:id')
  @Roles('admin')
  deleteUser(@Param('id') id: string) {
    return this.admin.deleteUser(id);
  }

  @Patch('users/:id/ban')
  @Roles('admin')
  banUser(@Param('id') id: string) {
    return this.admin.banUser(id, true);
  }

  @Patch('users/:id/unban')
  @Roles('admin')
  unbanUser(@Param('id') id: string) {
    return this.admin.banUser(id, false);
  }

  @Patch('users/:id/role')
  @Roles('admin')
  updateUserRole(
    @Param('id') id: string,
    @Body() dto: UpdateUserRoleDto,
    @Req() req: { user?: RequestUser },
  ) {
    return this.admin.updateUserRole(id, dto.role, req.user?.email || '');
  }

  @Patch('users/:id/approve-admin-request')
  @Roles('admin')
  approveAdminRequest(
    @Param('id') id: string,
    @Req() req: { user?: RequestUser },
  ) {
    return this.admin.approveAdminAccessRequest(id, req.user?.email || '');
  }

  @Patch('users/:id/subscription')
  @Roles('admin')
  updateSubscription(@Param('id') id: string, @Body() dto: UpdateSubscriptionDto) {
    return this.admin.updateSubscription(id, dto);
  }

  // ── Videos ──
  @Get('videos')
  @Roles('admin')
  getVideos(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.admin.listVideos(Number(page) || 1, Number(limit) || 20);
  }

  @Delete('videos/:id')
  @Roles('admin')
  deleteVideo(@Param('id') id: string) {
    return this.admin.deleteVideo(id);
  }

  @Patch('videos/:id/visibility')
  @Roles('admin')
  setVideoVisibility(@Param('id') id: string, @Body() dto: SetVideoVisibilityDto) {
    return this.admin.setVideoVisibility(id, dto.visibility);
  }

  // ── Stats ──
  @Get('stats')
  @Roles('admin')
  getStats() {
    return this.admin.getStats();
  }

  // ── Analytics ──
  @Get('analytics')
  @Roles('admin')
  getAnalytics() {
    return this.admin.getAdminAnalytics();
  }

  // ── Players ──
  @Get('players')
  getPlayers(@Query() query: AdminUserQueryDto) {
    return this.admin.listPlayers(query);
  }

  @Get('players/:id')
  @Roles('admin', 'expert', 'scouter')
  getPlayerDetail(@Param('id') id: string) {
    return this.admin.getPlayerDetail(id);
  }

  @Get('players/:id/documents/portrait')
  async getPlayerPortraitDocument(@Param('id') id: string, @Res() res: Response) {
    const portrait = await this.admin.getPlayerPortraitDocument(id);
    if (!portrait) return res.status(204).send();
    res.setHeader('Content-Type', portrait.contentType || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(portrait.fileName || 'bulletin-n3')}"`);
    return res.send(portrait.data);
  }

  @Get('players/:id/documents/badge')
  async getPlayerBadgeDocument(@Param('id') id: string, @Res() res: Response) {
    const badge = await this.admin.getPlayerBadgeDocument(id);
    if (!badge) return res.status(204).send();
    res.setHeader('Content-Type', badge.contentType || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(badge.fileName || 'medical-diploma')}"`);
    return res.send(badge.data);
  }

  @Get('players/:id/documents/player-id')
  async getPlayerIdDocument(@Param('id') id: string, @Res() res: Response) {
    const doc = await this.admin.getPlayerIdDocument(id);
    if (!doc) return res.status(204).send();
    res.setHeader('Content-Type', doc.contentType || 'application/octet-stream');
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(doc.fileName || 'player-id')}"`);
    return res.send(doc.data);
  }

  @Post('players/:id/video-request')
  @Roles('admin')
  sendVideoRequest(@Param('id') id: string) {
    return this.admin.recordVideoRequest(id);
  }

  @Post('players/:id/request-info-verification')
  @Roles('admin', 'scouter')
  requestInfoVerification(
    @Param('id') id: string,
    @Req() req: { user?: RequestUser },
  ) {
    return this.admin.requestInfoVerification(id, req.user?.sub || '');
  }

  @Patch('players/:id/expert-review')
  @Roles('admin', 'expert')
  submitExpertReview(
    @Param('id') id: string,
    @Body() dto: ExpertReviewDto,
    @Req() req: { user?: RequestUser },
  ) {
    return this.admin.setExpertReview(id, dto.decision, dto.report, req.user?.sub || '');
  }

  @Get('expert/earnings')
  @Roles('expert')
  getExpertEarnings(@Req() req: { user?: RequestUser }) {
    return this.admin.getExpertEarnings(req.user?.sub || '');
  }

  @Get('expert/invoices')
  @Roles('expert')
  getExpertPayoutInvoices(@Req() req: { user?: RequestUser }) {
    return this.admin.getExpertPayoutInvoices(req.user?.sub || '');
  }

  @Post('expert/claim-earnings')
  @Roles('expert')
  claimExpertEarnings(
    @Req() req: { user?: RequestUser },
    @Body() dto: ClaimEarningsDto,
  ) {
    return this.admin.claimExpertEarnings(req.user?.sub || '', dto);
  }

  @Get('billing/transactions')
  @Roles('admin')
  listBillingTransactions(@Query() query: BillingTransactionQueryDto) {
    return this.admin.listBillingTransactions(query);
  }

  @Patch('players/:id/scouter-decision')
  @Roles('admin', 'scouter')
  submitScouterDecision(@Param('id') id: string, @Body() dto: ScouterDecisionDto) {
    return this.admin.setScouterDecision(id, dto.decision);
  }

  @Patch('players/:id/pre-contract')
  @Roles('admin', 'scouter')
  updatePreContract(
    @Param('id') id: string,
    @Body() dto: PreContractDto,
    @Req() req: { user?: RequestUser },
  ) {
    return this.admin.updatePreContract(id, dto, req.user?.sub || '');
  }

  // ── Scouters ──
  @Get('scouters')
  @Roles('admin')
  getScouters(@Query() query: AdminUserQueryDto) {
    return this.admin.listScouters(query);
  }

  @Get('scouters/:id')
  @Roles('admin')
  getScouterDetail(@Param('id') id: string) {
    return this.admin.getScouterDetail(id);
  }

  // ── Reports ──
  @Get('reports')
  @Roles('admin')
  getReports(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.admin.listAllReports(Number(page) || 1, Number(limit) || 20);
  }

  // ── Experts ──
  @Post('experts/:id/notify-invoice-ready')
  @Roles('admin')
  notifyExpertInvoiceReady(@Param('id') id: string) {
    return this.admin.notifyExpertInvoiceReady(id);
  }

  // ── Notifications ──
  @Post('notifications/broadcast')
  @Roles('admin')
  broadcastNotification(@Body() dto: BroadcastNotificationDto) {
    return this.admin.broadcastNotification(dto);
  }
}
