import { Body, Controller, Get, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import type { RequestUser } from '../auth/request-user';
import { CreateReportDto } from './reports.dto';
import { ReportsService } from './reports.service';

@ApiTags('reports')
@ApiBearerAuth()
@Controller('reports')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('scouter')
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  @Post()
  async create(@Req() req: { user?: RequestUser }, @Body() dto: CreateReportDto) {
    const me = req.user!;
    return this.reports.create(me.sub, dto);
  }

  @Get()
  async list(@Req() req: { user?: RequestUser }, @Query('playerId') playerId?: string) {
    const me = req.user!;
    return this.reports.list(me.sub, playerId);
  }

  @Get(':id')
  async get(@Req() req: { user?: RequestUser }, @Param('id') id: string) {
    const me = req.user!;
    return this.reports.get(me.sub, id);
  }
}
