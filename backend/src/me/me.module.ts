import { Module } from '@nestjs/common';

import { MeController } from './me.controller';
import { UsersModule } from '../users/users.module';
import { VideosModule } from '../videos/videos.module';

@Module({
  imports: [VideosModule, UsersModule],
  controllers: [MeController],
})
export class MeModule {}
