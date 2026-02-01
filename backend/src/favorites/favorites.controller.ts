import { Controller, Delete, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import type { RequestUser } from '../auth/request-user';
import { FavoritesService } from './favorites.service';

@ApiTags('favorites')
@ApiBearerAuth()
@Controller('favorites')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('scouter')
export class FavoritesController {
  constructor(private readonly favorites: FavoritesService) {}

  @Get()
  async list(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    return this.favorites.list(me.sub);
  }

  @Post(':playerId')
  async add(@Req() req: { user?: RequestUser }, @Param('playerId') playerId: string) {
    const me = req.user!;
    return this.favorites.add(me.sub, playerId);
  }

  @Delete(':playerId')
  async remove(@Req() req: { user?: RequestUser }, @Param('playerId') playerId: string) {
    const me = req.user!;
    return this.favorites.remove(me.sub, playerId);
  }
}
