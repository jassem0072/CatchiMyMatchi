import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { ChallengesModule } from '../challenges/challenges.module';
import { FavoritesModule } from '../favorites/favorites.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { UsersModule } from '../users/users.module';

import { VideosController } from './videos.controller';
import { VideosService } from './videos.service';
import { Video, VideoSchema } from './videos.schema';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Video.name, schema: VideoSchema }]),
    ChallengesModule,
    NotificationsModule,
    FavoritesModule,
    UsersModule,
  ],
  controllers: [VideosController],
  providers: [VideosService],
  exports: [VideosService],
})
export class VideosModule {}
