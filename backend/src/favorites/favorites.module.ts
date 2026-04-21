import { Module, forwardRef } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { ChallengesModule } from '../challenges/challenges.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { UsersModule } from '../users/users.module';

import { Favorite, FavoriteSchema } from './favorites.schema';
import { FavoritesController } from './favorites.controller';
import { FavoritesService } from './favorites.service';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Favorite.name, schema: FavoriteSchema }]),
    forwardRef(() => ChallengesModule),
    NotificationsModule,
    UsersModule,
  ],
  controllers: [FavoritesController],
  providers: [FavoritesService],
  exports: [FavoritesService],
})
export class FavoritesModule {}
