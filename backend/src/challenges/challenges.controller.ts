import { Controller, Get, UseGuards, Request } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ChallengesService, CHALLENGE_DEFS } from './challenges.service';

@Controller('challenges')
export class ChallengesController {
  constructor(private readonly svc: ChallengesService) {}

  /** GET /challenges — returns all challenges with progress for the current user */
  @UseGuards(JwtAuthGuard)
  @Get()
  async list(@Request() req: any) {
    const userId: string = req.user.sub;
    const rows = await this.svc.getAll(userId);

    // Merge static definitions with user progress
    return CHALLENGE_DEFS.map((def) => {
      const row = rows.find((r) => r.challengeKey === def.key);
      return {
        key: def.key,
        icon: def.icon,
        titleEN: def.titleEN,
        titleFR: def.titleFR,
        descEN: def.descEN,
        descFR: def.descFR,
        progress: row?.progress ?? 0,
        target: def.target,
        completed: row?.completed ?? false,
        completedAt: row?.completedAt ?? null,
      };
    });
  }
}
