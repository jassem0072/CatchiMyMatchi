import { Module } from '@nestjs/common';

import { FavoritesModule } from '../favorites/favorites.module';
import { UsersModule } from '../users/users.module';
import { VideosModule } from '../videos/videos.module';
import { PlayersController } from './players.controller';
import { PlayersService } from './players.service';

@Module({
  imports: [UsersModule, VideosModule, FavoritesModule],
  controllers: [PlayersController],
  providers: [PlayersService],
})
export class PlayersModule {}
