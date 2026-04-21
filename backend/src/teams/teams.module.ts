import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { NotificationsModule } from '../notifications/notifications.module';
import { UsersModule } from '../users/users.module';
import { VideosModule } from '../videos/videos.module';

import { TeamsController } from './teams.controller';
import { TeamsService } from './teams.service';
import { Team, TeamSchema } from './teams.schema';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Team.name, schema: TeamSchema }]),
    NotificationsModule,
    UsersModule,
    VideosModule,
  ],
  controllers: [TeamsController],
  providers: [TeamsService],
  exports: [TeamsService],
})
export class TeamsModule {}
