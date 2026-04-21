import { Body, Controller, Get, Param, Post, Req, Res, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import type { RequestUser } from '../auth/request-user';
import { PlayersService } from './players.service';

@ApiTags('players')
@ApiBearerAuth()
@Controller('players')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('scouter', 'player')
export class PlayersController {
  constructor(private readonly players: PlayersService) {}

  @Get()
  async list(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    const scouterId = me.role === 'scouter' ? me.sub : '';
    return this.players.list(scouterId);
  }

  @Post('compare')
  async compare(
    @Req() req: { user?: RequestUser },
    @Body() body: { playerIdA: string; playerIdB: string },
  ) {
    const me = req.user!;
    const scouterId = me.role === 'scouter' ? me.sub : '';
    return this.players.compare(body.playerIdA, body.playerIdB, scouterId);
  }

  @Get(':playerId')
  async get(@Req() req: { user?: RequestUser }, @Param('playerId') playerId: string) {
    const me = req.user!;
    const scouterId = me.role === 'scouter' ? me.sub : '';
    return this.players.getPlayer(playerId, scouterId);
  }

  @Get(':playerId/videos')
  async videos(@Param('playerId') playerId: string) {
    return this.players.getPlayerVideos(playerId);
  }

  @Get(':playerId/dashboard')
  async dashboard(@Req() req: { user?: RequestUser }, @Param('playerId') playerId: string) {
    const me = req.user!;
    const scouterId = me.role === 'scouter' ? me.sub : '';
    return this.players.dashboard(playerId, scouterId);
  }

  @Get(':playerId/challenges')
  async challenges(@Param('playerId') playerId: string) {
    return this.players.getPlayerChallenges(playerId);
  }

  @Get(':playerId/portrait')
  async portrait(@Param('playerId') playerId: string, @Res() res: Response) {
    const portrait = await this.players.getPlayerPortrait(playerId);
    if (!portrait) return res.status(204).send();
    res.setHeader('Content-Type', portrait.contentType || 'image/jpeg');
    return res.send(portrait.data);
  }
}
