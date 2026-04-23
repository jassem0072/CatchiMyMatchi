import { Module } from '@nestjs/common';

import { MeController } from './me.controller';
import { AuthModule } from '../auth/auth.module';
import { ChallengesModule } from '../challenges/challenges.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { UsersModule } from '../users/users.module';
import { TeamsModule } from '../teams/teams.module';
import { VideosModule } from '../videos/videos.module';
import { AdminModule } from '../admin/admin.module';

@Module({
  imports: [VideosModule, UsersModule, AuthModule, ChallengesModule, NotificationsModule, TeamsModule, AdminModule],
  controllers: [MeController],
})
export class MeModule {}
