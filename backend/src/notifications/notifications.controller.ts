import { BadRequestException, Body, Controller, Get, Param, Patch, Post, UseGuards, Request } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { UsersService } from '../users/users.service';
import { NotificationsService } from './notifications.service';

@Controller('notifications')
export class NotificationsController {
  constructor(
    private readonly svc: NotificationsService,
    private readonly users: UsersService,
  ) {}

  /** GET /notifications — list all notifications for current user */
  @UseGuards(JwtAuthGuard)
  @Get()
  async list(@Request() req: any) {
    return this.svc.list(req.user.sub);
  }

  /** GET /notifications/unread-count */
  @UseGuards(JwtAuthGuard)
  @Get('unread-count')
  async unreadCount(@Request() req: any) {
    const count = await this.svc.unreadCount(req.user.sub);
    return { count };
  }

  /** PATCH /notifications/read-all */
  @UseGuards(JwtAuthGuard)
  @Patch('read-all')
  async markAllRead(@Request() req: any) {
    await this.svc.markAllRead(req.user.sub);
    return { ok: true };
  }

  /** PATCH /notifications/:id/read */
  @UseGuards(JwtAuthGuard)
  @Patch(':id/read')
  async markRead(@Request() req: any, @Param('id') id: string) {
    await this.svc.markRead(req.user.sub, id);
    return { ok: true };
  }

  /** POST /notifications/video-request — scouter sends a video request to a player */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('scouter')
  @Post('video-request')
  async videoRequest(
    @Request() req: any,
    @Body() body: { playerId?: string; message?: string },
  ) {
    if (!body.playerId) throw new BadRequestException('playerId is required');
    if (!body.message || !body.message.trim()) throw new BadRequestException('message is required');
    const scouter = await this.users.getById(req.user.sub);
    const rawName = (scouter as any).displayName || '';
    const email = (scouter as any).email || '';
    const scouterName = rawName.trim() || (email.includes('@') ? email.split('@')[0] : email) || 'A scout';
    const notif = await this.svc.notifyVideoRequest(
      body.playerId,
      req.user.sub,
      scouterName,
      body.message.trim(),
    );
    return { ok: true, notificationId: (notif as any)._id };
  }
}
