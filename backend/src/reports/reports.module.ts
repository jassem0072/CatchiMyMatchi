import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { VideosModule } from '../videos/videos.module';
import { Report, ReportSchema } from './reports.schema';
import { ReportsController } from './reports.controller';
import { ReportsService } from './reports.service';

@Module({
  imports: [MongooseModule.forFeature([{ name: Report.name, schema: ReportSchema }]), VideosModule],
  controllers: [ReportsController],
  providers: [ReportsService],
})
export class ReportsModule {}
