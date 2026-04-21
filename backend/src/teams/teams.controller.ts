import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { TeamsService } from './teams.service';
import { UsersService } from '../users/users.service';
import { VideosService } from '../videos/videos.service';

@Controller('teams')
export class TeamsController {
  constructor(
    private readonly teamsSvc: TeamsService,
    private readonly usersSvc: UsersService,
    private readonly videosSvc: VideosService,
  ) {}

  /** POST /teams — create a new team */
  @UseGuards(JwtAuthGuard)
  @Post()
  async create(@Request() req: any, @Body() body: { name: string }) {
    return this.teamsSvc.create(req.user.sub, body.name);
  }

  /** GET /teams — list teams the current user belongs to */
  @UseGuards(JwtAuthGuard)
  @Get()
  async list(@Request() req: any) {
    return this.teamsSvc.listByMember(req.user.sub);
  }

  /** GET /teams/my/teammates — get all teammates across all teams (must be before :id) */
  @UseGuards(JwtAuthGuard)
  @Get('my/teammates')
  async getTeammates(@Request() req: any) {
    const ids = await this.teamsSvc.getTeammates(req.user.sub);
    const details = await Promise.all(
      ids.map(async (id: string) => {
        try {
          return await this.usersSvc.getById(id);
        } catch {
          return { _id: id, displayName: 'Unknown' };
        }
      }),
    );
    return details;
  }

  /** GET /teams/:id — get team details with member info */
  @UseGuards(JwtAuthGuard)
  @Get(':id')
  async getById(@Request() req: any, @Param('id') id: string) {
    const team = await this.teamsSvc.getById(id);
    // Enrich with member details
    const memberDetails = await Promise.all(
      team.members.map(async (memberId: string) => {
        try {
          return await this.usersSvc.getById(memberId);
        } catch {
          return { _id: memberId, displayName: 'Unknown', email: '' };
        }
      }),
    );
    // Enrich pending invites with user details
    const pendingDetails = await Promise.all(
      (team.pendingInvites || []).map(async (uid: string) => {
        try {
          const u = await this.usersSvc.getById(uid);
          return { _id: uid, displayName: u.displayName || u.email, email: u.email };
        } catch {
          return { _id: uid, displayName: uid, email: '' };
        }
      }),
    );
    return { ...team, memberDetails, pendingDetails };
  }

  /** POST /teams/:id/invite — invite a player to the team */
  @UseGuards(JwtAuthGuard)
  @Post(':id/invite')
  async invite(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: { userId: string },
  ) {
    await this.teamsSvc.invite(id, req.user.sub, body.userId);
    return { ok: true };
  }

  /** POST /teams/:id/accept — accept a team invitation */
  @UseGuards(JwtAuthGuard)
  @Post(':id/accept')
  async accept(@Request() req: any, @Param('id') id: string) {
    await this.teamsSvc.acceptInvite(id, req.user.sub);
    return { ok: true };
  }

  /** POST /teams/:id/decline — decline a team invitation */
  @UseGuards(JwtAuthGuard)
  @Post(':id/decline')
  async decline(@Request() req: any, @Param('id') id: string) {
    await this.teamsSvc.declineInvite(id, req.user.sub);
    return { ok: true };
  }

  /** POST /teams/:id/leave — leave a team */
  @UseGuards(JwtAuthGuard)
  @Post(':id/leave')
  async leave(@Request() req: any, @Param('id') id: string) {
    await this.teamsSvc.leave(id, req.user.sub);
    return { ok: true };
  }

  /** DELETE /teams/:id/members/:userId — remove a member */
  @UseGuards(JwtAuthGuard)
  @Delete(':id/members/:userId')
  async removeMember(
    @Request() req: any,
    @Param('id') id: string,
    @Param('userId') userId: string,
  ) {
    await this.teamsSvc.removeMember(id, req.user.sub, userId);
    return { ok: true };
  }

  /** DELETE /teams/:id — delete a team */
  @UseGuards(JwtAuthGuard)
  @Delete(':id')
  async deleteTeam(@Request() req: any, @Param('id') id: string) {
    await this.teamsSvc.deleteTeam(id, req.user.sub);
    return { ok: true };
  }

  /** GET /teams/:id/videos — list videos where this team was tagged */
  @UseGuards(JwtAuthGuard)
  @Get(':id/videos')
  async teamVideos(@Request() req: any, @Param('id') id: string) {
    const videos = await this.videosSvc.listByTeamTag(id);
    // Enrich each video with uploader name
    const enriched = await Promise.all(
      videos.map(async (v: any) => {
        let uploaderName = 'Unknown';
        try {
          const owner = await this.usersSvc.getById(v.ownerId);
          uploaderName = (owner as any).displayName || (owner as any).email || 'Unknown';
        } catch {}
        return { ...v, uploaderName };
      }),
    );
    return enriched;
  }

  /** GET /teams/:id/search-players?q=... — search players to invite */
  @UseGuards(JwtAuthGuard)
  @Get(':id/search-players')
  async searchPlayers(
    @Param('id') id: string,
    @Query('q') q: string,
  ) {
    return this.teamsSvc.searchPlayersForInvite(id, q || '');
  }

}
