import { Module } from '@nestjs/common';

import { ChallengesModule } from '../challenges/challenges.module';
import { FavoritesModule } from '../favorites/favorites.module';
import { UsersModule } from '../users/users.module';
import { VideosModule } from '../videos/videos.module';
import { PlayersController } from './players.controller';
import { PlayersService } from './players.service';

@Module({
  imports: [UsersModule, VideosModule, FavoritesModule, ChallengesModule],
  controllers: [PlayersController],
  providers: [PlayersService],
})
export class PlayersModule {}
