import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class CreateReportDto {
  @ApiProperty()
  playerId!: string;

  @ApiPropertyOptional()
  videoId?: string;

  @ApiPropertyOptional()
  title?: string;

  @ApiPropertyOptional()
  notes?: string;

  @ApiPropertyOptional({ description: 'Optional client-side card snapshot (PAC/SHO/...)' })
  cardSnapshot?: Record<string, unknown>;
}
