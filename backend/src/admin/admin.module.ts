import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { User, UserSchema } from '../users/users.schema';
import { Video, VideoSchema } from '../videos/videos.schema';
import { Report, ReportSchema } from '../reports/reports.schema';
import { Notification, NotificationSchema } from '../notifications/notifications.schema';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: User.name, schema: UserSchema },
      { name: Video.name, schema: VideoSchema },
      { name: Report.name, schema: ReportSchema },
      { name: Notification.name, schema: NotificationSchema },
    ]),
  ],
  controllers: [AdminController],
  providers: [AdminService],
})
export class AdminModule {}
