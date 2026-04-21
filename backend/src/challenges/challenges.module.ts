import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { ChallengesController } from './challenges.controller';
import { ChallengesService } from './challenges.service';
import { ChallengeProgress, ChallengeProgressSchema } from './challenges.schema';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: ChallengeProgress.name, schema: ChallengeProgressSchema }]),
  ],
  controllers: [ChallengesController],
  providers: [ChallengesService],
  exports: [ChallengesService],
})
export class ChallengesModule {}
