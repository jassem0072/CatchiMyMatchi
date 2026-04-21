import { Controller, Delete, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import type { RequestUser } from '../auth/request-user';
import { ChallengesService, CHALLENGE_DEFS } from '../challenges/challenges.service';
import { NotificationsService } from '../notifications/notifications.service';
import { UsersService } from '../users/users.service';
import { FavoritesService } from './favorites.service';

@ApiTags('favorites')
@ApiBearerAuth()
@Controller('favorites')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('scouter')
export class FavoritesController {
  constructor(
    private readonly favorites: FavoritesService,
    private readonly challengesSvc: ChallengesService,
    private readonly notifSvc: NotificationsService,
    private readonly usersSvc: UsersService,
  ) {}

  @Get()
  async list(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    return this.favorites.list(me.sub);
  }

  @Post(':playerId')
  async add(@Req() req: { user?: RequestUser }, @Param('playerId') playerId: string) {
    const me = req.user!;
    const result = await this.favorites.add(me.sub, playerId);

    // Fire-and-forget: notify player, update rising_star challenge
    this.onFavorited(me.sub, playerId).catch(() => {});

    return result;
  }

  @Delete(':playerId')
  async remove(@Req() req: { user?: RequestUser }, @Param('playerId') playerId: string) {
    const me = req.user!;
    return this.favorites.remove(me.sub, playerId);
  }

  private async onFavorited(scouterId: string, playerId: string) {
    // Notify the player
    try {
      const scouter = await this.usersSvc.getById(scouterId);
      await this.notifSvc.notifyFavorited(playerId, scouter.displayName || 'A scouter');
    } catch {
      // ignore
    }

    // Update rising_star challenge for the player
    try {
      const favCount = (await this.favorites.listByPlayer(playerId)).length;
      const res = await this.challengesSvc.setProgress(playerId, 'rising_star', favCount);
      if (res.newlyCompleted) {
        const def = CHALLENGE_DEFS.find((d) => d.key === 'rising_star')!;
        await this.notifSvc.notifyChallengeCompleted(playerId, def.titleEN, def.titleFR);
      }
    } catch {
      // ignore
    }
  }
}
